import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:mic_visualization/core/constants/audio_tagging_config.dart';
import 'package:mic_visualization/features/home/data/mic_recording_repository.dart';

class ParecMicRecordingRepository implements MicRecordingRepository {
  final Map<String, Process> _processes = {};
  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};
  final Map<String, List<int>> _buffers = {};
  final Map<String, StreamController<List<double>>> _windowControllers = {};

  @override
  Stream<List<double>> windowsFor(String slot) {
    return _windowControllers
        .putIfAbsent(slot, () => StreamController<List<double>>.broadcast())
        .stream;
  }

  @override
  Future<void> startRecording(String slot, InputDevice? device) async {
    _buffers[slot] = [];

    final args = [
      if (device != null) '--device=${device.id}',
      '--rate=${AudioTaggingConfig.sampleRate}',
      '--channels=1',
      '--format=s16le',
      '--raw',
    ];

    final process = await Process.start('parec', args);
    _processes[slot] = process;
    _subscriptions[slot] = process.stdout.listen((chunk) => _onChunk(slot, chunk));
  }

  void _onChunk(String slot, List<int> chunk) {
    final buffer = _buffers[slot];
    if (buffer == null) return;

    final bytes = Uint8List.fromList(chunk);
    final byteData = ByteData.sublistView(bytes);
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      buffer.add(byteData.getInt16(i, Endian.little));
    }

    final windowSize = AudioTaggingConfig.windowSamples;
    while (buffer.length >= windowSize) {
      final windowInts = buffer.sublist(0, windowSize);
      buffer.removeRange(0, windowSize);
      final windowFloats = windowInts.map((s) => s / 32768.0).toList(growable: false);
      _windowControllers[slot]?.add(windowFloats);
    }
  }

  @override
  Future<void> stopRecording(String slot) async {
    await _subscriptions[slot]?.cancel();
    _processes[slot]?.kill();
    _processes.remove(slot);
    _subscriptions.remove(slot);
    _buffers.remove(slot);
  }

  @override
  Future<void> disposeAll() async {
    for (final slot in _processes.keys.toList()) {
      await stopRecording(slot);
    }
    for (final controller in _windowControllers.values) {
      await controller.close();
    }
    _windowControllers.clear();
  }
}