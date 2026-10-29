import 'package:hodhd_visualization/data/models/esp_transport.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';
import 'package:hodhd_visualization/data/local/settings_repository.dart';
import 'package:hodhd_visualization/data/security/security_key_store.dart';
import 'package:hodhd_visualization/data/services/ble_permissions.dart';
import 'package:hodhd_visualization/data/services/broker_task_handler.dart';
import 'package:network_info_plus/network_info_plus.dart';

class Esp32ControlCubit extends Cubit<Esp32ControlState> {
  Esp32ControlCubit() : super(const Esp32ControlState()) {
    _initForegroundTask();
    _requestPermissions();
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    _loadSettings();
    _loadLocalIps();
    _loadDeviceNames();
    _syncRunningState();
  }

  static const int barCount = 15;

  /// Equalizer bars. They change for every audio chunk, so they live outside
  /// the state: only the equalizer widget rebuilds, not the whole screen.
  final ValueNotifier<List<double>> equalizer =
  ValueNotifier<List<double>>(List<double>.filled(barCount, 0.1));

  /// Owned here (not in a State) so the screen can be a StatelessWidget.
  final TextEditingController portController = TextEditingController(text: '1883');

  int get _port =>
      int.tryParse(portController.text.trim()) ?? state.transport.defaultPort;

  /// Latest camera frame for the selected device (or any device when "All
  /// devices" is selected). Outside the state for the same reason as [equalizer].
  final ValueNotifier<VideoFrame?> video = ValueNotifier<VideoFrame?>(null);

  bool _serviceReady = false;
  bool _pcmReady = false;
  Future<void>? _pcmSetup;

  void _emit(Esp32ControlState s) {
    if (!isClosed) emit(s);
  }

  // ---- startup --------------------------------------------------------------

  Future<void> _loadSettings() async {
    final settings = await SettingsRepository.create();
    portController.text = settings.transport.defaultPort.toString();
    _emit(state.copyWith(transport: settings.transport));
  }

