class UserChild {
  const UserChild({
    required this.secondUserId,
    required this.userFullName,
    required this.privateAdmin,
    required this.generalAdmin,
  });

  final String secondUserId;
  final String userFullName;
  final String privateAdmin;
  final String generalAdmin;

  factory UserChild.fromJson(Map<String, dynamic> json) {
    return UserChild(
      secondUserId: json['second_user_id'] as String? ?? '',
      userFullName: json['user_full_name'] as String? ?? '',
      privateAdmin: json['private_admin'] as String? ?? '',
      generalAdmin: json['general_admin'] as String? ?? '',
    );
  }
}