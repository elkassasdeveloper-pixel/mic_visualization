import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mic_visualization/data/models/classification_record.dart';
import 'package:mic_visualization/data/models/registered_mic.dart';
import 'package:mic_visualization/data/repositories/classification_repository.dart';
import 'package:mic_visualization/features/tags_history/data/excel_export_service.dart';
import 'package:mic_visualization/features/tags_history/data/pdf_export_service.dart';

class TagsHistoryCubit extends Cubit<TagsHistoryState> {
  TagsHistoryCubit(this._repository,List<RegisteredMic> registeredMics ,{
    PdfExportService? pdfExportService,
    ExcelExportService? excelExportService
  }) :
        _pdfExportService = pdfExportService ?? PdfExportService(),
        _excelExportService = excelExportService ?? ExcelExportService(),
        super(TagsHistoryState(registeredMics: registeredMics)) {
    loadInitial();
  }

  final ClassificationRepository _repository;
  final PdfExportService _pdfExportService;
  final ExcelExportService _excelExportService;
  static const int pageSize = 50;

  Future<void> loadInitial() async {
    debugPrint('[TagsHistory] loadInitial — selectedSlot=${state.selectedSlot}');
    emit(state.copyWith(isLoading: true, records: [], hasMore: true, offset: 0));
    final records = await _repository.page(
      limit: pageSize,
      offset: 0,
      from: state.fromDate,
      to: state.toDate,
      slot: state.selectedSlot,
    );
    debugPrint('[TagsHistory] loadInitial result — ${records.length} rows, slots: ${records.map((r) => r.slot).toSet()}');
    emit(state.copyWith(
      records: records,
      isLoading: false,
      hasMore: records.length == pageSize,
      offset: records.length,
    ));
  }

  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;
    debugPrint('[TagsHistory] loadMore — selectedSlot=${state.selectedSlot}, offset=${state.offset}');
    emit(state.copyWith(isLoading: true));
    final more = await _repository.page(
      limit: pageSize,
      offset: state.offset,
      from: state.fromDate,
      to: state.toDate,
      slot: state.selectedSlot,
    );
    emit(state.copyWith(
      records: [...state.records, ...more],
      isLoading: false,
      hasMore: more.length == pageSize,
      offset: state.offset + more.length,
    ));
  }

  Future<void> setFromDate(DateTime? date) async {
    emit(state.copyWith(fromDate: date, clearFromDate: date == null));
    await loadInitial();
  }

  Future<void> setToDate(DateTime? date) async {
    emit(state.copyWith(toDate: date, clearToDate: date == null));
    await loadInitial();
  }

  Future<void> setSlot(String? slot) async {
    debugPrint('[TagsHistory] setSlot called with: $slot');
    emit(state.copyWith(selectedSlot: slot, clearSlot: slot == null));
    debugPrint('[TagsHistory] state.selectedSlot after emit: ${state.selectedSlot}');
    await loadInitial();
  }

  Future<String> exportToPdf() => _pdfExportService.export(state.records);

  Future<String> exportToExcel() => _excelExportService.export(state.records);

  Future<void> deleteAll() async {
    await _repository.deleteAll();
    emit(state.copyWith(records: [], hasMore: false, offset: 0));
  }
}

class TagsHistoryState {
  const TagsHistoryState({
    this.records = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.offset = 0,
    this.fromDate,
    this.toDate,
    this.selectedSlot,
  this.registeredMics = const [],
  });

  final List<ClassificationRecord> records;
  final bool isLoading;
  final bool hasMore;
  final int offset;
  final DateTime? fromDate;
  final DateTime? toDate;
  final String? selectedSlot;
  final List<RegisteredMic> registeredMics;

  TagsHistoryState copyWith({
    List<ClassificationRecord>? records,
    bool? isLoading,
    bool? hasMore,
    int? offset,
    DateTime? fromDate,
    DateTime? toDate,
    String? selectedSlot,
    List<RegisteredMic>? registeredMics,
    bool clearFromDate = false,
    bool clearToDate = false,
    bool clearSlot = false,
  }) {
    return TagsHistoryState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      offset: offset ?? this.offset,
      fromDate: clearFromDate ? null : (fromDate ?? this.fromDate),
      toDate: clearToDate ? null : (toDate ?? this.toDate),
      selectedSlot: clearSlot ? null : (selectedSlot ?? this.selectedSlot),
      registeredMics: registeredMics ?? this.registeredMics,
    );
  }
}