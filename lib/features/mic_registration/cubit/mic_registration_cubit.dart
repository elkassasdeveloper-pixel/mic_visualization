import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:mic_visualization/data/services/auth_api_service.dart';
import 'package:mic_visualization/data/services/sysuser_api_service.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';

class MicRegistrationCubit extends Cubit<MicRegistrationState> {
  MicRegistrationCubit(this._homeCubit, this._token) : super(_buildInitialState()) {
    userIdController.text = state.uuid;
    passwordController.text = state.uuid;
  }

  final HomeCubit _homeCubit;
  final String _token;

  static String _generateShortId() {
    final uuid = const Uuid().v4().replaceAll('-', '');
    return uuid.substring(0, 20);
  }

  static MicRegistrationState _buildInitialState() {
    final uuid = _generateShortId();
    return MicRegistrationState(
      uuid: uuid,
      userIdController: TextEditingController(),
      passwordController: TextEditingController(),
    );
  }

  TextEditingController get userIdController => state.userIdController;
  TextEditingController get passwordController => state.passwordController;

  void selectAllUserId() {
    userIdController.selection = TextSelection(baseOffset: 0, extentOffset: userIdController.text.length);
  }

  void selectAllPassword() {
    passwordController.selection = TextSelection(baseOffset: 0, extentOffset: passwordController.text.length);
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

  Future<void> register() async {
    if (state.fullName.trim().isEmpty) return;

    emit(state.copyWith(isSubmitting: true, errorMessage: null));

    try {
      await SysUserApiService().addUser(
        userId: state.uuid,
        password: state.uuid,
        fullName: state.fullName.trim(),
        token: _token,
      );

      final micLogin = await AuthApiService().login(userName: state.uuid, password: state.uuid);

      await _homeCubit.registerMic(
        RegisteredMic(id: state.uuid, fullName: state.fullName.trim()),
        micLogin,
      );

      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      emit(state.copyWith(isSubmitting: false, errorMessage: e.toString()));
    }
  }

  @override
  Future<void> close() {
    userIdController.dispose();
    passwordController.dispose();
    return super.close();
  }
}

class MicRegistrationState {
  const MicRegistrationState({
    required this.uuid,
    required this.userIdController,
    required this.passwordController,
    this.fullName = '',
    this.isSubmitting = false,
    this.isSuccess = false,
    this.errorMessage,
  });

  final String uuid;
  final TextEditingController userIdController;
  final TextEditingController passwordController;
  final String fullName;
  final bool isSubmitting;
  final bool isSuccess;
  final String? errorMessage;

  MicRegistrationState copyWith({
    String? fullName,
    bool? isSubmitting,
    bool? isSuccess,
    String? errorMessage,
  }) {
    return MicRegistrationState(
      uuid: uuid,
      userIdController: userIdController,
      passwordController: passwordController,
      fullName: fullName ?? this.fullName,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSuccess: isSuccess ?? this.isSuccess,
      errorMessage: errorMessage,
    );
  }
}