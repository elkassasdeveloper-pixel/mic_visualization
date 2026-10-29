import 'package:esp_smartconfig/esp_smartconfig.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hodhd_visualization/data/security/secure_channel.dart';
import 'package:hodhd_visualization/data/security/security_key_store.dart';
import 'package:hodhd_visualization/features/esp32_control/cubit/esp32_control_cubit.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SmartConfigCubit extends Cubit<SmartConfigState> {
  SmartConfigCubit({this.targetMac = '', this.targetName = ''})
      : super(const SmartConfigState()) {
    _prefillCurrentWifi();
  }

  /// MAC (no colons) of the device chosen in the dropdown on the previous
  /// screen. Empty string means "all devices".
  final String targetMac;

  /// Friendly name of that device (empty when targeting all devices).
  final String targetName;

  // Owned here (not in a State) so the screen can be a StatelessWidget.
  final TextEditingController ssidController = TextEditingController();
  final TextEditingController passwordController =
  TextEditingController(text: 'SayedNimer@2021@1442');

  final NetworkInfo _networkInfo = NetworkInfo();
  Provisioner? _provisioner;

  String get targetLabel => targetMac.isEmpty
      ? 'ALL connected devices'
      : '$targetName (${formatMac(targetMac)})';

  void _emit(SmartConfigState s) {
    if (!isClosed) emit(s);
  }

  Future<void> _prefillCurrentWifi() async {
    await Permission.locationWhenInUse.request();
    try {
      final ssid = await _networkInfo.getWifiName();
      ssidController.text = ssid != null ? ssid.replaceAll('"', '') : 'EngSayedNimer';
    } catch (_) {
      ssidController.text = 'EngSayedNimer';
    }
  }

  Future<void> startProvisioning() async {
    if (ssidController.text.isEmpty) {
      _emit(state.copyWith(status: 'Enter the WiFi SSID first'));
      return;
    }

    _emit(state.copyWith(
      isProvisioning: true,
      status: 'Starting SmartConfig...',
      connectedDevices: const [],
    ));

    String? bssid;
    try {
      bssid = await _networkInfo.getWifiBSSID();
    } catch (_) {
      bssid = null;
    }

    final keyBytes = await SecurityKeyStore.load();
    final espTouchKey = keyBytes == null ? null : SecureChannel(keyBytes).espTouchKey;

    final provisioner = Provisioner.espTouchV2();
    _provisioner = provisioner;

    provisioner.listen((response) {
      _emit(state.copyWith(
        connectedDevices: [...state.connectedDevices, response.bssidText],
        status: 'Device connected: ${response.bssidText}',
      ));
    });

    String? error;

    try {
      await provisioner.start(ProvisioningRequest.fromStrings(
        ssid: ssidController.text,
        bssid: bssid ?? '00:00:00:00:00:00',
        password: passwordController.text,
        encryptionKey: espTouchKey, // 16 chars, same key the firmware derives
      ));

      _emit(state.copyWith(status: 'Broadcasting credentials...'));
      await Future.delayed(const Duration(seconds: 30));
    } catch (e) {
      error = '$e';
      debugPrint('[SmartConfig] start failed: $e');
      _emit(state.copyWith(status: 'Error: $e'));
    } finally {
      provisioner.stop();
      _emit(state.copyWith(
        isProvisioning: false,
        status: (error == null && state.connectedDevices.isEmpty)
            ? 'Finished - no devices confirmed connection'
            : null,
      ));
    }
  }

  void stopProvisioning() {
    _provisioner?.stop();
    _emit(state.copyWith(isProvisioning: false, status: 'Stopped'));
  }

  /// Sends RESET to the selected device (or all). The confirmation dialog is
  /// shown by the screen before calling this.
  Future<void> resetWifi() async {
    final target = targetMac.isEmpty ? null : 'esp32-$targetMac';

    // The command travels through the broker, so it must be running.
    if (!await FlutterForegroundTask.isRunningService) {
      _emit(state.copyWith(status: 'Start the broker first - reset is sent through it'));
      return;
    }

    FlutterForegroundTask.sendDataToTask({
      'type': 'sendCommand',
      'value': 'RESET',
      'target': target,
    });

    _emit(state.copyWith(status: 'Reset sent to $targetLabel'));
  }

  @override
  Future<void> close() {
    _provisioner?.stop();
    ssidController.dispose();
    passwordController.dispose();
    return super.close();
  }
}

class SmartConfigState {
  const SmartConfigState({
    this.isProvisioning = false,
    this.status = 'Idle',
    this.connectedDevices = const [],
  });

  final bool isProvisioning;
  final String status;
  final List<String> connectedDevices;

  SmartConfigState copyWith({
    bool? isProvisioning,
    String? status,
    List<String>? connectedDevices,
  }) {
    return SmartConfigState(
      isProvisioning: isProvisioning ?? this.isProvisioning,
      status: status ?? this.status,
      connectedDevices: connectedDevices ?? this.connectedDevices,
    );
  }
}