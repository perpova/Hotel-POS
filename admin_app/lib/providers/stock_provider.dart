import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class StockProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  List<ProductModel> _products = [];
  List<IngredientModel> _ingredients = [];
  List<Map<String, dynamic>> _stockLogs = [];

  Timer? _debounce;

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<ProductModel> get products => _products;
  List<ProductModel> get lowStockProducts =>
      _products.where((p) => p.trackStock && p.stockQty <= p.minStockLevel).toList();
  List<IngredientModel> get ingredients => _ingredients;
  List<IngredientModel> get lowStockIngredients =>
      _ingredients.where((i) => i.isLowStock).toList();
  List<Map<String, dynamic>> get stockLogs => _stockLogs;

  Future<void> loadProducts() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _products = await ApiService.instance.getAllProducts();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadIngredients() async {
    try {
      _ingredients = await ApiService.instance.getIngredients();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadStockLogs() async {
    try {
      _stockLogs = await ApiService.instance.getStockLogs();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        ApiService.instance.getAllProducts(),
        ApiService.instance.getIngredients(),
        ApiService.instance.getStockLogs(),
      ]);
      _products = results[0] as List<ProductModel>;
      _ingredients = results[1] as List<IngredientModel>;
      _stockLogs = results[2] as List<Map<String, dynamic>>;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Instantly update a single product's stock qty from a WS event payload,
  /// no network call needed.
  void _patchProductStock(Map<String, dynamic> data) {
    try {
      final productId = (data['productId'] ?? data['product_id']) as int?;
      final newQty = (data['stock_qty'] ?? data['stockQty']) as int?;
      if (productId == null || newQty == null) {
        _scheduleReload(productsOnly: true);
        return;
      }
      final idx = _products.indexWhere((p) => p.id == productId);
      if (idx != -1) {
        final p = _products[idx];
        _products[idx] = ProductModel(
          id: p.id,
          name: p.name,
          categoryId: p.categoryId,
          price: p.price,
          cost: p.cost,
          activePrice: p.activePrice,
          stockQty: newQty,
          minStockLevel: p.minStockLevel,
          imageBase64: p.imageBase64,
          status: p.status,
          itemType: p.itemType,
          isFeatured: p.isFeatured,
          trackStock: p.trackStock,
          description: p.description,
        );
        notifyListeners();
      }
    } catch (_) {
      _scheduleReload(productsOnly: true);
    }
  }

  void _scheduleReload({bool productsOnly = false}) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 1000),
      productsOnly ? loadProducts : loadAll,
    );
  }

  Future<void> adjustProductStock(
      int productId, int qty, String type, String reason) async {
    await ApiService.instance.adjustStock(productId, qty, type, reason);
    // Optimistic local update
    final idx = _products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      final p = _products[idx];
      _products[idx] = ProductModel(
        id: p.id,
        name: p.name,
        categoryId: p.categoryId,
        price: p.price,
        cost: p.cost,
        activePrice: p.activePrice,
        stockQty: p.stockQty + qty,
        minStockLevel: p.minStockLevel,
        imageBase64: p.imageBase64,
        status: p.status,
        itemType: p.itemType,
        isFeatured: p.isFeatured,
        trackStock: p.trackStock,
        description: p.description,
      );
    }
    notifyListeners();
    await loadStockLogs();
  }

  Future<void> adjustIngredientStock(
      int id, double qty, String type, String reason) async {
    await ApiService.instance.adjustIngredientStock(id, qty, type, reason);
    await loadIngredients();
  }

  void onRealtimeEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';

    if (type == 'live_pos_state') return; // ignore high-frequency mirror events

    switch (type) {
      case 'stock_updated':
        // Server sends individual product stock change — patch in-place
        final data = event['data'];
        if (data is Map<String, dynamic>) {
          _patchProductStock(data);
        } else {
          _scheduleReload(productsOnly: true);
        }
        break;

      case 'ingredient_stock_updated':
        // Reload ingredients only
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 800), loadIngredients);
        break;

      case 'database_synchronized':
      case 'ws_reconnected':
        // Full stock refresh after sync or reconnect
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
