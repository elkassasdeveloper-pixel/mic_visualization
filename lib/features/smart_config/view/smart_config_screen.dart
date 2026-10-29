import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_visualization/features/smart_config/cubit/smart_config_cubit.dart';

class SmartConfigScreen extends StatelessWidget {
  /// MAC (no colons) of the device chosen in the dropdown on the previous
  /// screen. Empty string means "all devices".
  final String targetMac;

  /// Friendly name of that device (empty when targeting all devices).
  final String targetName;

  const SmartConfigScreen({super.key, this.targetMac = '', this.targetName = ''});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SmartConfigCubit(targetMac: targetMac, targetName: targetName),
      child: const _SmartConfigView(),
    );
  }
}

class _SmartConfigView extends StatelessWidget {
  const _SmartConfigView();

  Future<void> _confirmReset(BuildContext context) async {
    final cubit = context.read<SmartConfigCubit>();
    final label = cubit.targetLabel;
    final all = cubit.targetMac.isEmpty;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset WiFi?'),
        content: Text(
          'This erases the saved WiFi credentials on $label and restarts '
              '${all ? 'them' : 'it'}. The device(s) will wait for '
              'SmartConfig provisioning again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed == true) await cubit.resetWifi();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SmartConfigCubit>();

    return Scaffold(
      appBar: AppBar(title: const Text('WiFi Setup (SmartConfig)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: BlocBuilder<SmartConfigCubit, SmartConfigState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: cubit.ssidController,
                    decoration: const InputDecoration(
                        labelText: 'WiFi SSID', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cubit.passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'WiFi Password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: !state.isProvisioning
                            ? ElevatedButton(
                          onPressed: cubit.startProvisioning,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Start Provisioning'),
                          ),
                        )
                            : ElevatedButton(
                          onPressed: cubit.stopProvisioning,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red),
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Stop'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: state.isProvisioning
                              ? null
                              : () => _confirmReset(context),
                          icon: const Icon(Icons.restart_alt),
                          label: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text('Reset WiFi'),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (state.isProvisioning) const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(state.status, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  if (state.connectedDevices.isNotEmpty) ...[
                    const Text('Connected devices:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true, // size to its content
                      physics: const NeverScrollableScrollPhysics(), // the outer view scrolls
                      itemCount: state.connectedDevices.length,
                      itemBuilder: (context, index) => ListTile(
                        leading: const Icon(Icons.check_circle, color: Colors.green),
                        title: Text(state.connectedDevices[index]),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}