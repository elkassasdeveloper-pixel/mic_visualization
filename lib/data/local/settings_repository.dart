import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static Future<SettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs);
  }

  // Theme
  ThemeMode get themeMode => _prefs.getString('themeMode') == 'dark' ? ThemeMode.dark : ThemeMode.light;
  Future<void> setThemeMode(ThemeMode mode) => _prefs.setString('themeMode', mode == ThemeMode.dark ? 'dark' : 'light');

  double get fontScale => _prefs.getDouble('fontScale') ?? 1.0;
  Future<void> setFontScale(double value) => _prefs.setDouble('fontScale', value);

  Uint8List? get lightBackgroundBytes {
    final b64 = _prefs.getString('lightBackground');
    return b64 != null ? base64Decode(b64) : null;
  }

  Future<void> setLightBackgroundBytes(Uint8List? bytes) {
    if (bytes == null) return _prefs.remove('lightBackground');
    return _prefs.setString('lightBackground', base64Encode(bytes));
  }

  Uint8List? get darkBackgroundBytes {
    final b64 = _prefs.getString('darkBackground');
    return b64 != null ? base64Decode(b64) : null;
  }

  Future<void> setDarkBackgroundBytes(Uint8List? bytes) {
    if (bytes == null) return _prefs.remove('darkBackground');
    return _prefs.setString('darkBackground', base64Encode(bytes));
  }

  // HomeCubit settings
  double get minConfidence => _prefs.getDouble('minConfidence') ?? 0.5;
  Future<void> setMinConfidence(double value) => _prefs.setDouble('minConfidence', value);

  bool get publishEnabled => _prefs.getBool('publishEnabled') ?? true;
  Future<void> setPublishEnabled(bool value) => _prefs.setBool('publishEnabled', value);

  bool get postToCloudEnabled => _prefs.getBool('postToCloudEnabled') ?? false;
  Future<void> setPostToCloudEnabled(bool value) => _prefs.setBool('postToCloudEnabled', value);

  // Layout positions (slot -> [dx, dy] fractional)
  Map<String, Offset>? _decodePositions(String? json) {
    if (json == null) return null;
    final map = jsonDecode(json) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, Offset((v[0] as num).toDouble(), (v[1] as num).toDouble())));
  }

  String _encodePositions(Map<String, Offset> positions) {
    return jsonEncode(positions.map((k, v) => MapEntry(k, [v.dx, v.dy])));
  }

  Map<String, Offset>? get homeLayoutPositions => _decodePositions(_prefs.getString('homeLayout'));
  Future<void> setHomeLayoutPositions(Map<String, Offset> positions) =>
      _prefs.setString('homeLayout', _encodePositions(positions));

  Map<String, Offset>? get hudLayoutPositions => _decodePositions(_prefs.getString('hudLayout'));
  Future<void> setHudLayoutPositions(Map<String, Offset> positions) =>
      _prefs.setString('hudLayout', _encodePositions(positions));

  List<RegisteredMic> get registeredMics {
    final raw = _prefs.getString('registeredMics');
    if (raw == null) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => RegisteredMic.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> setRegisteredMics(List<RegisteredMic> mics) {
    return _prefs.setString('registeredMics', jsonEncode(mics.map((m) => m.toJson()).toList()));
  }

  Future<void> clearAll() async {
    await _prefs.clear();
  }
}