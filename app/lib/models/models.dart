import 'dart:convert';

double _toDouble(dynamic val) {
  if (val == null) return 0.0;
  if (val is num) return val.toDouble();
  if (val is String) {
    return double.tryParse(val) ?? 0.0;
  }
  return 0.0;
}

double toDouble(dynamic val) => _toDouble(val);

class UserModel {
  final int id;
  final String name;
  final String username;
  final String role; // 'admin', 'cashier', 'owner', 'kitchen', 'delivery', 'waiter'
  final String? email;
  final String? phone;
  final String status; // 'active', 'inactive'
  final String branch; // 'current', 'all'
  final String? imageBase64;

  UserModel({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.email,
    this.phone,
    this.status = 'active',
    this.branch = 'current',
    this.imageBase64,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
    id: json['id'],
    name: json['name'],
    username: json['username'],
    role: json['role'],
    email: json['email'],
    phone: json['phone'],
    status: json['status'] ?? 'active',
    branch: json['branch'] ?? 'current',
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
    'branch': branch,
    'image_base64': imageBase64,
  };
}

// Category Model
class CategoryModel {
  final int id;
  final String name;
  final int? parentId;
  final String? imageBase64;

  CategoryModel({required this.id, required this.name, this.parentId, this.imageBase64});

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
    id: json['id'],
    name: json['name'],
    parentId: json['parent_id'],
    imageBase64: json['image_base64'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parent_id': parentId,
    'image_base64': imageBase64,
  };
}

class ProductSize {
  final String name;
  final double price;

  ProductSize({required this.name, required this.price});

  factory ProductSize.fromJson(Map<String, dynamic> json) => ProductSize(
    name: json['name'] ?? '',
    price: _toDouble(json['price']),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
  };
}

class ProductExtra {
  final String name;
  final double price;
  final int? ingredientId;
  final double? qty;

  ProductExtra({
    required this.name,
    required this.price,
    this.ingredientId,
    this.qty,
  });

  factory ProductExtra.fromJson(Map<String, dynamic> json) => ProductExtra(
    name: json['name'] ?? '',
    price: _toDouble(json['price']),
    ingredientId: json['ingredient_id'] != null ? int.tryParse(json['ingredient_id'].toString()) : null,
    qty: json['qty'] != null ? _toDouble(json['qty']) : null,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'price': price,
    'ingredient_id': ingredientId,
    'qty': qty,
  };
}

// Product Model
class ProductModel {
  final int id;
  final String name;
  final String? sinhalaName;
  final String? description;
  final int categoryId;
  final double price;
  final double cost;
  final double activePrice; // Dynamic price calculation (inc happy hour)
  final bool isHappyHour;
  final String? barcode;
  final int stockQty;
  final int minStockLevel;
  final bool isShortEat;
  final String? imageBase64;
  final String status;
  final String itemType;
  final double tax;
  final bool isFeatured;
  final String? caution;
  final bool hasSizes;
  final bool hasExtras;
  final bool hasAddons;
  final bool trackStock;
  final bool isHappyHourEligible;
  final List<ProductSize> sizes;
  final List<ProductExtra> extras;
  final List<int> addons;

