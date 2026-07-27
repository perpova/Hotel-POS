import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../core/local_notification_service.dart';
import '../models/models.dart';

/// Manages in-app notifications & device system notification tray for:
///   • Raw stock going low (products & ingredients)
///   • Pre-orders due in 2 days, 1 day, or today (received day)
class NotificationProvider extends ChangeNotifier {
  List<AppNotification> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;

  // Track keys that have already triggered a device status bar push notification
  final Set<String> _notifiedSystemKeys = {};

  // Persistent set of notification keys that have been marked as read by user
  Set<String> _readKeys = {};

  // Debounce for rapid realtime events
  Timer? _stockDebounce;
  Timer? _preOrderDebounce;

  // Periodic local check (every 30 min) to catch missed WS events
  Timer? _periodicCheck;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;

  // ─── Initialization ────────────────────────────────────────────────────────

  void init() async {
    LocalNotificationService.instance.init();
    await _loadReadKeys();
    _loadAll();
    // Periodic refresh every 30 minutes (fallback when WS misses something)
    _periodicCheck = Timer.periodic(const Duration(minutes: 30), (_) {
      _loadAll(silent: true);
    });
  }

  Future<void> _loadReadKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('read_notification_keys') ?? [];
      _readKeys = list.toSet();
    } catch (_) {}
  }

  Future<void> _saveReadKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('read_notification_keys', _readKeys.toList());
    } catch (_) {}
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }
    try {
      // Load server notifications
      final raw = await ApiService.instance.getNotifications();
      final serverNotes = raw.map(AppNotification.fromServerJson).toList();

      // Compute local stock & pre-order alerts
      final stockAlerts = await _buildStockAlerts();
      final preOrderAlerts = await _buildPreOrderAlerts();

      // Merge: server first, then local (dedup by key)
      final seen = <String>{};
      final merged = <AppNotification>[];
      for (final n in [...serverNotes, ...stockAlerts, ...preOrderAlerts]) {
        if (seen.add(n.key)) {
          // Preserve persistent read status across app restarts
          if (_readKeys.contains(n.key)) {
            merged.add(n.copyWith(isRead: true));
          } else {
            merged.add(n);
          }
        }
      }
      merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _notifications = merged;
      _recalcUnread();

      // Fire system status bar notifications ONLY for unread items
      for (final n in merged) {
        if (!n.isRead) {
          _triggerSystemPush(n);
        }
      }
    } catch (_) {}

    _isLoading = false;
    notifyListeners();
  }

  // ─── Stock Alerts ──────────────────────────────────────────────────────────

  Future<List<AppNotification>> _buildStockAlerts() async {
    final alerts = <AppNotification>[];
    try {
      final products = await ApiService.instance.getAllProducts();
      final ingredients = await ApiService.instance.getIngredients();

      for (final p in products) {
        if (!p.trackStock) continue;
        if (p.isOutOfStock) {
          alerts.add(AppNotification(
            key: 'stock_out_${p.id}',
            title: '🚨 Out of Stock',
            message: '${p.name} is completely out of stock (${p.stockQty} units).',
            type: NotificationType.stockCritical,
            createdAt: DateTime.now(),
            isRead: false,
          ));
        } else if (p.isLowStock) {
          alerts.add(AppNotification(
            key: 'stock_low_${p.id}',
            title: '⚠️ Low Stock Alert',
            message: '${p.name} is running low — only ${p.stockQty} units left (min: ${p.minStockLevel}).',
            type: NotificationType.stockLow,
            createdAt: DateTime.now(),
            isRead: false,
          ));
        }
      }

      for (final i in ingredients) {
        if (i.isOutOfStock) {
          alerts.add(AppNotification(
            key: 'ing_out_${i.id}',
            title: '🚨 Ingredient Out',
            message: '${i.name} is completely out (${i.stockQty.toStringAsFixed(1)} ${i.unit}).',
            type: NotificationType.stockCritical,
            createdAt: DateTime.now(),
            isRead: false,
          ));
        } else if (i.isLowStock) {
          alerts.add(AppNotification(
            key: 'ing_low_${i.id}',
            title: '⚠️ Low Ingredient',
            message: '${i.name} is low — ${i.stockQty.toStringAsFixed(1)} ${i.unit} remaining (min: ${i.minStockLevel.toStringAsFixed(1)}).',
            type: NotificationType.stockLow,
            createdAt: DateTime.now(),
            isRead: false,
          ));
        }
      }
    } catch (_) {}
    return alerts;
  }

  // ─── Pre-Order Alerts ─────────────────────────────────────────────────────

  Future<List<AppNotification>> _buildPreOrderAlerts() async {
    final alerts = <AppNotification>[];
    try {
      final preOrders = await ApiService.instance.getPreOrders();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      for (final po in preOrders) {
        final status = po['status']?.toString() ?? 'pending';
        if (status == 'completed' || status == 'cancelled') continue;

        final receivedDateRaw = po['received_date']?.toString() ?? '';
        if (receivedDateRaw.isEmpty) continue;

        DateTime receivedDate;
        try {
          receivedDate = DateTime.parse(receivedDateRaw);
        } catch (_) {
          continue;
        }

        final dueDay = DateTime(receivedDate.year, receivedDate.month, receivedDate.day);
        final daysUntil = dueDay.difference(today).inDays;

        final poNum = po['pre_order_number']?.toString() ?? '#?';
        final customer = po['customer_name']?.toString() ?? 'Customer';
        final timeStr = _formatTime(receivedDate);

        if (daysUntil == 0) {
          // TODAY — pickup day
          alerts.add(AppNotification(
            key: 'preorder_today_${po['id']}',
            title: '📦 Pre-Order Ready Today',
            message: '$poNum for $customer is due TODAY at $timeStr. Please prepare!',
            type: NotificationType.preOrderToday,
            createdAt: today,
            isRead: false,
          ));
        } else if (daysUntil == 1) {
          // Tomorrow
          alerts.add(AppNotification(
            key: 'preorder_1day_${po['id']}',
            title: '🗓️ Pre-Order Tomorrow',
            message: '$poNum for $customer is due TOMORROW at $timeStr.',
            type: NotificationType.preOrderSoon,
            createdAt: today.subtract(const Duration(hours: 1)),
            isRead: false,
          ));
        } else if (daysUntil == 2) {
          // In 2 days
          alerts.add(AppNotification(
            key: 'preorder_2day_${po['id']}',
            title: '📅 Pre-Order in 2 Days',
            message: '$poNum for $customer is due in 2 days at $timeStr.',
            type: NotificationType.preOrderUpcoming,
            createdAt: today.subtract(const Duration(hours: 2)),
            isRead: false,
          ));
        }
      }
    } catch (_) {}
    return alerts;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $period';
  }

  // ─── Realtime Event Handler ───────────────────────────────────────────────

  void onRealtimeEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';

    switch (type) {
      case 'new_notification':
        // Server pushed a notification (e.g. pre-order 30 min alert from server)
        final data = event['data'] as Map<String, dynamic>?;
        if (data != null) {
          final n = AppNotification(
            key: 'server_ws_${DateTime.now().millisecondsSinceEpoch}',
            title: data['title']?.toString() ?? 'Notification',
            message: data['message']?.toString() ?? '',
            type: _typeFromString(data['type']?.toString()),
            createdAt: DateTime.now(),
            isRead: false,
          );
          _notifications.insert(0, n);
          _unreadCount++;
          _triggerSystemPush(n);
          notifyListeners();
        }
        // Also refresh everything after a short delay
        _scheduleFullRefresh();
        break;

      case 'stock_updated':
      case 'ingredient_stock_updated':
        // Stock changed — recompute stock alerts with debounce
        _stockDebounce?.cancel();
        _stockDebounce = Timer(const Duration(seconds: 3), () async {
          final fresh = await _buildStockAlerts();
          _mergeAlerts(fresh);
          notifyListeners();
        });
        break;

      case 'pre_order_created':
      case 'pre_order_updated':
      case 'pre_order_deleted':
        _preOrderDebounce?.cancel();
        _preOrderDebounce = Timer(const Duration(seconds: 2), () async {
          final fresh = await _buildPreOrderAlerts();
          _mergeAlerts(fresh, replacePrefix: 'preorder_');
          notifyListeners();
        });
        break;

      case 'database_synchronized':
      case 'ws_reconnected':
        _scheduleFullRefresh();
        break;
    }
  }

  void _scheduleFullRefresh() {
    _stockDebounce?.cancel();
    _stockDebounce = Timer(const Duration(seconds: 4), () => _loadAll(silent: true));
  }

  void _mergeAlerts(List<AppNotification> fresh, {String? replacePrefix}) {
    if (replacePrefix != null) {
      _notifications.removeWhere((n) => n.key.startsWith(replacePrefix));
    }
    final existing = {for (final n in _notifications) n.key: n};
    for (final n in fresh) {
      final isAlreadyRead = _readKeys.contains(n.key) || n.isRead;
      final updated = isAlreadyRead ? n.copyWith(isRead: true) : n;
      existing.putIfAbsent(n.key, () => updated);
      if (!updated.isRead) {
        _triggerSystemPush(updated);
      }
    }
    final merged = existing.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    _notifications = merged;
    _recalcUnread();
  }

  void _triggerSystemPush(AppNotification notification) {
    if (notification.isRead ||
        _readKeys.contains(notification.key) ||
        _notifiedSystemKeys.contains(notification.key)) {
      return;
    }
    _notifiedSystemKeys.add(notification.key);

    final isUrgent = notification.type == NotificationType.stockCritical ||
        notification.type == NotificationType.preOrderToday;

    LocalNotificationService.instance.showSystemNotification(
      id: notification.key.hashCode,
      title: notification.title,
      body: notification.message,
      isUrgent: isUrgent,
    );
  }

  NotificationType _typeFromString(String? raw) {
    switch (raw) {
      case 'pre_order_alert':
        return NotificationType.preOrderToday;
      case 'low_stock':
        return NotificationType.stockLow;
      default:
        return NotificationType.general;
    }
  }

  // ─── Read Handling ────────────────────────────────────────────────────────

  void markRead(String key) {
    final idx = _notifications.indexWhere((n) => n.key == key);
    if (idx != -1) {
      _notifications[idx] = _notifications[idx].copyWith(isRead: true);
      _readKeys.add(key);
      _saveReadKeys();
      _recalcUnread();
      notifyListeners();
      // If it's a server notification, tell the API
      final serverId = _notifications[idx].serverId;
      if (serverId != null) {
        ApiService.instance.markNotificationRead(serverId);
      }
    }
  }

  void markAllRead() {
    _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
    for (final n in _notifications) {
      _readKeys.add(n.key);
    }
    _saveReadKeys();
    _unreadCount = 0;
    notifyListeners();
    ApiService.instance.markAllNotificationsRead();
  }

  void _recalcUnread() {
    _unreadCount = _notifications.where((n) => !n.isRead).length;
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stockDebounce?.cancel();
    _preOrderDebounce?.cancel();
    _periodicCheck?.cancel();
    super.dispose();
  }
}

