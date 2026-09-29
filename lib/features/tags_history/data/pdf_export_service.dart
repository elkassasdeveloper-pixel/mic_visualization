import 'dart:typed_data';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:mic_visualization/core/utils/save_file.dart';
import 'package:mic_visualization/data/models/classification_record.dart';
import 'package:flutter/material.dart';

class PdfExportService {
  Future<String> export(List<ClassificationRecord> records) async {
    final document = PdfDocument();
    final page = document.pages.add();

    final grid = PdfGrid();
    grid.columns.add(count: 4);
    grid.headers.add(1);

    final header = grid.headers[0];
    header.cells[0].value = 'Slot';
    header.cells[1].value = 'Tag';
    header.cells[2].value = 'Confidence';
    header.cells[3].value = 'Timestamp';

    for (final record in records) {
      final row = grid.rows.add();
      row.cells[0].value = record.slot;
      row.cells[1].value = record.tag;
      row.cells[2].value = '${(record.confidence * 100).toStringAsFixed(0)}%';
      row.cells[3].value = record.timestamp.toString();
    }

    grid.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 0, page.getClientSize().width, page.getClientSize().height),
    );

    final bytes = document.saveSync();
    document.dispose();

    return saveFileBytes(
      Uint8List.fromList(bytes),
      'tags_history_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}