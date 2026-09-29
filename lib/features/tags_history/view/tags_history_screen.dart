import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:mic_visualization/data/repositories/classification_repository.dart';
import 'package:mic_visualization/features/tags_history/cubit/tags_history_cubit.dart';
import 'package:mic_visualization/features/tags_history/data/classification_data_source.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

class TagsHistoryScreen extends StatelessWidget {
  const TagsHistoryScreen({super.key, required this.classificationRepository, required this.registeredMics});

  final ClassificationRepository classificationRepository;
  final List<RegisteredMic> registeredMics;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TagsHistoryCubit(classificationRepository,registeredMics),
      child: const _TagsHistoryView(),
    );
  }
}

class _TagsHistoryView extends StatelessWidget {
  const _TagsHistoryView();

  Future<void> _pickDate(BuildContext context, {required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (picked == null) return;
    if (!context.mounted) return;

    final cubit = context.read<TagsHistoryCubit>();
    if (isFrom) {
      cubit.setFromDate(picked);
    } else {
      cubit.setToDate(picked.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tags History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Export PDF'),
                    onPressed: () async {
                      final cubit = context.read<TagsHistoryCubit>();
                      final result = await cubit.exportToPdf();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved: $result')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.grid_on),
                    label: const Text('Export Excel'),
                    onPressed: () async {
                      final cubit = context.read<TagsHistoryCubit>();
                      final result = await cubit.exportToExcel();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Saved: $result')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  tooltip: 'Delete all history',
                  onPressed: () async {
                    final cubit = context.read<TagsHistoryCubit>();
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Delete all history?'),
                        content: const Text('This permanently removes every recorded tag. This cannot be undone.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true),
                            child: const Text('Delete', style: TextStyle(color: Colors.red)),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true) {
                      await cubit.deleteAll();
                    }
                  },
                ),
              ],
            ),
          ),
          BlocBuilder<TagsHistoryCubit, TagsHistoryState>(
            buildWhen: (prev, curr) =>
            prev.selectedSlot != curr.selectedSlot ||
                prev.fromDate != curr.fromDate ||
                prev.toDate != curr.toDate,
            builder: (context, state) {
              final cubit = context.read<TagsHistoryCubit>();
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: DropdownButton<String?>(
                      value: state.selectedSlot,
                      isExpanded: true,
                      hint: const Text('Slot'),
                      items: [
                        const DropdownMenuItem<String?>(value: null, child: Text('All slots')),
                        ...state.registeredMics.map(
                              (mic) => DropdownMenuItem<String?>(value: mic.id, child: Text(mic.fullName)),
                        ),
                      ],
                      onChanged: cubit.setSlot,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(context, isFrom: true),
                            child: Text(state.fromDate == null
                                ? 'From date'
                                : state.fromDate!.toString().split(' ').first),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _pickDate(context, isFrom: false),
                            child: Text(state.toDate == null
                                ? 'To date'
                                : state.toDate!.toString().split(' ').first),
                          ),
                        ),
                        if (state.fromDate != null || state.toDate != null)
                          IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              cubit.setFromDate(null);
                              cubit.setToDate(null);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BlocBuilder<TagsHistoryCubit, TagsHistoryState>(
              buildWhen: (prev, curr) =>
              prev.records != curr.records ||
                  (prev.isLoading != curr.isLoading && curr.records.isEmpty),
              builder: (context, state) {
                final cubit = context.read<TagsHistoryCubit>();

                if (state.records.isEmpty && state.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state.records.isEmpty) {
                  return const Center(child: Text('No tags recorded yet',style: TextStyle(fontSize: 30),));
                }

                return SfDataGridTheme(
                  data: const SfDataGridThemeData(headerColor: Colors.blue),
                  child: SfDataGrid(
                    source: ClassificationDataSource(state.records,state.registeredMics),
                    columnWidthMode: ColumnWidthMode.fill,
                    gridLinesVisibility: GridLinesVisibility.both,
                    headerGridLinesVisibility: GridLinesVisibility.both,
                    loadMoreViewBuilder: (context, loadMoreRows) {
                      Future<String> loadRows() async {
                        if (!state.hasMore) return 'done';
                        await cubit.loadMore();
                        return 'done';
                      }
                  
                      return FutureBuilder<String>(
                        future: loadRows(),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return Container(
                              height: 60,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                border: Border(top: BorderSide(color: Colors.grey, width: 0.5)),
                              ),
                              child: const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      );
                    },
                    columns: [
                      GridColumn(
                        columnName: 'slot',
                        label: const Center(child: Text('Slot',style: TextStyle(fontSize: 24,color: Colors.white),)),
                      ),
                      GridColumn(
                        columnName: 'tag',
                        label: const Center(child: Text('Tag',style: TextStyle(fontSize: 24,color: Colors.white),)),
                      ),
                      GridColumn(
                        columnName: 'confidence',
                        label: const Center(child: Text('Confidence',style: TextStyle(fontSize: 24,color: Colors.white),)),
                      ),
                      GridColumn(
                        columnName: 'timestamp',
                        label: const Center(child: Text('Timestamp',style: TextStyle(fontSize: 24,color: Colors.white),)),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}