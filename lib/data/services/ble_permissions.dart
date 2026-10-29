
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Request permissions required for BLE scanning and connecting.
Future<bool> requestBluetoothPermissions() async {
  if (Platform.isIOS) {
    final status = await Permission.bluetooth.request();
    return status.isGranted;
  }

  if (Platform.isAndroid) {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();

    return results.values.every((status) => status.isGranted);
  }

  return false;
}
