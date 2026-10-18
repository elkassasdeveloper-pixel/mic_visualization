import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mic_visualization/data/models/esp_transport.dart';

import 'ble_audio_client.dart';
import 'mini_mqtt_broker.dart';
import 'mini_websocket_server.dart';

@pragma('vm:entry-point')
void startBrokerTaskCallback() {
  FlutterForegroundTask.setTaskHandler(BrokerTaskHandler());
}

class BrokerTaskHandler extends TaskHandler {
  final MiniMqttBroker _mqttBroker = MiniMqttBroker();
  final MiniWebSocketServer _wsServer = MiniWebSocketServer();
  final BleAudioClient _bleClient = BleAudioClient();

  StreamSubscription<String>? _logSub;
  StreamSubscription<int>? _clientCountSub;
  StreamSubscription<List<String>>? _clientIdsSub;
  StreamSubscription<MqttAudioChunk>? _audioSub;

  int _port = 1883;
  EspTransport _transport = EspTransport.mqtt;

  bool _started = false;
  bool _starting = false; // guards against two setConfig messages racing
  String _lastLog = '';

  String get _transportName => switch (_transport) {
    EspTransport.mqtt => 'MQTT broker',
    EspTransport.websocket => 'WebSocket server',
    EspTransport.bluetooth => 'Bluetooth',
  };

  @override
  Future<void> onStart(
      DateTime timestamp,
      TaskStarter starter,
      ) async {
    debugPrint('[BrokerTaskHandler] onStart');

    _setupSubscriptions();

    debugPrint('[BrokerTaskHandler] Ready');

    FlutterForegroundTask.sendDataToMain({
      'type': 'ready',
    });
  }

  void _setupSubscriptions() {
    _cancelSubscriptions();

    switch (_transport) {
      case EspTransport.websocket:
        _bind(_wsServer.logStream, _wsServer.clientCountStream,
            _wsServer.clientIdsStream, _wsServer.audioStream);
      case EspTransport.bluetooth:
        _bind(_bleClient.logStream, _bleClient.clientCountStream,
            _bleClient.clientIdsStream, _bleClient.audioStream);
      case EspTransport.mqtt:
        _bind(_mqttBroker.logStream, _mqttBroker.clientCountStream,
            _mqttBroker.clientIdsStream, _mqttBroker.audioStream);
    }
  }

  void _bind(
      Stream<String> log,
      Stream<int> count,
      Stream<List<String>> ids,
      Stream<MqttAudioChunk> audio,
      ) {
    _logSub = log.listen(_onLog);
    _clientCountSub = count.listen(_onClientCount);
    _clientIdsSub = ids.listen(_onClientIds);
    _audioSub = audio.listen(_onAudioChunk);
  }

  void _cancelSubscriptions() {
    _logSub?.cancel();
    _clientCountSub?.cancel();
    _clientIdsSub?.cancel();
    _audioSub?.cancel();
  }

  void _onLog(String msg) {
    debugPrint('[Server Log] $msg');
    _lastLog = msg;
    FlutterForegroundTask.sendDataToMain({
      'type': 'log',
      'value': msg,
    });
  }

