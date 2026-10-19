class RegisteredMic {
  const RegisteredMic({required this.id, required this.fullName});

  final String id; // MAC address (or legacy uuid), doubles as slot id
  final String fullName;

  Map<String, dynamic> toJson() => {'id': id, 'fullName': fullName};

  factory RegisteredMic.fromJson(Map<String, dynamic> json) =>
      RegisteredMic(id: json['id'] as String, fullName: json['fullName'] as String);
}

/// Turns a device id into the id used to register it:
///   "esp32-AA:BB:CC:DD:EE:FF" / "esp32-aabbccddeeff" / "aa-bb-cc-dd-ee-ff"
///     -> "AABBCCDDEEFF"
/// Anything that is not a 12-digit MAC is returned trimmed (minus "esp32-").
String normalizeMicId(String raw) {
  var s = raw.trim();
  if (s.toLowerCase().startsWith('esp32-')) s = s.substring(6);
  final compact = s.replaceAll(RegExp(r'[:\-\s]'), '');
  return RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(compact)
      ? compact.toUpperCase()
      : s;
}

/// True for ids that belong to an ESP32 streaming over the network
/// ("esp32-MAC" or a bare 12-digit MAC). Such a slot must only ever receive
/// that device's own audio, never a phone microphone.
bool isEspMicId(String id) {
  final s = id.trim();
  if (s.toLowerCase().startsWith('esp32-')) return true;
  return RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(s.replaceAll(RegExp(r'[:\-\s]'), ''));
}