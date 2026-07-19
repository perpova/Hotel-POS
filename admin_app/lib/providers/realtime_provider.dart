import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_service.dart';

class RealtimeProvider extends ChangeNotifier {
  final List<Map<String, dynamic>> _events = [];
  int _unreadNotifications = 0;
  bool _isConnected = false;
  StreamSubscription? _sub;

  // ── Live POS mirror ──────────────────────────────────────────
  Map<String, dynamic>? _livePosState;
  Timer? _livePosExpiry;
  Map<String, dynamic>? get livePosState => _livePosState;
  // ─────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get events => List.unmodifiable(_events);
  int get unreadNotifications => _unreadNotifications;
  bool get isConnected => _isConnected;

  // Listeners keyed by event type
  final Map<String, List<void Function(Map<String, dynamic>)>> _listeners = {};

  void init() {
    _sub?.cancel();
    _sub = ApiService.instance.eventStream.listen((event) {
      _events.insert(0, event);
      if (_events.length > 100) _events.removeLast();

      final type = event['type']?.toString() ?? '';

      // ── Live POS mirror: update banner, reset 30s expiry ─────
      if (type == 'live_pos_state') {
        _livePosState = event['data'] as Map<String, dynamic>?;
        _livePosExpiry?.cancel();
        _livePosExpiry = Timer(const Duration(seconds: 30), () {
          _livePosState = null;
          notifyListeners();
        });
        notifyListeners();
        return; // don't propagate further
      }

      // Notification badge
      if (type == 'new_notification') {
        _unreadNotifications++;
      }

      // Feature-specific listeners
      if (_listeners.containsKey(type)) {
        for (final cb in _listeners[type]!) {
          cb(event);
        }
      }
      // Wildcard listeners
      if (_listeners.containsKey('*')) {
        for (final cb in _listeners['*']!) {
          cb(event);
        }
      }

      notifyListeners();
    });

    _isConnected = true;
    notifyListeners();
  }

  void on(String eventType, void Function(Map<String, dynamic>) callback) {
    _listeners.putIfAbsent(eventType, () => []).add(callback);
  }

  void off(String eventType, void Function(Map<String, dynamic>) callback) {
    _listeners[eventType]?.remove(callback);
  }

  void clearUnreadNotifications() {
    _unreadNotifications = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _livePosExpiry?.cancel();
    super.dispose();
  }
}
