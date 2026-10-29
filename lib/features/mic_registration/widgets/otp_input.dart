import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpInput extends StatelessWidget {
  const OtpInput({
    super.key,
    required this.length,
    required this.onChanged,
    this.controller,
    this.focusNode,
  });

  final int length;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final effectiveController = controller ?? TextEditingController();
    final effectiveFocusNode = focusNode ?? FocusNode();
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => effectiveFocusNode.requestFocus(),
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            child: SizedBox(
              height: 1,
              child: TextField(
                controller: effectiveController,
                focusNode: effectiveFocusNode,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(length),
                ],
                autofocus: true,
                onChanged: onChanged,
              ),
            ),
          ),
          // Visual cells, purely presentational.
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: effectiveController,
            builder: (context, value, _) {
              final text = value.text;
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(length, (index) {
                  final char = index < text.length ? text[index] : '';
                  final isActive = index == text.length;

                  return Container(
                    width: 35,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive ? theme.colorScheme.primary : theme.colorScheme.outline,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    child: Text(char, style: theme.textTheme.headlineSmall),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}
