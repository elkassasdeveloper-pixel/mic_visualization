import 'package:flutter/material.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';
import 'package:mic_visualization/features/home/widgets/mic_icon_button.dart';

class MicIconRow extends StatelessWidget {
  const MicIconRow({
    super.key,
    required this.slots,
    required this.state,
    required this.onTap,
  });

  final List<String> slots;
  final HomeState state;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: slots
          .map((slot) => MicIconButton(
        isActive: state.isActive(slot),
        isRecording: state.isRecording(slot),
        tag: state.tagFor(slot),
        label: state.labelFor(slot),
        onTap: () => onTap(slot),
      ))
          .toList(),
    );
  }
}