import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';

class RegisteredMicsDataSource extends DataGridSource {
  RegisteredMicsDataSource(List<RegisteredMic> mics, this.onCellCopied) {
    _rows = mics.map(_buildRow).toList();
  }

  late List<DataGridRow> _rows;
  final void Function(String copiedValue) onCellCopied;

  DataGridRow _buildRow(RegisteredMic mic) {
    return DataGridRow(cells: [
      DataGridCell<String>(columnName: 'id', value: mic.id),
      DataGridCell<String>(columnName: 'name', value: mic.fullName),
    ]);
  }

  @override
  List<DataGridRow> get rows => _rows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        final text = cell.value.toString();
        return GestureDetector(
          onLongPress: () async{
            await Clipboard.setData(ClipboardData(text: text));
            onCellCopied(text);
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(cell.value.toString(),style:const TextStyle(fontSize: 24),),
          ),
        );
      }).toList(),
    );
  }
}