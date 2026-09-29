import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A message the broker observed being published by any connected client,
/// regardless of whether anyone else is subscribed to it. Used to feed
/// telemetry displays in the app without the app needing to "subscribe"
/// itself (it's the broker - it already sees every PUBLISH).
class MqttBrokerMessage {
  final String topic;
  final String payload;
  final String fromClientId;
  final DateTime receivedAt;

  MqttBrokerMessage({
    required this.topic,
    required this.payload,
    required this.fromClientId,
    required this.receivedAt,
  });
}

class MiniMqttBroker {
  ServerSocket? _server;
  final Map<Socket, _ClientState> _clients = {};

  RawDatagramSocket? _announceSocket;
  Timer? _announceTimer;
  static const int discoveryPort = 8890;

  final StreamController<String> _logController =
  StreamController<String>.broadcast();
  final StreamController<int> _clientCountController =
  StreamController<int>.broadcast();
  final StreamController<MqttBrokerMessage> _messageController =
  StreamController<MqttBrokerMessage>.broadcast();
  final StreamController<List<String>> _clientIdsController =
  StreamController<List<String>>.broadcast();

  Stream<String> get logStream => _logController.stream;
  Stream<int> get clientCountStream => _clientCountController.stream;

  /// Every PUBLISH the broker receives from any client, regardless of
  /// whether it had a matching subscriber. Use this to observe telemetry.
  Stream<MqttBrokerMessage> get messageStream => _messageController.stream;

  /// Emits the sorted list of MQTT client IDs currently connected (e.g.
  /// "esp32-AABBCCDDEEFF") every time a client connects or disconnects.
  Stream<List<String>> get clientIdsStream => _clientIdsController.stream;

  List<String> get connectedClientIds => (_clients.values
      .map((c) => c.clientId)
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList()
    ..sort());

  void _emitClientIds() {
    if (!_clientIdsController.isClosed) {
      _clientIdsController.add(connectedClientIds);
    }
  }

  int get connectedClientCount => _clients.length;
  bool get isRunning => _server != null;

  Future<void> start(int port) async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _log('Broker listening on port $port');
    _server!.listen(_handleClient, onError: (e) => _log('Server error: $e'));

