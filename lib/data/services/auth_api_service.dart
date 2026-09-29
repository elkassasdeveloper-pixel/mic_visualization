import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mic_visualization/core/constants/api_endpoints.dart';
import 'package:mic_visualization/data/models/login_response.dart';

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
    final response = await _dio.post(
      ApiEndpoints.login,
      data: {
        'user_id': userName,
        'password': password,
      },
    );
    debugPrint('[Auth] response for "$userName": ${response.statusCode} ${response.data}');
    return LoginResponse.fromJson(response.data as Map<String, dynamic>);
  }
}