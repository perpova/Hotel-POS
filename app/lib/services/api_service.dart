import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:hotel_pos/models/models.dart';
import 'package:hotel_pos/services/local_db.dart';

class APIService {
  static final APIService instance = APIService._init();
  APIService._init();

  // For localhost testing, default to standard express port 3000
  String _baseUrl = 'http://localhost:3000';
  String _wsUrl = 'ws://localhost:3000';
  String? _token;
  UserModel? currentUser;

  // Real-time Event Controller
  final _eventStreamController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get eventStream => _eventStreamController.stream;
  WebSocketChannel? _wsChannel;
  bool _isConnectingWs = false;

  String get baseUrl => _baseUrl;
  bool get isAuthenticated => _token != null;

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url;
    // Replace http(s) with ws(s)
    _wsUrl = url.replaceFirst('http', 'ws');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', url);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('api_base_url') ?? 'http://localhost:3000';
    _wsUrl = _baseUrl.replaceFirst('http', 'ws');
    _token = prefs.getString('auth_token');
    
    final userJson = prefs.getString('auth_user');
    if (userJson != null) {
      currentUser = UserModel.fromJson(jsonDecode(userJson));
      // Try connecting websocket
      connectWebSocket();
    }
  }

  // Check network connectivity
  Future<bool> checkOnline() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/categories')).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------
  // AUTHENTICATION APIs
  // ----------------------------------------------------
  Future<bool> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        currentUser = UserModel.fromJson(data['user']);
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);
        await prefs.setString('auth_user', jsonEncode(data['user']));
        
        connectWebSocket();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    currentUser = null;
    _wsChannel?.sink.close();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('auth_user');
  }

  Future<void> updateProfile(int id, Map<String, dynamic> userData) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/users/$id'),
      headers: _getHeaders(),
      body: jsonEncode(userData),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      currentUser = UserModel.fromJson(data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_user', jsonEncode(data));
      return;
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to update profile');
  }

  Future<void> updatePassword(int id, String password) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/users/$id/password'),
      headers: _getHeaders(),
      body: jsonEncode({'password': password}),
    );
    if (response.statusCode != 200) {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to change password');
    }
  }

  // ----------------------------------------------------
  // ROLES & PERMISSIONS
  // ----------------------------------------------------
  Future<List<Map<String, dynamic>>> getRoles() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/roles'), headers: _getHeaders());
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load roles');
  }

  Future<Map<String, dynamic>> createRole(String name) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/roles'),
      headers: _getHeaders(),
      body: jsonEncode({'name': name}),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    final e = jsonDecode(response.body);
    throw Exception(e['error'] ?? 'Failed to create role');
  }

  Future<void> updateRole(int id, String name) async {
    await http.put(Uri.parse('$_baseUrl/api/roles/$id'), headers: _getHeaders(), body: jsonEncode({'name': name}));
  }

  Future<void> deleteRole(int id) async {
    await http.delete(Uri.parse('$_baseUrl/api/roles/$id'), headers: _getHeaders());
  }

  Future<List<Map<String, dynamic>>> getRolePermissions(int roleId) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/roles/$roleId/permissions'), headers: _getHeaders());
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load permissions');
  }

  Future<void> saveRolePermissions(int roleId, List<Map<String, dynamic>> permissions) async {
    await http.put(
      Uri.parse('$_baseUrl/api/roles/$roleId/permissions'),
      headers: _getHeaders(),
      body: jsonEncode({'permissions': permissions}),
    );
  }

  Map<String, String> _getHeaders() {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $_token',
    };
  }

  // ----------------------------------------------------
  // REST CLIENT METHODS
  // ----------------------------------------------------
  Future<List<CategoryModel>> getCategories() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/categories'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((c) => CategoryModel.fromJson(c)).toList();
    }
    throw Exception('Failed to load categories');
  }

  Future<CategoryModel> createCategory(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/categories'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return CategoryModel.fromJson(jsonDecode(response.body));
    }
    try {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to create category');
    } catch (_) {
      throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
    }
  }

  Future<List<ProductModel>> getProducts() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/products'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((p) => ProductModel.fromJson(p)).toList();
    }
    throw Exception('Failed to load products');
  }

  Future<List<ProductModel>> getAllProducts() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/products?all=true'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((p) => ProductModel.fromJson(p)).toList();
    }
    throw Exception('Failed to load all products');
  }

  Future<ProductModel> createProduct(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/products'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return ProductModel.fromJson(jsonDecode(response.body));
    }
    try {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to create product');
    } catch (_) {
      throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
    }
  }

  Future<ProductModel> updateProduct(int id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/products/$id'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return ProductModel.fromJson(jsonDecode(response.body));
    }
    try {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to update product');
    } catch (_) {
      throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
    }
  }

  Future<void> deleteProduct(int id) async {
    final response = await http.delete(Uri.parse('$_baseUrl/api/products/$id'), headers: _getHeaders());
    if (response.statusCode != 200) {
      try {
        final errData = jsonDecode(response.body);
        throw Exception(errData['error'] ?? 'Failed to delete product');
      } catch (_) {
        throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
      }
    }
  }

  Future<void> importProductsExcel(List<int> fileBytes, String fileName) async {
    final uri = Uri.parse('$_baseUrl/api/products/import');
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $_token',
      })
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: fileName,
      ));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to import Excel');
    }
  }

  Future<List<int>> downloadProductsExcel() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/products/export'), headers: _getHeaders());
    if (response.statusCode == 200) {
      return response.bodyBytes;
    }
    throw Exception('Failed to export Excel');
  }

  Future<List<DiningTableModel>> getTables() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/tables'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((t) => DiningTableModel.fromJson(t)).toList();
    }
    throw Exception('Failed to load tables');
  }

  Future<void> updateTableStatus(int tableId, String status, {String? stewardName, int? currentOrderId}) async {
    await http.put(
      Uri.parse('$_baseUrl/api/tables/$tableId/status'),
      headers: _getHeaders(),
      body: jsonEncode({
        'status': status,
        'steward_name': stewardName,
        'current_order_id': currentOrderId,
      }),
    );
  }

  Future<DiningTableModel> createTable(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/tables'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return DiningTableModel.fromJson(jsonDecode(response.body));
    }
    try {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to create table');
    } catch (_) {
      throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
    }
  }

  Future<DiningTableModel> updateTable(int id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/tables/$id'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return DiningTableModel.fromJson(jsonDecode(response.body));
    }
    try {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to update table');
    } catch (_) {
      throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
    }
  }

  Future<void> deleteTable(int id) async {
    final response = await http.delete(Uri.parse('$_baseUrl/api/tables/$id'), headers: _getHeaders());
    if (response.statusCode != 200) {
      try {
        final errData = jsonDecode(response.body);
        throw Exception(errData['error'] ?? 'Failed to delete table');
      } catch (_) {
        throw Exception('Server error (${response.statusCode}): ${response.reasonPhrase}');
      }
    }
  }

  Future<List<CustomerModel>> getCustomers() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/customers'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((c) => CustomerModel.fromJson(c)).toList();
    }
    throw Exception('Failed to load customers');
  }

  Future<CustomerModel> createCustomer(Map<String, dynamic> customerData) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/customers'),
      headers: _getHeaders(),
      body: jsonEncode(customerData),
    );
    if (response.statusCode == 200) {
      return CustomerModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to create customer');
  }

  // Credit Settlement (weekly settlement)
  Future<void> settleCredit(int customerId, double amount, String paymentMethod) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/credit/settle'),
      headers: _getHeaders(),
      body: jsonEncode({
        'customer_id': customerId,
        'amount': amount,
        'payment_method': paymentMethod.toLowerCase(),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to settle credit balance');
    }
  }

  Future<void> editCreditSettlement(int settlementId, double newAmount, String newPaymentMethod) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/credit/settle/$settlementId'),
      headers: _getHeaders(),
      body: jsonEncode({
        'amount': newAmount,
        'payment_method': newPaymentMethod.toLowerCase(),
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to update credit settlement');
    }
  }

  Future<void> deleteCreditSettlement(int settlementId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/credit/settle/$settlementId'),
      headers: _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to delete credit settlement');
    }
  }

  // Shifts
  Future<ShiftModel?> getCurrentShift() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/shifts/current'), headers: _getHeaders());
    if (response.statusCode == 200 && response.body.isNotEmpty && response.body != 'null') {
      return ShiftModel.fromJson(jsonDecode(response.body));
    }
    return null;
  }

  Future<ShiftModel> openShift(double openingBalance) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/shifts/open'),
      headers: _getHeaders(),
      body: jsonEncode({'opening_balance': openingBalance}),
    );
    if (response.statusCode == 200) {
      return ShiftModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to open shift');
  }

  Future<ShiftModel> closeShift(int shiftId, double closingBalance, double actualClosingBalance) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/shifts/close'),
      headers: _getHeaders(),
      body: jsonEncode({
        'shift_id': shiftId,
        'closing_balance': closingBalance,
        'actual_closing_balance': actualClosingBalance,
      }),
    );
    if (response.statusCode == 200) {
      return ShiftModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to close shift');
  }

  Future<void> logDrawerCash(int shiftId, String type, double amount, String reason) async {
    await http.post(
      Uri.parse('$_baseUrl/api/shifts/drawer-log'),
      headers: _getHeaders(),
      body: jsonEncode({
        'shift_id': shiftId,
        'type': type,
        'amount': amount,
        'reason': reason,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> getDrawerLogs(int shiftId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/shifts/$shiftId/drawer-logs'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception('Failed to load drawer logs');
  }

  // Stock Adjustment
  Future<void> adjustStock(int productId, int changeQty, String type, String reason) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/products/$productId/stock'),
      headers: _getHeaders(),
      body: jsonEncode({
        'change_qty': changeQty,
        'type': type,
        'reason': reason,
      }),
    );
    if (response.statusCode != 200) {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to adjust stock');
    }
  }

  Future<List<Map<String, dynamic>>> getProductStockLogs() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/products/stock-logs'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception('Failed to load product stock logs');
  }

  // Raw Ingredients Stock
  Future<List<IngredientModel>> getIngredients() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/ingredients'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((i) => IngredientModel.fromJson(i)).toList();
    }
    throw Exception('Failed to load raw ingredients');
  }

  Future<void> createIngredient(String name, String unit) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/ingredients'),
      headers: _getHeaders(),
      body: jsonEncode({
        'name': name,
        'unit': unit,
      }),
    );
    if (response.statusCode != 200) {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to create ingredient');
    }
  }

  Future<void> adjustIngredientStock(int ingredientId, double changeQty, String type, String reason) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/ingredients/$ingredientId/stock'),
      headers: _getHeaders(),
      body: jsonEncode({
        'change_qty': changeQty,
        'type': type,
        'reason': reason,
      }),
    );
    if (response.statusCode != 200) {
      final errData = jsonDecode(response.body);
      throw Exception(errData['error'] ?? 'Failed to adjust raw ingredient stock');
    }
  }

  Future<List<Map<String, dynamic>>> getIngredientStockLogs() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/ingredients/logs'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception('Failed to load ingredient stock logs');
  }

  Future<void> configureHappyHour(int productId, double promoPrice, String startTime, String endTime, String days, String? name, int? categoryId) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/happyhour'),
      headers: _getHeaders(),
      body: jsonEncode({
        'product_id': productId,
        'promo_price': promoPrice,
        'start_time': startTime,
        'end_time': endTime,
        'days_of_week': days,
        'name': name,
        'category_id': categoryId,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to configure happy hour');
    }
  }

  Future<List<Map<String, dynamic>>> getHappyHours() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/happyhour'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    throw Exception('Failed to load happy hours');
  }

  Future<void> deleteHappyHour(int id) async {
    final response = await http.delete(Uri.parse('$_baseUrl/api/happyhour/$id'), headers: _getHeaders());
    if (response.statusCode != 200) {
      throw Exception('Failed to delete happy hour configuration');
    }
  }

  // Expenses
  Future<List<ExpenseModel>> getExpenses() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/expenses'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => ExpenseModel.fromJson(e)).toList();
    }
    throw Exception('Failed to load expenses');
  }

  Future<void> createExpense(Map<String, dynamic> expenseData) async {
    await http.post(
      Uri.parse('$_baseUrl/api/expenses'),
      headers: _getHeaders(),
      body: jsonEncode(expenseData),
    );
  }

  // Suppliers
  Future<List<SupplierModel>> getSuppliers() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/suppliers'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((s) => SupplierModel.fromJson(s)).toList();
    }
    throw Exception('Failed to load suppliers');
  }

  Future<SupplierModel> createSupplier(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/suppliers'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return SupplierModel.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to create supplier');
  }

  Future<SupplierModel> updateSupplier(int id, Map<String, dynamic> data) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/suppliers/$id'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode == 200) {
      return SupplierModel.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to update supplier');
  }

  Future<void> deleteSupplier(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/suppliers/$id'),
      headers: _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete supplier');
    }
  }

  Future<void> paySupplier(int id, double amount, String paymentSource, String remarks) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/suppliers/$id/pay'),
      headers: _getHeaders(),
      body: jsonEncode({
        'amount': amount,
        'payment_source': paymentSource,
        'remarks': remarks,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to process supplier payment');
    }
  }

  Future<List<SupplierDeliveryModel>> getSupplierDeliveries(int supplierId) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/suppliers/$supplierId/deliveries'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((d) => SupplierDeliveryModel.fromJson(d)).toList();
    }
    throw Exception('Failed to load supplier deliveries');
  }

  Future<void> createSupplierDelivery(int supplierId, Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/suppliers/$supplierId/deliveries'),
      headers: _getHeaders(),
      body: jsonEncode(data),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to log supplier delivery');
    }
  }

  Future<List<SupplierPaymentModel>> getSupplierPayments(int supplierId) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/suppliers/$supplierId/payments'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((p) => SupplierPaymentModel.fromJson(p)).toList();
    }
    throw Exception('Failed to load supplier payments');
  }

  Future<List<SupplierLedgerEntryModel>> getSupplierLedger(int supplierId) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/suppliers/$supplierId/ledger'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((l) => SupplierLedgerEntryModel.fromJson(l)).toList();
    }
    throw Exception('Failed to load supplier ledger');
  }



  Future<List<OrderModel>> getOrders() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/orders'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((o) => OrderModel.fromJson(o)).toList();
    }
    throw Exception('Failed to load orders');
  }

  Future<OrderModel> getOrderByNumber(String orderNumber) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/orders/by-number/$orderNumber'), headers: _getHeaders());
    if (response.statusCode == 200) {
      return OrderModel.fromJson(jsonDecode(response.body));
    }
    final errorMsg = jsonDecode(response.body)['error'] ?? 'Order not found';
    throw Exception(errorMsg);
  }

  Future<List<OrderItemModel>> getOrderItems(int orderId) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/orders/$orderId/items'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((i) => OrderItemModel.fromJson(i)).toList();
    }
    throw Exception('Failed to load order items');
  }

  // Promotions & Offers APIs
  Future<List<OfferModel>> getOffers() async {
    final response = await http.get(Uri.parse('$_baseUrl/api/offers'), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((o) => OfferModel.fromJson(o)).toList();
    }
    throw Exception('Failed to load offers');
  }

  Future<OfferModel> createOffer(Map<String, dynamic> offerData) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/offers'),
      headers: _getHeaders(),
      body: jsonEncode(offerData),
    );
    if (response.statusCode == 200) {
      return OfferModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to create offer');
  }

  Future<OfferModel> updateOffer(int id, Map<String, dynamic> offerData) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/offers/$id'),
      headers: _getHeaders(),
      body: jsonEncode(offerData),
    );
    if (response.statusCode == 200) {
      return OfferModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to update offer');
  }

  Future<void> deleteOffer(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/offers/$id'),
      headers: _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete offer');
    }
  }

  // User Management APIs
  Future<List<UserModel>> getUsers({String? role}) async {
    String url = '$_baseUrl/api/users';
    if (role != null) {
      url += '?role=$role';
    }
    final response = await http.get(Uri.parse(url), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((u) => UserModel.fromJson(u)).toList();
    }
    throw Exception('Failed to load users');
  }

  Future<UserModel> createUser(Map<String, dynamic> userData) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/users'),
      headers: _getHeaders(),
      body: jsonEncode(userData),
    );
    if (response.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to create user');
  }

  Future<UserModel> updateUser(int id, Map<String, dynamic> userData) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/users/$id'),
      headers: _getHeaders(),
      body: jsonEncode(userData),
    );
    if (response.statusCode == 200) {
      return UserModel.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to update user');
  }

  Future<void> resetUserPassword(int id, String password) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/users/$id/password'),
      headers: _getHeaders(),
      body: jsonEncode({'password': password}),
    );
    if (response.statusCode != 200) {
      throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to reset password');
    }
  }

  Future<void> deleteUser(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/users/$id'),
      headers: _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to deactivate user');
    }
  }

  // Customer Management APIs
  Future<CustomerModel> updateCustomer(int id, Map<String, dynamic> customerData) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/api/customers/$id'),
      headers: _getHeaders(),
      body: jsonEncode(customerData),
    );
    if (response.statusCode == 200) {
      return CustomerModel.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to update customer');
  }

  Future<void> deleteCustomer(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/customers/$id'),
      headers: _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete customer');
    }
  }

  Future<List<dynamic>> getCustomerLedger(int customerId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/customers/$customerId/ledger'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load customer ledger');
  }

  // Address Management APIs
  Future<List<AddressModel>> getAddresses(int id, {required bool isCustomer}) async {
    final typePath = isCustomer ? 'customers' : 'users';
    final response = await http.get(
      Uri.parse('$_baseUrl/api/$typePath/$id/addresses'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((a) => AddressModel.fromJson(a)).toList();
    }
    throw Exception('Failed to load addresses');
  }

  Future<AddressModel> saveAddress(int id, Map<String, dynamic> addrData, {required bool isCustomer}) async {
    final typePath = isCustomer ? 'customers' : 'users';
    final response = await http.post(
      Uri.parse('$_baseUrl/api/$typePath/$id/addresses'),
      headers: _getHeaders(),
      body: jsonEncode(addrData),
    );
    if (response.statusCode == 200) {
      return AddressModel.fromJson(jsonDecode(response.body));
    }
    throw Exception(jsonDecode(response.body)['error'] ?? 'Failed to save address');
  }

  Future<void> deleteAddress(int id) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/api/addresses/$id'),
      headers: _getHeaders(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to delete address');
    }
  }

  // Orders creation
  Future<Map<String, dynamic>> placeOrderOnline(OrderModel order) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/orders'),
      headers: _getHeaders(),
      body: jsonEncode(order.toJson()),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    final errData = jsonDecode(response.body);
    throw Exception(errData['error'] ?? 'Failed to place order online');
  }

  Future<void> updateOrderOnline(int orderId, Map<String, dynamic> updateFields) async {
    await http.put(
      Uri.parse('$_baseUrl/api/orders/$orderId'),
      headers: _getHeaders(),
      body: jsonEncode(updateFields),
    );
  }

  Future<OrderModel> getOrderByBarcode(String barcode) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/orders/barcode/$barcode'), headers: _getHeaders());
    if (response.statusCode == 200) {
      return OrderModel.fromJson(jsonDecode(response.body));
    }
    throw Exception('Order not found with barcode: $barcode');
  }

  // 2-Way Card Terminal communication
  Future<void> initiateCardPayment(double amount, String orderNumber) async {
    await http.post(
      Uri.parse('$_baseUrl/api/card-terminal/charge'),
      headers: _getHeaders(),
      body: jsonEncode({'amount': amount, 'order_number': orderNumber}),
    );
  }

  // LankaQR compliant generator helper
  Future<Map<String, dynamic>> getLankaQR(double amount, String orderNumber) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/lankaqr/generate?amount=$amount&order_number=$orderNumber'),
      headers: _getHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to generate LankaQR');
  }

  // Dashboard & Reports Data
  Future<Map<String, dynamic>> getDashboardReport({String? startDate, String? endDate}) async {
    String url = '$_baseUrl/api/reports/dashboard';
    if (startDate != null && endDate != null) {
      url += '?start_date=$startDate&end_date=$endDate';
    }
    final response = await http.get(Uri.parse(url), headers: _getHeaders());
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load dashboard report');
  }

  Future<Map<String, dynamic>> getEODSummary({String? date}) async {
    String url = '$_baseUrl/api/reports/eod';
    if (date != null) {
      url += '?date=$date';
    }
    final response = await http.get(Uri.parse(url), headers: _getHeaders());
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load EOD Summary');
  }

  Future<List> getHistoricalReport(String period) async {
    final response = await http.get(Uri.parse('$_baseUrl/api/reports/historical?period=$period'), headers: _getHeaders());
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load historical report');
  }

  Future<List<AuditLogModel>> getActivityLogs({String? date}) async {
    String url = '$_baseUrl/api/reports/logs';
    if (date != null) {
      url += '?date=$date';
    }
    final response = await http.get(Uri.parse(url), headers: _getHeaders());
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((l) => AuditLogModel.fromJson(l)).toList();
    }
    throw Exception('Failed to load logs');
  }

  // ----------------------------------------------------
  // SYSTEM SYNCHRONIZATION (LAN-first -> Server upload/download)
  // ----------------------------------------------------
  Future<Map<String, dynamic>?> syncOfflineData() async {
    try {
      final online = await checkOnline();
      if (!online) return null;

      final offlineOrders = await LocalDB.instance.getUnsyncedOrders();
      final offlineShifts = await LocalDB.instance.getUnsyncedShifts();
      final offlineExpenses = await LocalDB.instance.getUnsyncedExpenses();
      final offlineStockLogs = await LocalDB.instance.getUnsyncedStockLogs();
      final offlineAuditLogs = await LocalDB.instance.getUnsyncedAudits();

      if (offlineOrders.isEmpty && offlineShifts.isEmpty && offlineExpenses.isEmpty &&
          offlineStockLogs.isEmpty && offlineAuditLogs.isEmpty) {
        // Nothing to sync, just fetch latest server database
        return null;
      }

      final payload = {
        'offline_orders': offlineOrders.map((o) => o.toJson()).toList(),
        'offline_shifts': offlineShifts.map((s) => s.toJson()).toList(),
        'offline_expenses': offlineExpenses.map((e) => e.toJson()).toList(),
        'offline_stock_logs': offlineStockLogs,
        'offline_audit_logs': offlineAuditLogs
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/api/sync'),
        headers: _getHeaders(),
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        // Synchronization successful. Clear local cached edits.
        await LocalDB.instance.clearSyncedData();
        return jsonDecode(response.body);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ----------------------------------------------------
  // WEBSOCKET REALTIME EVENTS CLIENT
  // ----------------------------------------------------
  void connectWebSocket() {
    if (_isConnectingWs || _wsChannel != null) return;
    _isConnectingWs = true;

    try {
      print('Connecting WebSocket to $_wsUrl');
      _wsChannel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      
      _wsChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            _eventStreamController.add(data);
          } catch (e) {
            print('Error decoding websocket message: $e');
          }
        },
        onError: (err) {
          print('WebSocket error: $err');
          _reconnectWebSocket();
        },
        onDone: () {
          print('WebSocket connection closed.');
          _reconnectWebSocket();
        },
      );
      _isConnectingWs = false;
    } catch (e) {
      print('WebSocket connection failed: $e');
      _isConnectingWs = false;
      _reconnectWebSocket();
    }
  }

  void _reconnectWebSocket() {
    _wsChannel = null;
    if (currentUser != null) {
      Timer(const Duration(seconds: 5), () {
        connectWebSocket();
      });
    }
  }
}
