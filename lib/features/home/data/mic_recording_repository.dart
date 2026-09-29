import 'package:record/record.dart';

abstract class MicRecordingRepository {
  Stream<List<double>> windowsFor(String slot);
  Future<void> startRecording(String slot, InputDevice? device);
  Future<void> stopRecording(String slot);
  Future<void> disposeAll();
}