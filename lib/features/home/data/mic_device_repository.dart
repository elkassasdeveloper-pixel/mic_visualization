import 'dart:async';
import 'package:record/record.dart';

abstract class MicDeviceRepository {
  Stream<List<String>> watchConnectedDevices(List<String> Function() getSlotIds);
  Future<InputDevice?> deviceForSlot(String slot, List<String> slotIds);
}

class RecordMicDeviceRepository implements MicDeviceRepository {
  RecordMicDeviceRepository({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Stream<List<String>> watchConnectedDevices(List<String> Function() getSlotIds) async* {
    List<String> lastEmitted = [];

    while (true) {
      final devices = await _fetchDeviceSlots(getSlotIds());
      if (!_listEquals(devices, lastEmitted)) {
        lastEmitted = devices;
        yield devices;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<List<String>> _fetchDeviceSlots(List<String> slotIds) async {
    try {
      final inputDevices = await _recorder.listInputDevices();
      final connected = <String>[];
      for (var i = 0; i < inputDevices.length && i < slotIds.length; i++) {
        connected.add(slotIds[i]);
      }
      return connected;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<InputDevice?> deviceForSlot(String slot, List<String> slotIds) async {
    final inputDevices = await _recorder.listInputDevices();
    final index = slotIds.indexOf(slot);
    if (index < 0 || index >= inputDevices.length) return null;
    return inputDevices[index];
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void dispose() {
    _recorder.dispose();
  }
}