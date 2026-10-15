import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'mini_mqtt_broker.dart';
import 'mini_websocket_server.dart';

@pragma('vm:entry-point')
void startBrokerTaskCallback() {
  FlutterForegroundTask.setTaskHandler(BrokerTaskHandler());
}

class BrokerTaskHandler extends TaskHandler {
  final MiniMqttBroker _mqttBroker = MiniMqttBroker();
  final MiniWebSocketServer _wsServer = MiniWebSocketServer();

  StreamSubscription<String>? _logSub;
  StreamSubscription<int>? _clientCountSub;
  StreamSubscription<List<String>>? _clientIdsSub;
  StreamSubscription<MqttAudioChunk>? _audioSub;

  int _port = 1883;
  bool _useWebSocket = false;

  bool _started = false;
  bool _starting = false; // guards against two setConfig messages racing
  String _lastLog = '';

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

    if (_useWebSocket) {
      _logSub = _wsServer.logStream.listen(_onLog);
      _clientCountSub = _wsServer.clientCountStream.listen(_onClientCount);
      _clientIdsSub = _wsServer.clientIdsStream.listen(_onClientIds);
      _audioSub = _wsServer.audioStream.listen(_onAudioChunk);
    } else {
      _logSub = _mqttBroker.logStream.listen(_onLog);
      _clientCountSub = _mqttBroker.clientCountStream.listen(_onClientCount);
      _clientIdsSub = _mqttBroker.clientIdsStream.listen(_onClientIds);
      _audioSub = _mqttBroker.audioStream.listen(_onAudioChunk);
    }
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

      if (_useWebSocket) {
        debugPrint('[BrokerTaskHandler] Starting WebSocket server on port $_port...');
        await _wsServer.start(_port);
      } else {
        debugPrint('[BrokerTaskHandler] Starting MQTT broker on port $_port...');
        await _mqttBroker.start(_port);
      }

      _started = true;
      _starting = false;

      if (_lastLog.isEmpty) {
        _lastLog = '${_useWebSocket ? 'WebSocket server' : 'MQTT broker'} listening on port $_port';
      }

      debugPrint('[BrokerTaskHandler] Started successfully on port $_port');

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
    if (_useWebSocket) {
      await _wsServer.stop();
    } else {
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

  void _sendStatus() {
    final count = _useWebSocket
        ? _wsServer.connectedClientCount
        : _mqttBroker.connectedClientCount;
    final ids = _useWebSocket
        ? _wsServer.connectedClientIds
        : _mqttBroker.connectedClientIds;

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
          ? '${_useWebSocket ? 'WebSocket' : 'MQTT'} listening on port $_port'
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
        _port = data['port'] as int? ?? (_useWebSocket ? 8080 : 1883);
        _useWebSocket = data['useWebSocket'] as bool? ?? false;

        debugPrint(
          '[BrokerTaskHandler] Config received: '
              'port=$_port, useWebSocket=$_useWebSocket',
        );

        _startBroker();
        break;

      case 'getStatus':
        _sendStatus();
        break;

      case 'sendCommand':
        final command = data['value'] as String?;
        final cmdTarget = data['target'] as String?;

        if (command != null) {
          debugPrint('[BrokerTaskHandler] Publishing command: $command');
          if (_useWebSocket) {
            _wsServer.sendString(command, targetClientId: cmdTarget);
          } else {
            _mqttBroker.publishString('esp32/cmd', command, targetClientId: cmdTarget);
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

    debugPrint('[BrokerTaskHandler] Stopped from onDestroy');
  }
}
