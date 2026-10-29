import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hodhd_visualization/data/local/settings_repository.dart';
import 'package:hodhd_visualization/data/models/classification_record.dart';
import 'package:hodhd_visualization/data/models/esp_transport.dart';
import 'package:hodhd_visualization/data/models/login_response.dart';
import 'package:hodhd_visualization/data/models/registered_mic.dart';
import 'package:hodhd_visualization/data/repositories/classification_repository.dart';
import 'package:hodhd_visualization/data/repositories/realtime_repository.dart';
import 'package:hodhd_visualization/data/services/auth_api_service.dart';
import 'package:hodhd_visualization/data/services/ble_permissions.dart';
import 'package:hodhd_visualization/data/services/cloud_api_service.dart';
import 'package:hodhd_visualization/data/services/fugo_message_service.dart';
import 'package:hodhd_visualization/data/services/user_children_api_service.dart';
import 'package:hodhd_visualization/features/home/data/audio_tagging_service.dart';
import 'package:hodhd_visualization/features/home/data/mic_device_repository.dart';
import 'package:hodhd_visualization/features/home/data/mic_recording_repository.dart';

class HomeCubit extends Cubit<HomeState> {
  HomeCubit(
      this._deviceRepository,
      this._recordingRepository,
      this._taggingService,
      this._realtimeRepository,
      this._classificationRepository,
      this._cloudApiService,
      this._settings,
      Map<String, String> slotTokens,
      Map<String, String> fugoTokens,
      )   : _slotTokens = slotTokens,
        _fugoTokens = fugoTokens,
        super(HomeState(
        registeredMics: _settings.registeredMics,
        minConfidence: _settings.minConfidence,
        publishEnabled: _settings.publishEnabled,
        postToCloudEnabled: _settings.postToCloudEnabled,
        transport: _settings.transport,
      )) {
    _deviceSubscription = _deviceRepository
        .watchConnectedDevices(() => state.registeredMics.map((m) => m.id).toList())
        .listen((devices) {
      emit(state.copyWith(connectedDevices: devices));
      _autoRegisterConnected(devices);
    });
  }

  final MicDeviceRepository _deviceRepository;
  final MicRecordingRepository _recordingRepository;
  final AudioTaggingService _taggingService;
  final RealtimeRepository _realtimeRepository;
  final ClassificationRepository _classificationRepository;
  final CloudApiService _cloudApiService;
  final SettingsRepository _settings;
  final Map<String, String> _slotTokens;
  final Map<String, String> _fugoTokens;

  /// Device ids we already tried to log in with since they last connected.
  final Set<String> _autoLoginTried = {};

  late final StreamSubscription<List<String>> _deviceSubscription;
  final Map<String, StreamSubscription<List<double>>> _windowSubscriptions = {};

