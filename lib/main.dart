import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_perf_monitor/flutter_perf_monitor.dart';
import 'package:mic_visualization/app/startup/startup_cubit.dart';
import 'package:mic_visualization/app/startup/startup_screen.dart';
import 'package:mic_visualization/core/theme/theme_cubit.dart';
import 'package:mic_visualization/core/widgets/custom_error_widget.dart';
import 'package:mic_visualization/data/local/settings_repository.dart';
import 'package:mic_visualization/data/repositories/auth_repository.dart';
import 'package:mic_visualization/data/repositories/realtime_repository.dart';
import 'package:mic_visualization/data/services/auth_api_service.dart';
import 'package:mic_visualization/data/services/database_ffi.dart';

void main() async{
  WidgetsFlutterBinding.ensureInitialized();
  // Required before runApp() when using flutter_foreground_task (Android only).
  if (!kIsWeb && Platform.isAndroid) {
    FlutterForegroundTask.initCommunicationPort();
  }
  initializeDatabaseFfi();
  FlutterPerfMonitor.initialize();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  final settingsRepository = await SettingsRepository.create();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return CustomErrorWidget(details: details);
  };
  runApp(MyApp(settingsRepository: settingsRepository));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.settingsRepository});

  final SettingsRepository settingsRepository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ThemeCubit(settingsRepository),
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            themeMode: themeState.themeMode,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark(),
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(themeState.fontScale),
                ),
                child: child!,
              );
            },
            home: BlocProvider(
              create: (context) =>
                  StartupCubit(
                      ApiAuthRepository(AuthApiService()),
                      CentrifugeRealtimeRepository(),
                      settingsRepository
                  ),
              child: StartupScreen(settingsRepository: settingsRepository,),
            ),
          );
        },
      ),
    );
  }
}