import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/core/theme/theme_cubit.dart';

class ThemeSwitchTile extends StatelessWidget {
  const ThemeSwitchTile({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark mode'),
          value: state.themeMode == ThemeMode.dark,
          onChanged: context.read<ThemeCubit>().toggleDarkMode,
        );
      },
    );
  }
}