import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit(this._settings)
      : super(ThemeState(
    themeMode: _settings.themeMode,
    fontScale: _settings.fontScale,
    lightBackgroundBytes: _settings.lightBackgroundBytes,
    darkBackgroundBytes: _settings.darkBackgroundBytes,
  ));

  final SettingsRepository _settings;

  void toggleDarkMode(bool isDark) {
    final mode = isDark ? ThemeMode.dark : ThemeMode.light;
    emit(state.copyWith(themeMode: mode));
    _settings.setThemeMode(mode);
  }

  void setFontScale(double scale) {
    emit(state.copyWith(fontScale: scale));
    _settings.setFontScale(scale);
  }

  void setLightBackground(Uint8List? bytes) {
    emit(state.copyWith(lightBackgroundBytes: bytes, clearLightBackground: bytes == null));
    _settings.setLightBackgroundBytes(bytes);
  }

  void setDarkBackground(Uint8List? bytes) {
    emit(state.copyWith(darkBackgroundBytes: bytes, clearDarkBackground: bytes == null));
    _settings.setDarkBackgroundBytes(bytes);
  }
}

class ThemeState {
  const ThemeState({
    this.themeMode = ThemeMode.light,
    this.fontScale = 1.0,
    this.lightBackgroundBytes,
    this.darkBackgroundBytes,
  });

  final ThemeMode themeMode;
  final double fontScale;
  final Uint8List? lightBackgroundBytes;
  final Uint8List? darkBackgroundBytes;

  ThemeState copyWith({
    ThemeMode? themeMode,
    double? fontScale,
    Uint8List? lightBackgroundBytes,
    Uint8List? darkBackgroundBytes,
    bool clearLightBackground = false,
    bool clearDarkBackground = false,
  }) {
    return ThemeState(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      lightBackgroundBytes:
      clearLightBackground ? null : (lightBackgroundBytes ?? this.lightBackgroundBytes),
      darkBackgroundBytes:
      clearDarkBackground ? null : (darkBackgroundBytes ?? this.darkBackgroundBytes),
    );
  }
}