  Future<void> toggleRecording(String slot) async {
    if (state.recordingSlots.contains(slot)) {
      debugPrint('[HomeCubit] stopping $slot');
      await _windowSubscriptions[slot]?.cancel();
      _windowSubscriptions.remove(slot);
      await _recordingRepository.stopRecording(slot);
      emit(
        state.copyWith(
          recordingSlots: {...state.recordingSlots}..remove(slot),
          tags: {...state.tags}..remove(slot),
          tagLabels: {...state.tagLabels}..remove(slot),
        ),
      );
      return;
    }
    debugPrint('[HomeCubit] starting $slot');
    final device = await _deviceRepository.deviceForSlot(slot, state.registeredMics.map((m) => m.id).toList(),);
    await _recordingRepository.startRecording(slot, device);
    emit(state.copyWith(recordingSlots: {...state.recordingSlots, slot}));

    _windowSubscriptions[slot] = _recordingRepository.windowsFor(slot).listen((
        samples,
        ) async {
      final tag = await _taggingService.classify(
        samples,
        minConfidence: state.minConfidence,
      );
      final now = DateTime.now();
      if (tag == null) {
        debugPrint('[HomeCubit] $slot -> no_tags (below 50%)');
        emit(
          state.copyWith(
            tags: {...state.tags, slot: 'No Tags'},
            tagLabels: {...state.tagLabels, slot: 'no_tags'},
          ),
        );
        return;
      }
      final remarks =
          "${tag.label} (${(tag.confidence * 100).toStringAsFixed(0)}%)";
      debugPrint('[HomeCubit] $slot -> classified tag: $remarks');
      emit(
        state.copyWith(
          tags: {...state.tags, slot: remarks},
          tagLabels: {...state.tagLabels, slot: tag.label},
        ),
      );
      await _classificationRepository.insert(
        ClassificationRecord(
          slot: slot,
          tag: tag.label,
          confidence: tag.confidence,
          timestamp: now,
        ),
      );
      if (state.publishEnabled) {
        await _realtimeRepository.publishTag(slot, tag.label, tag.confidence);
      }
      if (state.postToCloudEnabled) {
        try {
          final token = _slotTokens[slot] ?? '';
          await _cloudApiService.postTagCloud(
            slot: slot,
            remarks: remarks,
            token: token,
          );
        } catch (e) {
          debugPrint(e.toString());
        }
        final fugoToken = _fugoTokens[slot];
        if (fugoToken != null) {
          try {
            await FugoMessageService().postMessage(
              token: fugoToken,
              message: "${tag.label} , ${(tag.confidence * 100).toStringAsFixed(0)}%",
            );
          } catch (e) {
            debugPrint('[HomeCubit] fugo post failed: $e');
          }
        }
      }
    });
  }

  void setMinConfidence(double value) {
    emit(state.copyWith(minConfidence: value));
    _settings.setMinConfidence(value);
  }

  void setPublishEnabled(bool value) {
    emit(state.copyWith(publishEnabled: value));
    _settings.setPublishEnabled(value);
  }

  void setPostToCloudEnabled(bool value) {
    emit(state.copyWith(postToCloudEnabled: value));
    _settings.setPostToCloudEnabled(value);
  }

  void setUseWebSocket(bool value) =>
      setTransport(value ? EspTransport.websocket : EspTransport.mqtt);

