import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mini_mqtt_broker.dart'; // for MqttAudioChunk

class MiniWebSocketServer {
  HttpServer? _server;
  final Map<WebSocket, String> _clients = {};

  RawDatagramSocket? _announceSocket;
  Timer? _announceTimer;
  static const int discoveryPort = 8890;

  final StreamController<String> _logController =
  StreamController<String>.broadcast();
  final StreamController<int> _clientCountController =
  StreamController<int>.broadcast();
  final StreamController<List<String>> _clientIdsController =
  StreamController<List<String>>.broadcast();
  final StreamController<MqttAudioChunk> _audioController =
  StreamController<MqttAudioChunk>.broadcast();
  final StreamController<MqttAudioChunk> _videoController =
  StreamController<MqttAudioChunk>.broadcast();

  Stream<String> get logStream => _logController.stream;
  Stream<int> get clientCountStream => _clientCountController.stream;
  Stream<List<String>> get clientIdsStream => _clientIdsController.stream;
  Stream<MqttAudioChunk> get audioStream => _audioController.stream;

  /// Camera frames: binary messages tagged 0x02.
  Stream<MqttAudioChunk> get videoStream => _videoController.stream;

  List<String> get connectedClientIds => (_clients.values
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

  /// Set by the task handler: appends the authentication tag to announcements.
  String Function(String body)? signDiscovery;

  Future<void> start(int port) async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _log('WebSocket server listening on port $port');

    _server!.listen((HttpRequest request) async {
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        try {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleClient(socket, request);
        } catch (e) {
          _log('Error upgrading WebSocket request: $e');
        }
      } else {
        request.response.statusCode = HttpStatus.forbidden;
        await request.response.close();
      }
    }, onError: (e) => _log('Server error: $e'));

    await _startAnnouncing(port);
  }

  void _handleClient(WebSocket socket, HttpRequest request) {
    final queryId = request.uri.queryParameters['clientId'] ??
        request.uri.queryParameters['id'];
    final clientId = queryId ?? 'esp32-${socket.hashCode}';

    _clients[socket] = clientId;
    _log('WS client connected: $clientId');
    if (!_clientCountController.isClosed) {
      _clientCountController.add(_clients.length);
    }
    _emitClientIds();

    socket.listen(
          (data) {
        if (data is List<int>) {
          // Binary frames start with a type byte: 0x01 audio, 0x02 camera frame.
          if (data.length < 2) return;
          final type = data[0];
          final payload = data.sublist(1);
          final id = _clients[socket] ?? clientId;
          if (type == 0x02) {
            if (!_videoController.isClosed) {
              _videoController.add(MqttAudioChunk(clientId: id, payload: payload));
            }
          } else if (type == 0x01) {
            if (!_audioController.isClosed) {
              _audioController.add(MqttAudioChunk(clientId: id, payload: payload));
            }
          }
        } else if (data is String) {
          try {
            final jsonMap = jsonDecode(data);
            if (jsonMap is Map && jsonMap['type'] == 'identify') {
              final newId = jsonMap['clientId'] as String?;
              if (newId != null && newId.isNotEmpty) {
                _clients[socket] = newId;
                _emitClientIds();
                _log('WS client identified as "$newId"');
              }
            } else if (jsonMap is Map &&
                jsonMap['type'] == 'audio' &&
                jsonMap['data'] is List) {
              final payload = (jsonMap['data'] as List).cast<int>();
              if (!_audioController.isClosed) {
                _audioController.add(MqttAudioChunk(
                  clientId: _clients[socket] ?? clientId,
                  payload: payload,
                ));
              }
            }
          } catch (_) {
            _log('WS message from ${_clients[socket]}: $data');
          }
        }
      },
      onError: (e) => _log('WS Client error: $e'),
      onDone: () => _removeClient(socket),
      cancelOnError: true,
    );
  }

  void _removeClient(WebSocket socket) {
    final id = _clients.remove(socket);
    if (id != null) {
      _log('WS client disconnected: $id');
      if (!_clientCountController.isClosed) {
        _clientCountController.add(_clients.length);
      }
      _emitClientIds();
    }
    try {
      socket.close();
    } catch (_) {}
  }

  /// Sends an already-encrypted packet as a binary frame.
  void sendBytes(List<int> payload, {String? targetClientId}) {
    for (final entry in _clients.entries.toList()) {
      if (targetClientId != null && entry.value != targetClientId) continue;
      try {
        entry.key.add(payload);
      } catch (e) {
        _log('Error sending to WS client ${entry.value}: $e');
      }
    }
  }

  void sendString(String payload, {String? targetClientId}) {
    for (final entry in _clients.entries.toList()) {
      if (targetClientId != null && entry.value != targetClientId) {
        continue;
      }
      try {
        entry.key.add(payload);
      } catch (e) {
        _log('Error sending to WS client ${entry.value}: $e');
      }
    }
  }

  Future<void> _startAnnouncing(int port) async {
    final ip = await _pickWifiIPv4();
    if (ip == null) {
      _log('Could not determine local IP - server announcement disabled');
      return;
    }

    try {
      _announceSocket = await RawDatagramSocket.bind(InternetAddress(ip), 0);
    } catch (_) {
      _announceSocket =
      await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    }
    _announceSocket?.broadcastEnabled = true;

    final body = 'WS_SERVER:$ip:$port';

    // Limited broadcast + subnet-directed broadcast (assumes a /24 network,
    // which is what home routers use). Some routers/APs/OSes drop one of them.
    final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
    final parts = ip.split('.');
    if (parts.length == 4) {
      targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
    }

    var errorLogged = false;
    _announceTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      final message = utf8.encode(signDiscovery?.call(body) ?? body);
      for (final target in targets) {
        try {
          final sent = _announceSocket?.send(message, target, discoveryPort);
          if (sent == 0 && !errorLogged) {
            errorLogged = true;
            _log('Discovery broadcast to ${target.address} was not sent');
          }
        } catch (e) {
          if (!errorLogged) {
            errorLogged = true;
            _log('Discovery broadcast to ${target.address} failed: $e');
          }
        }
      }
    });

    _log('Announcing WebSocket server $ip:$port to '
        '${targets.map((t) => t.address).join(', ')} on UDP:$discoveryPort');
  }

  static bool _isPrivateIPv4(String a) =>
      a.startsWith('192.168.') ||
          a.startsWith('10.') ||
          RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);

  Future<String?> _pickWifiIPv4() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      const wifiPrefixes = ['wlan', 'swlan', 'ap', 'eth', 'en'];
      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          final a = addr.address;
          if (_isPrivateIPv4(a) && wifiPrefixes.any(name.startsWith)) return a;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> stop() async {
    for (final socket in _clients.keys.toList()) {
      try {
        socket.close();
      } catch (_) {}
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;

    _announceTimer?.cancel();
    _announceTimer = null;
    _announceSocket?.close();
    _announceSocket = null;

    if (!_clientCountController.isClosed) {
      _clientCountController.add(0);
    }
    _emitClientIds();
    _log('WebSocket server stopped');
  }

  void dispose() {
    stop();
    _logController.close();
    _clientCountController.close();
    _clientIdsController.close();
    _audioController.close();
    _videoController.close();
  }

  void _log(String message) {
    if (!_logController.isClosed) {
      _logController.add(message);
    }
  }
}