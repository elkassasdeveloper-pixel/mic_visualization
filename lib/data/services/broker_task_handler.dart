import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'mini_mqtt_broker.dart';

@pragma('vm:entry-point')
void startBrokerTaskCallback() {
  FlutterForegroundTask.setTaskHandler(BrokerTaskHandler());
}

class BrokerTaskHandler extends TaskHandler {
  final MiniMqttBroker _broker = MiniMqttBroker();

  StreamSubscription<String>? _logSub;
  StreamSubscription<int>? _clientCountSub;
  StreamSubscription<MqttBrokerMessage>? _messageSub;
  StreamSubscription<List<String>>? _clientIdsSub;

  int _port = 1883;
  String _colorTopic = 'esp32/led/set';

  bool _started = false;
  bool _starting = false; // guards against two setConfig messages racing

  @override
  Future<void> onStart(
      DateTime timestamp,
      TaskStarter starter,
      ) async {
    debugPrint('[BrokerTaskHandler] onStart');

    _logSub = _broker.logStream.listen((msg) {
      debugPrint('[Broker] $msg');

      FlutterForegroundTask.sendDataToMain({
        'type': 'log',
        'value': msg,
      });
    });

    _clientCountSub = _broker.clientCountStream.listen((count) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'clientCount',
        'value': count,
      });
    });

    _clientIdsSub = _broker.clientIdsStream.listen((ids) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'clients',
        'value': ids,
      });
    });

    _messageSub = _broker.messageStream.listen((msg) {
      FlutterForegroundTask.sendDataToMain({
        'type': 'message',
        'topic': msg.topic,
        'payload': msg.payload,
        'fromClientId': msg.fromClientId,
        'receivedAt': msg.receivedAt.toIso8601String(),
      });
    });

    debugPrint('[BrokerTaskHandler] Ready');

    FlutterForegroundTask.sendDataToMain({
      'type': 'ready',
    });
  }

  Future<void> _startBroker() async {
    if (_started || _starting) {
      debugPrint('[BrokerTaskHandler] Broker already started/starting');
      if (_started) _sendStatus();
      return;
    }
    _starting = true;

    try {
      debugPrint(
        '[BrokerTaskHandler] Starting broker on port $_port...',
      );

      await _broker.start(_port);

      _started = true;
      _starting = false;

      debugPrint(
        '[BrokerTaskHandler] Broker started successfully on $_port',
      );

      FlutterForegroundTask.sendDataToMain({
        'type': 'running',
        'value': true,
      });
    } catch (e, stackTrace) {
      _starting = false;
      debugPrint(
        '[BrokerTaskHandler] FAILED to start broker: $e',
      );

      debugPrint(stackTrace.toString());

      FlutterForegroundTask.sendDataToMain({
        'type': 'error',
        'value': 'Failed to start broker: $e',
      });
    }
  }

  Future<void> _stopBroker() async {
    await _broker.stop(); // also emits clientCount = 0 and an empty client list
    _started = false;
    _starting = false;

    FlutterForegroundTask.sendDataToMain({
      'type': 'running',
      'value': false,
    });
  }

  /// Reports the current broker state so a freshly opened UI can sync up.
  void _sendStatus() {
    FlutterForegroundTask.sendDataToMain({
      'type': 'running',
      'value': _started,
    });
    FlutterForegroundTask.sendDataToMain({
      'type': 'clientCount',
      'value': _broker.connectedClientCount,
    });
    FlutterForegroundTask.sendDataToMain({
      'type': 'clients',
      'value': _broker.connectedClientIds,
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
        _port = data['port'] as int? ?? 1883;
        _colorTopic =
            data['colorTopic'] as String? ?? 'esp32/led/set';

        debugPrint(
          '[BrokerTaskHandler] Config received: '
              'port=$_port, colorTopic=$_colorTopic',
        );

        // Start AFTER receiving the configuration.
        _startBroker();
        break;

      case 'getStatus':
        _sendStatus();
        break;

      case 'sendColor':
        final color = data['value'] as String?;
        // Optional MQTT client ID (e.g. "esp32-AABBCCDDEEFF"). null = all.
        final target = data['target'] as String?;

        if (color != null) {
          debugPrint(
            '[BrokerTaskHandler] Publishing color: $color',
          );

          _broker.publishString(
            _colorTopic,
            color,
            targetClientId: target,
          );
        }
        break;

      case 'sendCommand':
      // Plain-text command (e.g. "RESET") published on the same topic the
      // ESP32s subscribe to, optionally to a single client ID.
        final command = data['value'] as String?;
        final cmdTarget = data['target'] as String?;

        if (command != null) {
          debugPrint('[BrokerTaskHandler] Publishing command: $command '
              '(target: ${cmdTarget ?? 'all'})');
          _broker.publishString(
            _colorTopic,
            command,
            targetClientId: cmdTarget,
          );
        }
        break;

      case 'stop':
        debugPrint('[BrokerTaskHandler] Stop requested');

        // Close sockets and release the port first; the UI then stops the
        // service itself once this has had time to run.
        _stopBroker();
        break;

      default:
        debugPrint(
          '[BrokerTaskHandler] Unknown command: ${data['type']}',
        );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(
      DateTime timestamp,
      bool isTimeout,
      ) async {
    debugPrint(
      '[BrokerTaskHandler] onDestroy '
          '(isTimeout=$isTimeout)',
    );

    await _logSub?.cancel();
    await _clientCountSub?.cancel();
    await _messageSub?.cancel();
    await _clientIdsSub?.cancel();

    await _broker.stop();
    _broker.dispose();

    debugPrint('[BrokerTaskHandler] Broker stopped from onDestroy');
  }
}