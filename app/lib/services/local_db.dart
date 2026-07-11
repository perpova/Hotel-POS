import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:hotel_pos/models/models.dart';

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
    _database = await _initDB('local_pos.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
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
  // CLEAR OUT PENDING AFTER SYNC COMPLETE
  // ----------------------------------------------------
  Future<void> clearSyncedData() async {
    if (kIsWeb) {
      final prefs = await _getPrefs();
      await prefs.remove('offline_orders');
      await prefs.remove('offline_order_items');
      await prefs.remove('offline_shifts');
      await prefs.remove('offline_expenses');
      await prefs.remove('offline_stock_logs');
      await prefs.remove('offline_audit_logs');
    } else {
      final db = await instance.database;
      await db.delete('offline_orders', where: 'sync_status = ?', whereArgs: ['pending']);
      await db.delete('offline_order_items');
      await db.delete('offline_shifts', where: 'sync_status = ?', whereArgs: ['pending']);
      await db.delete('offline_expenses', where: 'sync_status = ?', whereArgs: ['pending']);
      await db.delete('offline_stock_logs', where: 'sync_status = ?', whereArgs: ['pending']);
      await db.delete('offline_audit_logs', where: 'sync_status = ?', whereArgs: ['pending']);
    }
  }
}
