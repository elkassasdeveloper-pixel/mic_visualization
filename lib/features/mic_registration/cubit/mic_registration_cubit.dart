import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:mic_visualization/data/services/auth_api_service.dart';
import 'package:mic_visualization/data/services/sysuser_api_service.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';

class MicRegistrationCubit extends Cubit<MicRegistrationState> {
  MicRegistrationCubit(this._homeCubit, this._token)
      : super(MicRegistrationState(availableDevices: _available(_homeCubit))) {
    // Keep the "connected devices" list live while the screen is open.
    _homeSub = _homeCubit.stream.listen(
          (_) => emit(state.copyWith(availableDevices: _available(_homeCubit))),
    );
  }

  final HomeCubit _homeCubit;
  final String _token;
  StreamSubscription<HomeState>? _homeSub;

  final TextEditingController macController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  /// Connected devices that are not registered yet, as bare MAC addresses.
  static List<String> _available(HomeCubit home) {
    final registered =
    home.state.registeredMics.map((m) => normalizeMicId(m.id)).toSet();
    final ids = <String>{};
    for (final device in home.state.connectedDevices) {
      final id = normalizeMicId(device);
      if (id.isNotEmpty && !registered.contains(id)) ids.add(id);
    }
    return ids.toList()..sort();
  }

  /// Picks one of the connected devices.
  void selectDevice(String id) {
    macController.text = id;
    setMicId(id);
  }

  /// Called when the MAC field is edited (or a device is picked).
  void setMicId(String raw) {
    final id = normalizeMicId(raw);
    // The backend password is the id itself, same as before with the uuid.
    passwordController.text = id;
    emit(state.copyWith(micId: id));
  }

  void selectAllMac() {
    macController.selection =
        TextSelection(baseOffset: 0, extentOffset: macController.text.length);
  }

  void selectAllPassword() {
    passwordController.selection = TextSelection(
        baseOffset: 0, extentOffset: passwordController.text.length);
  }

  void setFullName(String fullName) {
    emit(state.copyWith(fullName: fullName));
  }

  String get expectedOtp {
    final now = DateTime.now();
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    final year = (now.year % 100).toString().padLeft(2, '0');
    return '$day$month$year';
  }

  bool verifyOtp(String otp) => otp == expectedOtp;

  /// Returns an error message, or null when the form can be submitted.
  String? validate() {
    if (state.micId.isEmpty) {
      return 'Select a connected device or enter its MAC address';
    }
    if (state.fullName.trim().isEmpty) return 'Full name is required';
    final taken = _homeCubit.state.registeredMics
        .any((m) => normalizeMicId(m.id) == state.micId);
    if (taken) return 'This device is already registered';
    return null;
  }

  Future<void> register() async {
    final error = validate();
    if (error != null) {
      emit(state.copyWith(errorMessage: error));
      return;
    }

    emit(state.copyWith(isSubmitting: true, errorMessage: null));

    try {
      final id = state.micId; // MAC address, no "esp32-" prefix
      final name = state.fullName.trim();

      await SysUserApiService().addUser(
        userId: id,
        password: id,
        fullName: name,
        token: _token,
      );

      final micLogin = await AuthApiService().login(userName: id, password: id);

      await _homeCubit.registerMic(
        RegisteredMic(id: id, fullName: name),
        micLogin,
      );

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _homeSub?.cancel();
    macController.dispose();
    passwordController.dispose();
    return super.close();
  }
}

class MicRegistrationState {
  const MicRegistrationState({
    this.micId = '',
    this.availableDevices = const [],
    this.fullName = '',
    this.isSubmitting = false,
    this.isSuccess = false,
    this.errorMessage,
  });

  /// Normalized MAC address that will be used as user id / slot id.
  final String micId;
  final List<String> availableDevices;
  final String fullName;
  final bool isSubmitting;
  final bool isSuccess;
  final String? errorMessage;

  MicRegistrationState copyWith({
    String? micId,
    List<String>? availableDevices,
    String? fullName,
    bool? isSubmitting,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return MicRegistrationState(
      micId: micId ?? this.micId,
      availableDevices: availableDevices ?? this.availableDevices,
      fullName: fullName ?? this.fullName,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage,
    );
  }
}