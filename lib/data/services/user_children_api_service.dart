import 'package:dio/dio.dart';
import 'package:mic_visualization/core/constants/api_endpoints.dart';
import 'package:mic_visualization/data/models/user_child.dart';

class UserChildrenApiService {
  UserChildrenApiService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
  final Dio _dio;

  Future<String?> findPrivateAdminTokenForSaeed(String token) async {
    final response = await _dio.get(
      ApiEndpoints.userChildren,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final json = response.data as Map<String, dynamic>;
    final data = json['data'] as List<dynamic>? ?? [];

    for (final entry in data) {
      final child = UserChild.fromJson(entry as Map<String, dynamic>);
      if (child.secondUserId == 'saeed') {
        return child.privateAdmin;
      }
    }
    return null;
  }
}