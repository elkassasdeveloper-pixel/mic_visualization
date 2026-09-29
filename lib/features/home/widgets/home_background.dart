import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/core/constants/app_images.dart';
import 'package:mic_visualization/core/theme/theme_cubit.dart';

class HomeBackground extends StatelessWidget {
  const HomeBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        final isLight = state.themeMode == ThemeMode.light;
        final customBytes = isLight ? state.lightBackgroundBytes : state.darkBackgroundBytes;

        final ImageProvider imageProvider = customBytes != null
            ? MemoryImage(customBytes)
            : AssetImage(isLight ? AppImages.car : AppImages.darkCar) as ImageProvider;

        return Container(
          decoration: BoxDecoration(
            image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
          ),
          child: child,
        );
      },
    );
  }
}