  Future<void> _syncRunningState() async {
    final running = await FlutterForegroundTask.isRunningService;
    _emit(state.copyWith(running: running));

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

  Future<void> _loadLocalIps() async {
    final ip = await NetworkInfo().getWifiIP();
    if (ip != null) _emit(state.copyWith(localIps: [ip]));
  }

  // ---- messages from the foreground task ------------------------------------

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
        final logValue = data['value'] as String? ?? '';
        if (logValue.isNotEmpty) _emit(state.copyWith(lastLog: logValue));
        break;

      case 'clientCount':
        _emit(state.copyWith(clientCount: data['value'] as int));
        break;

      case 'clients':
        final ids = (data['value'] as List).cast<String>();
        final macs = ids
            .where((id) => id.startsWith(espClientIdPrefix))
            .map((id) => id.substring(espClientIdPrefix.length))
            .toList()
          ..sort();
        final gone = {...state.audioDevices, ...state.videoDevices}
            .where((m) => !macs.contains(m))
            .toSet();
        if (gone.isNotEmpty) {
          _emit(state.copyWith(
            audioDevices: state.audioDevices.difference(gone),
            videoDevices: state.videoDevices.difference(gone),
          ));
          if (gone.contains(video.value?.mac)) video.value = null;
        }
        _emit(state.copyWith(deviceMacs: macs));
        break;

      case 'running':
        final isRunning = data['value'] as bool;
        _emit(state.copyWith(running: isRunning));
        if (isRunning) {
          _ensurePcm();
        } else {
          _releasePcm();
        }
        break;

      case 'error':
        debugPrint('[UI] Broker error: ${data['value']}');
        _emit(state.copyWith(running: false, lastLog: data['value'].toString()));
        break;

      case 'message':
        final msg = TelemetryMessage(
          topic: data['topic'] as String? ?? 'esp32/telemetry',
          payload: data['payload'] as String? ?? '',
          fromClientId: data['fromClientId'] as String? ?? '',
          receivedAt: DateTime.parse(
            data['receivedAt'] as String? ?? DateTime.now().toIso8601String(),
          ),
        );
        _emit(state.copyWith(messages: [msg, ...state.messages]));
        break;

      case 'audio':
        final from = data['clientId'] as String? ?? '';
        _markStream(from, audio: true);
        // Only play / visualize the device picked in the dropdown.
        if (state.selectedMac != allDevices &&
            from != '$espClientIdPrefix${state.selectedMac}') {
          break;
        }
        _handleAudio((data['value'] as List).cast<int>());
        break;

      case 'video':
        final fromVideo = data['clientId'] as String? ?? '';
        final mac = _macOf(fromVideo);
        _markStream(fromVideo, audio: false);
        // Only show the device picked in the dropdown.
        if (state.selectedMac != allDevices && mac != state.selectedMac) break;
        if (isClosed) break;
        video.value = VideoFrame(
          mac: mac,
          bytes: data['value'] is Uint8List
              ? data['value'] as Uint8List
              : Uint8List.fromList((data['value'] as List).cast<int>()),
        );
        break;
    }
  }

  String _macOf(String clientId) => clientId.startsWith(espClientIdPrefix)
      ? clientId.substring(espClientIdPrefix.length)
      : clientId;

  /// Remembers that [clientId] sends audio or video (emits only on the first packet).
  void _markStream(String clientId, {required bool audio}) {
    final mac = _macOf(clientId);
    if (audio) {
      if (!state.audioDevices.contains(mac)) {
        _emit(state.copyWith(audioDevices: {...state.audioDevices, mac}));
      }
    } else if (!state.videoDevices.contains(mac)) {
      _emit(state.copyWith(videoDevices: {...state.videoDevices, mac}));
    }
  }

  // ---- audio: PCM playback + equalizer --------------------------------------

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
    if (isClosed || bytes.length < 2 || bytes.length % 2 != 0) return;

    final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
    final samples = <int>[
      for (var i = 0; i < bytes.length; i += 2) byteData.getInt16(i, Endian.little),
    ];

    _updateEqualizer(samples);

    try {
      await _ensurePcm();
      await FlutterPcmSound.feed(PcmArrayInt16.fromList(samples));
    } catch (e) {
      debugPrint('[UI] PCM feed failed: $e');
    }
  }

  void _updateEqualizer(List<int> rawPcmData) {
    if (isClosed) return;

    // Group the PCM data into bars and use each group's RMS as its height.
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

    equalizer.value = newBarHeights;
  }

  // ---- configuration sent to the task ----------------------------------------

  Map<String, Object> _configMessage(int port) => {
    'type': 'setConfig',
    'port': port,
    'transport': state.transport.id,
    'useWebSocket': state.transport == EspTransport.websocket,
  };

  /// Tells already-connected ESP32s which Wi-Fi protocol to use. Skipped for
  /// Bluetooth: a device that is connected over BLE is already in BLE mode and
  /// would be kicked out of it by a USE_WEBSOCKET command.
  void _sendProtocolCommand() {
    if (state.transport == EspTransport.bluetooth) return;
    FlutterForegroundTask.sendDataToTask({
      'type': 'sendCommand',
      'value': state.transport.espCommand,
    });
  }

  Future<void> _sendBrokerConfig() async {
    if (!_serviceReady) {
      debugPrint('[UI] Task is not ready yet');
      return;
    }
    await sendSecret();
    debugPrint('[UI] Sending configuration: transport=${state.transport.id}, port=$_port');
    FlutterForegroundTask.sendDataToTask(_configMessage(_port));
    _sendProtocolCommand();
    debugPrint('[UI] Configuration sent');
  }

  /// Passes the master key to the foreground task (it never touches secure storage itself).
  Future<void> sendSecret([Uint8List? key]) async {
    final k = key ?? await SecurityKeyStore.load();
    FlutterForegroundTask.sendDataToTask({
      'type': 'setSecret',
      'value': k == null ? '' : base64Encode(k),
    });
  }

  // ---- start / stop -----------------------------------------------------------

  Future<void> toggleServer() async {
    if (state.busy) return;
    _emit(state.copyWith(busy: true));
    try {
      if (state.running) {
        await _stopServer();
      } else {
        await _startServer();
      }
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  Future<void> _stopServer() async {
    debugPrint('[UI] Stopping server...');
    _releasePcm();

    // 1) Ask the task to close its sockets / BLE links and free the port.
    FlutterForegroundTask.sendDataToTask({'type': 'stop'});
    await Future.delayed(const Duration(milliseconds: 500));

    // 2) Stop the Android service.
    final result = await FlutterForegroundTask.stopService();
    debugPrint('[UI] stopService result: $result');

    for (var i = 0; i < 25; i++) {
      if (!await FlutterForegroundTask.isRunningService) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    if (!isClosed) {
      equalizer.value = List<double>.filled(barCount, 0.1);
      video.value = null;
    }
    _emit(state.copyWith(
      running: false,
      clientCount: 0,
      deviceMacs: const [],
      audioDevices: const {},
      videoDevices: const {},
      lastLog: 'Server stopped',
    ));
  }

  Future<void> _startServer() async {
    final port = _port;
    final transport = state.transport;

    // The permission dialog needs an Activity, so ask here (UI isolate)
    // before the service isolate starts scanning.
    if (transport == EspTransport.bluetooth && !await requestBluetoothPermissions()) {
      _emit(state.copyWith(
          lastLog: 'Bluetooth permission denied - allow "Nearby devices" for this app'));
      return;
    }

    _emit(state.copyWith(lastLog: 'Starting ${transport.label}...'));

    final settings = await SettingsRepository.create();
    await settings.setTransport(transport);

    try {
      final result = await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'ESP32 Audio Service',
        notificationText: transport.usesPort
            ? 'Starting server on port $port...'
            : 'Scanning for Bluetooth devices...',
        callback: startBrokerTaskCallback,
      );

      debugPrint('[UI] startService result: $result');

      if (result is ServiceRequestFailure) {
        debugPrint('[UI] Service failed: ${result.error}');

        if (result.error.toString().contains('ServiceAlreadyStarted')) {
          _serviceReady = true;
          await _sendBrokerConfig();
          FlutterForegroundTask.sendDataToTask({'type': 'getStatus'});

          for (var i = 0; i < 15 && !state.running && !isClosed; i++) {
            await Future.delayed(const Duration(milliseconds: 200));
          }

          if (!isClosed && !state.running) {
            await FlutterForegroundTask.stopService();
            _emit(state.copyWith(
                lastLog: 'Service was not responding and was stopped - tap Start again'));
          }
          return;
        }

        _emit(state.copyWith(running: false));
        return;
      }

      _emit(state.copyWith(running: true));
      FlutterForegroundTask.sendDataToTask(_configMessage(port));
      _sendProtocolCommand();

      debugPrint('[UI] Configuration sent to server task');
    } catch (e, stackTrace) {
      debugPrint('[UI] startService FAILED: $e');
      debugPrint(stackTrace.toString());
      _emit(state.copyWith(running: false));
    }
  }

  // ---- transport selection (MQTT / WebSocket / Bluetooth) ---------------------

  Future<void> _adoptTransport(EspTransport next) async {
    portController.text = next.defaultPort.toString();
    _emit(state.copyWith(transport: next));
    final settings = await SettingsRepository.create();
    await settings.setTransport(next);
  }

  Future<void> changeTransport(EspTransport? next) async {
    if (next == null || next == state.transport || state.busy) return;

    // Not running: just remember the choice.
    if (!state.running) {
      await _adoptTransport(next);
      return;
    }

    // Running: move the ESP32s over first (the command travels over the
    // current link), then restart the phone side with the new transport.
    _emit(state.copyWith(busy: true, lastLog: 'Switching devices to ${next.label}...'));
    try {
      if (next == EspTransport.bluetooth && !await requestBluetoothPermissions()) {
        _emit(state.copyWith(lastLog: 'Bluetooth permission denied'));
        return;
      }

      FlutterForegroundTask.sendDataToTask({
        'type': 'sendCommand',
        'value': next.espCommand,
      });
      await Future.delayed(const Duration(milliseconds: 1000));

      await _stopServer();
      await _adoptTransport(next);
      await _startServer();
    } finally {
      _emit(state.copyWith(busy: false));
    }
  }

  // ---- devices ------------------------------------------------------------------

  void selectDevice(String mac) {
    _emit(state.copyWith(selectedMac: mac));
    video.value = null; // the next frame comes from the new selection
    // drop audio already queued from the previous device
    _releasePcm();
  }

  Future<void> _loadDeviceNames() async {
    final raw = await FlutterForegroundTask.getData<String>(key: 'deviceNames');
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _emit(state.copyWith(
        deviceNames: map.map((k, v) => MapEntry(k, v.toString())),
      ));
    } catch (_) {}
  }

  /// An empty [name] removes the custom name (back to the default "Mic XXXX").
  Future<void> renameDevice(String mac, String name) async {
    final names = {...state.deviceNames};
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      names.remove(mac);
    } else {
      names[mac] = trimmed;
    }
    _emit(state.copyWith(deviceNames: names));
    await FlutterForegroundTask.saveData(key: 'deviceNames', value: jsonEncode(names));
  }

  @override
  Future<void> close() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    _releasePcm();
    final closing = super.close(); // isClosed is true from here on
    equalizer.dispose();
    video.dispose();
    portController.dispose();
    return closing;
  }
}
/// The sketch connects with client ID "esp32-<MAC without colons".
const String espClientIdPrefix = 'esp32-';

