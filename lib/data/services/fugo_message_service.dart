import 'package:dio/dio.dart';
import 'package:mic_visualization/core/constants/api_endpoints.dart';

class FugoMessageService {
  FugoMessageService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: ApiEndpoints.messageBaseUrl));
  final Dio _dio;

  Future<void> postMessage({required String token, required String message}) async {
    await _dio.post(
      ApiEndpoints.addFugoMessage,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
      data: {'message': message},
    );
  }
}