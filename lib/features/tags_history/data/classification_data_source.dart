import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:mic_visualization/data/models/classification_record.dart';

class ClassificationDataSource extends DataGridSource {
  ClassificationDataSource(List<ClassificationRecord> records,List<RegisteredMic> registeredMics) {
    final nameById = {for (final mic in registeredMics) mic.id: mic.fullName};
    _rows = records.map((r) => _buildRow(r, nameById)).toList();
  }

  late List<DataGridRow> _rows;
  final _dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

  DataGridRow _buildRow(ClassificationRecord record, Map<String, String> nameById) {
    return DataGridRow(cells: [
      DataGridCell<String>(columnName: 'slot', value:nameById[record.slot] ?? record.slot),
      DataGridCell<String>(columnName: 'tag', value: record.tag),
      DataGridCell<String>(
        columnName: 'confidence',
        value:'${(record.confidence * 100).toStringAsFixed(0)}%'
           ,
      ),
      DataGridCell<String>(
        columnName: 'timestamp',
        value: _dateFormat.format(record.timestamp),
      ),
    ]);
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(child: Text(cell.value.toString(),style: const TextStyle(fontSize: 24,),)),
        );
      }).toList(),
    );
  }
}