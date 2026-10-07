import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';
import 'package:mic_visualization/data/repositories/classification_repository.dart';
import 'package:mic_visualization/data/repositories/realtime_repository.dart';
import 'package:mic_visualization/data/services/cloud_api_service.dart';
import 'package:mic_visualization/features/esp32_control/view/esp32_control_screen.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';
import 'package:mic_visualization/features/home/cubit/home_layout_cubit.dart';
import 'package:mic_visualization/features/home/data/audio_tagging_service.dart';
import 'package:mic_visualization/features/home/data/mic_device_repository.dart';
import 'package:mic_visualization/features/home/data/parec_mic_recording_repository.dart';
import 'package:mic_visualization/features/home/data/record_backed_mic_recording_repository.dart';
import 'package:mic_visualization/features/home/widgets/draggable_mic_button.dart';
import 'package:mic_visualization/features/home/widgets/home_background.dart';
import 'package:mic_visualization/features/settings/view/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.taggingService,
    required this.realtimeRepository,
    required this.settingsRepository,
    required this.adminToken,
    required this.slotTokens,
    required this.fugoTokens,
  });

  final AudioTaggingService taggingService;
  final RealtimeRepository realtimeRepository;
  final SettingsRepository settingsRepository;
  final String adminToken;
  final Map<String, String> fugoTokens;
  final Map<String, String> slotTokens;

  @override
  Widget build(BuildContext context) {
    final classificationRepository = SqfliteClassificationRepository();

    // The providers wrap the whole Scaffold (not just the body) so the drawer
    // can also reach HomeCubit / HomeLayoutCubit, which Settings needs.
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => HomeCubit(
            RecordMicDeviceRepository(),
            Platform.isLinux ? ParecMicRecordingRepository() : RecordBackedMicRecordingRepository(),
            taggingService,
            realtimeRepository,
            classificationRepository,
            CloudApiService(),
            settingsRepository,
            slotTokens,
            fugoTokens,
          ),
        ),
        BlocProvider(create: (_) => HomeLayoutCubit(settingsRepository)),
      ],
      child: Builder(
        builder: (context) => Scaffold(
          drawer: _buildDrawer(context, classificationRepository),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: HomeBackground(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final containerSize = Size(constraints.maxWidth, constraints.maxHeight);

                  return BlocBuilder<HomeCubit, HomeState>(
                    builder: (context, state) {
                      final cubit = context.read<HomeCubit>();
                      final layoutCubit = context.read<HomeLayoutCubit>();

                      return BlocBuilder<HomeLayoutCubit, HomeLayoutState>(
                        builder: (context, layout) {
                          return Stack(
                            children: [
                              for (final mic in state.registeredMics)
                                DraggableMicButton(
                                  isActive: state.isActive(mic.id),
                                  isRecording: state.isRecording(mic.id),
                                  tag: state.tagFor(mic.id),
                                  label: state.labelFor(mic.id),
                                  onTap: () => cubit.toggleRecording(mic.id),
                                  fractionalPosition: layout.positionFor(mic.id),
                                  containerSize: containerSize,
                                  onPositionChanged: (pos) => layoutCubit.updatePosition(mic.id, pos),
                                  onDragEnd: layoutCubit.commitPositions,
                                ),
                              Positioned(
                                top: 0,
                                left: 0,
                                child: Builder(
                                  builder: (ctx) => IconButton(
                                    icon: const Icon(Icons.menu),
                                    tooltip: 'Menu',
                                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ESP32 provisioning/broker features rely on Android-only plugins
  /// (foreground service + SmartConfig), so the entry is hidden elsewhere.
  bool get _esp32Supported => !kIsWeb && Platform.isAndroid;

  Widget _buildDrawer(
      BuildContext context,
      SqfliteClassificationRepository classificationRepository,
      ) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ListTile(
            title: Text('Menu', style: Theme.of(context).textTheme.headlineLarge),
          ),
          const Divider(thickness: 1,),
          if (_esp32Supported)
            ListTile(
              titleTextStyle: Theme.of(context).textTheme.titleMedium,
              subtitleTextStyle: Theme.of(context).textTheme.bodyMedium,
              leading: const Icon(Icons.lightbulb_outline),
              title: const Text('ESP32 LED Control'),
              subtitle: const Text('MQTT broker & WiFi setup'),
              onTap: () {
                Navigator.of(context).pop(); // close the drawer
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const Esp32ControlScreen(),
                  ),
                );
              },
            ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            titleTextStyle: Theme.of(context).textTheme.titleMedium,
            onTap: () {
              // Read the cubits first, then close the drawer and navigate.
              final cubit = context.read<HomeCubit>();
              final layoutCubit = context.read<HomeLayoutCubit>();

              Navigator.of(context).pop(); // close the drawer
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => MultiBlocProvider(
                    providers: [
                      BlocProvider.value(value: cubit),
                      BlocProvider.value(value: layoutCubit),
                    ],
                    child: SettingsScreen(
                      classificationRepository: classificationRepository,
                      adminToken: adminToken,
                      settingsRepository: settingsRepository,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}