import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';
import 'package:mic_visualization/data/services/broker_task_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class Esp32ControlScreen extends StatefulWidget {
  const Esp32ControlScreen({super.key});

  @override
  State<Esp32ControlScreen> createState() => _Esp32ControlScreenState();
}

class _Esp32ControlScreenState extends State<Esp32ControlScreen> with WidgetsBindingObserver {
  final _portController = TextEditingController(text: '1883');

  String _lastLog = '';
  int _clientCount = 0;
  bool _running = false;
  bool _useWebSocket = false;
  List<String> _localIps = [];

  final List<_TelemetryMessage> _messages = [];

  // The sketch connects with client ID "esp32-<MAC without colons>".
  static const String _clientIdPrefix = 'esp32-';
  static const String _allDevices = ''; // dropdown value for "All devices"
  List<String> _deviceMacs = []; // MACs (no colons) currently connected
  String _selectedMac = _allDevices;
  Map<String, String> _deviceNames = {}; // MAC (no colons) -> display name

  bool _serviceReady = false;
  bool _busy = false; // true while starting/stopping the service

  // ---- audio (equalizer + PCM playback) ----
  List<double> _visualizerValues = List.filled(15, 0.1);
  bool _pcmReady = false;
  Future<void>? _pcmSetup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initForegroundTask();
    _requestPermissions();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _loadSettings();
    _loadLocalIps();
    _loadDeviceNames();
    _syncRunningState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _releasePcm();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final settings = await SettingsRepository.create();
    if (mounted) {
      setState(() {
        _useWebSocket = settings.useWebSocket;
        _portController.text = _useWebSocket ? '8080' : '1883';
      });
    }
  }

  Future<void> _syncRunningState() async {
    final running = await FlutterForegroundTask.isRunningService;
    if (mounted) setState(() => _running = running);

    if (running) {
      // The service outlives this screen, so the task will not send 'ready'
      // or 'running' again. Ask it directly for its current state.
      _serviceReady = true;
      FlutterForegroundTask.sendDataToTask({'type': 'getStatus'});
    }
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'esp32_mqtt_broker',
        channelName: 'ESP32 Service',
        channelDescription: 'Keeps the server running for the ESP32 device.',
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _requestPermissions() async {
    if (!await FlutterForegroundTask.canDrawOverlays) {
      // Not required for this app (no overlay UI), skipped intentionally.
    }
    await FlutterForegroundTask.requestNotificationPermission();

    // Ignoring battery optimizations makes Android far less likely to kill
    // the service in the background. Strongly recommended for this use case.
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;

    if (data['type'] != 'audio') debugPrint('[UI] Task data: $data');

    switch (data['type']) {
      case 'ready':
        debugPrint('[UI] Foreground task is READY');

        _serviceReady = true;

        _sendBrokerConfig();
        break;

      case 'log':
        if (mounted) {
          final logValue = data['value'] as String? ?? '';
          setState(() {
            if (logValue.isNotEmpty) {
              _lastLog = logValue;
            }
          });
        }
        break;

      case 'clientCount':
        if (mounted) {
          setState(() {
            _clientCount = data['value'] as int;
          });
        }
        break;

      case 'clients':
        final ids = (data['value'] as List).cast<String>();
        final macs = ids
            .where((id) => id.startsWith(_clientIdPrefix))
            .map((id) => id.substring(_clientIdPrefix.length))
            .toList()
          ..sort();
        if (mounted) setState(() => _deviceMacs = macs);
        break;

      case 'running':
        final isRunning = data['value'] as bool;
        if (mounted) {
          setState(() {
            _running = isRunning;
          });
        }
        if (isRunning) {
          _ensurePcm();
        } else {
          _releasePcm();
        }
        break;

      case 'error':
        debugPrint('[UI] Broker error: ${data['value']}');

        if (mounted) {
          setState(() {
            _running = false;
            _lastLog = data['value'].toString();
          });
        }
        break;

      case 'message':
        final msg = _TelemetryMessage(
          topic: data['topic'] as String? ?? 'esp32/telemetry',
          payload: data['payload'] as String? ?? '',
          fromClientId: data['fromClientId'] as String? ?? '',
          receivedAt: DateTime.parse(
            data['receivedAt'] as String? ?? DateTime.now().toIso8601String(),
          ),
        );

        if (mounted) {
          setState(() {
            _messages.insert(0, msg);
          });
        }
        break;

      case 'audio':
        _handleAudio((data['value'] as List).cast<int>());
        break;
    }
  }

  // ---- audio: PCM playback + equalizer ------------------------------------

  Future<void> _ensurePcm() async {
    if (_pcmReady) return;
    final setup = _pcmSetup ??= () async {
      try {
        await FlutterPcmSound.setup(sampleRate: 16000, channelCount: 1);
        FlutterPcmSound.start();
        _pcmReady = true;
      } finally {
        _pcmSetup = null;
      }
    }();
    await setup;
  }

  void _releasePcm() {
    if (!_pcmReady) return;
    _pcmReady = false;
    FlutterPcmSound.release();
  }

  Future<void> _handleAudio(List<int> bytes) async {
    if (bytes.length < 2 || bytes.length % 2 != 0) return;

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    final samples = <int>[
      for (var i = 0; i < bytes.length; i += 2)
        byteData.getInt16(i, Endian.little),
    ];

    _updateEqualizerUI(samples);

    try {
      await _ensurePcm();
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(samples));
    } catch (e) {
      debugPrint('[UI] PCM feed failed: $e');
    }
  }

  void _updateEqualizerUI(List<int> rawPcmData) {
    if (!mounted) return;

    // Group the PCM data into bars and use each group's RMS as its height.
    final int barCount = _visualizerValues.length;
    final int chunkSize = (rawPcmData.length / barCount).floor();
    if (chunkSize <= 0) return;

    final List<double> newBarHeights = [];

    for (int i = 0; i < barCount; i++) {
      double sum = 0.0;
      final int startIdx = i * chunkSize;

      for (int j = 0; j < chunkSize; j++) {
        final double normalizedSample = rawPcmData[startIdx + j].abs() / 32767.0;
        sum += normalizedSample * normalizedSample;
      }

      final double rms = math.sqrt(sum / chunkSize);

      // Add some motion on top of the real signal amplitude.
      final double variation =
          math.sin(DateTime.now().millisecondsSinceEpoch * 0.005 + i) * 0.3;
      newBarHeights.add((rms + variation).clamp(0.05, 1.0));
    }

    setState(() => _visualizerValues = newBarHeights);
  }

  Future<void> _sendBrokerConfig() async {
    if (!_serviceReady) {
      debugPrint('[UI] Task is not ready yet');
      return;
    }

    final defaultPort = _useWebSocket ? 8080 : 1883;
    final port =
        int.tryParse(_portController.text.trim()) ?? defaultPort;

    debugPrint('[UI] Sending broker configuration...');
    debugPrint('[UI] port=$port, useWebSocket=$_useWebSocket');

    FlutterForegroundTask.sendDataToTask({
      'type': 'setConfig',
      'port': port,
      'useWebSocket': _useWebSocket,
    });

    FlutterForegroundTask.sendDataToTask({
      'type': 'sendCommand',
      'value': _useWebSocket ? 'USE_WEBSOCKET:1' : 'USE_WEBSOCKET:0',
    });

    debugPrint('[UI] Configuration sent');
  }

  Future<void> _loadLocalIps() async {
    final networkInfo = NetworkInfo();
    final ip = await networkInfo.getWifiIP();
    if (mounted && ip != null) setState(() => _localIps = [ip]);
  }

  Future<void> _toggleBroker() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _toggleBrokerImpl();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleBrokerImpl() async {
    if (_running) {
      debugPrint('[UI] Stopping broker...');
      _releasePcm();

      // 1) Ask the task to close its sockets and free the port.
      FlutterForegroundTask.sendDataToTask({
        'type': 'stop',
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // 2) Stop the Android service.
      final result = await FlutterForegroundTask.stopService();
      debugPrint('[UI] stopService result: $result');

      for (var i = 0; i < 25; i++) {
        if (!await FlutterForegroundTask.isRunningService) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        setState(() {
          _running = false;
          _clientCount = 0;
          _deviceMacs = [];
          _visualizerValues = List.filled(15, 0.1);
          _lastLog = 'Server stopped';
        });
      }
      return;
    }

    final defaultPort = _useWebSocket ? 8080 : 1883;
    final port =
        int.tryParse(_portController.text.trim()) ?? defaultPort;

    if (mounted) {
      setState(() {
        _lastLog = 'Starting ${_useWebSocket ? 'WebSocket' : 'MQTT'} server...';
      });
    }

    final settings = await SettingsRepository.create();
    await settings.setUseWebSocket(_useWebSocket);

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'ESP32 Audio Service',
        notificationText: 'Starting server on port $port...',
        callback: startBrokerTaskCallback,
      );

      debugPrint('[UI] startService result: $result');

      if (result is ServiceRequestFailure) {
        debugPrint('[UI] Service failed: ${result.error}');

        if (result.error.toString().contains('ServiceAlreadyStarted')) {
          _serviceReady = true;
          await _sendBrokerConfig();
          FlutterForegroundTask.sendDataToTask({'type': 'getStatus'});

          for (var i = 0; i < 15 && !_running && mounted; i++) {
            await Future.delayed(const Duration(milliseconds: 200));
          }

          if (mounted && !_running) {
            await FlutterForegroundTask.stopService();
            setState(() {
              _lastLog = 'Service was not responding and was stopped - '
                  'tap Start again';
            });
          }
          return;
        }

        if (mounted) {
          setState(() {
            _running = false;
          });
        }

        return;
      }

      if (mounted) setState(() => _running = true);
      FlutterForegroundTask.sendDataToTask({
        'type': 'setConfig',
        'port': port,
        'useWebSocket': _useWebSocket,
      });

      FlutterForegroundTask.sendDataToTask({
        'type': 'sendCommand',
        'value': _useWebSocket ? 'USE_WEBSOCKET:1' : 'USE_WEBSOCKET:0',
      });

      debugPrint('[UI] Configuration sent to server task');
    } catch (e, stackTrace) {
      debugPrint('[UI] startService FAILED: $e');
      debugPrint(stackTrace.toString());

      setState(() {
        _running = false;
      });
    }
  }

  String _formatMac(String mac) {
    if (mac.length != 12) return mac;
    return [for (var i = 0; i < 12; i += 2) mac.substring(i, i + 2)].join(':');
  }

  // ---- device names (value = MAC, label = friendly name) -----------------

  Future<void> _loadDeviceNames() async {
    final raw = await FlutterForegroundTask.getData<String>(key: 'deviceNames');
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _deviceNames = map.map((k, v) => MapEntry(k, v.toString()));
        });
      }
    } catch (_) {}
  }

  Future<void> _saveDeviceNames() async {
    await FlutterForegroundTask.saveData(
      key: 'deviceNames',
      value: jsonEncode(_deviceNames),
    );
  }

  /// Friendly name for a MAC. Falls back to "Mic XXXX" (last 4 hex digits)
  /// until the user gives the device a name.
  String _deviceLabel(String mac) {
    final custom = _deviceNames[mac];
    if (custom != null && custom.isNotEmpty) return custom;
    final tail = mac.length >= 4 ? mac.substring(mac.length - 4) : mac;
    return 'Mic $tail';
  }

  /// Label for an MQTT client id such as "esp32-AABBCCDDEEFF".
  String _clientLabel(String clientId) {
    if (clientId.startsWith(_clientIdPrefix)) {
      return _deviceLabel(clientId.substring(_clientIdPrefix.length));
    }
    return clientId;
  }

  Future<void> _renameSelectedDevice() async {
    final mac = _selectedMac;
    if (mac == _allDevices) return;

    final controller = TextEditingController(text: _deviceNames[mac] ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Name for ${_formatMac(mac)}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            hintText: _deviceLabel(mac),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || !mounted) return; // cancelled
    setState(() {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        _deviceNames.remove(mac); // back to the default "Mic XXXX"
      } else {
        _deviceNames[mac] = trimmed;
      }
    });
    await _saveDeviceNames();
  }

  Widget _buildDeviceSelector() {
    // Keep the selected device in the list even if it goes offline, so the
    // dropdown never ends up with a value that has no matching item.
    final macs = {
      ..._deviceMacs,
      if (_selectedMac != _allDevices) _selectedMac,
    }.toList()
      ..sort((a, b) =>
          _deviceLabel(a).toLowerCase().compareTo(_deviceLabel(b).toLowerCase()));
    final values = <String>[_allDevices, ...macs];

    String macLine(String mac) => _deviceMacs.contains(mac)
        ? _formatMac(mac)
        : '${_formatMac(mac)} (offline)';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Target device',
              helperText: _deviceMacs.isEmpty
                  ? 'No ESP32 connected yet'
                  : 'Telemetry is limited to the selected device',
              border: const OutlineInputBorder(),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _selectedMac,
                onChanged: _running
                    ? (value) =>
                    setState(() => _selectedMac = value ?? _allDevices)
                    : null,
                // What the closed dropdown shows (single line).
                selectedItemBuilder: (context) => [
                  for (final v in values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        v == _allDevices
                            ? 'All devices'
                            : '${_deviceLabel(v)}  ·  ${_formatMac(v)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                // What the open list shows: name + MAC underneath.
                items: [
                  for (final v in values)
                    DropdownMenuItem<String>(
                      value: v, // the MAC (no colons); '' = all devices
                      child: v == _allDevices
                          ? const Text('All devices')
                          : Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_deviceLabel(v),
                              overflow: TextOverflow.ellipsis),
                          Text(
                            macLine(v),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename selected device',
            onPressed:
            _selectedMac == _allDevices ? null : _renameSelectedDevice,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages = _selectedMac == _allDevices
        ? _messages
        : _messages
        .where((m) => m.fromClientId == '$_clientIdPrefix$_selectedMac')
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('ESP32 Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi),
            tooltip: 'WiFi Setup (SmartConfig)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SmartConfigScreen(
                    targetMac: _selectedMac,
                    targetName: _selectedMac == _allDevices
                        ? ''
                        : _deviceLabel(_selectedMac),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBrokerCard(_running),
            const SizedBox(height: 12),
            Text('Status: ${_lastLog.isEmpty ? (_running ? "Server running" : "Server stopped") : _lastLog}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            _buildDeviceSelector(),
            const SizedBox(height: 24),
            Text('Telemetry', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (visibleMessages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No messages received yet'),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleMessages.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final msg = visibleMessages[index];
                  return ListTile(
                    dense: true,
                    title: Text(msg.payload, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text(
                        '${msg.topic} (${_clientLabel(msg.fromClientId)}) · ${msg.receivedAt.toIso8601String()}'),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrokerCard(bool running) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('This phone\'s IP address(es):', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            if (_localIps.isEmpty)
              const Text('Looking up...')
            else
              ..._localIps.map((ip) => Text(ip)),
            const SizedBox(height: 4),
            const Text(
              'The service keeps running in the background (even if you swipe the app '
                  'away) thanks to the persistent notification - do not force-stop the app '
                  'from Android settings.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portController,
              enabled: !running,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_useWebSocket ? 'Protocol: WebSocket' : 'Protocol: MQTT'),
              subtitle: Text(
                _useWebSocket
                    ? 'ESP32 connects via WebSocket (ws://)'
                    : 'ESP32 connects via MQTT broker',
              ),
              value: _useWebSocket,
              onChanged: running
                  ? null
                  : (value) async {
                      setState(() {
                        _useWebSocket = value;
                        _portController.text = value ? '8080' : '1883';
                      });
                      final settings = await SettingsRepository.create();
                      await settings.setUseWebSocket(value);
                    },
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _toggleBroker,
              child: Text(running ? 'Stop Server' : 'Start Server'),
            ),
            const SizedBox(height: 4),
            Text('Connected clients: $_clientCount'),
            // Equalizer
            Container(
              height: 200,
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: CustomPaint(
                painter: EqualizerPainter(barHeights: _visualizerValues),
                child: Container(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryMessage {
  final String topic;
  final String payload;
  final String fromClientId;
  final DateTime receivedAt;

  _TelemetryMessage({
    required this.topic,
    required this.payload,
    required this.fromClientId,
    required this.receivedAt,
  });
}

// ---------------- SmartConfig screen ----------------

class SmartConfigScreen extends StatefulWidget {
  /// MAC (no colons) of the device chosen in the dropdown on the previous
  /// screen. Empty string means "all devices".
  final String targetMac;

  /// Friendly name of that device (empty when targeting all devices).
  final String targetName;

  const SmartConfigScreen({super.key, this.targetMac = '', this.targetName = ''});

  @override
  State<SmartConfigScreen> createState() => _SmartConfigScreenState();
}

class _SmartConfigScreenState extends State<SmartConfigScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController(text: "SayedNimer@2021@1442");
  final _networkInfo = NetworkInfo();

  Provisioner? _provisioner;
  bool _isProvisioning = false;
  String _status = 'Idle';
  final List<String> _connectedDevices = [];

  @override
  void initState() {
    super.initState();
    _prefillCurrentWifi();
  }

  @override
  void dispose() {
    _provisioner?.stop();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _prefillCurrentWifi() async {
    await Permission.locationWhenInUse.request();
    try {
      final ssid = await _networkInfo.getWifiName();
      if (ssid != null) {
        _ssidController.text = ssid.replaceAll('"', '');
      }else {
        _ssidController.text = "EngSayedNimer";
      }
    } catch (_) {
      _ssidController.text = "EngSayedNimer";
    }
  }

  Future<void> _startProvisioning() async {
    if (_ssidController.text.isEmpty) {
      setState(() => _status = 'Enter the WiFi SSID first');
      return;
    }

    setState(() {
      _isProvisioning = true;
      _status = 'Starting SmartConfig...';
      _connectedDevices.clear();
    });

    String? bssid;
    try {
      bssid = await _networkInfo.getWifiBSSID();
    } catch (_) {
      bssid = null;
    }

    final provisioner = Provisioner.espTouch();
    _provisioner = provisioner;

    provisioner.listen((response) {
      setState(() {
        _connectedDevices.add(response.bssidText);
        _status = 'Device connected: ${response.bssidText}';
      });
    });

    try {
      await provisioner.start(ProvisioningRequest.fromStrings(
        ssid: _ssidController.text,
        bssid: bssid ?? '',
        password: _passwordController.text,
      ));

      setState(() => _status = 'Broadcasting credentials...');
      await Future.delayed(const Duration(seconds: 30));
    } catch (e) {
      setState(() => _status = 'Error: $e');
    } finally {
      provisioner.stop();
      setState(() {
        _isProvisioning = false;
        if (_connectedDevices.isEmpty && _status != 'Error') {
          _status = 'Finished - no devices confirmed connection';
        }
      });
    }
  }

  Future<void> _resetDeviceWifi() async {
    final target =
    widget.targetMac.isEmpty ? null : 'esp32-${widget.targetMac}';
    final label = target == null
        ? 'ALL connected devices'
        : '${widget.targetName} (${_prettyMac(widget.targetMac)})';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset WiFi?'),
        content: Text(
          'This erases the saved WiFi credentials on $label and restarts '
              '${target == null ? 'them' : 'it'}. The device(s) will wait for '
              'SmartConfig provisioning again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // The command travels through the broker, so it must be running.
    if (!await FlutterForegroundTask.isRunningService) {
      if (mounted) {
        setState(() => _status = 'Start the broker first - reset is sent through it');
      }
      return;
    }

    FlutterForegroundTask.sendDataToTask({
      'type': 'sendCommand',
      'value': 'RESET',
      'target': target,
    });

    if (mounted) {
      setState(() => _status = 'Reset sent to $label');
    }
  }

  void _stopProvisioning() {
    _provisioner?.stop();
    setState(() {
      _isProvisioning = false;
      _status = 'Stopped';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi Setup (SmartConfig)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _ssidController,
                decoration: const InputDecoration(labelText: 'WiFi SSID', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'WiFi Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: !_isProvisioning
                        ? ElevatedButton(
                      onPressed: _startProvisioning,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Start Provisioning'),
                      ),
                    )
                        : ElevatedButton(
                      onPressed: _stopProvisioning,
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Stop'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProvisioning ? null : _resetDeviceWifi,
                      icon: const Icon(Icons.restart_alt),
                      label: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Reset WiFi'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_isProvisioning) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(_status, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 16),
              if (_connectedDevices.isNotEmpty) ...[
                const Text('Connected devices:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,                        // size to its content
                  physics: const NeverScrollableScrollPhysics(), // the outer view scrolls
                  itemCount: _connectedDevices.length,
                  itemBuilder: (context, index) => ListTile(
                    leading: const Icon(Icons.check_circle, color: Colors.green),
                    title: Text(_connectedDevices[index]),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _prettyMac(String mac) {
  if (mac.length != 12) return mac;
  return [for (var i = 0; i < 12; i += 2) mac.substring(i, i + 2)].join(':');
}

// Custom painter that renders the equalizer bars.
class EqualizerPainter extends CustomPainter {
  final List<double> barHeights;

  EqualizerPainter({required this.barHeights});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.cyanAccent, Colors.blueAccent, Colors.purpleAccent],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    const double spacing = 6.0;
    final double totalSpacing = spacing * (barHeights.length - 1);
    final double barWidth = (size.width - totalSpacing) / barHeights.length;

    for (int i = 0; i < barHeights.length; i++) {
      final double x = i * (barWidth + spacing);
      final double barHeight = barHeights[i] * size.height;
      final double y = size.height - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(4.0),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant EqualizerPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights;
  }
}
