import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

class ApiService {
  static final ApiService instance = ApiService._init();
  ApiService._init();

  String _baseUrl = 'http://192.168.1.100:3000';
  String _wsUrl = 'ws://192.168.1.100:3000';
  String? _token;
  UserModel? currentUser;

  // Real-time stream
  final _eventStreamCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventStreamCtrl.stream;

  WebSocketChannel? _wsChannel;
  bool _isConnecting = false;
  Timer? _reconnectTimer;

  String get baseUrl => _baseUrl;
  String? get token => _token;
  bool get isAuthenticated => _token != null && currentUser != null;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_token',
      };

  // ─── INIT ────────────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('admin_base_url') ?? 'http://192.168.1.100:3000';
    _wsUrl = _baseUrl.replaceFirst('http', 'ws');
    _token = prefs.getString('admin_token');

    final userJson = prefs.getString('admin_user');
    if (userJson != null) {
      try {
        currentUser = UserModel.fromJson(jsonDecode(userJson));
        connectWebSocket();
      } catch (_) {}
    }
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    _wsUrl = _baseUrl.replaceFirst('http', 'ws');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('admin_base_url', _baseUrl);
  }

  // ─── AUTH ────────────────────────────────────────────────────────────
  Future<bool> login(String username, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final user = UserModel.fromJson(data['user']);
        if (user.role != 'admin' && user.role != 'owner') {
          throw Exception('Access denied. Admin or Owner role required.');
        }
        _token = data['token'];
        currentUser = user;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('admin_token', _token!);
        await prefs.setString('admin_user', jsonEncode(data['user']));
        connectWebSocket();
        return true;
      }
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Login failed');
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    _token = null;
    currentUser = null;
    _wsChannel?.sink.close();
    _reconnectTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('admin_token');
    await prefs.remove('admin_user');
  }

  // ─── WEBSOCKET ───────────────────────────────────────────────────────
  void connectWebSocket() {
    if (_isConnecting || _token == null) return;
    _isConnecting = true;

    try {
      _wsChannel?.sink.close();
      _wsChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      _isConnecting = false;

      // Emit reconnect event so all providers do a fresh data load
      Future.delayed(const Duration(milliseconds: 300), () {
        _eventStreamCtrl.add({'type': 'ws_reconnected'});
      });

      _wsChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message.toString()) as Map<String, dynamic>;
            _eventStreamCtrl.add(data);
          } catch (_) {}
        },
        onDone: () {
          _isConnecting = false;
          _scheduleReconnect();
        },
        onError: (_) {
          _isConnecting = false;
          _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (_) {
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_token != null) connectWebSocket();
    });
  }

  void sendWsEvent(Map<String, dynamic> data) {
    try {
      _wsChannel?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  // ─── DASHBOARD ───────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDashboardStats() async {
    // Fetch orders for today and current shift data in parallel
    final results = await Future.wait([
      _getJson('$_baseUrl/api/orders/today'),
      _getJson('$_baseUrl/api/shifts/current'),
      _getJson('$_baseUrl/api/tables'),
    ]);

    final orders = results[0] is List ? results[0] as List : [];
    final shift = results[1];
    final tables = results[2] is List ? results[2] as List : [];

    double revenue = 0;
    double cashRevenue = 0;
    double cardRevenue = 0;
    double creditRevenue = 0;
    int paidOrders = 0;
    int unpaidOrders = 0;

    for (final o in orders) {
      if (o['payment_status'] == 'paid') {
        final total = double.tryParse(o['total'].toString()) ?? 0;
        revenue += total;
        paidOrders++;
        if (o['payment_method'] == 'cash') cashRevenue += total;
        if (o['payment_method'] == 'card') cardRevenue += total;
        if (o['payment_method'] == 'credit') creditRevenue += total;
      } else if (o['status'] != 'cancelled') {
        unpaidOrders++;
      }
    }

    return {
      'revenue': revenue,
      'cashRevenue': cashRevenue,
      'cardRevenue': cardRevenue,
      'creditRevenue': creditRevenue,
      'totalOrders': orders.length,
      'paidOrders': paidOrders,
      'unpaidOrders': unpaidOrders,
      'shift': shift,
      'tables': tables,
      'recentOrders': orders.length > 10 ? orders.sublist(orders.length - 10) : orders,
    };
  }

  // ─── ORDERS ──────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getTodayOrders() async {
    final data = await _getJson('$_baseUrl/api/orders/today');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  Future<List<Map<String, dynamic>>> getOrdersByDate(String from, String to) async {
    final data = await _getJson('$_baseUrl/api/orders/range?from=$from&to=$to');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  Future<Map<String, dynamic>> getOrderDetails(dynamic id) async {
    final data = await _getJson('$_baseUrl/api/orders/$id');
    if (data is Map<String, dynamic>) return data;
    throw Exception('Failed to load order details');
  }

  Future<List<Map<String, dynamic>>> getUsersReport(String from, String to) async {
    final data = await _getJson('$_baseUrl/api/admin/users-report?from=$from&to=$to');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  Future<Map<String, dynamic>> getTransactions(String from, String to) async {
    final data = await _getJson('$_baseUrl/api/admin/transactions?from=$from&to=$to');
    if (data is Map<String, dynamic>) return data;
    return {'total_revenue': 0, 'by_cash': 0, 'by_card': 0, 'by_credit': 0, 'count': 0, 'transactions': []};
  }

  // ─── PRODUCTS ─────────────────────────────────────────────────────────
  Future<List<ProductModel>> getAllProducts() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/products?all=true'),
      headers: _headers,
    ).timeout(const Duration(seconds: 15));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((p) => ProductModel.fromJson(p)).toList();
    }
    throw Exception('Failed to load products');
  }

  Future<void> adjustStock(int productId, int changeQty, String type, String reason) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/products/$productId/stock'),
      headers: _headers,
      body: jsonEncode({'change_qty': changeQty, 'type': type, 'reason': reason}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Stock adjustment failed');
    }
  }

  Future<List<Map<String, dynamic>>> getStockLogs() async {
    final data = await _getJson('$_baseUrl/api/products/stock-logs');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  // ─── INGREDIENTS ─────────────────────────────────────────────────────
  Future<List<IngredientModel>> getIngredients() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/ingredients'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((i) => IngredientModel.fromJson(i)).toList();
    }
    throw Exception('Failed to load ingredients');
  }

  Future<void> adjustIngredientStock(int id, double changeQty, String type, String reason) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/ingredients/$id/stock'),
      headers: _headers,
      body: jsonEncode({'change_qty': changeQty, 'type': type, 'reason': reason}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Ingredient stock adjustment failed');
    }
  }

  // ─── NOTIFICATIONS ───────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getNotifications() async {
    final data = await _getJson('$_baseUrl/api/notifications');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  Future<void> markNotificationRead(int id) async {
    await http.put(
      Uri.parse('$_baseUrl/api/notifications/$id/read'),
      headers: _headers,
    ).timeout(const Duration(seconds: 5));
  }

  Future<void> markAllNotificationsRead() async {
    await http.put(
      Uri.parse('$_baseUrl/api/notifications/read-all'),
      headers: _headers,
    ).timeout(const Duration(seconds: 5));
  }

  // ─── CATEGORIES ──────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getCategories() async {
    final data = await _getJson('$_baseUrl/api/categories');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  // ─── TABLES ──────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> getTables() async {
    final data = await _getJson('$_baseUrl/api/tables');
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  // ─── USER MANAGEMENT ─────────────────────────────────────────
  Future<List<UserModel>> getUsers({String? role}) async {
    String url = '$_baseUrl/api/users';
    if (role != null) url += '?role=$role';
    final res = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((u) => UserModel.fromJson(u)).toList();
    }
    throw Exception('Failed to load users');
  }

  Future<UserModel> createUser(Map<String, dynamic> userData) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/users'),
      headers: _headers,
      body: jsonEncode(userData),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['error'] ?? 'Failed to create user');
  }

  Future<UserModel> updateUser(int id, Map<String, dynamic> userData) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/users/$id'),
      headers: _headers,
      body: jsonEncode(userData),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(res.body));
    }
    final err = jsonDecode(res.body);
    throw Exception(err['error'] ?? 'Failed to update user');
  }

  Future<void> resetUserPassword(int id, String password) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/users/$id/password'),
      headers: _headers,
      body: jsonEncode({'password': password}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to reset password');
    }
  }

  Future<void> deleteUser(int id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/users/$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to deactivate user');
    }
  }

  // ─── ROLES & PERMISSIONS ──────────────────────────────────────
  Future<List<Map<String, dynamic>>> getRoles() async {
    final res = await http.get(Uri.parse('$_baseUrl/api/roles'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    throw Exception('Failed to load roles');
  }

  Future<Map<String, dynamic>> createRole(String name) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/roles'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) return jsonDecode(res.body);
    final err = jsonDecode(res.body);
    throw Exception(err['error'] ?? 'Failed to create role');
  }

  Future<void> updateRole(int id, String name) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/roles/$id'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to update role');
    }
  }

  Future<void> deleteRole(int id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/api/roles/$id'),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to delete role');
    }
  }

  Future<List<Map<String, dynamic>>> getRolePermissions(int roleId) async {
    final res = await http.get(Uri.parse('$_baseUrl/api/roles/$roleId/permissions'), headers: _headers).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    throw Exception('Failed to load permissions');
  }

  Future<void> saveRolePermissions(int roleId, List<Map<String, dynamic>> permissions) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/roles/$roleId/permissions'),
      headers: _headers,
      body: jsonEncode({'permissions': permissions}),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to save role permissions');
    }
  }

  // ─── STAFF ATTENDANCE & PAYROLL / SALARY APIs ──────────────
  Future<List<Map<String, dynamic>>> getStaffAttendanceSummary({int? userId, String? from, String? to}) async {
    String url = '$_baseUrl/api/staff/attendance/summary';
    final List<String> params = [];
    if (userId != null) params.add('user_id=$userId');
    if (from != null) params.add('from=$from');
    if (to != null) params.add('to=$to');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final data = await _getJson(url);
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  Future<Map<String, dynamic>> getPayrollSettings() async {
    final data = await _getJson('$_baseUrl/api/staff/payroll/settings');
    if (data is Map<String, dynamic>) return data;
    return {'global_ot_rate': 250.0, 'salary_notification_days': 2, 'staff_settings': []};
  }

  Future<void> updatePayrollSettings({
    double? globalOtRate,
    String? globalOtStartTime,
    int? salaryNotificationDays,
    List<Map<String, dynamic>>? userSettings,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/api/staff/payroll/settings'),
      headers: _headers,
      body: jsonEncode({
        if (globalOtRate != null) 'global_ot_rate': globalOtRate,
        if (globalOtStartTime != null) 'global_ot_start_time': globalOtStartTime,
        if (salaryNotificationDays != null) 'salary_notification_days': salaryNotificationDays,
        if (userSettings != null) 'user_settings': userSettings,
      }),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to update payroll settings');
    }
  }

  Future<List<Map<String, dynamic>>> getStaffAdvances({int? userId, String? status}) async {
    String url = '$_baseUrl/api/staff/advances';
    final List<String> params = [];
    if (userId != null) params.add('user_id=$userId');
    if (status != null) params.add('status=$status');
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final data = await _getJson(url);
    return data is List ? List<Map<String, dynamic>>.from(data) : [];
  }

  Future<void> grantStaffAdvance(int userId, double amount, String reason, String date) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/staff/advances'),
      headers: _headers,
      body: jsonEncode({
        'user_id': userId,
        'amount': amount,
        'reason': reason,
        'advance_date': date,
      }),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to grant staff advance');
    }
  }

  Future<Map<String, dynamic>> calculateStaffSalary(int userId, {String? periodStart, String? periodEnd}) async {
    String url = '$_baseUrl/api/staff/payroll/calculate?user_id=$userId';
    if (periodStart != null) url += '&period_start=$periodStart';
    if (periodEnd != null) url += '&period_end=$periodEnd';

    final data = await _getJson(url);
    if (data is Map<String, dynamic>) return data;
    throw Exception('Failed to calculate staff salary');
  }

  Future<void> processSalaryPayment(Map<String, dynamic> payrollData) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/staff/payroll/pay'),
      headers: _headers,
      body: jsonEncode(payrollData),
    ).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      final err = jsonDecode(res.body);
      throw Exception(err['error'] ?? 'Failed to process salary payment');
    }
  }

  // ─── HELPER ──────────────────────────────────────────────────────────
  Future<dynamic> _getJson(String url) async {
    try {
      final res = await http.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return null;
  }

  Future<bool> checkConnectivity() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/api/categories'))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
