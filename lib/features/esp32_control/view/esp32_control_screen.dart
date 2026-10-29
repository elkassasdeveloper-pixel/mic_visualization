import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hodhd_visualization/data/models/esp_transport.dart';
import 'package:hodhd_visualization/features/esp32_control/cubit/esp32_control_cubit.dart';

import 'package:hodhd_visualization/features/esp32_control/widgets/media_panel.dart';
import 'package:hodhd_visualization/features/esp32_control/widgets/security_key_card.dart';
import 'package:hodhd_visualization/features/smart_config/view/smart_config_screen.dart';

class Esp32ControlScreen extends StatelessWidget {
  const Esp32ControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => Esp32ControlCubit(),
      child: const _Esp32ControlView(),
    );
  }
}

class _Esp32ControlView extends StatelessWidget {
  const _Esp32ControlView();

  Future<void> _renameDevice(BuildContext context, Esp32ControlState state) async {
    final cubit = context.read<Esp32ControlCubit>();
    final mac = state.selectedMac;
    if (mac == allDevices) return;

    // No TextEditingController needed: the dialog field keeps its own text.
    var value = state.deviceNames[mac] ?? '';
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Name for ${formatMac(mac)}'),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          maxLength: 30,
          decoration: InputDecoration(
            hintText: state.deviceLabel(mac),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => value = v,
          onFieldSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(value),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null) return; // cancelled
    await cubit.renameDevice(mac, name);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<Esp32ControlCubit>();

    return BlocBuilder<Esp32ControlCubit, Esp32ControlState>(
      builder: (context, state) {
        final visibleMessages = state.visibleMessages;

        return Scaffold(
          appBar: AppBar(
            title: const Text('ESP32 Control'),
            actions: [
              IconButton(
                icon: const Icon(Icons.wifi),
                tooltip: 'WiFi Setup (SmartConfig)',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SmartConfigScreen(
                        targetMac: state.selectedMac,
                        targetName: state.selectedMac == allDevices
                            ? ''
                            : state.deviceLabel(state.selectedMac),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SecurityKeyCard(onKeyChanged: cubit.sendSecret),
                const SizedBox(height: 12),
                _buildBrokerCard(context, state),
                const SizedBox(height: 12),
                Text('Status: ${state.statusText}',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                _buildDeviceSelector(context, state),
                const SizedBox(height: 24),
                Text('Telemetry', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (visibleMessages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No messages received yet'),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: visibleMessages.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final msg = visibleMessages[index];
                      return ListTile(
                        dense: true,
                        title: Text(msg.payload,
                            style: const TextStyle(fontFamily: 'monospace')),
                        subtitle: Text(
                            '${msg.topic} (${state.clientLabel(msg.fromClientId)}) · ${msg.receivedAt.toIso8601String()}'),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDeviceSelector(BuildContext context, Esp32ControlState state) {
    final cubit = context.read<Esp32ControlCubit>();

    // Keep the selected device in the list even if it goes offline, so the
    // dropdown never ends up with a value that has no matching item.
    final macs = {
      ...state.deviceMacs,
      if (state.selectedMac != allDevices) state.selectedMac,
    }.toList()
      ..sort((a, b) => state
          .deviceLabel(a)
          .toLowerCase()
          .compareTo(state.deviceLabel(b).toLowerCase()));
    final values = <String>[allDevices, ...macs];

    String macLine(String mac) => state.deviceMacs.contains(mac)
        ? formatMac(mac)
        : '${formatMac(mac)} (offline)';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Target device',
              helperText: state.deviceMacs.isEmpty
                  ? 'No ESP32 connected yet'
                  : 'Telemetry is limited to the selected device',
              border: const OutlineInputBorder(),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: state.selectedMac,
                onChanged: state.running
                    ? (value) => cubit.selectDevice(value ?? allDevices)
                    : null,
                // What the closed dropdown shows (single line).
                selectedItemBuilder: (context) => [
                  for (final v in values)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        v == allDevices
                            ? 'All devices'
                            : '${state.deviceLabel(v)}  ·  ${formatMac(v)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                // What the open list shows: name + MAC underneath.
                items: [
                  for (final v in values)
                    DropdownMenuItem<String>(
                      value: v, // the MAC (no colons); '' = all devices
                      child: v == allDevices
                          ? const Text('All devices')
                          : Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(state.deviceLabel(v),
                              overflow: TextOverflow.ellipsis),
                          Text(
                            macLine(v),
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.edit),
            tooltip: 'Rename selected device',
            onPressed: state.selectedMac == allDevices
                ? null
                : () => _renameDevice(context, state),
          ),
        ),
      ],
    );
  }

  Widget _buildBrokerCard(BuildContext context, Esp32ControlState state) {
    final cubit = context.read<Esp32ControlCubit>();
    final running = state.running;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.transport.usesPort) ...[
              Text('This phone\'s IP address(es):',
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              if (state.localIps.isEmpty)
                const Text('Looking up...')
              else
                ...state.localIps.map((ip) => Text(ip)),
            ],
            const SizedBox(height: 4),
            const Text(
              'The service keeps running in the background (even if you swipe the app '
                  'away) thanks to the persistent notification - do not force-stop the app '
                  'from Android settings.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (state.transport.usesPort)
              TextField(
                controller: cubit.portController,
                enabled: !running,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Port'),
              ),
            const SizedBox(height: 12),
            Text('Connection', style: Theme.of(context).textTheme.labelLarge),
            // RadioGroup.onChanged cannot be null, so "disabled" is done by
            // blocking touches and dimming while a switch is in progress.
            IgnorePointer(
              ignoring: state.busy,
              child: Opacity(
                opacity: state.busy ? 0.5 : 1.0,
                child: RadioGroup<EspTransport>(
                  groupValue: state.transport,
                  onChanged: (value) {
                    if (!state.busy) cubit.changeTransport(value);
                  },
                  child: Column(
                    children: [
                      for (final t in EspTransport.values)
                        RadioListTile<EspTransport>(
                          contentPadding: EdgeInsets.zero,
                          value: t,
                          title: Text(t.label),
                          subtitle: Text(t.description),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: state.busy ? null : cubit.toggleServer,
              child: Text(
                state.transport == EspTransport.bluetooth
                    ? (running ? 'Stop Bluetooth' : 'Start Bluetooth')
                    : (running ? 'Stop Server' : 'Start Server'),
              ),
            ),
            const SizedBox(height: 4),
            Text('Connected clients: ${state.clientCount}'),
            const SizedBox(height: 12),
            // Camera frames and/or the equalizer, depending on the selected device.
            const MediaPanel(),
          ],
        ),
      ),
    );
  }
}