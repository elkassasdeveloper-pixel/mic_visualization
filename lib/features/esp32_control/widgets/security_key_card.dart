import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hodhd_visualization/data/security/secure_channel.dart';
import 'package:hodhd_visualization/data/security/security_key_store.dart';

/// Read-only status of the key bundled with the app.
class SecurityKeyCard extends StatelessWidget {
  const SecurityKeyCard({super.key, this.onKeyChanged});

  /// Kept so existing call sites compile; the key can no longer change.
  final void Function(Uint8List? key)? onKeyChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FutureBuilder<Uint8List?>(
          future: SecurityKeyStore.load(),
          builder: (context, snapshot) {
            final key = snapshot.data;
            final text = snapshot.connectionState != ConnectionState.done
                ? 'Loading key...'
                : key == null
                ? 'No key found in the app: the link is NOT encrypted.'
                : 'Encryption key built into the app. Fingerprint: '
                '${SecureChannel(key).fingerprint}';
            return Row(
              children: [
                Icon(key == null ? Icons.lock_open : Icons.lock_outline),
                const SizedBox(width: 8),
                Expanded(child: Text(text)),
              ],
            );
          },
        ),
      ),
    );
  }
}