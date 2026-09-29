import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';
import 'package:mic_visualization/data/repositories/auth_repository.dart';
import 'package:mic_visualization/data/repositories/realtime_repository.dart';
import 'package:mic_visualization/data/services/user_children_api_service.dart';
import 'package:mic_visualization/features/home/data/audio_tagging_service.dart';

class StartupCubit extends Cubit<StartupState> {
  StartupCubit(this._authRepository, this._realtimeRepository, this._settings)
      : super(const StartupInitial());

  final AuthRepository _authRepository;
  final RealtimeRepository _realtimeRepository;
  final SettingsRepository _settings;

  static const String _adminUserId = 'saeed';
  static const String _adminPassword = 'zakigommah';

  Future<void> authenticate() async {
    emit(const StartupLoading());

    final adminLogin = await _authRepository.login(userName: _adminUserId, password: _adminPassword);
    if (!adminLogin.isSuccess) {
      emit(const StartupFailure());
      return;
    }

    final slotTokens = <String, String>{};
    final fugoTokens = <String, String>{};

    for (final mic in _settings.registeredMics) {
      final micLogin = await _authRepository.login(userName: mic.id, password: mic.id);
      if (!micLogin.isSuccess) continue;

      slotTokens[mic.id] = micLogin.token;
        await _realtimeRepository.connectSlot(mic.id, micLogin.token2);

      try {
        final fugoToken = await UserChildrenApiService().findPrivateAdminTokenForSaeed(micLogin.token);
        if (fugoToken != null) {
          fugoTokens[mic.id] = fugoToken;
        }
      } catch (_) {
        // fugo token unavailable — that mic just won't post fugo messages
      }
    }

    final taggingService = await AudioTaggingService.create();

    emit(StartupSuccess(
      taggingService: taggingService,
      realtimeRepository: _realtimeRepository,
      adminToken: adminLogin.token,
      slotTokens: slotTokens,
      fugoTokens: fugoTokens,
    ));
  }
}

sealed class StartupState {
  const StartupState();
}

class StartupInitial extends StartupState {
  const StartupInitial();
}

class StartupLoading extends StartupState {
  const StartupLoading();
}

class StartupFailure extends StartupState {
  const StartupFailure();
}

class StartupSuccess extends StartupState {
  const StartupSuccess({
    required this.taggingService,
    required this.realtimeRepository,
    required this.adminToken,
    required this.slotTokens,
    required this.fugoTokens,
  });

  final AudioTaggingService taggingService;
  final RealtimeRepository realtimeRepository;
  final String adminToken;
  final Map<String, String> slotTokens;
  final Map<String, String> fugoTokens;
}