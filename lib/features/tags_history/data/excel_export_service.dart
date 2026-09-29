import 'dart:typed_data';
import 'package:syncfusion_flutter_xlsio/xlsio.dart';
import 'package:mic_visualization/core/utils/save_file.dart';
import 'package:mic_visualization/data/models/classification_record.dart';

class ExcelExportService {
  Future<String> export(List<ClassificationRecord> records) async {
    final workbook = Workbook();
    final sheet = workbook.worksheets[0];

    sheet.getRangeByName('A1').setText('Slot');
    sheet.getRangeByName('B1').setText('Tag');
    sheet.getRangeByName('C1').setText('Confidence');
    sheet.getRangeByName('D1').setText('Timestamp');

    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      final row = i + 2;
      sheet.getRangeByIndex(row, 1).setText(record.slot);
      sheet.getRangeByIndex(row, 2).setText(record.tag);
      sheet.getRangeByIndex(row, 3).setText('${(record.confidence * 100).toStringAsFixed(0)}%',
      );
      sheet.getRangeByIndex(row, 4).setText(record.timestamp.toString());
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();

    return saveFileBytes(
      Uint8List.fromList(bytes),
      'tags_history_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
  }
}