  Future<void> setTransport(EspTransport transport) async {
    if (transport == state.transport) return;

    final serviceRunning =
        !kIsWeb && (Platform.isAndroid || Platform.isIOS) && await FlutterForegroundTask.isRunningService;

    if (serviceRunning &&
        transport == EspTransport.bluetooth &&
        !await requestBluetoothPermissions()) {
      debugPrint('[HomeCubit] Bluetooth permission denied - staying on ${state.transport.label}');
      return;
    }

    emit(state.copyWith(transport: transport));
    await _settings.setTransport(transport);

    if (serviceRunning) {
      // 1) Tell the ESP32s to switch; the command travels over the CURRENT link.
      FlutterForegroundTask.sendDataToTask({
        'type': 'sendCommand',
        'value': transport.espCommand,
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // 2) Move the phone side over; the task restarts for the new transport.
      FlutterForegroundTask.sendDataToTask({
        'type': 'setConfig',
        'port': transport.defaultPort,
        'transport': transport.id,
        'useWebSocket': transport == EspTransport.websocket,
      });
    }
  }

  /// When an ESP32 connects, try to log in with its MAC (user id = password).
  /// Success  -> the device is already known to the server, so register it here.
  /// Failure  -> leave it for manual registration (Register Mic screen).
  void _autoRegisterConnected(List<String> devices) {
    final present = <String>{};

    for (final device in devices) {
      if (!isEspMicId(device)) continue; // local microphones are not auto-registered
      final id = normalizeMicId(device);
      present.add(id);

      if (_autoLoginTried.contains(id)) continue;
      if (state.registeredMics.any((m) => normalizeMicId(m.id) == id)) continue;

      _autoLoginTried.add(id);
      _tryAutoRegister(id);
    }

    // Forget devices that went away, so a reconnect gets a fresh attempt.
    _autoLoginTried.retainAll(present);
  }

  Future<void> _tryAutoRegister(String id) async {
    try {
      final login = await AuthApiService().login(userName: id, password: id);
      if (isClosed) return;

      if (!login.isSuccess) {
        debugPrint('[HomeCubit] $id has no account yet - register it manually');
        return;
      }

      // It may have been registered by hand while the login was running.
      if (state.registeredMics.any((m) => normalizeMicId(m.id) == id)) return;

      debugPrint('[HomeCubit] $id logged in - registering automatically');
      await registerMic(RegisteredMic(id: id, fullName: 'ESP32 ($id)'), login);
    } catch (e) {
      debugPrint('[HomeCubit] auto-register failed for $id: $e');
    }
  }

  Future<void> registerMic(RegisteredMic mic, LoginResponse micLogin) async {
    final updated = [...state.registeredMics, mic];
    emit(state.copyWith(registeredMics: updated));
    _settings.setRegisteredMics(updated);

    if (micLogin.isSuccess) {
      _slotTokens[mic.id] = micLogin.token;
      await _realtimeRepository.connectSlot(mic.id, micLogin.token2);

      try {
        final fugoToken = await UserChildrenApiService().findPrivateAdminTokenForSaeed(micLogin.token);
        if (fugoToken != null) {
          _fugoTokens[mic.id] = fugoToken;
        }
      } catch (_) {
        // fugo token unavailable for this newly registered mic
      }
    }
  }

  @override
  Future<void> close() async {
    await _deviceSubscription.cancel();
    for (final sub in _windowSubscriptions.values) {
      await sub.cancel();
    }
    await _recordingRepository.disposeAll();
    return super.close();
  }
}

class HomeState {
  const HomeState({
    this.registeredMics = const [],
    this.connectedDevices = const [],
    this.recordingSlots = const {},
    this.tags = const {},
    this.tagLabels = const {},
    this.minConfidence = 0.5,
    this.publishEnabled = true,
    this.postToCloudEnabled = false,
    this.transport = EspTransport.mqtt,
  });

  final List<RegisteredMic> registeredMics;
  final List<String> connectedDevices;
  final Set<String> recordingSlots;
  final Map<String, String> tags;
  final Map<String, String> tagLabels;
  final double minConfidence;
  final bool publishEnabled;
  final bool postToCloudEnabled;
  final EspTransport transport;

  bool get useWebSocket => transport == EspTransport.websocket;

  /// A slot is active when a connected device matches it, whether the device
  /// id is "esp32-AABBCCDDEEFF" or the bare MAC "AABBCCDDEEFF".
  bool isActive(String slot) {
    final key = normalizeMicId(slot);
    return connectedDevices.any((d) => d == slot || normalizeMicId(d) == key);
  }
  bool isRecording(String slot) => recordingSlots.contains(slot);
  String? tagFor(String slot) => tags[slot];
  String? labelFor(String slot) => tagLabels[slot];

  HomeState copyWith({
    List<RegisteredMic>? registeredMics,
    List<String>? connectedDevices,
    Set<String>? recordingSlots,
    Map<String, String>? tags,
    Map<String, String>? tagLabels,
    double? minConfidence,
    bool? publishEnabled,
    bool? postToCloudEnabled,
    EspTransport? transport,
  }) {
    return HomeState(
      registeredMics: registeredMics ?? this.registeredMics,
      connectedDevices: connectedDevices ?? this.connectedDevices,
      recordingSlots: recordingSlots ?? this.recordingSlots,
      tags: tags ?? this.tags,
      tagLabels: tagLabels ?? this.tagLabels,
      minConfidence: minConfidence ?? this.minConfidence,
      publishEnabled: publishEnabled ?? this.publishEnabled,
      postToCloudEnabled: postToCloudEnabled ?? this.postToCloudEnabled,
      transport: transport ?? this.transport,
    );
  }
}