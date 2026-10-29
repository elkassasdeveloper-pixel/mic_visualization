import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:hodhd_visualization/core/constants/api_endpoints.dart';
import 'package:hodhd_visualization/data/models/login_response.dart';

class AuthApiService {
  AuthApiService({Dio? dio})
      : _dio = dio ??
      Dio(BaseOptions(
        baseUrl: ApiEndpoints.baseUrl,
      ));

  final Dio _dio;

  Future<LoginResponse> login({
    required String userName,
    required String password,
  }) async {
    debugPrint('[Auth] POST ${ApiEndpoints.login} for "$userName"');
    try {
      final response = await _dio.post(
        ApiEndpoints.login,
        data: {
          'user_id': userName,
          'password': password,
        },
      );
      debugPrint('[Auth] response for "$userName": ${response.statusCode} ${response.data}');
      if (response.data is Map<String, dynamic>) {
        return LoginResponse.fromJson(response.data as Map<String, dynamic>);
      }
      return const LoginResponse(token: '', token2: '', userId: '', isSuccess: false);
    } on DioException catch (e) {
      debugPrint('[Auth] Login failed for "$userName": ${e.response?.statusCode} ${e.message}');
      return const LoginResponse(token: '', token2: '', userId: '', isSuccess: false);
    } catch (e) {
      debugPrint('[Auth] Unexpected error logging in "$userName": $e');
      return const LoginResponse(token: '', token2: '', userId: '', isSuccess: false);
    }
  }
}
