import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_perf_monitor/flutter_perf_monitor.dart';

class PerfMonitorCard extends StatefulWidget {
  const PerfMonitorCard({super.key});

  @override
  State<PerfMonitorCard> createState() => _PerfMonitorCardState();
}

class _PerfMonitorCardState extends State<PerfMonitorCard> {
  Timer? _timer;
  double _fps = 0;
  double _memoryUsedMb = 0;
  List<double> _perCoreCpu = const [];

  @override
  void initState() {
    super.initState();
    FlutterPerfMonitor.startMonitoring();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  void _refresh() {
    final fps =  FlutterPerfMonitor.getFPS();
    final memoryBytes =  FlutterPerfMonitor.getMemoryUsage();
    final cpu =  FlutterPerfMonitor.getPerCoreCpuUsage();

    if (!mounted) return;
    setState(() {
      _fps = fps;
      _memoryUsedMb = memoryBytes / (1024 * 1024);
      _perCoreCpu = cpu;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    FlutterPerfMonitor.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avgCpu = _perCoreCpu.isEmpty ? 0.0 : _perCoreCpu.reduce((a, b) => a + b) / _perCoreCpu.length;

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
          Text('FPS: ${_fps.toStringAsFixed(1)}'),
          Text('Memory: ${_memoryUsedMb.toStringAsFixed(1)} MB'),
          Text('CPU (avg): ${avgCpu.toStringAsFixed(1)}%'),
        ],
      ),
    );
  }
}