    await _startAnnouncing();
  }

  Future<void> _startAnnouncing() async {
    final ip = await _pickWifiIPv4();
    if (ip == null) {
      _log('Could not determine local IP - broker announcement disabled');
      return;
    }

    // Bind to the Wi-Fi address so the broadcast leaves through Wi-Fi even
    // when mobile data is on. Fall back to "any" if that fails.
    try {
      _announceSocket = await RawDatagramSocket.bind(InternetAddress(ip), 0);
    } catch (e) {
      _log('Could not bind announce socket to $ip ($e) - using any interface');
      _announceSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _announceSocket!.broadcastEnabled = true;

    final message = utf8.encode('MQTT_BROKER:$ip');

    // Limited broadcast + subnet-directed broadcast (assumes a /24 network,
    // which is what home routers use). Some routers/APs drop one of them.
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
    final parts = ip.split('.');
    if (parts.length == 4) {
      targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
    }

    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      for (final target in targets) {
        try {
          _announceSocket?.send(message, target, discoveryPort);
        } catch (_) {}
      }
    });

    _log('Announcing broker IP $ip on UDP:$discoveryPort every 2s '
        '(to ${targets.map((t) => t.address).join(', ')})');
  }

  static bool _isPrivateIPv4(String a) =>
      a.startsWith('192.168.') ||
          a.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);

  /// Picks the phone's Wi-Fi (or hotspot / ethernet) IPv4 address instead of
  /// blindly taking the first interface, which on Android is often the
  /// mobile-data one (rmnet*, ccmni*) and would make the ESP32 connect to an
  /// address it can never reach.
  Future<String?> _pickWifiIPv4() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );

    _log('Network interfaces: ${interfaces
            .map((i) =>
        '${i.name}=${i.addresses.map((a) => a.address).join('/')}')
            .join(', ')}');

    const wifiPrefixes = ['wlan', 'swlan', 'ap', 'eth', 'en'];
    const mobilePrefixes = ['rmnet', 'ccmni', 'pdp', 'tun', 'ppp', 'dummy', 'v4-'];

    String? privateFallback;
    String? anyFallback;

    for (final iface in interfaces) {
      final name = iface.name.toLowerCase();
      for (final addr in iface.addresses) {
        final a = addr.address;
        anyFallback ??= a;
        if (!_isPrivateIPv4(a)) continue;
        if (wifiPrefixes.any(name.startsWith)) return a;
        if (!mobilePrefixes.any(name.startsWith)) privateFallback ??= a;
      }
    }
    return privateFallback ?? anyFallback;
  }

  Future<void> stop() async {
    for (final socket in _clients.keys.toList()) {
      socket.destroy();
    }
    _clients.clear();
    await _server?.close();
    _server = null;

    _announceTimer?.cancel();
    _announceTimer = null;
    _announceSocket?.close();
    _announceSocket = null;

    _log('Broker stopped');
    _clientCountController.add(0);
    _emitClientIds();
  }

  void dispose() {
    stop();
    _logController.close();
    _clientCountController.close();
    _messageController.close();
    _clientIdsController.close();
  }

  void _log(String message) => _logController.add(message);

  void _handleClient(Socket socket) {
    final state = _ClientState();
    _clients[socket] = state;
    _log('Client connected: ${socket.remoteAddress.address}');
    _clientCountController.add(_clients.length);

    socket.listen(
          (data) => _onData(socket, state, data),
      onError: (e) => _log('Client error: $e'),
      onDone: () => _removeClient(socket),
      cancelOnError: true,
    );
  }

  void _removeClient(Socket socket) {
    if (_clients.remove(socket) != null) {
      _log('Client disconnected');
      _clientCountController.add(_clients.length);
      _emitClientIds();
    }
    socket.destroy();
  }

  void _onData(Socket socket, _ClientState state, Uint8List data) {
    state.buffer.addAll(data);
    while (true) {
      final packet = _tryReadPacket(state.buffer);
      if (packet == null) return; // wait for more bytes
      try {
        _handlePacket(socket, state, packet);
      } catch (e) {
        _log('Error handling packet: $e');
      }
    }
  }

  /// Extracts one full MQTT packet (fixed header + remaining bytes) from the
  /// front of [buffer] if enough data is available, removing it from
  /// [buffer]. Returns null if a full packet isn't available yet.
  Uint8List? _tryReadPacket(List<int> buffer) {
    if (buffer.isEmpty) return null;

    int multiplier = 1;
    int value = 0;
    int index = 1;
    int encodedByte;
    do {
      if (index >= buffer.length) return null;
      encodedByte = buffer[index];
      value += (encodedByte & 127) * multiplier;
      multiplier *= 128;
      index++;
    } while ((encodedByte & 128) != 0);

    final totalLength = index + value;
    if (buffer.length < totalLength) return null;

    final packetBytes = Uint8List.fromList(buffer.sublist(0, totalLength));
    buffer.removeRange(0, totalLength);
    return packetBytes;
  }

  int _remainingLengthFieldSize(Uint8List packet) {
    int index = 1;
    while ((packet[index] & 128) != 0) {
      index++;
    }
    return index; // number of bytes the remaining-length field occupied
  }

  void _handlePacket(Socket socket, _ClientState state, Uint8List packet) {
    final packetType = (packet[0] & 0xF0) >> 4;
    switch (packetType) {
      case 1:
        _handleConnect(socket, state, packet);
        break;
      case 3:
        _handlePublish(socket, state, packet);
        break;
      case 8:
        _handleSubscribe(socket, state, packet);
        break;
      case 10:
        _handleUnsubscribe(socket, state, packet);
        break;
      case 12: // PINGREQ
        socket.add(Uint8List.fromList([0xD0, 0x00])); // PINGRESP
        break;
      case 14: // DISCONNECT
        _removeClient(socket);
        break;
      default:
        _log('Ignoring unsupported packet type $packetType');
    }
  }

  void _handleConnect(Socket socket, _ClientState state, Uint8List packet) {
    int offset = 1 + _remainingLengthFieldSize(packet);
    final protoNameLen = (packet[offset] << 8) | packet[offset + 1];
    offset += 2 + protoNameLen;
    offset += 1; // protocol level
    offset += 1; // connect flags
    offset += 2; // keep alive
    final clientIdLen = (packet[offset] << 8) | packet[offset + 1];
    offset += 2;
    state.clientId = utf8.decode(packet.sublist(offset, offset + clientIdLen));

    _log('CONNECT from "${state.clientId}"');

    // MQTT spec: a new connection with the same client ID replaces the old
    // one. Without this, a device that dropped off the network would leave a
    // stale socket behind (this broker has no keep-alive timeout).
    if (state.clientId.isNotEmpty) {
      for (final entry in _clients.entries.toList()) {
        if (entry.key != socket && entry.value.clientId == state.clientId) {
          _log('Dropping stale connection for "${state.clientId}"');
          _removeClient(entry.key);
        }
      }
    }

    // CONNACK: session present = 0, return code = 0 (accepted)
    socket.add(Uint8List.fromList([0x20, 0x02, 0x00, 0x00]));
    _emitClientIds();
  }

  void _handleSubscribe(Socket socket, _ClientState state, Uint8List packet) {
    int offset = 1 + _remainingLengthFieldSize(packet);
    final packetId = (packet[offset] << 8) | packet[offset + 1];
    offset += 2;

    final grantedQos = <int>[];
    while (offset < packet.length) {
      final topicLen = (packet[offset] << 8) | packet[offset + 1];
      offset += 2;
      final topic = utf8.decode(packet.sublist(offset, offset + topicLen));
      offset += topicLen;
      final requestedQos = packet[offset];
      offset += 1;

      state.subscriptions.add(topic);
      grantedQos.add(requestedQos > 1 ? 1 : requestedQos);
      _log('"${state.clientId}" subscribed to "$topic"');
    }

    final body = <int>[packetId >> 8, packetId & 0xFF, ...grantedQos];
    socket.add(Uint8List.fromList([0x90, body.length, ...body]));
  }

  void _handleUnsubscribe(
      Socket socket, _ClientState state, Uint8List packet) {
    int offset = 1 + _remainingLengthFieldSize(packet);
    final packetId = (packet[offset] << 8) | packet[offset + 1];
    offset += 2;

    while (offset < packet.length) {
      final topicLen = (packet[offset] << 8) | packet[offset + 1];
      offset += 2;
      final topic = utf8.decode(packet.sublist(offset, offset + topicLen));
      offset += topicLen;
      state.subscriptions.remove(topic);
    }

    socket.add(
        Uint8List.fromList([0xB0, 0x02, packetId >> 8, packetId & 0xFF]));
  }

  void _handlePublish(Socket socket, _ClientState state, Uint8List packet) {
    final flags = packet[0] & 0x0F;
    final qos = (flags >> 1) & 0x03;
    int offset = 1 + _remainingLengthFieldSize(packet);
    final topicLen = (packet[offset] << 8) | packet[offset + 1];
    offset += 2;
    final topic = utf8.decode(packet.sublist(offset, offset + topicLen));
    offset += topicLen;

    int packetId = 0;
    if (qos > 0) {
      packetId = (packet[offset] << 8) | packet[offset + 1];
      offset += 2;
    }

    final payload = packet.sublist(offset);
    final payloadString = utf8.decode(payload, allowMalformed: true);

    _log('PUBLISH "$topic" from "${state.clientId}": $payloadString');

    _messageController.add(MqttBrokerMessage(
      topic: topic,
      payload: payloadString,
      fromClientId: state.clientId,
      receivedAt: DateTime.now(),
    ));

    if (qos == 1) {
      socket.add(
          Uint8List.fromList([0x40, 0x02, packetId >> 8, packetId & 0xFF]));
    }

    publish(topic, payload);
  }

  /// Publishes [payload] bytes to every connected client subscribed to the
  /// exact [topic] (no wildcard matching). Always sent at QoS 0.
  ///
  /// If [targetClientId] is given, only the client with that MQTT client ID
  /// receives it (it still has to be subscribed to [topic]).
  void publish(String topic, List<int> payload, {String? targetClientId}) {
    final topicBytes = utf8.encode(topic);
    final variableHeader = <int>[
      topicBytes.length >> 8,
      topicBytes.length & 0xFF,
      ...topicBytes,
    ];
    final remaining = variableHeader.length + payload.length;
    final fixedHeader = <int>[0x30, ..._encodeRemainingLength(remaining)];
    final fullPacket =
    Uint8List.fromList([...fixedHeader, ...variableHeader, ...payload]);

    var sentCount = 0;
    for (final entry in _clients.entries) {
      if (targetClientId != null && entry.value.clientId != targetClientId) {
        continue;
      }
      if (entry.value.subscriptions.contains(topic)) {
        entry.key.add(fullPacket);
        sentCount++;
      }
    }
    _log('Published "$topic" to $sentCount subscriber(s)'
        '${targetClientId != null ? ' (target: $targetClientId)' : ''}');
  }

  /// Convenience for publishing a plain text payload.
  void publishString(String topic, String payload, {String? targetClientId}) {
    publish(topic, utf8.encode(payload), targetClientId: targetClientId);
  }

  List<int> _encodeRemainingLength(int length) {
    final bytes = <int>[];
    var value = length;
    do {
      var byte = value % 128;
      value = value ~/ 128;
      if (value > 0) byte |= 0x80;
      bytes.add(byte);
    } while (value > 0);
    return bytes;
  }
}

class _ClientState {
  String clientId = '';
  final List<int> buffer = [];
  final Set<String> subscriptions = {};
}