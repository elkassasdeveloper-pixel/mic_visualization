import 'package:flutter/material.dart';

// Custom painter that renders the equalizer bars.
class EqualizerPainter extends CustomPainter {
  final List<double> barHeights;

  EqualizerPainter({required this.barHeights});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [Colors.cyanAccent, Colors.blueAccent, Colors.purpleAccent],
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    const double spacing = 6.0;
    final double totalSpacing = spacing * (barHeights.length - 1);
    final double barWidth = (size.width - totalSpacing) / barHeights.length;

    for (int i = 0; i < barHeights.length; i++) {
      final double x = i * (barWidth + spacing);
      final double barHeight = barHeights[i] * size.height;
      final double y = size.height - barHeight;

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        const Radius.circular(4.0),
      );

      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant EqualizerPainter oldDelegate) {
    return oldDelegate.barHeights != barHeights;
  }
}