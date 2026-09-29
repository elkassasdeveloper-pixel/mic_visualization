import 'package:flutter/material.dart';
import 'package:mic_visualization/core/constants/tag_images.dart';
import 'package:mic_visualization/features/home/widgets/mic_icon_button.dart';

class DraggableMicButton extends StatelessWidget {
  const DraggableMicButton({
    super.key,
    required this.isActive,
    required this.isRecording,
    this.tag,
    this.label,
    required this.onTap,
    required this.fractionalPosition,
    required this.containerSize,
    required this.onPositionChanged,
    required this.onDragEnd,
  });

  final bool isActive;
  final bool isRecording;
  final String? tag;
  final String? label;
  final VoidCallback onTap;
  final Offset fractionalPosition;
  final Size containerSize;
  final ValueChanged<Offset> onPositionChanged;
  final VoidCallback onDragEnd;

  static const double _iconSize = 48;
  static const double _textLineHeight = 40;
  static const double _imageSize = 280;
  static const double _compactBox = 70; // icon alone, with a little slack
  static const double _textBoxWidth = 260;
  static const double _imageBoxWidth = 300;

  // Mirrors MicIconButton's actual conditional rendering, so the reserved
  // drag box always matches what will really be on screen.
  (double width, double height) _footprint() {
    final imagePath = label != null ? TagImages.forLabel(label!) : null;

    double height = _iconSize;
    double width = _compactBox;

    if (!isActive) {
      height += _textLineHeight; // "not active"
      width = _textBoxWidth;
    } else if (isRecording && tag != null) {
      height += _textLineHeight; // tag text
      width = _textBoxWidth;
    }

    if (imagePath != null) {
      height += 4 + _imageSize;
      width = _imageBoxWidth;
    }

    return (width, height + 8); // small buffer
  }

  @override
  Widget build(BuildContext context) {
    final (widgetWidth, widgetHeight) = _footprint();

    final rawPixel = Offset(
      fractionalPosition.dx * containerSize.width,
      fractionalPosition.dy * containerSize.height,
    );

    final left = (rawPixel.dx - widgetWidth / 2)
        .clamp(0.0, (containerSize.width - widgetWidth).clamp(0.0, double.infinity));
    final top = (rawPixel.dy - widgetHeight / 2)
        .clamp(0.0, (containerSize.height - widgetHeight).clamp(0.0, double.infinity));

    return Positioned(
      left: left,
      top: top,
      width: widgetWidth,
      child: GestureDetector(
        onPanUpdate: (details) {
          final newCenter = Offset(left + widgetWidth / 2, top + widgetHeight / 2) + details.delta;
          onPositionChanged(Offset(
            newCenter.dx / containerSize.width,
            newCenter.dy / containerSize.height,
          ));
        },
        onPanEnd: (_) => onDragEnd(),
        child: MicIconButton(isActive: isActive, isRecording: isRecording, tag: tag, label: label, onTap: onTap),
      ),
    );
  }
}