import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class LivePosProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<OrderSummary> _orders = [];
  String _filter = 'all'; // all, active, paid, cancelled

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
      _orders.sort((a, b) => b.id.compareTo(a.id)); // newest first
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }

  void onRealtimeEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    if ([
      'order_created',
      'payment_completed',
      'order_updated',
      'order_status_changed',
    ].contains(type)) {
      // Add or update order from event data
      final data = event['data'];
      if (data != null && data is Map<String, dynamic>) {
        final incoming = OrderSummary.fromJson(data);
        final idx = _orders.indexWhere((o) => o.id == incoming.id);
        if (idx != -1) {
          _orders[idx] = incoming;
        } else {
          _orders.insert(0, incoming);
        }
        notifyListeners();
      } else {
        // Fallback: reload
        load();
      }
    }
  }
}