/// Dropdown value for "All devices".
const String allDevices = '';

class TelemetryMessage {
  const TelemetryMessage({
    required this.topic,
    required this.payload,
    required this.fromClientId,
    required this.receivedAt,
  });

  final String topic;
  final String payload;
  final String fromClientId;
  final DateTime receivedAt;
}

/// One camera frame (JPEG) and the device it came from (MAC without colons).
class VideoFrame {
  const VideoFrame({required this.mac, required this.bytes});
  final String mac;
  final Uint8List bytes;
}

/// "AABBCCDDEEFF" -> "AA:BB:CC:DD:EE:FF"
String formatMac(String mac) {
  if (mac.length != 12) return mac;
  return [for (var i = 0; i < 12; i += 2) mac.substring(i, i + 2)].join(':');
}

class Esp32ControlState {
  const Esp32ControlState({
    this.transport = EspTransport.mqtt,
    this.running = false,
    this.busy = false,
    this.lastLog = '',
    this.clientCount = 0,
    this.deviceMacs = const [],
    this.selectedMac = allDevices,
    this.deviceNames = const {},
    this.localIps = const [],
    this.messages = const [],
    this.audioDevices = const {},
    this.videoDevices = const {},
  });

  final EspTransport transport;

  final bool running;

  /// True while starting, stopping or switching transport.
  final bool busy;
  final String lastLog;
  final int clientCount;

