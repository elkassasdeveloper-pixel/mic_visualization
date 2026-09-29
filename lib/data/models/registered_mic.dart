class RegisteredMic {
  const RegisteredMic({required this.id, required this.fullName});

  final String id; // uuid, doubles as slot id
  final String fullName;

  Map<String, dynamic> toJson() => {'id': id, 'fullName': fullName};

  factory RegisteredMic.fromJson(Map<String, dynamic> json) =>
      RegisteredMic(id: json['id'] as String, fullName: json['fullName'] as String);
}