// ─── Data Models ─────────────────────────────────────────────────────────────

enum NotificationType {
  stockLow,
  stockCritical,
  preOrderToday,
  preOrderSoon,
  preOrderUpcoming,
  general,
}

class AppNotification {
  final String key;
  final String title;
  final String message;
  final NotificationType type;
  final DateTime createdAt;
  final bool isRead;
  final int? serverId; // non-null for server-sourced notifications

  const AppNotification({
    required this.key,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    required this.isRead,
    this.serverId,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        key: key,
        title: title,
        message: message,
        type: type,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        serverId: serverId,
      );

  factory AppNotification.fromServerJson(Map<String, dynamic> json) {
    DateTime createdAt;
    try {
      createdAt = DateTime.parse(json['created_at'].toString());
    } catch (_) {
      createdAt = DateTime.now();
    }
    final rawType = json['type']?.toString() ?? 'general';
    NotificationType type = NotificationType.general;
    if (rawType == 'pre_order_alert') type = NotificationType.preOrderToday;
    if (rawType == 'low_stock') type = NotificationType.stockLow;

    return AppNotification(
      key: 'server_${json['id']}',
      title: json['title']?.toString() ?? 'Notification',
      message: json['message']?.toString() ?? '',
      type: type,
      createdAt: createdAt,
      isRead: json['is_read'] == true || json['is_read'] == 1,
      serverId: json['id'] as int?,
    );
  }
}
