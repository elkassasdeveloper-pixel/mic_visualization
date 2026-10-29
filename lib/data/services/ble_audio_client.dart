import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:hodhd_visualization/data/security/secure_channel.dart';

import 'mini_mqtt_broker.dart' show MqttAudioChunk;

/// G.711 u-law -> 16-bit PCM lookup table.
final Int16List _ulawTable = () {
  final t = Int16List(256);
  for (var i = 0; i < 256; i++) {
    final u = ~i & 0xFF;
    final exp = (u >> 4) & 0x07;
    final mant = u & 0x0F;
    final s = (((mant << 3) + 0x84) << exp) - 0x84;
    t[i] = (u & 0x80) != 0 ? -s : s;
  }
  return t;
}();

class _Peer {
  _Peer(this.clientId, this.device, this.rx);

  final String clientId;
  final BluetoothDevice device;
  final BluetoothCharacteristic rx;
  StreamSubscription<dynamic>? connSub;
  StreamSubscription<dynamic>? audioSub;
  StreamSubscription<dynamic>? videoSub;

  // Camera frame reassembly: each notification is [frameId][index][count] + data.
  final BytesBuilder vid = BytesBuilder(copy: false);
  int vidFrame = -1;
  int vidNext = 0;

  final BytesBuilder pcm = BytesBuilder(copy: false);
  bool primed = false;
  DateTime? lastAudio;
}

/// Bluetooth LE counterpart of [MiniMqttBroker] / [MiniWebSocketServer]:
/// same streams, same chunk type, so [BrokerTaskHandler] can treat all
/// transports alike. The phone is the BLE *central*: it scans for ESP32s
/// advertising the audio service, connects to them, and forwards their audio
/// as 16-bit little-endian PCM at 16 kHz (what the rest of the app expects).
class BleAudioClient {
  static final Guid serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid rxUuid = Guid('6e400002-b5a3-f393-e0a9-e50e24dcca9e'); // commands
  static final Guid audioUuid = Guid('6e400004-b5a3-f393-e0a9-e50e24dcca9e'); // u-law audio
  static final Guid idUuid = Guid('6e400005-b5a3-f393-e0a9-e50e24dcca9e'); // "esp32-<MAC>"
  static final Guid videoUuid = Guid('6e400006-b5a3-f393-e0a9-e50e24dcca9e'); // camera frame fragments

  // Playback jitter buffer: first chunk after ~200 ms, then ~100 ms chunks.
  static const int _firstEmitBytes = 6400;
  static const int _emitBytes = 3200;

  final Map<String, _Peer> _peers = {};
  final Map<String, DateTime> _lastAttempt = {};
  final Set<String> _seen = {};
  bool _connecting = false;
  bool _running = false;

  /// Set by the task handler when a master key is configured.
  SecureChannel? channel;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _watchdog;

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

  /// Complete camera frames (JPEG), reassembled from notifications.
  Stream<MqttAudioChunk> get videoStream => _videoController.stream;

  int get connectedClientCount => _peers.length;
  List<String> get connectedClientIds =>
      (_peers.values.map((p) => p.clientId).toList()..sort());
  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    if (!await FlutterBluePlus.isSupported) {
      throw StateError('Bluetooth LE is not supported on this device');
    }
    _running = true;
    try {
      // In a fresh isolate the adapter state starts as "unknown" for a moment,
      // so wait for a real value before deciding Bluetooth is off.
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () => BluetoothAdapterState.unknown,
      );
      _log('Bluetooth adapter state: ${state.name}');
      if (state != BluetoothAdapterState.on) {
        _log('Bluetooth is off - turn it on to continue');
        await FlutterBluePlus.adapterState
            .where((s) => s == BluetoothAdapterState.on)
            .first
            .timeout(const Duration(seconds: 30));
      }

      _scanSub = FlutterBluePlus.onScanResults.listen(
        _onScanResults,
        onError: (Object e) => _log('Scan error: $e'),
      );
      await _startScan();

