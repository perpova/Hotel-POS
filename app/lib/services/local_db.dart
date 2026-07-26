import 'dart:convert';
import 'dart:io' show Platform, Directory;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:hotel_pos/models/models.dart';
import 'api_service.dart';

class LocalDB {
  static final LocalDB instance = LocalDB._init();
  static Database? _database;

  LocalDB._init();

  // Web fallback storage using SharedPreferences
  SharedPreferences? _webPrefs;

  Future<Database> get database async {
    if (_database != null) return _database!;
    if (kIsWeb) {
      throw UnsupportedError('SQLite is not supported on web. Use web storage helpers.');
    }
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS || defaultTargetPlatform == TargetPlatform.windows)) {
      try {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      } catch (_) {}
    }
    _database = await _initDB('local_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    try {
      final dbDir = Directory(dbPath);
      if (!dbDir.existsSync()) {
        dbDir.createSync(recursive: true);
      }
    } catch (_) {}

    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDB,
      onUpgrade: _onUpgradeDB,
    );
  }

  Future _onUpgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add cached_shifts table introduced in v2
      await db.execute('CREATE TABLE IF NOT EXISTS cached_shifts (id INTEGER PRIMARY KEY, user_id INTEGER, start_time TEXT, end_time TEXT, opening_balance REAL, closing_balance REAL, actual_closing_balance REAL, status TEXT)');
    }
    if (oldVersion < 3) {
      // Re-create cached_categories and master tables to ensure correct column definitions
      await db.execute('DROP TABLE IF EXISTS cached_categories');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_categories (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER, image_base64 TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_products (id INTEGER PRIMARY KEY, json_data TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_tables (id INTEGER PRIMARY KEY, table_number TEXT, capacity INTEGER, status TEXT, current_order_id INTEGER, steward_name TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, birthday TEXT, credit_limit REAL, outstanding_balance REAL, favorite_items TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_users (id INTEGER PRIMARY KEY, name TEXT, username TEXT, role TEXT, phone TEXT, image_base64 TEXT, status TEXT)');
    }
    if (oldVersion < 4) {
      await db.execute('CREATE TABLE IF NOT EXISTS cached_ingredients (id INTEGER PRIMARY KEY, name TEXT, stock_qty REAL, unit TEXT, min_stock_level REAL)');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_happy_hours (id INTEGER PRIMARY KEY, json_data TEXT)');
      await db.execute('CREATE TABLE IF NOT EXISTS cached_offers (id INTEGER PRIMARY KEY, json_data TEXT)');
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const textNullable = 'TEXT';
    const doubleType = 'REAL NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const intNullable = 'INTEGER';

    // Offline Orders Table
    await db.execute('''
      CREATE TABLE offline_orders (
        id $idType,
        order_number $textType,
        table_id $intNullable,
        order_type $textType,
        delivery_platform $textNullable,
        customer_id $intNullable,
        steward_name $textNullable,
        status $textType,
        payment_status $textType,
        payment_method $textNullable,
        subtotal $doubleType,
        discount $doubleType,
        total $doubleType,
        cashier_id $intType,
        shift_id $intType,
        kot_printed $intType,
        ack_printed $intType,
        card_tx_reference $textNullable,
        barcode $textType,
        created_at $textType,
        sync_status $textType,
        received_amount REAL DEFAULT 0.0,
        change_amount REAL DEFAULT 0.0
      )
    ''');

    // Offline Order Items Table
    await db.execute('''
      CREATE TABLE offline_order_items (
        id $idType,
        order_number $textType,
        product_id $intType,
        product_name $textType,
        product_sinhala_name $textNullable,
        quantity $intType,
        price $doubleType,
        notes $textNullable,
        status $textType,
        is_short_eat $intType
      )
    ''');

    // Offline Shifts Table
    await db.execute('''
      CREATE TABLE offline_shifts (
        id $intType PRIMARY KEY,
        user_id $intType,
        start_time $textType,
        end_time $textNullable,
        opening_balance $doubleType,
        closing_balance $doubleType,
        actual_closing_balance $doubleType,
        status $textType,
        sync_status $textType
      )
    ''');

    // Offline Expenses Table
    await db.execute('''
      CREATE TABLE offline_expenses (
        id $intType PRIMARY KEY,
        title $textType,
        amount $doubleType,
        category $textType,
        payment_source $textType,
        recorded_by $intType,
        expense_date $textType,
        created_at $textType,
        sync_status $textType
      )
    ''');

    // Offline Stock Logs Table
    await db.execute('''
      CREATE TABLE offline_stock_logs (
        id $idType,
        product_id $intType,
        change_qty $intType,
        type $textType,
        reason $textNullable,
        user_id $intType,
        timestamp $textType,
        sync_status $textType
      )
    ''');

    // Offline Audit Logs Table
    await db.execute('''
      CREATE TABLE offline_audit_logs (
        id $idType,
        action_type $textType,
        table_name $textNullable,
        record_id $intNullable,
        details $textType,
        user_id $intType,
        timestamp $textType,
        sync_status $textType
      )
    ''');

    // Master Data Local Mirror Tables (Never Auto-Deleted)
    await db.execute('CREATE TABLE IF NOT EXISTS cached_categories (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER, image_base64 TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_products (id INTEGER PRIMARY KEY, json_data TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_tables (id INTEGER PRIMARY KEY, table_number TEXT, capacity INTEGER, status TEXT, current_order_id INTEGER, steward_name TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, birthday TEXT, credit_limit REAL, outstanding_balance REAL, favorite_items TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_users (id INTEGER PRIMARY KEY, name TEXT, username TEXT, role TEXT, phone TEXT, image_base64 TEXT, status TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_shifts (id INTEGER PRIMARY KEY, user_id INTEGER, start_time TEXT, end_time TEXT, opening_balance REAL, closing_balance REAL, actual_closing_balance REAL, status TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_ingredients (id INTEGER PRIMARY KEY, name TEXT, stock_qty REAL, unit TEXT, min_stock_level REAL)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_happy_hours (id INTEGER PRIMARY KEY, json_data TEXT)');
    await db.execute('CREATE TABLE IF NOT EXISTS cached_offers (id INTEGER PRIMARY KEY, json_data TEXT)');
  }

  // ----------------------------------------------------
  // COMMON WEB PERSISTENCE HELPERS
  // ----------------------------------------------------
  Future<SharedPreferences> _getPrefs() async {
    _webPrefs ??= await SharedPreferences.getInstance();
    return _webPrefs!;
  }

  // Save/Get lists of JSONs on web
  Future<void> _webSaveList(String key, List<Map<String, dynamic>> list) async {
    final prefs = await _getPrefs();
    await prefs.setString(key, jsonEncode(list));
  }

  Future<List<Map<String, dynamic>>> _webGetList(String key) async {
    final prefs = await _getPrefs();
    final data = prefs.getString(key);
    if (data == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(data));
  }

  // ----------------------------------------------------
  // ORDER CACHING (OFFLINE SAVING)
  // ----------------------------------------------------

  Future<int> saveOrderOffline(OrderModel order) async {
    if (kIsWeb) {
      final orders = await _webGetList('offline_orders');
      final items = await _webGetList('offline_order_items');
      
      final orderJson = order.toJson();
      orderJson['sync_status'] = 'pending';
      final int generatedId = DateTime.now().millisecondsSinceEpoch % 1000000;
      orderJson['id'] = generatedId;
      orders.add(orderJson);
      
      for (var item in order.items) {
        final itemJson = item.toJson();
        itemJson['order_number'] = order.orderNumber;
        items.add(itemJson);
      }
      
      await _webSaveList('offline_orders', orders);
      await _webSaveList('offline_order_items', items);
      return generatedId;
    } else {
      final db = await instance.database;
      
      final int orderId = await db.insert('offline_orders', {
        'order_number': order.orderNumber,
        'table_id': order.tableId,
        'order_type': order.orderType,
        'delivery_platform': order.deliveryPlatform,
        'customer_id': order.customerId,
        'steward_name': order.stewardName,
        'status': order.status,
        'payment_status': order.paymentStatus,
        'payment_method': order.paymentMethod,
        'subtotal': order.subtotal,
        'discount': order.discount,
        'total': order.total,
        'cashier_id': order.cashierId,
        'shift_id': order.shiftId,
        'kot_printed': order.kotPrinted ? 1 : 0,
        'ack_printed': order.ackPrinted ? 1 : 0,
        'card_tx_reference': order.cardTxReference,
        'barcode': order.barcode,
        'created_at': order.createdAt,
        'sync_status': 'pending',
        'received_amount': order.receivedAmount,
        'change_amount': order.changeAmount
      });

      for (var item in order.items) {
        await db.insert('offline_order_items', {
          'order_number': order.orderNumber,
          'product_id': item.productId,
          'product_name': item.productName,
          'product_sinhala_name': item.productSinhalaName,
          'quantity': item.quantity,
          'price': item.price,
          'notes': item.notes,
          'status': item.status,
          'is_short_eat': item.isShortEat ? 1 : 0
        });
      }
      return orderId;
    }
  }

  Future<List<OrderModel>> getUnsyncedOrders() async {
    if (kIsWeb) {
      final orders = await _webGetList('offline_orders');
      final items = await _webGetList('offline_order_items');
      
      return orders.where((o) => o['sync_status'] == 'pending').map((o) {
        final oNum = o['order_number'];
        final orderItems = items
            .where((i) => i['order_number'] == oNum)
            .map((i) => OrderItemModel.fromJson(i))
            .toList();
        
        o['items'] = orderItems.map((i) => i.toJson()).toList();
        return OrderModel.fromJson(o);
      }).toList();
    } else {
      final db = await instance.database;
      final orderMaps = await db.query('offline_orders', where: 'sync_status = ?', whereArgs: ['pending']);
      
      List<OrderModel> orders = [];
      for (var map in orderMaps) {
        final orderNumber = map['order_number'] as String;
        final itemMaps = await db.query('offline_order_items', where: 'order_number = ?', whereArgs: [orderNumber]);
        
        List<OrderItemModel> items = itemMaps.map((i) => OrderItemModel(
          productId: i['product_id'] as int,
          productName: i['product_name'] as String,
          productSinhalaName: i['product_sinhala_name'] as String?,
          quantity: i['quantity'] as int,
          price: toDouble(i['price']),
          notes: i['notes'] as String?,
          status: i['status'] as String,
          isShortEat: i['is_short_eat'] == 1,
        )).toList();

        orders.add(OrderModel(
          id: map['id'] as int?,
          orderNumber: orderNumber,
          tableId: map['table_id'] as int?,
          orderType: map['order_type'] as String,
          deliveryPlatform: map['delivery_platform'] as String?,
          customerId: map['customer_id'] as int?,
          stewardName: map['steward_name'] as String?,
          status: map['status'] as String,
          paymentStatus: map['payment_status'] as String,
          paymentMethod: map['payment_method'] as String?,
          subtotal: toDouble(map['subtotal']),
          discount: toDouble(map['discount']),
          total: toDouble(map['total']),
          cashierId: map['cashier_id'] as int,
          shiftId: map['shift_id'] as int,
          kotPrinted: map['kot_printed'] == 1,
          ackPrinted: map['ack_printed'] == 1,
          cardTxReference: map['card_tx_reference'] as String?,
          barcode: map['barcode'] as String,
          createdAt: map['created_at'] as String,
          receivedAmount: toDouble(map['received_amount'] ?? 0.0),
          changeAmount: toDouble(map['change_amount'] ?? 0.0),
          items: items,
        ));
      }
      return orders;
    }
  }

  // ----------------------------------------------------
  // SHIFTS CACHING (OFFLINE SHIFTS)
  // ----------------------------------------------------
  Future<void> saveShiftOffline(ShiftModel shift) async {
    if (kIsWeb) {
      final shifts = await _webGetList('offline_shifts');
      final sJson = shift.toJson();
      sJson['sync_status'] = 'pending';
      shifts.add(sJson);
      await _webSaveList('offline_shifts', shifts);
    } else {
      final db = await instance.database;
      await db.insert('offline_shifts', {
        'id': shift.id,
        'user_id': shift.userId,
        'start_time': shift.startTime,
        'end_time': shift.endTime,
        'opening_balance': shift.openingBalance,
        'closing_balance': shift.closingBalance,
        'actual_closing_balance': shift.actualClosingBalance,
        'status': shift.status,
        'sync_status': 'pending'
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<List<ShiftModel>> getUnsyncedShifts() async {
    if (kIsWeb) {
      final shifts = await _webGetList('offline_shifts');
      return shifts
          .where((s) => s['sync_status'] == 'pending')
          .map((s) => ShiftModel.fromJson(s))
          .toList();
    } else {
      final db = await instance.database;
      final maps = await db.query('offline_shifts', where: 'sync_status = ?', whereArgs: ['pending']);
      return maps.map((s) => ShiftModel.fromJson(s)).toList();
    }
  }

  // ----------------------------------------------------
  // EXPENSES CACHING (OFFLINE EXPENSES)
  // ----------------------------------------------------
  Future<void> saveExpenseOffline(ExpenseModel expense) async {
    if (kIsWeb) {
      final expenses = await _webGetList('offline_expenses');
      final eJson = expense.toJson();
      eJson['sync_status'] = 'pending';
      expenses.add(eJson);
      await _webSaveList('offline_expenses', expenses);
    } else {
      final db = await instance.database;
      await db.insert('offline_expenses', {
        'id': expense.id,
        'title': expense.title,
        'amount': expense.amount,
        'category': expense.category,
        'payment_source': expense.paymentSource,
        'recorded_by': expense.recordedBy,
        'expense_date': expense.expenseDate,
        'created_at': expense.createdAt,
        'sync_status': 'pending'
      });
    }
  }

  Future<List<ExpenseModel>> getUnsyncedExpenses() async {
    if (kIsWeb) {
      final expenses = await _webGetList('offline_expenses');
      return expenses
          .where((e) => e['sync_status'] == 'pending')
          .map((e) => ExpenseModel.fromJson(e))
          .toList();
    } else {
      final db = await instance.database;
      final maps = await db.query('offline_expenses', where: 'sync_status = ?', whereArgs: ['pending']);
      return maps.map((e) => ExpenseModel.fromJson(e)).toList();
    }
  }

  // ----------------------------------------------------
  // AUDIT & STOCK LOG CACHING
  // ----------------------------------------------------
  Future<void> saveAuditOffline(String actionType, String? tableName, int? recordId, String details, int userId) async {
    final timestamp = DateTime.now().toIso8601String();
    if (kIsWeb) {
      final logs = await _webGetList('offline_audit_logs');
      logs.add({
        'action_type': actionType,
        'table_name': tableName,
        'record_id': recordId,
        'details': details,
        'user_id': userId,
        'timestamp': timestamp,
        'sync_status': 'pending'
      });
      await _webSaveList('offline_audit_logs', logs);
    } else {
      final db = await instance.database;
      await db.insert('offline_audit_logs', {
        'action_type': actionType,
        'table_name': tableName,
        'record_id': recordId,
        'details': details,
        'user_id': userId,
        'timestamp': timestamp,
        'sync_status': 'pending'
      });
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedAudits() async {
    if (kIsWeb) {
      final logs = await _webGetList('offline_audit_logs');
      return logs.where((l) => l['sync_status'] == 'pending').toList();
    } else {
      final db = await instance.database;
      return await db.query('offline_audit_logs', where: 'sync_status = ?', whereArgs: ['pending']);
    }
  }

  Future<void> saveStockLogOffline(int productId, int changeQty, String type, String reason, int userId) async {
    final timestamp = DateTime.now().toIso8601String();
    if (kIsWeb) {
      final logs = await _webGetList('offline_stock_logs');
      logs.add({
        'product_id': productId,
        'change_qty': changeQty,
        'type': type,
        'reason': reason,
        'user_id': userId,
        'timestamp': timestamp,
        'sync_status': 'pending'
      });
      await _webSaveList('offline_stock_logs', logs);
    } else {
      final db = await instance.database;
      await db.insert('offline_stock_logs', {
        'product_id': productId,
        'change_qty': changeQty,
        'type': type,
        'reason': reason,
        'user_id': userId,
        'timestamp': timestamp,
        'sync_status': 'pending'
      });
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedStockLogs() async {
    if (kIsWeb) {
      final logs = await _webGetList('offline_stock_logs');
      return logs.where((l) => l['sync_status'] == 'pending').toList();
    } else {
      final db = await instance.database;
      return await db.query('offline_stock_logs', where: 'sync_status = ?', whereArgs: ['pending']);
    }
  }

  // ----------------------------------------------------
  // CLEAR OUT & RETENTION (2 DAYS RULE FOR SYNCED ORDERS)
  // ----------------------------------------------------
  Future<void> markAllPendingAsSynced() async {
    if (kIsWeb) {
      final orders = await _webGetList('offline_orders');
      for (var o in orders) {
        o['sync_status'] = 'synced';
      }
      await _webSaveList('offline_orders', orders);
    } else {
      final db = await instance.database;
      await db.update('offline_orders', {'sync_status': 'synced'}, where: 'sync_status = ?', whereArgs: ['pending']);
      await db.update('offline_shifts', {'sync_status': 'synced'}, where: 'sync_status = ?', whereArgs: ['pending']);
      await db.update('offline_expenses', {'sync_status': 'synced'}, where: 'sync_status = ?', whereArgs: ['pending']);
      await db.update('offline_stock_logs', {'sync_status': 'synced'}, where: 'sync_status = ?', whereArgs: ['pending']);
      await db.update('offline_audit_logs', {'sync_status': 'synced'}, where: 'sync_status = ?', whereArgs: ['pending']);
    }
  }

  Future<void> purgeSyncedDataOlderThan2Days() async {
    // NOTE: This method ONLY purges transactional offline records.
    // cached_products, cached_categories, cached_users, cached_tables, cached_shifts
    // are NEVER touched here — they are master data and must persist indefinitely.
    final cutoffDate = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
    if (kIsWeb) {
      final orders = await _webGetList('offline_orders');
      final items = await _webGetList('offline_order_items');
      
      final remainingOrders = orders.where((o) {
        if (o['sync_status'] == 'synced') {
          final createdAt = o['created_at']?.toString() ?? '';
          return createdAt.compareTo(cutoffDate) >= 0;
        }
        return true;
      }).toList();

      final remainingOrderNumbers = remainingOrders.map((o) => o['order_number']).toSet();
      final remainingItems = items.where((i) => remainingOrderNumbers.contains(i['order_number'])).toList();

      await _webSaveList('offline_orders', remainingOrders);
      await _webSaveList('offline_order_items', remainingItems);
    } else {
      final db = await instance.database;
      // Only delete TRANSACTIONAL offline tables — never cached master data tables
      await db.delete('offline_orders', where: 'sync_status = ? AND created_at < ?', whereArgs: ['synced', cutoffDate]);
      await db.execute('DELETE FROM offline_order_items WHERE order_number NOT IN (SELECT order_number FROM offline_orders)');
      await db.delete('offline_shifts', where: 'sync_status = ? AND start_time < ?', whereArgs: ['synced', cutoffDate]);
      await db.delete('offline_expenses', where: 'sync_status = ? AND created_at < ?', whereArgs: ['synced', cutoffDate]);
      await db.delete('offline_stock_logs', where: 'sync_status = ? AND timestamp < ?', whereArgs: ['synced', cutoffDate]);
      await db.delete('offline_audit_logs', where: 'sync_status = ? AND timestamp < ?', whereArgs: ['synced', cutoffDate]);
    }
  }

  Future<void> clearSyncedData() async {
    await markAllPendingAsSynced();
    await purgeSyncedDataOlderThan2Days();
  }

  // ----------------------------------------------------
  // MASTER DATA LOCAL MIRROR (ITEMS, CATEGORIES, TABLES, USERS, CUSTOMERS)
  // ----------------------------------------------------
  Future<void> cacheCategories(List<CategoryModel> categories) async {
    if (kIsWeb) {
      await _webSaveList('cached_categories', categories.map((c) => c.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_categories');
        for (var c in categories) {
          batch.insert('cached_categories', {
            'id': c.id,
            'name': c.name,
            'parent_id': c.parentId,
            'image_base64': c.imageBase64,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        // Self-heal table schema if old SQLite database file is missing columns
        await db.execute('DROP TABLE IF EXISTS cached_categories');
        await db.execute('CREATE TABLE IF NOT EXISTS cached_categories (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER, image_base64 TEXT)');
        final batch = db.batch();
        for (var c in categories) {
          batch.insert('cached_categories', {
            'id': c.id,
            'name': c.name,
            'parent_id': c.parentId,
            'image_base64': c.imageBase64,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<List<CategoryModel>> getCachedCategories() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_categories');
      return list.map((c) => CategoryModel.fromJson(Map<String, dynamic>.from(c))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_categories');
        return maps.map((c) => CategoryModel.fromJson(c)).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> cacheProducts(List<ProductModel> products) async {
    if (kIsWeb) {
      await _webSaveList('cached_products', products.map((p) => p.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_products');
        for (var p in products) {
          batch.insert('cached_products', {
            'id': p.id,
            'json_data': jsonEncode(p.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('DROP TABLE IF EXISTS cached_products');
        await db.execute('CREATE TABLE IF NOT EXISTS cached_products (id INTEGER PRIMARY KEY, json_data TEXT)');
        final batch = db.batch();
        for (var p in products) {
          batch.insert('cached_products', {
            'id': p.id,
            'json_data': jsonEncode(p.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<List<ProductModel>> getCachedProducts() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_products');
      return list.map((p) => ProductModel.fromJson(Map<String, dynamic>.from(p))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_products');
        return maps.map((p) {
          final rawJson = p['json_data'] as String;
          return ProductModel.fromJson(jsonDecode(rawJson) as Map<String, dynamic>);
        }).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> cacheTables(List<DiningTableModel> tables) async {
    if (kIsWeb) {
      await _webSaveList('cached_tables', tables.map((t) => t.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_tables');
        for (var t in tables) {
          batch.insert('cached_tables', {
            'id': t.id,
            'table_number': t.tableNumber,
            'capacity': t.capacity,
            'status': t.status,
            'current_order_id': t.currentOrderId,
            'steward_name': t.stewardName,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('DROP TABLE IF EXISTS cached_tables');
        await db.execute('CREATE TABLE IF NOT EXISTS cached_tables (id INTEGER PRIMARY KEY, table_number TEXT, capacity INTEGER, status TEXT, current_order_id INTEGER, steward_name TEXT)');
        final batch = db.batch();
        for (var t in tables) {
          batch.insert('cached_tables', {
            'id': t.id,
            'table_number': t.tableNumber,
            'capacity': t.capacity,
            'status': t.status,
            'current_order_id': t.currentOrderId,
            'steward_name': t.stewardName,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<List<DiningTableModel>> getCachedTables() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_tables');
      return list.map((t) => DiningTableModel.fromJson(Map<String, dynamic>.from(t))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_tables');
        return maps.map((t) => DiningTableModel.fromJson(t)).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> cacheCustomers(List<CustomerModel> customers) async {
    if (kIsWeb) {
      await _webSaveList('cached_customers', customers.map((c) => c.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_customers');
        for (var c in customers) {
          batch.insert('cached_customers', {
            'id': c.id,
            'name': c.name,
            'phone': c.phone,
            'birthday': c.birthday,
            'credit_limit': c.creditLimit,
            'outstanding_balance': c.outstandingBalance,
            'favorite_items': c.favoriteItems,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('DROP TABLE IF EXISTS cached_customers');
        await db.execute('CREATE TABLE IF NOT EXISTS cached_customers (id INTEGER PRIMARY KEY, name TEXT, phone TEXT, birthday TEXT, credit_limit REAL, outstanding_balance REAL, favorite_items TEXT)');
        final batch = db.batch();
        for (var c in customers) {
          batch.insert('cached_customers', {
            'id': c.id,
            'name': c.name,
            'phone': c.phone,
            'birthday': c.birthday,
            'credit_limit': c.creditLimit,
            'outstanding_balance': c.outstandingBalance,
            'favorite_items': c.favoriteItems,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<List<CustomerModel>> getCachedCustomers() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_customers');
      return list.map((c) => CustomerModel.fromJson(Map<String, dynamic>.from(c))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_customers');
        return maps.map((c) => CustomerModel.fromJson(c)).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> cacheUsers(List<UserModel> users) async {
    if (kIsWeb) {
      await _webSaveList('cached_users', users.map((u) => u.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_users');
        for (var u in users) {
          batch.insert('cached_users', {
            'id': u.id,
            'name': u.name,
            'username': u.username,
            'role': u.role,
            'phone': u.phone,
            'image_base64': u.imageBase64,
            'status': u.status,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('DROP TABLE IF EXISTS cached_users');
        await db.execute('CREATE TABLE IF NOT EXISTS cached_users (id INTEGER PRIMARY KEY, name TEXT, username TEXT, role TEXT, phone TEXT, image_base64 TEXT, status TEXT)');
        final batch = db.batch();
        for (var u in users) {
          batch.insert('cached_users', {
            'id': u.id,
            'name': u.name,
            'username': u.username,
            'role': u.role,
            'phone': u.phone,
            'image_base64': u.imageBase64,
            'status': u.status,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<List<UserModel>> getCachedUsers() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_users');
      return list.map((u) => UserModel.fromJson(Map<String, dynamic>.from(u))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_users');
        return maps.map((u) => UserModel.fromJson(u)).toList();
      } catch (e) {
        return [];
      }
    }
  }

  // ----------------------------------------------------
  // SHIFTS MIRROR CACHE (Master Data — never auto-deleted)
  // ----------------------------------------------------
  Future<void> cacheShifts(List<ShiftModel> shifts) async {
    if (kIsWeb) {
      await _webSaveList('cached_shifts', shifts.map((s) => s.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_shifts');
        for (var s in shifts) {
          batch.insert('cached_shifts', {
            'id': s.id,
            'user_id': s.userId,
            'start_time': s.startTime,
            'end_time': s.endTime,
            'opening_balance': s.openingBalance,
            'closing_balance': s.closingBalance,
            'actual_closing_balance': s.actualClosingBalance,
            'status': s.status,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('DROP TABLE IF EXISTS cached_shifts');
        await db.execute('CREATE TABLE IF NOT EXISTS cached_shifts (id INTEGER PRIMARY KEY, user_id INTEGER, start_time TEXT, end_time TEXT, opening_balance REAL, closing_balance REAL, actual_closing_balance REAL, status TEXT)');
        final batch = db.batch();
        for (var s in shifts) {
          batch.insert('cached_shifts', {
            'id': s.id,
            'user_id': s.userId,
            'start_time': s.startTime,
            'end_time': s.endTime,
            'opening_balance': s.openingBalance,
            'closing_balance': s.closingBalance,
            'actual_closing_balance': s.actualClosingBalance,
            'status': s.status,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      }
    }
  }

  Future<List<ShiftModel>> getCachedShifts() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_shifts');
      return list.map((s) => ShiftModel.fromJson(Map<String, dynamic>.from(s))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_shifts', orderBy: 'start_time DESC');
        return maps.map((s) => ShiftModel.fromJson(s)).toList();
      } catch (e) {
        return [];
      }
    }
  }

  // ----------------------------------------------------
  // PRECISE SYNC STATUS HELPERS
  // ----------------------------------------------------
  /// Marks a specific offline order as synced by its order_number.
  Future<void> markOrderSynced(String orderNumber) async {
    if (kIsWeb) {
      final orders = await _webGetList('offline_orders');
      for (var o in orders) {
        if (o['order_number'] == orderNumber) o['sync_status'] = 'synced';
      }
      await _webSaveList('offline_orders', orders);
    } else {
      final db = await instance.database;
      await db.update('offline_orders', {'sync_status': 'synced'},
          where: 'order_number = ?', whereArgs: [orderNumber]);
    }
  }

  /// Marks a specific offline shift as synced by its id.
  Future<void> markShiftSynced(int shiftId) async {
    if (kIsWeb) {
      final shifts = await _webGetList('offline_shifts');
      for (var s in shifts) {
        if (s['id'] == shiftId) s['sync_status'] = 'synced';
      }
      await _webSaveList('offline_shifts', shifts);
    } else {
      final db = await instance.database;
      await db.update('offline_shifts', {'sync_status': 'synced'},
          where: 'id = ?', whereArgs: [shiftId]);
    }
  }

  // ----------------------------------------------------
  // INGREDIENTS, HAPPY HOURS, OFFERS LOCAL MIRROR CACHE
  // ----------------------------------------------------
  Future<void> cacheIngredients(List<IngredientModel> ingredients) async {
    if (kIsWeb) {
      await _webSaveList('cached_ingredients', ingredients.map((i) => i.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_ingredients');
        for (var i in ingredients) {
          batch.insert('cached_ingredients', {
            'id': i.id,
            'name': i.name,
            'stock_qty': i.stockQty,
            'unit': i.unit,
            'min_stock_level': i.minStockLevel,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('CREATE TABLE IF NOT EXISTS cached_ingredients (id INTEGER PRIMARY KEY, name TEXT, stock_qty REAL, unit TEXT, min_stock_level REAL)');
      }
    }
  }

  Future<List<IngredientModel>> getCachedIngredients() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_ingredients');
      return list.map((i) => IngredientModel.fromJson(Map<String, dynamic>.from(i))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_ingredients');
        return maps.map((i) => IngredientModel.fromJson(i)).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> cacheHappyHours(List<Map<String, dynamic>> happyHours) async {
    if (kIsWeb) {
      await _webSaveList('cached_happy_hours', happyHours);
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_happy_hours');
        for (var h in happyHours) {
          batch.insert('cached_happy_hours', {
            'id': h['id'],
            'json_data': jsonEncode(h),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('CREATE TABLE IF NOT EXISTS cached_happy_hours (id INTEGER PRIMARY KEY, json_data TEXT)');
      }
    }
  }

  Future<List<Map<String, dynamic>>> getCachedHappyHours() async {
    if (kIsWeb) {
      return await _webGetList('cached_happy_hours');
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_happy_hours');
        return maps.map((h) => jsonDecode(h['json_data'] as String) as Map<String, dynamic>).toList();
      } catch (e) {
        return [];
      }
    }
  }

  Future<void> cacheOffers(List<OfferModel> offers) async {
    if (kIsWeb) {
      await _webSaveList('cached_offers', offers.map((o) => o.toJson()).toList());
    } else {
      final db = await instance.database;
      try {
        final batch = db.batch();
        batch.delete('cached_offers');
        for (var o in offers) {
          batch.insert('cached_offers', {
            'id': o.id,
            'json_data': jsonEncode(o.toJson()),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await batch.commit(noResult: true);
      } catch (e) {
        await db.execute('CREATE TABLE IF NOT EXISTS cached_offers (id INTEGER PRIMARY KEY, json_data TEXT)');
      }
    }
  }

  Future<List<OfferModel>> getCachedOffers() async {
    if (kIsWeb) {
      final list = await _webGetList('cached_offers');
      return list.map((o) => OfferModel.fromJson(Map<String, dynamic>.from(o))).toList();
    } else {
      final db = await instance.database;
      try {
        final maps = await db.query('cached_offers');
        return maps.map((o) => OfferModel.fromJson(jsonDecode(o['json_data'] as String))).toList();
      } catch (e) {
        return [];
      }
    }
  }

  // Batch mark synced helpers
  Future<void> markOrdersSyncedBatch(List<String> orderNumbers) async {
    if (orderNumbers.isEmpty) return;
    for (var num in orderNumbers) {
      await markOrderSynced(num);
    }
  }

  Future<void> markShiftsSyncedBatch(List<int> shiftIds) async {
    if (shiftIds.isEmpty) return;
    for (var id in shiftIds) {
      await markShiftSynced(id);
    }
  }

  Future<void> markExpensesSyncedBatch(List<int> expenseIds) async {
    if (expenseIds.isEmpty) return;
    if (kIsWeb) {
      final expenses = await _webGetList('offline_expenses');
      for (var e in expenses) {
        if (expenseIds.contains(e['id'])) e['sync_status'] = 'synced';
      }
      await _webSaveList('offline_expenses', expenses);
    } else {
      final db = await instance.database;
      final batch = db.batch();
      for (var id in expenseIds) {
        batch.update('offline_expenses', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> markStockLogsSyncedBatch(List<int> ids) async {
    if (ids.isEmpty) return;
    if (kIsWeb) {
      final logs = await _webGetList('offline_stock_logs');
      for (var l in logs) {
        if (ids.contains(l['id'])) l['sync_status'] = 'synced';
      }
      await _webSaveList('offline_stock_logs', logs);
    } else {
      final db = await instance.database;
      final batch = db.batch();
      for (var id in ids) {
        batch.update('offline_stock_logs', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> markAuditLogsSyncedBatch(List<int> ids) async {
    if (ids.isEmpty) return;
    if (kIsWeb) {
      final logs = await _webGetList('offline_audit_logs');
      for (var l in logs) {
        if (ids.contains(l['id'])) l['sync_status'] = 'synced';
      }
      await _webSaveList('offline_audit_logs', logs);
    } else {
      final db = await instance.database;
      final batch = db.batch();
      for (var id in ids) {
        batch.update('offline_audit_logs', {'sync_status': 'synced'}, where: 'id = ?', whereArgs: [id]);
      }
      await batch.commit(noResult: true);
    }
  }

  /// Fetches all orders saved in Local DB (both pending and synced)
  Future<List<OrderModel>> getAllOrders() async {
    try {
      if (kIsWeb) {
        final orders = await _webGetList('offline_orders');
        final items = await _webGetList('offline_order_items');
        return orders.map((o) {
          final oNum = o['order_number'];
          final orderItems = items
              .where((i) => i['order_number'] == oNum)
              .map((i) => OrderItemModel.fromJson(i))
              .toList();
          o['items'] = orderItems.map((i) => i.toJson()).toList();
          return OrderModel.fromJson(o);
        }).toList();
      } else {
        final db = await instance.database;
        final orderMaps = await db.query('offline_orders', orderBy: 'id DESC');
        
        List<OrderModel> orders = [];
        for (var map in orderMaps) {
          final orderNumber = map['order_number'] as String;
          final itemMaps = await db.query('offline_order_items', where: 'order_number = ?', whereArgs: [orderNumber]);
          
          List<OrderItemModel> items = itemMaps.map((i) => OrderItemModel(
            productId: i['product_id'] as int,
            productName: i['product_name'] as String,
            productSinhalaName: i['product_sinhala_name'] as String?,
            quantity: i['quantity'] as int,
            price: toDouble(i['price']),
            notes: i['notes'] as String?,
            status: i['status'] as String,
            isShortEat: i['is_short_eat'] == 1,
          )).toList();

          orders.add(OrderModel(
            id: map['id'] as int?,
            orderNumber: orderNumber,
            tableId: map['table_id'] as int?,
            orderType: map['order_type'] as String,
            deliveryPlatform: map['delivery_platform'] as String?,
            customerId: map['customer_id'] as int?,
            stewardName: map['steward_name'] as String?,
            status: map['status'] as String,
            paymentStatus: map['payment_status'] as String,
            paymentMethod: map['payment_method'] as String?,
            subtotal: toDouble(map['subtotal']),
            discount: toDouble(map['discount']),
            total: toDouble(map['total']),
            cashierId: map['cashier_id'] as int,
            shiftId: map['shift_id'] as int,
            kotPrinted: map['kot_printed'] == 1,
            ackPrinted: map['ack_printed'] == 1,
            cardTxReference: map['card_tx_reference'] as String?,
            barcode: map['barcode'] as String,
            createdAt: map['created_at'] as String,
            receivedAmount: toDouble(map['received_amount'] ?? 0.0),
            changeAmount: toDouble(map['change_amount'] ?? 0.0),
            items: items,
          ));
        }
        return orders;
      }
    } catch (e) {
      print('getAllOrders exception: $e');
      return [];
    }
  }

  /// Caches a batch of orders into local SQLite DB
  Future<void> cacheOrders(List<OrderModel> orders) async {
    try {
      if (orders.isEmpty) return;
      if (kIsWeb) {
        final existingOrders = await _webGetList('offline_orders');
        final existingItems = await _webGetList('offline_order_items');
        
        for (var order in orders) {
          final idx = existingOrders.indexWhere((o) => o['order_number'] == order.orderNumber);
          final oJson = order.toJson();
          oJson['sync_status'] = 'synced';
          if (idx != -1) {
            existingOrders[idx] = oJson;
          } else {
            existingOrders.add(oJson);
          }

          for (var item in order.items) {
            final itemJson = item.toJson();
            itemJson['order_number'] = order.orderNumber;
            final iIdx = existingItems.indexWhere((i) => i['order_number'] == order.orderNumber && i['product_id'] == item.productId);
            if (iIdx != -1) {
              existingItems[iIdx] = itemJson;
            } else {
              existingItems.add(itemJson);
            }
          }
        }
        await _webSaveList('offline_orders', existingOrders);
        await _webSaveList('offline_order_items', existingItems);
      } else {
        final db = await instance.database;
        final batch = db.batch();
        for (var order in orders) {
          batch.insert('offline_orders', {
            'id': order.id,
            'order_number': order.orderNumber,
            'table_id': order.tableId,
            'order_type': order.orderType,
            'delivery_platform': order.deliveryPlatform,
            'customer_id': order.customerId,
            'steward_name': order.stewardName,
            'status': order.status,
            'payment_status': order.paymentStatus,
            'payment_method': order.paymentMethod,
            'subtotal': order.subtotal,
            'discount': order.discount,
            'total': order.total,
            'cashier_id': order.cashierId,
            'shift_id': order.shiftId,
            'kot_printed': order.kotPrinted ? 1 : 0,
            'ack_printed': order.ackPrinted ? 1 : 0,
            'card_tx_reference': order.cardTxReference,
            'barcode': order.barcode,
            'created_at': order.createdAt,
            'sync_status': 'synced',
            'received_amount': order.receivedAmount,
            'change_amount': order.changeAmount
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          for (var item in order.items) {
            batch.insert('offline_order_items', {
              'order_number': order.orderNumber,
              'product_id': item.productId,
              'product_name': item.productName,
              'product_sinhala_name': item.productSinhalaName,
              'quantity': item.quantity,
              'price': item.price,
              'notes': item.notes,
              'status': item.status,
              'is_short_eat': item.isShortEat ? 1 : 0
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
        await batch.commit(noResult: true);
      }
    } catch (e) {
      print('cacheOrders exception: $e');
    }
  }

  /// Calculates breakdown of all pending offline records in Local DB and Local MySQL DB
  Future<Map<String, int>> getPendingCounts() async {
    try {
      final allOrders = await getAllOrders();
      final unsyncedOrders = await getUnsyncedOrders();
      final unsyncedShifts = await getUnsyncedShifts();
      final unsyncedExpenses = await getUnsyncedExpenses();
      final unsyncedStockLogs = await getUnsyncedStockLogs();
      final unsyncedAudits = await getUnsyncedAudits();

      // Query Local MySQL Workbench DB unsynced orders count
      final int localMySqlOrdersCount = await APIService.instance.getLocalMySqlSyncStatus();

      final int ordersTotal = allOrders.length;
      final int ordersPending = unsyncedOrders.length + localMySqlOrdersCount;
      final int shiftsPending = unsyncedShifts.length;
      final int expensesPending = unsyncedExpenses.length;
      final int stockLogsPending = unsyncedStockLogs.length;
      final int auditLogsPending = unsyncedAudits.length;
      final int totalPending = ordersPending + shiftsPending + expensesPending + stockLogsPending + auditLogsPending;

      return {
        'orders': ordersPending,
        'orders_total': (ordersTotal + localMySqlOrdersCount).toInt(),
        'shifts': shiftsPending,
        'expenses': expensesPending,
        'stock_logs': stockLogsPending,
        'audit_logs': auditLogsPending,
        'total': totalPending,
      };
    } catch (_) {
      return {
        'orders': 0,
        'orders_total': 0,
        'shifts': 0,
        'expenses': 0,
        'stock_logs': 0,
        'audit_logs': 0,
        'total': 0,
      };
    }
  }
}

