import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
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
  final _topicController = TextEditingController(text: 'esp32/led/set');

  String _lastLog = '';
  int _clientCount = 0;
  bool _running = false;
  List<String> _localIps = [];

  final List<_TelemetryMessage> _messages = [];

  // The sketch connects with client ID "esp32-<MAC without colons>".
  static const String _clientIdPrefix = 'esp32-';
  static const String _allDevices = ''; // dropdown value for "All devices"
  List<String> _deviceMacs = []; // MACs (no colons) currently connected
  String _selectedMac = _allDevices;

  bool _serviceReady = false;
  bool _busy = false; // true while starting/stopping the service

  final Map<String, Color> _colors = {
    'red': Colors.red,
    'green': Colors.green,
    'blue': Colors.blue,
    'yellow': Colors.yellow,
    'cyan': Colors.cyan,
    'magenta': Colors.pinkAccent,
    'orange': Colors.orange,
    'purple': Colors.purple,
    'white': Colors.white,
    'off': Colors.black,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initForegroundTask();
    _requestPermissions();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _loadLocalIps();
    _syncRunningState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _portController.dispose();
    _topicController.dispose();
    super.dispose();
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
        channelName: 'ESP32 MQTT Broker',
        channelDescription: 'Keeps the MQTT broker running for the ESP32 device.',
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

    debugPrint('[UI] Task data: $data');

    switch (data['type']) {
      case 'ready':
        debugPrint('[UI] Foreground task is READY');

        _serviceReady = true;

        _sendBrokerConfig();
        break;

      case 'log':
        if (mounted) {
          setState(() {
            _lastLog = data['value'] as String;
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
        if (mounted) {
          setState(() {
            _running = data['value'] as bool;
          });
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
          topic: data['topic'] as String,
          payload: data['payload'] as String,
          fromClientId: data['fromClientId'] as String,
          receivedAt: DateTime.parse(
            data['receivedAt'] as String,
          ),
        );

        if (msg.topic == _topicController.text.trim()) {
          return;
        }

        if (mounted) {
          setState(() {
            _messages.insert(0, msg);
          });
        }
        break;
    }
  }

  void _sendBrokerConfig() {
    if (!_serviceReady) {
      debugPrint('[UI] Task is not ready yet');
      return;
    }

    final port =
        int.tryParse(_portController.text.trim()) ?? 1883;

    final colorTopic = _topicController.text.trim();

    debugPrint('[UI] Sending broker configuration...');
    debugPrint('[UI] port=$port');
    debugPrint('[UI] colorTopic=$colorTopic');

    FlutterForegroundTask.sendDataToTask({
      'type': 'setConfig',
      'port': port,
      'colorTopic': colorTopic,
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

      // 1) Ask the task to close its sockets and free the port.
      FlutterForegroundTask.sendDataToTask({
        'type': 'stop',
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // 2) Stop the Android service.
      final result = await FlutterForegroundTask.stopService();
      debugPrint('[UI] stopService result: $result');

      // 3) Wait until it is really gone (max ~5 s), otherwise an immediate
      //    restart would hit "service already started" on a dying service.
      for (var i = 0; i < 25; i++) {
        if (!await FlutterForegroundTask.isRunningService) break;
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (mounted) {
        setState(() {
          _running = false;
          _clientCount = 0;
          _deviceMacs = [];
          _lastLog = 'Broker stopped';
        });
      }
      return;
    }

    final port =
        int.tryParse(_portController.text.trim()) ?? 1883;

    final colorTopic = _topicController.text.trim();

    debugPrint('[UI] Starting broker...');
    debugPrint('[UI] port=$port');
    debugPrint('[UI] colorTopic=$colorTopic');

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'ESP32 MQTT Broker',
        notificationText: 'Starting broker on port $port...',
        callback: startBrokerTaskCallback,
      );

      debugPrint('[UI] startService result: $result');

      if (result is ServiceRequestFailure) {
        debugPrint('[UI] Service failed: ${result.error}');

        // Service is already alive (e.g. started earlier / screen was
        // re-opened): just re-attach the UI instead of showing "Start".
        if (result.error.toString().contains('ServiceAlreadyStarted')) {
          // A service is alive. Ask it to start the broker and wait for it to
          // confirm - do NOT assume it is running, it might be a leftover
          // that is shutting down.
          _serviceReady = true;
          _sendBrokerConfig();
          FlutterForegroundTask.sendDataToTask({'type': 'getStatus'});

          for (var i = 0; i < 15 && !_running && mounted; i++) {
            await Future.delayed(const Duration(milliseconds: 200));
          }

          if (mounted && !_running) {
            await FlutterForegroundTask.stopService();
            setState(() {
              _lastLog = 'Service was not responding and was stopped - '
                  'tap Start Broker again';
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

// Only send configuration if the service actually started.
      if (mounted) setState(() => _running = true);
      FlutterForegroundTask.sendDataToTask({
        'type': 'setConfig',
        'port': port,
        'colorTopic': colorTopic,
      });

      debugPrint('[UI] Configuration sent to broker task');
    } catch (e, stackTrace) {
      debugPrint('[UI] startService FAILED: $e');
      debugPrint(stackTrace.toString());

      setState(() {
        _running = false;
      });
    }
  }

  void _sendColor(String colorName) {
    final target =
    _selectedMac == _allDevices ? null : '$_clientIdPrefix$_selectedMac';

    FlutterForegroundTask.sendDataToTask({
      'type': 'sendColor',
      'value': colorName,
      'target': target,
    });

    final where = target == null ? 'all devices' : _formatMac(_selectedMac);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sent "$colorName" to $where'),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  String _formatMac(String mac) {
    if (mac.length != 12) return mac;
    return [for (var i = 0; i < 12; i += 2) mac.substring(i, i + 2)].join(':');
  }

  Widget _buildDeviceSelector() {
    // Keep the selected device in the list even if it goes offline, so the
    // dropdown never ends up with a value that has no matching item.
    final macs = {
      ..._deviceMacs,
      if (_selectedMac != _allDevices) _selectedMac,
    }.toList()
      ..sort();

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Target device',
        helperText: _deviceMacs.isEmpty
            ? 'No ESP32 connected yet'
            : 'Colors and telemetry are limited to the selected device',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _selectedMac,
          onChanged: _running
              ? (value) => setState(() => _selectedMac = value ?? _allDevices)
              : null,
          items: [
            const DropdownMenuItem(
              value: _allDevices,
              child: Text('All devices'),
            ),
            for (final mac in macs)
              DropdownMenuItem(
                value: mac,
                child: Text(
                  _deviceMacs.contains(mac)
                      ? _formatMac(mac)
                      : '${_formatMac(mac)} (offline)',
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
      ),
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
        title: const Text('ESP32 LED Control (Broker)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.wifi),
            tooltip: 'WiFi Setup (SmartConfig)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SmartConfigScreen(targetMac: _selectedMac),
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
            Text('Status: $_lastLog', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 20),
            _buildDeviceSelector(),
            const SizedBox(height: 20),
            Text('Colors', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: _colors.entries.map((entry) {
                return _ColorButton(
                  label: entry.key,
                  color: entry.value,
                  enabled: _running,
                  onTap: () => _sendColor(entry.key),
                );
              }).toList(),
            ),
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
                        '${msg.topic} (${msg.fromClientId}) · ${msg.receivedAt.toIso8601String()}'),
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
              'The broker keeps running in the background (even if you swipe the app '
                  'away) thanks to the persistent notification - do not force-stop the app '
                  'from Android settings, that kills it like any other app.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _portController,
                    enabled: !running,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Port'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _topicController,
                    enabled: !running,
                    decoration: const InputDecoration(labelText: 'Topic'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _toggleBroker,
              child: Text(running ? 'Stop Broker' : 'Start Broker'),
            ),
            const SizedBox(height: 4),
            Text('Connected clients: $_clientCount'),
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

class _ColorButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;

  const _ColorButton({
    required this.label,
    required this.color,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = color.computeLuminance() < 0.4;
    return Material(
      color: color.withValues(alpha: enabled ? 1.0 : 0.35),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- SmartConfig screen ----------------

class SmartConfigScreen extends StatefulWidget {
  /// MAC (no colons) of the device chosen in the dropdown on the previous
  /// screen. Empty string means "all devices".
  final String targetMac;

  const SmartConfigScreen({super.key, this.targetMac = ''});

  @override
  State<SmartConfigScreen> createState() => _SmartConfigScreenState();
}

class _SmartConfigScreenState extends State<SmartConfigScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
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
      }
    } catch (_) {}
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
        : _prettyMac(widget.targetMac);

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