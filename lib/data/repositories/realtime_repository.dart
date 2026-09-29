import 'dart:convert';

import 'package:centrifuge/centrifuge.dart' as centrifuge;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:mic_visualization/core/constants/centrifuge_config.dart';
import 'package:mic_visualization/data/services/centrifuge_client_factory.dart';

abstract class RealtimeRepository {
  Future<void> connectSlot(String slot, String userJwtToken);

  Future<void> publishTag(String slot, String label, double confidence);

  Future<void> disconnectSlot(String slot);

  Future<void> disconnectAll();
}

class CentrifugeRealtimeRepository implements RealtimeRepository {
  CentrifugeRealtimeRepository({CentrifugeClientFactory? factory})
    : _factory = factory ?? CentrifugeClientFactory();

  final CentrifugeClientFactory _factory;
  final Map<String, centrifuge.Client> _clients = {};
  final Map<String, centrifuge.Subscription> _subscriptions = {};

  @override
  Future<void> connectSlot(String slot, String userJwtToken) async {
    final client = _factory.createClient(userJwtToken);
    _clients[slot] = client;

    // Public channel — no subscription token needed.
    final subscription = client.newSubscription(CentrifugeConfig.publicChannel);
    _subscriptions[slot] = subscription;

    await subscription.subscribe();
    await client.connect();
  }

  @override
  Future<void> publishTag(String slot, String label, double confidence) async {
    final subscription = _subscriptions[slot];
    if (subscription == null) {
      debugPrint('[Realtime] publish FAILED — no subscription for $slot');
      throw StateError(
        'No subscription for slot "$slot". Call connectSlot first.',
      );
    }
    final now = DateTime.now();
    final payload = jsonEncode({
      'slot': slot,
      'tag': label,
      'confidence': confidence,
      'timestamp': "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}",
    });
    debugPrint('[Realtime] publishing to $slot: $payload');
    try {
      await subscription.publish(utf8.encode(payload));
      debugPrint('[Realtime] published OK for $slot');
    } catch (e) {
      debugPrint('[Realtime] publish FAILED for $slot: $e');
    }
  }

  @override
  Future<void> disconnectSlot(String slot) async {
    await _subscriptions[slot]?.unsubscribe();
    await _clients[slot]?.disconnect();
    _subscriptions.remove(slot);
    _clients.remove(slot);
  }

  @override
  Future<void> disconnectAll() async {
    for (final slot in _clients.keys.toList()) {
      await disconnectSlot(slot);
    }
  }
}
