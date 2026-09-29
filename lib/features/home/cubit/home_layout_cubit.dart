import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/core/constants/mic_slots.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';

class HomeLayoutCubit extends Cubit<HomeLayoutState> {
  HomeLayoutCubit(this._settings)
      : super(HomeLayoutState(positions: _settings.homeLayoutPositions ?? _defaults));

  final SettingsRepository _settings;

  static const Map<String, Offset> _defaults = {
    MicSlots.topLeft: Offset(0.08, 0.08),
    MicSlots.topRight: Offset(0.92, 0.08),
    MicSlots.center: Offset(0.5, 0.5),
    MicSlots.bottomLeft: Offset(0.08, 0.92),
    MicSlots.bottomRight: Offset(0.92, 0.92),
  };

  void updatePosition(String slot, Offset fractionalPosition) {
    final clamped = Offset(fractionalPosition.dx.clamp(0.0, 1.0), fractionalPosition.dy.clamp(0.0, 1.0));
    emit(state.copyWith(positions: {...state.positions, slot: clamped}));
  }

  void commitPositions() {
    _settings.setHomeLayoutPositions(state.positions);
  }

  void resetToDefault() {
    emit(const HomeLayoutState(positions: _defaults));
    _settings.setHomeLayoutPositions(_defaults);
  }
}

class HomeLayoutState {
  const HomeLayoutState({required this.positions});

  final Map<String, Offset> positions;

  Offset positionFor(String slot) => positions[slot] ?? const Offset(0.5, 0.5);

  HomeLayoutState copyWith({Map<String, Offset>? positions}) {
    return HomeLayoutState(positions: positions ?? this.positions);
  }
}