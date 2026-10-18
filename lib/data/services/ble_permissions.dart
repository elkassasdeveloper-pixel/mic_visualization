import 'package:permission_handler/permission_handler.dart';

/// Runtime permissions needed to scan for and connect to BLE devices
/// (Android 12+ "Nearby devices"). Call this from the UI isolate; the
/// foreground-service isolate has no Activity to show the dialog.
Future<bool> requestBluetoothPermissions() async {
  final results = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();
  return results.values.every((s) => s.isGranted);
}