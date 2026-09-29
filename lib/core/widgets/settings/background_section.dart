import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/core/theme/theme_cubit.dart';
import 'package:mic_visualization/core/widgets/settings/background_picker_tile.dart';

class BackgroundSection extends StatelessWidget {
  const BackgroundSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Background', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        BlocBuilder<ThemeCubit, ThemeState>(
          buildWhen: (prev, curr) => prev.lightBackgroundBytes != curr.lightBackgroundBytes,
          builder: (context, state) {
            return BackgroundPickerTile(
              label: 'Light theme background',
              currentBytes: state.lightBackgroundBytes,
              onChanged: context.read<ThemeCubit>().setLightBackground,
            );
          },
        ),
        BlocBuilder<ThemeCubit, ThemeState>(
          buildWhen: (prev, curr) => prev.darkBackgroundBytes != curr.darkBackgroundBytes,
          builder: (context, state) {
            return BackgroundPickerTile(
              label: 'Dark theme background',
              currentBytes: state.darkBackgroundBytes,
              onChanged: context.read<ThemeCubit>().setDarkBackground,
            );
          },
        ),
      ],
    );
  }
}