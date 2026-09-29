import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/core/theme/theme_cubit.dart';

class FontScaleSlider extends StatelessWidget {
  const FontScaleSlider({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Font size: ${(state.fontScale * 100).toStringAsFixed(0)}%'),
            Slider(
              value: state.fontScale,
              min: 0.8,
              max: 1.6,
              divisions: 16,
              label: '${(state.fontScale * 100).toStringAsFixed(0)}%',
              onChanged: context.read<ThemeCubit>().setFontScale,
            ),
          ],
        );
      },
    );
  }
}