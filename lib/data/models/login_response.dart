class LoginResponse {
  const LoginResponse({
    required this.token,
    required this.token2,
    required this.userId,
   required this.isSuccess,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    final isSuccess = json['isSuccess'] as bool? ?? false;
    final data = json['data'] as Map<String, dynamic>?;

    if (!isSuccess || data == null) {
      return const LoginResponse(
        userId: '',
        token: '',
        token2: '',
        isSuccess: false,
      );
    }

    return LoginResponse(
      token: data['token'] as String? ?? '',
      token2: data['token2'] as String? ?? '',
      isSuccess: true,
      userId: data['user_id'] as String? ?? '',
    );
  }

  final String token;
  final String token2;
  final String userId;
  final bool isSuccess;
}