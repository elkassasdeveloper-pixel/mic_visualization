import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/features/home/cubit/home_cubit.dart';
import 'package:mic_visualization/features/mic_registration/cubit/mic_registration_cubit.dart';
import 'package:mic_visualization/features/mic_registration/widgets/otp_input.dart';

class MicRegistrationScreen extends StatelessWidget {
  const MicRegistrationScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    final homeCubit = context.read<HomeCubit>();
    return BlocProvider(
      create: (_) => MicRegistrationCubit(homeCubit, token),
      child: const _MicRegistrationView(),
    );
  }
}

class _MicRegistrationView extends StatelessWidget {
  const _MicRegistrationView();

  Future<void> _showOtpDialog(BuildContext context) async {
    final cubit = context.read<MicRegistrationCubit>();
    String currentOtp = '';
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            return AlertDialog(
              title: const Text('Enter OTP'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OtpInput(
                    length: 6,
                    onChanged: (value) {
                      currentOtp = value;
                      if (errorText != null) setState(() => errorText = null);
                    },
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: TextStyle(color: Theme.of(dialogContext).colorScheme.error)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    if (cubit.verifyOtp(currentOtp)) {
                      Navigator.of(dialogContext).pop(true);
                    } else {
                      setState(() => errorText = 'Incorrect code');
                    }
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      cubit.register();
    }
  }

  void _onRegisterPressed(BuildContext context) {
    final cubit = context.read<MicRegistrationCubit>();
    final error = cubit.validate();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _showOtpDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MicRegistrationCubit, MicRegistrationState>(
      listenWhen: (prev, curr) => prev.isSuccess != curr.isSuccess || prev.errorMessage != curr.errorMessage,
      listener: (context, state) {
        if (state.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration success')),
          );
          Navigator.of(context).pop();
          return;
        }
        if (state.errorMessage != null) {
          debugPrint(state.errorMessage);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Registration failed: ${state.errorMessage}')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Register Mic')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: BlocBuilder<MicRegistrationCubit, MicRegistrationState>(
            builder: (context, state) {
              final cubit = context.read<MicRegistrationCubit>();

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connected devices',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (state.availableDevices.isEmpty)
                      const Text(
                        'No unregistered device is connected right now. '
                            'Connect one, or type its MAC address below.',
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final id in state.availableDevices)
                            ChoiceChip(
                              label: Text(id),
                              selected: state.micId == id,
                              onSelected: (_) => cubit.selectDevice(id),
                            ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: cubit.macController,
                      onChanged: cubit.setMicId,
                      onTap: cubit.selectAllMac,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'MAC address (User ID)',
                        helperText: 'Without "esp32-", e.g. AABBCCDDEEFF',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cubit.passwordController,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                      onTap: cubit.selectAllPassword,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: cubit.setFullName,
                      decoration: const InputDecoration(labelText: 'Full name'),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: state.isSubmitting ? null : () => _onRegisterPressed(context),
                      child: state.isSubmitting
                          ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Register'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}