      // Android silently ends scans now and then; keep one running.
      _watchdog = Timer.periodic(const Duration(seconds: 15), (_) {
        if (_running && !FlutterBluePlus.isScanningNow) _startScan();
      });
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  Future<void> _startScan() async {
    try {
      // No hardware service-UUID filter: many phones only match it against the
      // advertising packet, not the scan response, and would miss the ESP32.
      // We filter by name / service UUID in _onScanResults instead.
      await FlutterBluePlus.startScan(
        continuousUpdates: true, // re-report devices that start advertising again
        androidScanMode: AndroidScanMode.balanced,
      );
      _log('Scanning for ESP32 devices over Bluetooth...');
    } catch (e) {
      _log('Could not start Bluetooth scan: $e');
    }
  }

  void _onScanResults(List<ScanResult> results) {
    if (!_running || _connecting) return;
    for (final r in results) {
      final key = r.device.remoteId.str;
      final name = r.advertisementData.advName.isNotEmpty
          ? r.advertisementData.advName
          : r.device.platformName;
      final isOurs = name.startsWith('esp32-') ||
          r.advertisementData.serviceUuids.contains(serviceUuid);
      if (!isOurs) continue;
      if (_seen.add(key)) _log('Found $name (${r.rssi} dBm)');
      if (_peers.containsKey(key)) continue;
      final last = _lastAttempt[key];
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 3)) {
        continue;
      }
      _connect(r); // one connection attempt at a time
      break;
    }
  }

  Future<void> _connect(ScanResult r) async {
    _connecting = true;
    final device = r.device;
    final key = device.remoteId.str;
    _lastAttempt[key] = DateTime.now();

    // The firmware advertises its name as "esp32-<MAC>", the same id it uses
    // for MQTT/WebSocket, so a mic keeps its identity across transports.
    final advName = r.advertisementData.advName;
    var clientId = advName.startsWith('esp32-') ? advName : '';

    try {
      _log('Connecting to ${advName.isNotEmpty ? advName : key}...');
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        mtu: 247,
      );
      if (Platform.isAndroid) {
        // iOS chooses the connection interval itself (this call is Android-only).
        await device.requestConnectionPriority(
            connectionPriorityRequest: ConnectionPriority.high);
      }

      final services = await device.discoverServices();
      final svc = services.firstWhere((s) => s.uuid == serviceUuid);
      final rx = svc.characteristics.firstWhere((c) => c.uuid == rxUuid);
      final audio = svc.characteristics.firstWhere((c) => c.uuid == audioUuid);

      // iOS often delivers no name in the scan result and uses a random UUID
      // as remoteId, so ask the device for its real id.
      clientId = await _resolveClientId(device, svc, clientId, key);

      final peer = _Peer(clientId, device, rx);
      peer.connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _drop(key);
      });

      await audio.setNotifyValue(true);
      peer.audioSub = audio.onValueReceived.listen((d) => _onAudio(peer, d));

      // Camera is optional: only devices with a camera expose this characteristic.
      final videoChars = svc.characteristics.where((c) => c.uuid == videoUuid).toList();
      if (videoChars.isNotEmpty) {
        await videoChars.first.setNotifyValue(true);
        peer.videoSub = videoChars.first.onValueReceived.listen((d) => _onVideo(peer, d));
      }

      _peers[key] = peer;
      _emitClients();
      _log('Bluetooth device connected: $clientId');

      // The firmware only streams after this command.
      final ch = channel;
      await rx.write(ch != null
          ? ch.encryptCommand(clientId, 'AUDIO:START')
          : utf8.encode('AUDIO:START'));
    } catch (e) {
      _log('Bluetooth connect failed ($clientId): $e');
      try {
        await device.disconnect();
      } catch (_) {}
      _drop(key);
    } finally {
      _connecting = false;
    }
  }

  /// "esp32-<MAC": from the id characteristic, else the advertised name,
  /// else the connected device name, else (last resort) the remote id.
  Future<String> _resolveClientId(
      BluetoothDevice device,
      BluetoothService svc,
      String known,
      String key,
      ) async {
    for (final c in svc.characteristics) {
      if (c.uuid != idUuid) continue;
      try {
        final text = utf8.decode(await c.read()).trim();
        if (text.startsWith('esp32-')) return text;
      } catch (_) {}
    }
    if (known.startsWith('esp32-')) return known;
    final name = device.platformName;
    if (name.startsWith('esp32-')) return name;
    return 'esp32-${key.replaceAll(':', '').replaceAll('-', '').toUpperCase()}';
  }

  void _drop(String key) {
    final peer = _peers.remove(key);
    if (peer == null) return;
    peer.connSub?.cancel();
    peer.audioSub?.cancel();
    peer.videoSub?.cancel();
    _log('Bluetooth device disconnected: ${peer.clientId}');
    _emitClients();
  }

  void _onAudio(_Peer p, List<int> data) {
    if (data.isEmpty) return;

    // Decrypt first; drop anything that is not authentic.
    List<int> audio = data;
    final ch = channel;
    if (ch != null) {
      final plain = ch.decryptUplink(p.clientId, data);
      if (plain == null) return;
      audio = plain;
    }

    // After a pause, start a fresh jitter buffer.
    final now = DateTime.now();
    if (p.lastAudio != null &&
        now.difference(p.lastAudio!) > const Duration(milliseconds: 500)) {
      p.primed = false;
      p.pcm.clear();
    }
    p.lastAudio = now;

    // u-law bytes -> int16 little-endian bytes
    final out = Uint8List(audio.length * 2);
    final bd = ByteData.sublistView(out);
    for (var i = 0; i < audio.length; i++) {
      bd.setInt16(i * 2, _ulawTable[audio[i]], Endian.little);
    }
    p.pcm.add(out);

    final threshold = p.primed ? _emitBytes : _firstEmitBytes;
    if (p.pcm.length >= threshold && !_audioController.isClosed) {
      p.primed = true;
      _audioController
          .add(MqttAudioChunk(clientId: p.clientId, payload: p.pcm.takeBytes()));
    }
  }

  /// Puts the camera frame back together. A lost notification drops the frame.
  void _onVideo(_Peer p, List<int> d) {
    if (d.length < 4) return;
    final frameId = d[0], index = d[1], count = d[2];

    if (index == 0) {
      p.vid.clear();
      p.vidFrame = frameId;
      p.vidNext = 0;
    }
    if (frameId != p.vidFrame || index != p.vidNext) {
      p.vidFrame = -1; // gap: wait for the start of the next frame
      return;
    }
    p.vid.add(d.sublist(3));
    p.vidNext++;
    if (p.vidNext < count) return;

    final frame = p.vid.takeBytes();
    p.vidFrame = -1;

    var payload = frame;
    final ch = channel;
    if (ch != null) {
      final plain = ch.decryptVideo(p.clientId, frame);
      if (plain == null) return;
      payload = plain;
    }
    if (!_videoController.isClosed) {
      _videoController.add(MqttAudioChunk(clientId: p.clientId, payload: payload));
    }
  }

  /// Writes an already-encrypted command packet.
  void sendBytes(List<int> payload, {String? targetClientId}) {
    for (final p in _peers.values.toList()) {
      if (targetClientId != null && p.clientId != targetClientId) continue;
      p.rx.write(payload).catchError((Object e) {
        _log('Error sending to ${p.clientId}: $e');
      });
    }
  }

  /// Writes a command to the connected ESP32(s), like publishing on esp32/cmd.
  void sendString(String payload, {String? targetClientId}) {
    for (final p in _peers.values.toList()) {
      if (targetClientId != null && p.clientId != targetClientId) continue;
      p.rx.write(utf8.encode(payload)).catchError((Object e) {
        _log('Error sending to ${p.clientId}: $e');
      });
    }
  }

  void _emitClients() {
    if (!_clientCountController.isClosed) {
      _clientCountController.add(_peers.length);
    }
    if (!_clientIdsController.isClosed) {
      _clientIdsController.add(connectedClientIds);
    }
  }

  Future<void> stop() async {
    _running = false;
    _watchdog?.cancel();
    _watchdog = null;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    for (final p in _peers.values.toList()) {
      p.connSub?.cancel();
      p.audioSub?.cancel();
      p.videoSub?.cancel();
      try {
        await p.device.disconnect();
      } catch (_) {}
    }
    _peers.clear();
    _seen.clear();
    _emitClients();
    _log('Bluetooth stopped');
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
    if (!_logController.isClosed) _logController.add(message);
  }
}