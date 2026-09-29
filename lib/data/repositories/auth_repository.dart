import 'package:mic_visualization/data/models/login_response.dart';
import 'package:mic_visualization/data/services/auth_api_service.dart';

abstract class AuthRepository {
  Future<LoginResponse> login({required String userName, required String password});
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._service);
  final AuthApiService _service;

  @override
  Future<LoginResponse> login({required String userName, required String password}) {
    return _service.login(userName: userName, password: password);
  }
}