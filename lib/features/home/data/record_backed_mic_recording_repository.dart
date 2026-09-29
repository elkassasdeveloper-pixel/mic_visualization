import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mic_visualization/features/home/data/mic_recording_repository.dart';
import 'package:record/record.dart';
import 'package:mic_visualization/core/constants/audio_tagging_config.dart';

class RecordBackedMicRecordingRepository implements MicRecordingRepository{
  final Map<String, AudioRecorder> _recorders = {};
  final Map<String, StreamSubscription<Uint8List>> _subscriptions = {};
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
    debugPrint('[Recording] starting $slot on device: ${device?.id} / ${device?.label ?? "default"}');
    final recorder = AudioRecorder();
    _recorders[slot] = recorder;
    _buffers[slot] = [];
    int chunkCount = 0;

    final stream = await recorder.startStream(
      RecordConfig(
        device: device,
        encoder: AudioEncoder.pcm16bits,
        sampleRate: AudioTaggingConfig.sampleRate,
        numChannels: 1,
      ),
    );
    debugPrint('[Recording] $slot stream started');
    _subscriptions[slot] = stream.listen((chunk) {
      chunkCount++;
      if (chunkCount % 20 == 1) {
        debugPrint('[Recording] $slot received chunk #$chunkCount (${chunk.length} bytes)');
      }
      _onChunk(slot, chunk);
    }, onError: (e) {
      debugPrint('[Recording] $slot stream ERROR: $e');
    });
  }

  void _onChunk(String slot, Uint8List chunk) {
    final buffer = _buffers[slot];
    if (buffer == null) return;

    // PCM16 little-endian: 2 bytes per sample.
    final byteData = ByteData.sublistView(chunk);
    for (var i = 0; i + 1 < chunk.length; i += 2) {
      buffer.add(byteData.getInt16(i, Endian.little));
    }

    final windowSize = AudioTaggingConfig.windowSamples;
    while (buffer.length >= windowSize) {
      final windowInts = buffer.sublist(0, windowSize);
      buffer.removeRange(0, windowSize);

      final windowFloats = windowInts
          .map((s) => s / 32768.0) // int16 -> float32 [-1.0, 1.0]
          .toList(growable: false);
      debugPrint('[Recording] $slot window ready (${windowFloats.length} samples)');
      _windowControllers[slot]?.add(windowFloats);
    }
  }

@override
  Future<void> stopRecording(String slot) async {
    await _subscriptions[slot]?.cancel();
    await _recorders[slot]?.stop();
    _subscriptions.remove(slot);
    _recorders.remove(slot);
    _buffers.remove(slot);
  }

@override
  Future<void> disposeAll() async {
    for (final slot in _recorders.keys.toList()) {
      await stopRecording(slot);
    }
    for (final controller in _windowControllers.values) {
      await controller.close();
    }
    _windowControllers.clear();
  }
}