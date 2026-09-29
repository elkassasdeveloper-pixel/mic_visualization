import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class BackgroundPickerTile extends StatelessWidget {
  const BackgroundPickerTile({
    super.key,
    required this.label,
    required this.currentBytes,
    required this.onChanged,
  });

  final String label;
  final Uint8List? currentBytes;
  final ValueChanged<Uint8List?> onChanged;

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);

    if (file == null) return; // user canceled

    final bytes = await file.readAsBytes();
    onChanged(bytes);
  }


  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: currentBytes != null
                ? Image.memory(currentBytes!, width: 56, height: 56, fit: BoxFit.cover)
                : Container(
              width: 56,
              height: 56,
              color: Colors.grey.shade300,
              child: const Icon(Icons.image_not_supported, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (currentBytes != null)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Reset to default',
              onPressed: () => onChanged(null),
            ),
          OutlinedButton(onPressed: _pickImage, child: const Text('Choose')),
        ],
      ),
    );
  }
}