import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';
import 'package:mic_visualization/data/models/classification_record.dart';
import 'package:mic_visualization/data/models/login_response.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:mic_visualization/data/repositories/classification_repository.dart';
import 'package:mic_visualization/data/repositories/realtime_repository.dart';
import 'package:mic_visualization/data/services/cloud_api_service.dart';
import 'package:mic_visualization/data/services/fugo_message_service.dart';
import 'package:mic_visualization/data/services/user_children_api_service.dart';
import 'package:mic_visualization/features/home/data/audio_tagging_service.dart';
import 'package:mic_visualization/features/home/data/mic_device_repository.dart';
import 'package:mic_visualization/features/home/data/mic_recording_repository.dart';

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
      )) {
    _deviceSubscription = _deviceRepository
        .watchConnectedDevices(() => state.registeredMics.map((m) => m.id).toList())
        .listen((devices) => emit(state.copyWith(connectedDevices: devices)));
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
  });

  final List<RegisteredMic> registeredMics;
  final List<String> connectedDevices;
  final Set<String> recordingSlots;
  final Map<String, String> tags;
  final Map<String, String> tagLabels;
  final double minConfidence;
  final bool publishEnabled;
  final bool postToCloudEnabled;

  bool isActive(String slot) => connectedDevices.contains(slot);
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
    );
  }
}