  ProductModel({
    required this.id,
    required this.name,
    this.sinhalaName,
    this.description,
    required this.categoryId,
    required this.price,
    required this.cost,
    required this.activePrice,
    required this.isHappyHour,
    this.barcode,
    required this.stockQty,
    required this.minStockLevel,
    required this.isShortEat,
    this.imageBase64,
    this.status = 'active',
    this.itemType = 'Veg',
    this.tax = 0.00,
    this.isFeatured = false,
    this.caution,
    this.hasSizes = false,
    this.hasExtras = false,
    this.hasAddons = false,
    this.trackStock = true,
    this.isHappyHourEligible = true,
    this.sizes = const [],
    this.extras = const [],
    this.addons = const [],
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    List<ProductSize> sizesList = [];
    if (json['sizes'] != null) {
      if (json['sizes'] is String) {
        try {
          final decoded = jsonDecode(json['sizes']) as List;
          sizesList = decoded.map((x) => ProductSize.fromJson(x)).toList();
        } catch (_) {}
      } else if (json['sizes'] is List) {
        sizesList = (json['sizes'] as List).map((x) => ProductSize.fromJson(x)).toList();
      }
    }

    List<ProductExtra> extrasList = [];
    if (json['extras'] != null) {
      if (json['extras'] is String) {
        try {
          final decoded = jsonDecode(json['extras']) as List;
          extrasList = decoded.map((x) => ProductExtra.fromJson(x)).toList();
        } catch (_) {}
      } else if (json['extras'] is List) {
        extrasList = (json['extras'] as List).map((x) => ProductExtra.fromJson(x)).toList();
      }
    }

    List<int> addonsList = [];
    if (json['addons'] != null) {
      if (json['addons'] is String) {
        try {
          final decoded = jsonDecode(json['addons']) as List;
          addonsList = decoded.map((x) => int.parse(x.toString())).toList();
        } catch (_) {}
      } else if (json['addons'] is List) {
        addonsList = (json['addons'] as List).map((x) => int.parse(x.toString())).toList();
      }
    }

    return ProductModel(
      id: json['id'],
      name: json['name'],
      sinhalaName: json['sinhala_name'],
      description: json['description'],
      categoryId: json['category_id'],
      price: _toDouble(json['price']),
      cost: _toDouble(json['cost']),
      activePrice: _toDouble(json['active_price'] ?? json['price']),
      isHappyHour: json['is_happy_hour'] == true || json['is_happy_hour'] == 1,
      barcode: json['barcode'],
      stockQty: json['stock_qty'] ?? 0,
      minStockLevel: json['min_stock_level'] ?? 10,
      isShortEat: json['is_short_eat'] == true || json['is_short_eat'] == 1,
      imageBase64: json['image_base64'],
      status: json['status'] ?? 'active',
      itemType: json['item_type'] ?? 'Veg',
      tax: _toDouble(json['tax']),
      isFeatured: json['is_featured'] == true || json['is_featured'] == 1,
      caution: json['caution'],
      hasSizes: json['has_sizes'] == true || json['has_sizes'] == 1,
      hasExtras: json['has_extras'] == true || json['has_extras'] == 1,
      hasAddons: json['has_addons'] == true || json['has_addons'] == 1,
      trackStock: json['track_stock'] == true || json['track_stock'] == 1 || json['track_stock'] == null,
      isHappyHourEligible: json['is_happy_hour_eligible'] == true || json['is_happy_hour_eligible'] == 1 || json['is_happy_hour_eligible'] == null,
      sizes: sizesList,
      extras: extrasList,
      addons: addonsList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'sinhala_name': sinhalaName,
    'description': description,
    'category_id': categoryId,
    'price': price,
    'cost': cost,
    'active_price': activePrice,
    'is_happy_hour': isHappyHour,
    'barcode': barcode,
    'stock_qty': stockQty,
    'min_stock_level': minStockLevel,
    'is_short_eat': isShortEat,
    'image_base64': imageBase64,
    'status': status,
    'item_type': itemType,
    'tax': tax,
    'is_featured': isFeatured,
    'caution': caution,
    'has_sizes': hasSizes,
    'has_extras': hasExtras,
    'has_addons': hasAddons,
    'track_stock': trackStock ? 1 : 0,
    'is_happy_hour_eligible': isHappyHourEligible ? 1 : 0,
    'sizes': sizes.map((x) => x.toJson()).toList(),
    'extras': extras.map((x) => x.toJson()).toList(),
    'addons': addons,
  };
}

// Table Model
class DiningTableModel {
  final int id;
  final String tableNumber;
  final int capacity;
  final String status; // 'empty' [Green], 'seated' [Red], 'billing' [Yellow]
  final int? currentOrderId;
  final String? stewardName;
  final String activeStatus;

  DiningTableModel({
    required this.id,
    required this.tableNumber,
    required this.capacity,
    required this.status,
    this.currentOrderId,
    this.stewardName,
    this.activeStatus = 'active',
  });

  factory DiningTableModel.fromJson(Map<String, dynamic> json) => DiningTableModel(
    id: json['id'],
    tableNumber: json['table_number'],
    capacity: json['capacity'] ?? 4,
    status: json['status'] ?? 'empty',
    currentOrderId: json['current_order_id'],
    stewardName: json['steward_name'],
    activeStatus: json['active_status'] ?? 'active',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'table_number': tableNumber,
    'capacity': capacity,
    'status': status,
    'current_order_id': currentOrderId,
    'steward_name': stewardName,
    'active_status': activeStatus,
  };
}

class CustomerModel {
  final int id;
  final String name;
  final String phone;
  final String? email;
  final String? birthday;
  final String? favoriteItems;
  final double creditLimit;
  final double outstandingBalance;
  final String? imageBase64;

  CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.birthday,
    this.favoriteItems,
    required this.creditLimit,
    required this.outstandingBalance,
    this.imageBase64,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) => CustomerModel(
    id: json['id'],
    name: json['name'],
    phone: json['phone'],
    email: json['email'],
    birthday: json['birthday'],
    favoriteItems: json['favorite_items'],
    creditLimit: _toDouble(json['credit_limit']),
    outstandingBalance: _toDouble(json['outstanding_balance']),
    imageBase64: json['image_base64'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'birthday': birthday,
    'favorite_items': favoriteItems,
    'credit_limit': creditLimit,
    'outstanding_balance': outstandingBalance,
    'image_base64': imageBase64,
  };
}

class AddressModel {
  final int id;
  final int? userId;
  final int? customerId;
  final String label; // 'Home', 'Work', 'Other'
  final String addressLine;
  final double? latitude;
  final double? longitude;

  AddressModel({
    required this.id,
    this.userId,
    this.customerId,
    required this.label,
    required this.addressLine,
    this.latitude,
    this.longitude,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) => AddressModel(
    id: json['id'],
    userId: json['user_id'],
    customerId: json['customer_id'],
    label: json['label'] ?? 'Home',
    addressLine: json['address_line'] ?? '',
    latitude: json['latitude'] != null ? double.tryParse(json['latitude'].toString()) : null,
    longitude: json['longitude'] != null ? double.tryParse(json['longitude'].toString()) : null,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'customer_id': customerId,
    'label': label,
    'address_line': addressLine,
    'latitude': latitude,
    'longitude': longitude,
  };
}

// Order Item Model
class OrderItemModel {
  final int? id;
  final int? orderId;
  final int productId;
  final String productName;
  final String? productSinhalaName;
  final int quantity;
  final double price;
  final String? notes;
  final String status; // 'pending', 'preparing', 'completed'
  final bool isShortEat;
  final List<ProductExtra> extras;

  OrderItemModel({
    this.id,
    this.orderId,
    required this.productId,
    required this.productName,
    this.productSinhalaName,
    required this.quantity,
    required this.price,
    this.notes,
    this.status = 'pending',
    this.isShortEat = false,
    this.extras = const [],
  });

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    List<ProductExtra> extrasList = [];
    if (json['extras'] != null) {
      if (json['extras'] is String) {
        try {
          final decoded = jsonDecode(json['extras']) as List;
          extrasList = decoded.map((x) => ProductExtra.fromJson(x)).toList();
        } catch (_) {}
      } else if (json['extras'] is List) {
        extrasList = (json['extras'] as List).map((x) => ProductExtra.fromJson(x)).toList();
      }
    }

    return OrderItemModel(
      id: json['id'],
      orderId: json['order_id'],
      productId: json['product_id'],
      productName: json['product_name'] ?? 'Product',
      productSinhalaName: json['product_sinhala_name'],
      quantity: json['quantity'],
      price: _toDouble(json['price']),
      notes: json['notes'],
      status: json['status'] ?? 'pending',
      isShortEat: json['is_short_eat'] == true || json['is_short_eat'] == 1,
      extras: extrasList,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_id': orderId,
    'product_id': productId,
    'product_name': productName,
    'product_sinhala_name': productSinhalaName,
    'quantity': quantity,
    'price': price,
    'notes': notes,
    'status': status,
    'is_short_eat': isShortEat ? 1 : 0,
    'extras': extras.map((e) => e.toJson()).toList(),
  };
}

// Order Model
class OrderModel {
  final int? id;
  final String orderNumber;
  final int? tableId;
  final String orderType; // 'dine_in', 'takeaway', 'delivery'
  final String? deliveryPlatform; // 'uber_eats', 'pickme', 'phone', 'direct'
  final int? customerId;
  final String? stewardName;
  final String status; // 'pending', 'preparing', 'prepared', 'out_for_delivery', 'delivered', 'cancelled'
  final String paymentStatus; // 'unpaid', 'paid'
  final String? paymentMethod; // 'cash', 'credit', 'card', 'qr'
  final double subtotal;
  final double discount;
  final double total;
  final int cashierId;
  final int shiftId;
  final bool kotPrinted;
  final bool ackPrinted;
  final String? cardTxReference;
  final String barcode;
  final String createdAt;
  final String? updatedAt;
  final List<OrderItemModel> items;

  OrderModel({
    this.id,
    required this.orderNumber,
    this.tableId,
    required this.orderType,
    this.deliveryPlatform,
    this.customerId,
    this.stewardName,
    this.status = 'pending',
    this.paymentStatus = 'unpaid',
    this.paymentMethod,
    required this.subtotal,
    this.discount = 0.00,
    required this.total,
    required this.cashierId,
    required this.shiftId,
    this.kotPrinted = false,
    this.ackPrinted = false,
    this.cardTxReference,
    required this.barcode,
    required this.createdAt,
    this.updatedAt,
    required this.items,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<OrderItemModel> mappedItems = itemsList.map((i) => OrderItemModel.fromJson(i)).toList();

    return OrderModel(
      id: json['id'],
      orderNumber: json['order_number'],
      tableId: json['table_id'],
      orderType: json['order_type'],
      deliveryPlatform: json['delivery_platform'],
      customerId: json['customer_id'],
      stewardName: json['steward_name'],
      status: json['status'] ?? 'pending',
      paymentStatus: json['payment_status'] ?? 'unpaid',
      paymentMethod: json['payment_method'],
      subtotal: _toDouble(json['subtotal']),
      discount: _toDouble(json['discount']),
      total: _toDouble(json['total']),
      cashierId: json['cashier_id'],
      shiftId: json['shift_id'],
      kotPrinted: json['kot_printed'] == true || json['kot_printed'] == 1,
      ackPrinted: json['ack_printed'] == true || json['ack_printed'] == 1,
      cardTxReference: json['card_tx_reference'],
      barcode: json['barcode'] ?? json['order_number'],
      createdAt: json['created_at'],
      updatedAt: json['updated_at'] ?? json['created_at'],
      items: mappedItems,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_number': orderNumber,
    'table_id': tableId,
    'order_type': orderType,
    'delivery_platform': deliveryPlatform,
    'customer_id': customerId,
    'steward_name': stewardName,
    'status': status,
    'payment_status': paymentStatus,
    'payment_method': paymentMethod,
    'subtotal': subtotal,
    'discount': discount,
    'total': total,
    'cashier_id': cashierId,
    'shift_id': shiftId,
    'kot_printed': kotPrinted ? 1 : 0,
    'ack_printed': ackPrinted ? 1 : 0,
    'card_tx_reference': cardTxReference,
    'barcode': barcode,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

// Shift Model
class ShiftModel {
  final int id;
  final int userId;
  final String startTime;
  final String? endTime;
  final double openingBalance;
  final double closingBalance;
  final double actualClosingBalance;
  final String status; // 'open', 'closed'

  ShiftModel({
    required this.id,
    required this.userId,
    required this.startTime,
    this.endTime,
    required this.openingBalance,
    required this.closingBalance,
    required this.actualClosingBalance,
    required this.status,
  });

  factory ShiftModel.fromJson(Map<String, dynamic> json) => ShiftModel(
    id: json['id'],
    userId: json['user_id'],
    startTime: json['start_time'],
    endTime: json['end_time'],
    openingBalance: _toDouble(json['opening_balance']),
    closingBalance: _toDouble(json['closing_balance']),
    actualClosingBalance: _toDouble(json['actual_closing_balance']),
    status: json['status'] ?? 'open',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'start_time': startTime,
    'end_time': endTime,
    'opening_balance': openingBalance,
    'closing_balance': closingBalance,
    'actual_closing_balance': actualClosingBalance,
    'status': status,
  };
}

// Expense Model
class ExpenseModel {
  final int id;
  final String title;
  final double amount;
  final String category; // 'ingredients', 'salary', 'utility', 'rent', 'other'
  final String paymentSource; // 'drawer', 'bank'
  final int recordedBy;
  final String expenseDate;
  final String createdAt;

  ExpenseModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.paymentSource,
    required this.recordedBy,
    required this.expenseDate,
    required this.createdAt,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) => ExpenseModel(
    id: json['id'],
    title: json['title'],
    amount: _toDouble(json['amount']),
    category: json['category'],
    paymentSource: json['payment_source'],
    recordedBy: json['recorded_by'],
    expenseDate: json['expense_date'],
    createdAt: json['created_at'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'amount': amount,
    'category': category,
    'payment_source': paymentSource,
    'recorded_by': recordedBy,
    'expense_date': expenseDate,
    'created_at': createdAt,
  };
}

// Audit Log Model
class AuditLogModel {
  final int id;
  final String actionType;
  final String? tableName;
  final int? recordId;
  final String details;
  final int userId;
  final String timestamp;
  final String? username;
  final String? role;

  AuditLogModel({
    required this.id,
    required this.actionType,
    this.tableName,
    this.recordId,
    required this.details,
    required this.userId,
    required this.timestamp,
    this.username,
    this.role,
  });

  factory AuditLogModel.fromJson(Map<String, dynamic> json) => AuditLogModel(
    id: json['id'],
    actionType: json['action_type'],
    tableName: json['table_name'],
    recordId: json['record_id'],
    details: json['details'],
    userId: json['user_id'],
    timestamp: json['timestamp'],
    username: json['username'],
    role: json['role'],
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'action_type': actionType,
    'table_name': tableName,
    'record_id': recordId,
    'details': details,
    'user_id': userId,
    'timestamp': timestamp,
  };
}

// Offer Model
class OfferModel {
  final int? id;
  final String name;
  final double discountPercentage;
  final String startDate;
  final String endDate;
  final String? imageBase64;
  final String status; // 'active', 'inactive'

  OfferModel({
    this.id,
    required this.name,
    required this.discountPercentage,
    required this.startDate,
    required this.endDate,
    this.imageBase64,
    this.status = 'active',
  });

  factory OfferModel.fromJson(Map<String, dynamic> json) => OfferModel(
    id: json['id'],
    name: json['name'],
    discountPercentage: toDouble(json['discount_percentage']),
    startDate: json['start_date'],
    endDate: json['end_date'],
    imageBase64: json['image_base64'],
    status: json['status'] ?? 'active',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'discount_percentage': discountPercentage,
    'start_date': startDate,
    'end_date': endDate,
    'image_base64': imageBase64,
    'status': status,
  };
}

class IngredientModel {
  final int id;
  final String name;
  final double stockQty;
  final String unit;

  IngredientModel({
    required this.id,
    required this.name,
    required this.stockQty,
    required this.unit,
  });

  factory IngredientModel.fromJson(Map<String, dynamic> json) => IngredientModel(
        id: json['id'],
        name: json['name'],
        stockQty: double.tryParse(json['stock_qty'].toString()) ?? 0.0,
        unit: json['unit'] ?? 'kg',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'stock_qty': stockQty,
        'unit': unit,
      };
}
