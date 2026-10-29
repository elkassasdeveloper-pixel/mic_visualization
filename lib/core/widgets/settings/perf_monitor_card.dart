import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_perf_monitor/flutter_perf_monitor.dart';

class PerfMonitorCard extends StatelessWidget {
  const PerfMonitorCard({super.key});

  static Stream<_PerfData> _createPerfStream() {
    late StreamController<_PerfData> controller;
    Timer? timer;

    void update() {
      final fps = FlutterPerfMonitor.getFPS();
      final memoryBytes = FlutterPerfMonitor.getMemoryUsage();
      final cpu = FlutterPerfMonitor.getPerCoreCpuUsage();
      final memoryUsedMb = memoryBytes / (1024 * 1024);
      final avgCpu = cpu.isEmpty ? 0.0 : cpu.reduce((a, b) => a + b) / cpu.length;

      if (!controller.isClosed) {
        controller.add(_PerfData(
          fps: fps,
          memoryMb: memoryUsedMb,
          avgCpu: avgCpu,
        ));
      }
    }

    controller = StreamController<_PerfData>.broadcast(
      onListen: () {
        FlutterPerfMonitor.startMonitoring();
        update();
        timer = Timer.periodic(const Duration(seconds: 1), (_) => update());
      },
      onCancel: () {
        timer?.cancel();
        FlutterPerfMonitor.stopMonitoring();
        controller.close();
      },
    );

    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<_PerfData>(
      stream: _createPerfStream(),
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _PerfData(fps: 0, memoryMb: 0, avgCpu: 0);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Performance', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Text('FPS: ${data.fps.toStringAsFixed(1)}'),
              Text('Memory: ${data.memoryMb.toStringAsFixed(1)} MB'),
              Text('CPU (avg): ${data.avgCpu.toStringAsFixed(1)}%'),
            ],
          ),
        );
      },
    );
  }
}

class _PerfData {
  const _PerfData({
    required this.fps,
    required this.memoryMb,
    required this.avgCpu,
  });

  final double fps;
  final double memoryMb;
  final double avgCpu;
}
