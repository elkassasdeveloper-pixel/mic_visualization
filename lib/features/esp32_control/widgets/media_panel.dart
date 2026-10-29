import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_visualization/features/esp32_control/cubit/esp32_control_cubit.dart';
import 'package:hodhd_visualization/features/esp32_control/widgets/equalizer_painter.dart';

/// What the selected device sends:
///   camera only    -> camera frames
///   microphone only-> equalizer
///   both           -> camera frames above the equalizer
///   nothing yet    -> equalizer (idle), as before
class MediaPanel extends StatelessWidget {
  const MediaPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<Esp32ControlCubit>();

    return BlocBuilder<Esp32ControlCubit, Esp32ControlState>(
      buildWhen: (p, c) =>
      p.showVideo != c.showVideo ||
          p.showEqualizer != c.showEqualizer ||
          p.selectedMac != c.selectedMac,
      builder: (context, state) {
        final showEqualizer = state.showEqualizer || !state.showVideo;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.showVideo) _VideoView(cubit: cubit),
            if (state.showVideo && showEqualizer) const SizedBox(height: 12),
            if (showEqualizer) _EqualizerView(cubit: cubit),
          ],
        );
      },
    );
  }
}

class _VideoView extends StatelessWidget {
  const _VideoView({required this.cubit});

  final Esp32ControlCubit cubit;

  @override
  Widget build(BuildContext context) {
    // Rebuilds on its own for every frame, without rebuilding the screen.
    return ValueListenableBuilder<VideoFrame?>(
      valueListenable: cubit.video,
      builder: (context, frame, _) {
        if (frame == null) {
          return const SizedBox(
            height: 160,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 8),
                  Text('Waiting for camera...'),
                ],
              ),
            ),
          );
        }
        final label = cubit.state.deviceLabel(frame.mac);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Image.memory(
                  frame.bytes,
                  gaplessPlayback: true, // no flicker between frames
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                  const SizedBox(height: 120, child: Center(child: Text('Corrupted frame dropped'))),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}

class _EqualizerView extends StatelessWidget {
  const _EqualizerView({required this.cubit});

  final Esp32ControlCubit cubit;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<double>>(
      valueListenable: cubit.equalizer,
      builder: (context, bars, _) => Container(
        height: 200,
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: CustomPaint(
          painter: EqualizerPainter(barHeights: bars),
          child: Container(),
        ),
      ),
    );
  }
}