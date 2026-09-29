class ApiEndpoints {
  ApiEndpoints._();

  static const String baseUrl = 'https://tasklistapi.erpfirst.net/api';
  static const String messageBaseUrl = 'https://islahsearchapi.hodhdsoft.com/api';

  static const String login = '/HodhdAuthorization/login';
  static const String addToCloud = '/SysAttendanceTrans/Add';
  static const String getFromCloud = '/SysAttendanceTrans/GetList';
  static const String addSysUser = '/HodhdSysUser/Add';
  static const String userChildren = '/HodhdAuthorization/user_childern';
  static const String addFugoMessage = '/FugoMessage/Add';
}