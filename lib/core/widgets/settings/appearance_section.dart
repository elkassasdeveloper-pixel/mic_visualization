import 'package:flutter/material.dart';
import 'package:mic_visualization/core/widgets/settings/font_scale_slider.dart';
import 'package:mic_visualization/core/widgets/settings/theme_switch_tile.dart';

class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const ThemeSwitchTile(),
        const FontScaleSlider(),
      ],
    );
  }
}