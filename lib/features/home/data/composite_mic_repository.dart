import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hodhd_visualization/core/constants/audio_tagging_config.dart';
import 'package:hodhd_visualization/data/models/registered_mic.dart';
import 'package:hodhd_visualization/features/home/data/mic_device_repository.dart';
import 'package:hodhd_visualization/features/home/data/mic_recording_repository.dart';
import 'package:hodhd_visualization/features/home/data/parec_mic_recording_repository.dart';
import 'package:hodhd_visualization/features/home/data/record_backed_mic_recording_repository.dart';
import 'package:record/record.dart';

/// Device repository that merges connected local microphones and connected
/// MQTT broker clients (e.g. ESP32 devices).
class CompositeMicDeviceRepository implements MicDeviceRepository {
  CompositeMicDeviceRepository({MicDeviceRepository? localRepository})
      : _localRepository = localRepository ?? RecordMicDeviceRepository();

  final MicDeviceRepository _localRepository;
  List<String> _mqttClients = [];
  StreamController<List<String>>? _controller;
  StreamSubscription<List<String>>? _localSub;
  List<String> Function()? _currentGetSlotIds;

  @override
  Stream<List<String>> watchConnectedDevices(
      List<String> Function() getSlotIds) {
    _currentGetSlotIds = getSlotIds;

    _controller ??= StreamController<List<String>>.broadcast(
      onListen: () {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          FlutterForegroundTask.addTaskDataCallback(_onTaskData);
        }
      },
      onCancel: () {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
        }
      },
    );

    _localSub?.cancel();
    // ESP32 slots never map to a local microphone, so the local repository
    // only gets to see the non-ESP slots.
    _localSub = _localRepository
        .watchConnectedDevices(
            () => getSlotIds().where((s) => !isEspMicId(s)).toList())
        .listen((localDevices) {
      _emitCombined(localDevices);
    });

    return _controller!.stream;
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'clients') {
      final clients = (data['value'] as List?)?.cast<String>() ?? [];
      _mqttClients = clients;
      _emitCombined([]);
    }
  }

  void _emitCombined(List<String> localDevices) {
    final slotIds = _currentGetSlotIds?.call() ?? [];
    final combined = <String>{...localDevices};

    // Connected network clients ("esp32-<MAC>"): show the registered slot that
    // belongs to the same MAC, otherwise the raw client id so it can be
    // registered from the Register Mic screen.
    for (final client in _mqttClients) {
      final key = normalizeMicId(client);
      final matches = slotIds
          .where((slot) => slot == client || normalizeMicId(slot) == key)
          .toList();
      if (matches.isEmpty) {
        combined.add(client);
      } else {
        combined.addAll(matches);
      }
    }

    if (!_controller!.isClosed) {
      _controller!.add(combined.toList());
    }
  }

  @override
  Future<InputDevice?> deviceForSlot(
      String slot, List<String> slotIds) {
    // An ESP32 streams its own audio; it must never be tied to a phone mic.
    if (isEspMicId(slot)) return Future.value(null);
    return _localRepository.deviceForSlot(
        slot, slotIds.where((s) => !isEspMicId(s)).toList());
  }
}

/// Recording repository that receives PCM audio chunks from local microphones
/// and MQTT clients via [FlutterForegroundTask], accumulates them into windows of
/// [AudioTaggingConfig.windowSamples] float32 samples, and yields them for classification.
class CompositeMicRecordingRepository implements MicRecordingRepository {
  CompositeMicRecordingRepository({MicRecordingRepository? localRepository})
      : _localRepository = localRepository ??
      (Platform.isLinux
          ? ParecMicRecordingRepository()
          : RecordBackedMicRecordingRepository()) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    }
  }

  final MicRecordingRepository _localRepository;
  final Map<String, List<int>> _mqttBuffers = {};
  final Map<String, StreamController<List<double>>> _windowControllers = {};
  final Set<String> _recordingSlots = {};

  void _onTaskData(Object data) {
    if (data is! Map) return;
    if (data['type'] == 'audio') {
      final bytes = (data['value'] as List?)?.cast<int>();
      final clientId = data['clientId'] as String? ?? '';
      if (bytes != null && bytes.isNotEmpty) {
        _handleMqttAudioBytes(clientId, bytes);
      }
    }
  }

  void _handleMqttAudioBytes(String clientId, List<int> bytes) {
    if (bytes.length < 2 || bytes.length % 2 != 0) return;

    // Route the audio to the slot registered for the SAME device (same MAC).
    final key = normalizeMicId(clientId);
    final targetSlots = <String>{};

    for (final slot in _recordingSlots) {
      if (slot == clientId || (key.isNotEmpty && normalizeMicId(slot) == key)) {
        targetSlots.add(slot);
      }
    }

    // Fallback for old slots that are not tied to a MAC (e.g. uuid-registered):
    // never feed another ESP32's audio into a MAC-registered slot.
    if (targetSlots.isEmpty) {
      targetSlots.addAll(_recordingSlots.where((s) => !isEspMicId(s)));
    }

    if (targetSlots.isEmpty) return;

    for (final slot in targetSlots) {
      final buffer = _mqttBuffers.putIfAbsent(slot, () => []);

      final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
      for (var i = 0; i + 1 < bytes.length; i += 2) {
        buffer.add(byteData.getInt16(i, Endian.little));
      }

      final windowSize = AudioTaggingConfig.windowSamples;
      while (buffer.length >= windowSize) {
        final windowInts = buffer.sublist(0, windowSize);
        buffer.removeRange(0, windowSize);

        final windowFloats = windowInts
            .map((s) => s / 32768.0) // int16 -> float32 [-1.0, 1.0]
            .toList(growable: false);

        debugPrint(
            '[CompositeRecording] $slot MQTT audio window ready (${windowFloats.length} samples)');
        if (_windowControllers[slot] != null &&
            !_windowControllers[slot]!.isClosed) {
          _windowControllers[slot]!.add(windowFloats);
        }
      }
    }
  }

  @override
  Stream<List<double>> windowsFor(String slot) {
    final controller = _windowControllers.putIfAbsent(
        slot, () => StreamController<List<double>>.broadcast());

    // ESP32 slots get audio only from the network, never from a local mic.
    final localStream =
    isEspMicId(slot) ? null : _localRepository.windowsFor(slot);
    StreamSubscription<List<double>>? localSub;

    controller.onListen = () {
      localSub = localStream?.listen(
            (window) {
          if (!controller.isClosed) controller.add(window);
        },
        onError: (e) {
          if (!controller.isClosed) controller.addError(e);
        },
      );
    };

    controller.onCancel = () {
      localSub?.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> startRecording(String slot, InputDevice? device) async {
    _recordingSlots.add(slot);
    _mqttBuffers[slot] = [];
    try {
      if (!isEspMicId(slot)) {
        await _localRepository.startRecording(slot, device);
      }
    } catch (e) {
      debugPrint('[CompositeRecording] Local recorder start note: $e');
    }
  }

  @override
  Future<void> stopRecording(String slot) async {
    _recordingSlots.remove(slot);
    _mqttBuffers.remove(slot);
    try {
      if (!isEspMicId(slot)) {
        await _localRepository.stopRecording(slot);
      }
    } catch (e) {
      debugPrint('[CompositeRecording] Local recorder stop note: $e');
    }
  }

  @override
  Future<void> disposeAll() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    }
    await _localRepository.disposeAll();
    for (final controller in _windowControllers.values) {
      await controller.close();
    }
    _windowControllers.clear();
    _mqttBuffers.clear();
    _recordingSlots.clear();
  }
}