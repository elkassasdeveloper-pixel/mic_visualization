import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_visualization/app/startup/startup_cubit.dart';
import 'package:hodhd_visualization/data/local/settings_repository.dart';
import 'package:hodhd_visualization/features/home/view/home_screen.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key, required this.settingsRepository});
  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StartupCubit, StartupState>(
      builder: (context, state) {
        return switch (state) {
          StartupInitial() || StartupLoading() =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
          StartupFailure() => const Scaffold(body: Center(child: Text('Login failed'))),
          StartupSuccess(:final taggingService, :final realtimeRepository, :final adminToken, :final slotTokens, :final fugoTokens) =>
              HomeScreen(
                taggingService: taggingService,
                realtimeRepository: realtimeRepository,
                settingsRepository: settingsRepository,
                adminToken: adminToken,
                slotTokens: slotTokens,
                fugoTokens: fugoTokens,
              ),
        };
      },
    );
  }
}