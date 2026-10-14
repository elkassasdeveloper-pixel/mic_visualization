import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/core/widgets/settings/appearance_section.dart';
import 'package:mic_visualization/core/widgets/settings/background_section.dart';
import 'package:mic_visualization/core/widgets/settings/layout_reset_tile.dart';
import 'package:mic_visualization/core/widgets/settings/perf_monitor_card.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';
import 'package:mic_visualization/data/repositories/classification_repository.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';
import 'package:mic_visualization/features/home/cubit/home_layout_cubit.dart';
import 'package:mic_visualization/features/home/widgets/min_confidence_slider.dart';
import 'package:mic_visualization/features/mic_registration/view/mic_registration_screen.dart';
import 'package:mic_visualization/features/registered_mics/view/registered_mics_screen.dart';
import 'package:mic_visualization/features/tags_history/view/tags_history_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.classificationRepository, required this.adminToken, required this.settingsRepository});

  final ClassificationRepository classificationRepository;
  final String adminToken;
  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const PerfMonitorCard(),
          const Divider(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.mic_external_on),
            label: const Text('Register new mic'),
            onPressed: () {
              final homeCubit = context.read<HomeCubit>();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BlocProvider.value(
                  value: homeCubit,
  child: MicRegistrationScreen(token: adminToken),
)),
              );
            },
          ),
          const Divider(height: 32),
          OutlinedButton.icon(
            icon: const Icon(Icons.list),
            label: const Text('View registered mics'),
            onPressed: () {
              final homeCubit = context.read<HomeCubit>();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => BlocProvider.value(
                  value: homeCubit,
  child: const RegisteredMicsScreen(),
)),
              );
            },
          ),
          const Divider(height: 32),
          Text('Detection', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          BlocBuilder<HomeCubit, HomeState>(
            buildWhen: (prev, curr) => prev.minConfidence != curr.minConfidence,
            builder: (context, state) {
              return MinConfidenceSlider(
                value: state.minConfidence,
                onChanged: context.read<HomeCubit>().setMinConfidence,
              );
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.list_alt),
            label: const Text('View tags history'),
            onPressed: () {
              final registeredMics = context.read<HomeCubit>().state.registeredMics;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TagsHistoryScreen(
                    classificationRepository: classificationRepository,
                    registeredMics: registeredMics,
                  ),
                ),
              );
            },
          ),
          const Divider(height: 32),

          Text('Data sharing', style: Theme.of(context).textTheme.titleMedium),
          BlocBuilder<HomeCubit, HomeState>(
            buildWhen: (prev, curr) =>
                prev.publishEnabled != curr.publishEnabled,
            builder: (context, state) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Send data through Centrifugo'),
                subtitle: const Text(
                  'When off, tags are still saved locally but not broadcast live',
                ),
                value: state.publishEnabled,
                onChanged: context.read<HomeCubit>().setPublishEnabled,
              );
            },
          ),
          BlocBuilder<HomeCubit, HomeState>(
            buildWhen: (prev, curr) =>
                prev.postToCloudEnabled != curr.postToCloudEnabled,
            builder: (context, state) {
              return SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Post tags to Cloud API'),
                subtitle: const Text(
                  'Sends each classified tag as an attendance record',
                ),
                value: state.postToCloudEnabled,
                onChanged: context.read<HomeCubit>().setPostToCloudEnabled,
              );
            },
          ),
          const Divider(height: 32),

          const AppearanceSection(),
          const Divider(height: 32),

          const BackgroundSection(),
          const Divider(height: 32),

          LayoutResetTile(
            label: 'Reset mic positions',
            onReset: () => context.read<HomeLayoutCubit>().resetToDefault(),
          ),
          const Divider(height: 32),
          Text('Danger zone', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.delete_sweep, color: Colors.red),
            label: const Text('Clear cache', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Clear cache?'),
                  content: const Text(
                    'This resets theme, background photos, confidence threshold, '
                        'toggles, layout positions, and removes all registered mics. '
                        'This cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: const Text('Clear', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );

              if (confirmed != true) return;
              if (!context.mounted) return;

              await settingsRepository.clearAll();

              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared — restart the app for changes to fully apply')),
              );
            },
          ),
        ],
      ),
    );
  }
}
