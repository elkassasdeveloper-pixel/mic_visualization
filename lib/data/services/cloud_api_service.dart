import 'package:dio/dio.dart';
import 'package:mic_visualization/core/constants/api_endpoints.dart';
import 'package:mic_visualization/data/models/classification_record.dart';

class CloudApiService {
  CloudApiService({Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));

  final Dio _dio;

  Future<void> postTagCloud({
    required String slot,
    required String remarks,
    required String token,
  }) async {
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';

    await _dio.post(
      ApiEndpoints.addToCloud,
      queryParameters: {
        "m_code" : "1",
        "app_id" : "tl"
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
      data: {
        'attendance_id': 0,
        'user_attendance_id': slot,
        'attendance_type_code': 5,
        'attendance_date': date,
        'attendance_time': time,
        'branch_num': 0,
        'person_id': 0,
        'emp_num': 0,
        'statistic_maps': '',
        'attendance_ip': '',
        'attendance_longitude': '',
        'attendance_latitude': '',
        'is_on_time': '',
        'attendance_device': '',
        'remarks': remarks,
        'fk_user_attendance_id_descr': '',
        'fk_attendance_type_code_descr': '',
        'fk_branch_num_descr': '',
        'fk_person_id_descr': '',
        'fk_emp_num_descr': '',
      },
    );
  }

  Future<CloudListResult> getList({
    required int pageNumber,
    required int pageSize,
    required String token,
    String? slot,
    DateTime? from,
    DateTime? to,
  }) async {
    final response = await _dio.get(
      ApiEndpoints.getFromCloud,
      options: Options(
        headers: {
          'Authorization': 'Bearer $token',
        },
      ),
      queryParameters: {
        'm_code': 1,
        'app_id': 'tl',
        'pageSize': pageSize,
        'pageNumber': pageNumber,
        'attendance_type_code': 5,
        'FilterType': 3,
        'user_attendance_id': ?slot,
        if (from != null) 'date_from': _formatDate(from),
        if (to != null) 'date_to': _formatDate(to),
      },
    );

    final json = response.data as Map<String, dynamic>;
    final rawList = json['data'] as List<dynamic>? ?? [];
    final numberOfPages = json['numberOfPages'] as int? ?? 1;

    final records = rawList
        .map((e) => _toClassificationRecord(e as Map<String, dynamic>))
        .toList();

    return CloudListResult(records: records, hasMore: pageNumber < numberOfPages);
  }

  String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
  }

  ClassificationRecord _toClassificationRecord(Map<String, dynamic> json) {
    final slot = json['attendance_user_name'] as String? ?? '';
    final remarks = json['remarks'] as String? ?? '';

    final match = RegExp(r'^(.*) \((\d+)%\)$').firstMatch(remarks);
    final tag = match != null ? match.group(1)! : remarks;
    final confidence = match != null ? int.parse(match.group(2)!) / 100.0 : 0.0;

    final dateStr = json['attendance_date'] as String? ?? '';
    final timeStr = json['attendance_time'] as String? ?? '';
    final timestamp = _parseTimestamp(dateStr, timeStr);

    return ClassificationRecord(slot: slot, tag: tag, confidence: confidence, timestamp: timestamp);
  }

  DateTime _parseTimestamp(String dateStr, String timeStr) {
    try {
      final year = int.parse(dateStr.substring(0, 4));
      final month = int.parse(dateStr.substring(4, 6));
      final day = int.parse(dateStr.substring(6, 8));
      final paddedTime = timeStr.padLeft(4, '0');
      final hour = int.parse(paddedTime.substring(0, 2));
      final minute = int.parse(paddedTime.substring(2, 4));
      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return DateTime.now();
    }
  }
}

class CloudListResult {
  const CloudListResult({required this.records, required this.hasMore});
  final List<ClassificationRecord> records;
  final bool hasMore;
}