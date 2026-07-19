double _toDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val) ?? 0.0;
  return 0.0;
}

class UserModel {
  final int id;
  final String name;
  final String username;
  final String role;
  final String? email;
  final String? phone;
  final String status;
  final String? imageBase64;

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.email,
    this.phone,
    this.status = 'active',
    this.imageBase64,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'],
        name: json['name'] ?? '',
        username: json['username'] ?? '',
        role: json['role'] ?? '',
        email: json['email'],
        phone: json['phone'],
        status: json['status'] ?? 'active',
        imageBase64: json['image_base64'],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'username': username,
        'role': role,
        'email': email,
        'phone': phone,
        'status': status,
        'image_base64': imageBase64,
      };
}

class ProductModel {
  final int id;
  final String name;
  final int categoryId;
  final double price;
  final double cost;
  final double activePrice;
  final int stockQty;
  final int minStockLevel;
  final String? imageBase64;
  final String status;
  final String itemType;
  final bool isFeatured;
  final bool trackStock;
  final bool isHappyHourEligible;
  final String? description;

  ProductModel({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.price,
    required this.cost,
    required this.activePrice,
    required this.stockQty,
    required this.minStockLevel,
    this.imageBase64,
    this.status = 'active',
    this.itemType = 'Veg',
    this.isFeatured = false,
    this.trackStock = true,
    this.isHappyHourEligible = true,
    this.description,
  });

  bool get isLowStock => trackStock && stockQty <= minStockLevel;
  bool get isOutOfStock => trackStock && stockQty <= 0;
  double get stockPercent =>
      minStockLevel <= 0 ? 1.0 : (stockQty / (minStockLevel * 2)).clamp(0.0, 1.0);

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
        id: json['id'],
        name: json['name'] ?? '',
        categoryId: json['category_id'] ?? 0,
        price: _toDouble(json['price']),
        cost: _toDouble(json['cost']),
        activePrice: _toDouble(json['active_price'] ?? json['price']),
        stockQty: json['stock_qty'] ?? 0,
        minStockLevel: json['min_stock_level'] ?? 10,
        imageBase64: json['image_base64'],
        status: json['status'] ?? 'active',
        itemType: json['item_type'] ?? 'Veg',
        isFeatured: json['is_featured'] == true || json['is_featured'] == 1,
        trackStock: json['track_stock'] == true ||
            json['track_stock'] == 1 ||
            json['track_stock'] == null,
        isHappyHourEligible: json['is_happy_hour_eligible'] == true ||
            json['is_happy_hour_eligible'] == 1 ||
            json['is_happy_hour_eligible'] == null,
        description: json['description'],
      );
}

class IngredientModel {
  final int id;
  final String name;
  final double stockQty;
  final String unit;
  final double minStockLevel;

  IngredientModel({
    required this.id,
    required this.name,
    required this.stockQty,
    required this.unit,
    required this.minStockLevel,
  });

  bool get isLowStock => stockQty <= minStockLevel;
  bool get isOutOfStock => stockQty <= 0;

  factory IngredientModel.fromJson(Map<String, dynamic> json) => IngredientModel(
        id: json['id'],
        name: json['name'] ?? '',
        stockQty: _toDouble(json['stock_qty']),
        unit: json['unit'] ?? 'kg',
        minStockLevel: _toDouble(json['min_stock_level']),
      );
}

class OrderSummary {
  final int id;
  final String orderNumber;
  final String orderType;
  final String status;
  final String paymentStatus;
  final String? paymentMethod;
  final double total;
  final int? tableId;
  final String? tableNumber;
  final String createdAt;
  final List<Map<String, dynamic>> items;
  final int? cashierId;
  final String? cashierName;
  final double discount;

  OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.orderType,
    required this.status,
    required this.paymentStatus,
    this.paymentMethod,
    required this.total,
    this.tableId,
    this.tableNumber,
    required this.createdAt,
    this.items = const [],
    this.cashierId,
    this.cashierName,
    this.discount = 0,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'];
    List<Map<String, dynamic>> parsedItems = [];
    if (itemsList is List) {
      parsedItems = itemsList.map((i) => Map<String, dynamic>.from(i)).toList();
    }
    return OrderSummary(
      id: json['id'] ?? 0,
      orderNumber: json['order_number'] ?? '',
      orderType: json['order_type'] ?? 'dine_in',
      status: json['status'] ?? 'pending',
      paymentStatus: json['payment_status'] ?? 'unpaid',
      paymentMethod: json['payment_method'],
      total: _toDouble(json['total']),
      tableId: json['table_id'],
      tableNumber: json['table_number'],
      createdAt: json['created_at']?.toString() ?? '',
      items: parsedItems,
      cashierId: json['cashier_id'],
      cashierName: json['cashier_name'],
      discount: _toDouble(json['discount']),
    );
  }

  String get displayType {
    switch (orderType) {
      case 'dine_in': return 'Dine In';
      case 'takeaway': return 'Takeaway';
      case 'delivery': return 'Delivery';
      default: return orderType;
    }
  }

  bool get isPaid => paymentStatus == 'paid';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => !isPaid && !isCancelled;
}

class NotificationModel {
  final int id;
  final String title;
  final String message;
  final String type;
  final bool isRead;
  final String createdAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) => NotificationModel(
        id: json['id'] ?? 0,
        title: json['title'] ?? '',
        message: json['message'] ?? '',
        type: json['type'] ?? 'general',
        isRead: json['is_read'] == true || json['is_read'] == 1,
        createdAt: json['created_at']?.toString() ?? '',
      );
}
