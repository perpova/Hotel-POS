import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotel_pos/services/api_service.dart';
import 'package:hotel_pos/services/local_db.dart';

/// SyncService — Manages all bi-directional synchronisation between the
/// Flutter app's local SQLite database and the remote server MySQL database.
///
/// Responsibilities:
///   1. On login / network reconnect: pull all master data from server → local DB
///   2. On network reconnect: push all pending offline records → server
///   3. Periodic sync every 30 seconds while online
///   4. Daily purge of synced transactional records older than 2 days
///   5. NEVER deletes cached master data (products, categories, users, tables, shifts)
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  Timer? _periodicTimer;
  bool _isSyncing = false;

  static const String _lastPurgeKey = 'last_purge_date';

  // ----------------------------------------------------------------
  // INIT — called once from main.dart after api.init()
  // ----------------------------------------------------------------
  Future<void> init() async {
    // Initial master data pull (non-blocking — don't block app startup)
    _doInitialSync();

    // Start periodic 30-second sync timer
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _runPeriodicSync();
    });
  }

  void dispose() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  // ----------------------------------------------------------------
  // INITIAL SYNC — runs once on startup, non-blocking
  // ----------------------------------------------------------------
  Future<void> _doInitialSync() async {
    // Small delay to allow the app UI to render first
    await Future.delayed(const Duration(seconds: 2));
    await refreshMasterDataFromServer();
    await _runDailyPurgeIfNeeded();
  }

  // ----------------------------------------------------------------
  // PERIODIC SYNC — called every 30 seconds
  // ----------------------------------------------------------------
  Future<void> _runPeriodicSync() async {
    if (_isSyncing) return; // Prevent overlapping sync runs
    _isSyncing = true;
    try {
      final online = await APIService.instance.checkOnline();
      if (online) {
        // 1. Push any pending offline data to server
        await pushOfflineDataToServer();
        // 2. Pull latest master data from server
        await refreshMasterDataFromServer();
        // 3. Daily purge if needed
        await _runDailyPurgeIfNeeded();
      }
    } catch (e) {
      debugPrint('[SyncService] Periodic sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ----------------------------------------------------------------
  // ON NETWORK RECONNECT — call this when connectivity is restored
  // ----------------------------------------------------------------
  Future<void> onNetworkReconnected() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      debugPrint('[SyncService] Network reconnected — starting sync');
      await pushOfflineDataToServer();
      await refreshMasterDataFromServer();
    } catch (e) {
      debugPrint('[SyncService] Reconnect sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  // ----------------------------------------------------------------
  // REFRESH MASTER DATA: Server → Local DB
  // ----------------------------------------------------------------
  /// Pulls the full master data snapshot from the server and writes it into
  /// the local SQLite cache tables. Safe to call at any time — server always wins.
  Future<bool> refreshMasterDataFromServer() async {
    try {
      if (!APIService.instance.isAuthenticated) return false;
      final success = await APIService.instance.getMasterData();
      if (success) {
        debugPrint('[SyncService] Master data refreshed from server ✓');
      }
      return success;
    } catch (e) {
      debugPrint('[SyncService] refreshMasterDataFromServer error: $e');
      return false;
    }
  }

  // ----------------------------------------------------------------
  // PUSH OFFLINE DATA: Local DB → Server
  // ----------------------------------------------------------------
  /// Finds all records with sync_status=pending in local DB and POSTs them
  /// to /api/sync. On success, marks them as synced and schedules a purge.
  Future<Map<String, dynamic>?> pushOfflineDataToServer() async {
    try {
      if (!APIService.instance.isAuthenticated) return null;
      final result = await APIService.instance.syncOfflineData();
      if (result != null) {
        debugPrint('[SyncService] Offline data pushed to server ✓ → ${result['counts']}');
      }
      return result;
    } catch (e) {
      debugPrint('[SyncService] pushOfflineDataToServer error: $e');
      return null;
    }
  }

  // ----------------------------------------------------------------
  // DAILY PURGE — removes synced transactional data older than 2 days
  // ----------------------------------------------------------------
  /// Runs at most once per day. Deletes synced offline_orders, offline_shifts,
  /// offline_expenses, offline_stock_logs, offline_audit_logs older than 2 days.
  /// NEVER touches cached_products, cached_categories, cached_users,
  /// cached_tables, or cached_shifts.
  Future<void> _runDailyPurgeIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastPurge = prefs.getString(_lastPurgeKey);
      final today = DateTime.now().toIso8601String().substring(0, 10); // 'YYYY-MM-DD'

      if (lastPurge == today) return; // Already ran today

      await LocalDB.instance.purgeSyncedDataOlderThan2Days();
      await prefs.setString(_lastPurgeKey, today);
      debugPrint('[SyncService] Daily purge completed for $today');
    } catch (e) {
      debugPrint('[SyncService] Daily purge error: $e');
    }
  }

  // ----------------------------------------------------------------
  // PUBLIC FORCE SYNC — call from UI (e.g. pull-to-refresh)
  // ----------------------------------------------------------------
  Future<void> forceSync() async {
    await pushOfflineDataToServer();
    await refreshMasterDataFromServer();
  }
}
