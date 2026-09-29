import 'package:flutter/material.dart';

class LayoutResetTile extends StatelessWidget {
  const LayoutResetTile({super.key, required this.label, required this.onReset});

  final String label;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Layout', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.restart_alt),
          label: Text(label),
          onPressed: onReset,
        ),
      ],
    );
  }
}