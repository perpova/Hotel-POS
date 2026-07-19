import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class LivePosProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<OrderSummary> _orders = [];
  String _filter = 'all';

  Timer? _debounce;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get filter => _filter;

  List<OrderSummary> get orders {
    switch (_filter) {
      case 'active':
        return _orders.where((o) => o.isActive).toList();
      case 'paid':
        return _orders.where((o) => o.isPaid).toList();
      case 'cancelled':
        return _orders.where((o) => o.isCancelled).toList();
      case 'dine_in':
        return _orders.where((o) => o.orderType == 'dine_in').toList();
      case 'takeaway':
        return _orders.where((o) => o.orderType == 'takeaway').toList();
      default:
        return _orders;
    }
  }

  int get activeCount => _orders.where((o) => o.isActive).length;
  int get paidCount => _orders.where((o) => o.isPaid).length;
  int get totalCount => _orders.length;

  void setFilter(String f) {
    _filter = f;
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final raw = await ApiService.instance.getTodayOrders();
      _orders = raw.map((o) => OrderSummary.fromJson(o)).toList();
      _orders.sort((a, b) => b.id.compareTo(a.id));
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Instantly patch a single order from a WS event payload, no network call needed.
  void _patchOrder(Map<String, dynamic> data) {
    try {
      final incoming = OrderSummary.fromJson(data);
      final idx = _orders.indexWhere((o) => o.id == incoming.id);
      if (idx != -1) {
        _orders[idx] = incoming;
      } else {
        _orders.insert(0, incoming);
      }
      notifyListeners();
    } catch (_) {
      // Fallback to full reload if data is incomplete
      _scheduleReload();
    }
  }

  /// Debounced full reload — 800ms after the last trigger.
  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), load);
  }

  void onRealtimeEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';

    // Skip — not order-related
    if (type == 'live_pos_state') return;

    switch (type) {
      // ── Events that carry full order payload — instant patch ─────────
      case 'order_created':
      case 'payment_completed':
      case 'order_updated':
      case 'order_status_changed':
        final data = event['data'];
        if (data is Map<String, dynamic> && data.containsKey('id')) {
          _patchOrder(data);
        } else {
          _scheduleReload();
        }
        break;

      // ── Events that don't carry order data — debounced full reload ───
      case 'database_synchronized':
      case 'shift_updated':
      case 'ws_reconnected':
        _scheduleReload();
        break;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}
