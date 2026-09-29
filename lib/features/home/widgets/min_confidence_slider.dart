import 'package:flutter/material.dart';

class MinConfidenceSlider extends StatelessWidget {
  const MinConfidenceSlider({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Min confidence: ${(value * 100).toStringAsFixed(0)}%',
          style: const TextStyle(fontSize: 16),
        ),
        SizedBox(
          width: 300,
          child: Slider(
            value: value,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            label: '${(value * 100).toStringAsFixed(0)}%',
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}