  void _onClientCount(int count) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'clientCount',
      'value': count,
    });
  }

  void _onClientIds(List<String> ids) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'clients',
      'value': ids,
    });
  }

  void _onAudioChunk(MqttAudioChunk chunk) {
    FlutterForegroundTask.sendDataToMain({
      'type': 'audio',
      'value': chunk.payload,
      'clientId': chunk.clientId,
    });
  }

  Future<void> _startBroker() async {
    if (_started || _starting) {
      debugPrint('[BrokerTaskHandler] Server already started/starting');
      if (_started) _sendStatus();
      return;
    }
    _starting = true;

    try {
      _setupSubscriptions();

      switch (_transport) {
        case EspTransport.websocket:
          debugPrint('[BrokerTaskHandler] Starting WebSocket server on port $_port...');
          await _wsServer.start(_port);
        case EspTransport.bluetooth:
          debugPrint('[BrokerTaskHandler] Starting Bluetooth scan...');
          await _bleClient.start();
        case EspTransport.mqtt:
          debugPrint('[BrokerTaskHandler] Starting MQTT broker on port $_port...');
          await _mqttBroker.start(_port);
      }

      _started = true;
      _starting = false;

      if (_lastLog.isEmpty) {
        _lastLog = _transport.usesPort
            ? '$_transportName listening on port $_port'
            : 'Bluetooth scanning for ESP32 devices';
      }

      debugPrint('[BrokerTaskHandler] Started successfully ($_transportName)');

      _sendStatus();
    } catch (e, stackTrace) {
      _starting = false;
      debugPrint('[BrokerTaskHandler] FAILED to start server: $e');
      debugPrint(stackTrace.toString());

      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'value': 'Failed to start server: $e',
      });
    }
  }

  Future<void> _stopBroker() async {
    switch (_transport) {
      case EspTransport.websocket:
        await _wsServer.stop();
      case EspTransport.bluetooth:
        await _bleClient.stop();
      case EspTransport.mqtt:
        await _mqttBroker.stop();
    }
    _started = false;
    _starting = false;
    _lastLog = 'Server stopped';

    FlutterForegroundTask.sendDataToMain({
      'type': 'running',
      'value': false,
    });
    FlutterForegroundTask.sendDataToMain({
      'type': 'log',
      'value': _lastLog,
    });
  }

  /// Applies a new transport/port. If a server is already running with a
  /// different configuration it is stopped first, then started again.
  Future<void> _applyConfig(EspTransport next, int port) async {
    final changed = next != _transport || port != _port;
    if (_started && changed) {
      await _stopBroker(); // stops the OLD transport
      _lastLog = '';
    }
    _transport = next;
    _port = port;
    await _startBroker();
  }

  void _sendStatus() {
    final int count;
    final List<String> ids;
    switch (_transport) {
      case EspTransport.websocket:
        count = _wsServer.connectedClientCount;
        ids = _wsServer.connectedClientIds;
      case EspTransport.bluetooth:
        count = _bleClient.connectedClientCount;
        ids = _bleClient.connectedClientIds;
      case EspTransport.mqtt:
        count = _mqttBroker.connectedClientCount;
        ids = _mqttBroker.connectedClientIds;
    }

    FlutterForegroundTask.sendDataToMain({
      'type': 'running',
      'value': _started,
    });
    FlutterForegroundTask.sendDataToMain({
      'type': 'clientCount',
      'value': count,
    });
    FlutterForegroundTask.sendDataToMain({
      'type': 'clients',
      'value': ids,
    });
    FlutterForegroundTask.sendDataToMain({
      'type': 'log',
      'value': _lastLog.isNotEmpty
          ? _lastLog
          : (_started
          ? (_transport.usesPort
          ? '$_transportName listening on port $_port'
          : 'Bluetooth scanning for ESP32 devices')
          : 'Server stopped'),
    });
  }

  @override
  void onReceiveData(Object data) {
    debugPrint('[BrokerTaskHandler] Received: $data');

    if (data is! Map) {
      debugPrint('[BrokerTaskHandler] Invalid data type');
      return;
    }

    switch (data['type']) {
      case 'setConfig':
      // New messages carry 'transport'; older callers only send 'useWebSocket'.
        final next = data['transport'] is String
            ? EspTransport.fromId(data['transport'] as String)
            : ((data['useWebSocket'] as bool? ?? false)
            ? EspTransport.websocket
            : EspTransport.mqtt);
        final port = data['port'] as int? ?? next.defaultPort;

        debugPrint(
          '[BrokerTaskHandler] Config received: '
              'transport=${next.id}, port=$port',
        );

        _applyConfig(next, port);
        break;

      case 'getStatus':
        _sendStatus();
        break;

      case 'sendCommand':
        final command = data['value'] as String?;
        final cmdTarget = data['target'] as String?;

        if (command != null) {
          debugPrint('[BrokerTaskHandler] Sending command: $command');
          switch (_transport) {
            case EspTransport.websocket:
              _wsServer.sendString(command, targetClientId: cmdTarget);
            case EspTransport.bluetooth:
              _bleClient.sendString(command, targetClientId: cmdTarget);
            case EspTransport.mqtt:
              _mqttBroker.publishString('esp32/cmd', command,
                  targetClientId: cmdTarget);
          }
        }
        break;

      case 'stop':
        debugPrint('[BrokerTaskHandler] Stop requested');
        _stopBroker();
        break;

      default:
        debugPrint('[BrokerTaskHandler] Unknown command: ${data['type']}');
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(
      DateTime timestamp,
      bool isTimeout,
      ) async {
    debugPrint('[BrokerTaskHandler] onDestroy');

    _cancelSubscriptions();
    await _mqttBroker.stop();
    _mqttBroker.dispose();
    await _wsServer.stop();
    _wsServer.dispose();
    await _bleClient.stop();
    _bleClient.dispose();

    debugPrint('[BrokerTaskHandler] Stopped from onDestroy');
  }
}