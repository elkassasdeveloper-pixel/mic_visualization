/// How the phone talks to the ESP32 microphones.
enum EspTransport {
  mqtt(
    id: 'mqtt',
    label: 'MQTT',
    description: 'ESP32 connects to the broker on this phone over Wi-Fi',
    defaultPort: 1883,
    espCommand: 'USE_WEBSOCKET:0',
  ),
  websocket(
    id: 'websocket',
    label: 'WebSocket',
    description: 'ESP32 connects to this phone over Wi-Fi (ws://)',
    defaultPort: 8080,
    espCommand: 'USE_WEBSOCKET:1',
  ),
  bluetooth(
    id: 'bluetooth',
    label: 'Bluetooth (BLE)',
    description: 'ESP32 connects directly to this phone, no Wi-Fi needed',
    defaultPort: 0,
    espCommand: 'PROTOCOL_BLE',
  );

  const EspTransport({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultPort,
    required this.espCommand,
  });

  final String id;
  final String label;
  final String description;
  final int defaultPort;

  /// Command understood by the ESP32 firmware to switch it to this transport.
  final String espCommand;

  bool get usesPort => this != EspTransport.bluetooth;

  static EspTransport fromId(String? id, {EspTransport fallback = mqtt}) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return fallback;
  }
}