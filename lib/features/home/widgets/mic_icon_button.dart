import 'package:flutter/material.dart';
import 'package:mic_visualization/core/constants/tag_images.dart';

class MicIconButton extends StatelessWidget {
  const MicIconButton({
    super.key,
    required this.isActive,
    this.isRecording = false,
    this.tag,
    this.label,
    this.onTap,
    this.size = 48,
  });

  final bool isActive;
  final bool isRecording;
  final String? tag;
  final String? label;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final imagePath = label != null ? TagImages.forLabel(label!) : null;
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: isActive ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic,
            size: size,
            color: !isActive
                ? onSurface.withValues(alpha: 0.35)
                : isRecording
                ? theme.colorScheme.error
                : onSurface,
          ),
          if (!isActive)
             Text('not active', style: TextStyle(fontSize: 30, color: theme.colorScheme.error)),
          if (isActive && isRecording && tag != null)
            Text(tag!, style: const TextStyle(fontSize: 30,color: Colors.blue)),
          if (imagePath != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Image.asset(imagePath, width: 280, height: 280, fit: BoxFit.cover),
            ),
        ],
      ),
    );
  }
}