import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class DashboardProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _tables = [];
  List<Map<String, dynamic>> _recentOrders = [];
  List<Map<String, dynamic>> _topProducts = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get stats => _stats;
  List<Map<String, dynamic>> get tables => _tables;
  List<Map<String, dynamic>> get recentOrders => _recentOrders;
  List<Map<String, dynamic>> get topProducts => _topProducts;

  double get todayRevenue => (_stats?['revenue'] as num?)?.toDouble() ?? 0;
  double get cashRevenue => (_stats?['cashRevenue'] as num?)?.toDouble() ?? 0;
  double get cardRevenue => (_stats?['cardRevenue'] as num?)?.toDouble() ?? 0;
  double get creditRevenue => (_stats?['creditRevenue'] as num?)?.toDouble() ?? 0;
  int get totalOrders => _stats?['totalOrders'] as int? ?? 0;
  int get paidOrders => _stats?['paidOrders'] as int? ?? 0;
  int get unpaidOrders => _stats?['unpaidOrders'] as int? ?? 0;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        ApiService.instance.getDashboardStats(),
        ApiService.instance.getTodayOrders(),
      ]);

      _stats = results[0] as Map<String, dynamic>;
      final allOrders = results[1] as List<Map<String, dynamic>>;

      // Recent orders (newest first, last 20)
      _recentOrders = allOrders.reversed.take(20).toList();

      // Tables from stats
      final tablesRaw = _stats?['tables'];
      if (tablesRaw is List) {
        _tables = List<Map<String, dynamic>>.from(tablesRaw);
      }

      // Top products: count items sold per product
      final productCount = <String, Map<String, dynamic>>{};
      for (final order in allOrders) {
        if (order['items'] is List) {
          for (final item in order['items'] as List) {
            final name = item['product_name']?.toString() ?? 'Unknown';
            final qty = (item['quantity'] as num?)?.toInt() ?? 1;
            final price = (item['price'] as num?)?.toDouble() ?? 0;
            if (!productCount.containsKey(name)) {
              productCount[name] = {'name': name, 'qty': 0, 'revenue': 0.0};
            }
            productCount[name]!['qty'] =
                (productCount[name]!['qty'] as int) + qty;
            productCount[name]!['revenue'] =
                (productCount[name]!['revenue'] as double) + (price * qty);
          }
        }
      }
      final sorted = productCount.values.toList()
        ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
      _topProducts = sorted.take(5).toList();

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
      'shift_updated',
      'table_status_changed',
    ].contains(type)) {
      load(); // Refresh on relevant events
    }
  }
}
