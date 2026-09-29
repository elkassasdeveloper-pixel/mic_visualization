import 'package:dio/dio.dart';
import 'package:mic_visualization/core/constants/api_endpoints.dart';

class SysUserApiService {
  SysUserApiService({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
  final Dio _dio;

  Future<void> addUser({
    required String userId,
    required String password,
    required String fullName,
    required String token,
  }) async {
    await _dio.post(
      ApiEndpoints.addSysUser,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
      queryParameters: {"m_code" : 1},
      data: {
        'user_id': userId,
        'user_full_name': fullName,
        'job_title': '',
        'password': password,
        'work_email': '',
        'private_email': '',
        'mobile_no1': '',
        'mobile_no2': '',
        'remarks': '',
        'max_discount': 0,
        'is_admin': 'N',
        'is_active': 'Y',
        'curr_company_num': 0,
        'curr_year_num': 0,
        'curr_branch_num': 0,
        'emp_num': 0,
        'fk_curr_branch_num_descr': '',
        'fk_emp_num_descr': '',
      },
    );
  }
}