  /// MACs (no colons) currently connected.
  final List<String> deviceMacs;
  final String selectedMac;

  /// MAC (no colons) -> display name.
  final Map<String, String> deviceNames;
  final List<String> localIps;
  final List<TelemetryMessage> messages;

  /// MACs that are currently sending audio / camera frames. Devices are not
  /// asked what they have: a stream shows up when its first packet arrives.
  final Set<String> audioDevices;
  final Set<String> videoDevices;

  /// Is there a camera to show for the current selection?
  bool get showVideo => selectedMac == allDevices
      ? videoDevices.isNotEmpty
      : videoDevices.contains(selectedMac);

  /// Is there a microphone to show for the current selection?
  bool get showEqualizer => selectedMac == allDevices
      ? audioDevices.isNotEmpty
      : audioDevices.contains(selectedMac);

  String get statusText => lastLog.isEmpty
      ? (running ? 'Server running' : 'Server stopped')
      : lastLog;

  /// Friendly name for a MAC. Falls back to "Mic XXXX" (last 4 hex digits)
  /// until the user gives the device a name.
  String deviceLabel(String mac) {
    final custom = deviceNames[mac];
    if (custom != null && custom.isNotEmpty) return custom;
    final tail = mac.length >= 4 ? mac.substring(mac.length - 4) : mac;
    return 'Mic $tail';
  }

  /// Label for a client id such as "esp32-AABBCCDDEEFF".
  String clientLabel(String clientId) {
    if (clientId.startsWith(espClientIdPrefix)) {
      return deviceLabel(clientId.substring(espClientIdPrefix.length));
    }
    return clientId;
  }

  List<TelemetryMessage> get visibleMessages => selectedMac == allDevices
      ? messages
      : messages
      .where((m) => m.fromClientId == '$espClientIdPrefix$selectedMac')
      .toList();

  Esp32ControlState copyWith({
    EspTransport? transport,
    bool? running,
    bool? busy,
    String? lastLog,
    int? clientCount,
    List<String>? deviceMacs,
    String? selectedMac,
    Map<String, String>? deviceNames,
    List<String>? localIps,
    List<TelemetryMessage>? messages,
    Set<String>? audioDevices,
    Set<String>? videoDevices,
  }) {
    return Esp32ControlState(
      transport: transport ?? this.transport,
      running: running ?? this.running,
      busy: busy ?? this.busy,
      lastLog: lastLog ?? this.lastLog,
      clientCount: clientCount ?? this.clientCount,
      deviceMacs: deviceMacs ?? this.deviceMacs,
      selectedMac: selectedMac ?? this.selectedMac,
      deviceNames: deviceNames ?? this.deviceNames,
      localIps: localIps ?? this.localIps,
      messages: messages ?? this.messages,
      audioDevices: audioDevices ?? this.audioDevices,
      videoDevices: videoDevices ?? this.videoDevices,
    );
  }
}