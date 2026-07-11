import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../api_service.dart';

class DashboardController extends ChangeNotifier {
  Map<String, dynamic>? _reportData;
  bool _isLoading = false;
  String _selectedBranch = 'Mirpur-1 (Main)';
  String _selectedLanguage = 'English';

  // Date ranges for individual panels
  DateTimeRange _salesDateRange = DateTimeRange(
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
  );

  DateTimeRange _ordersDateRange = DateTimeRange(
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
  );

  DateTimeRange _customerDateRange = DateTimeRange(
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
  );

  DateTimeRange _statsDateRange = DateTimeRange(
    start: DateTime(2026, 7, 11),
    end: DateTime(2026, 7, 11),
  );

  // Getters
  Map<String, dynamic>? get reportData => _reportData;
  bool get isLoading => _isLoading;
  String get selectedBranch => _selectedBranch;
  String get selectedLanguage => _selectedLanguage;
  DateTimeRange get salesDateRange => _salesDateRange;
  DateTimeRange get ordersDateRange => _ordersDateRange;
  DateTimeRange get customerDateRange => _customerDateRange;
  DateTimeRange get statsDateRange => _statsDateRange;

  // Setters & Actions
  void setBranch(String branch) {
    if (_selectedBranch != branch) {
      _selectedBranch = branch;
      notifyListeners();
    }
  }

  void setLanguage(String lang) {
    if (_selectedLanguage != lang) {
      _selectedLanguage = lang;
      notifyListeners();
    }
  }

  void setSalesDateRange(DateTimeRange range) {
    _salesDateRange = range;
    notifyListeners();
    loadDashboardData(range: range);
  }

  void setOrdersDateRange(DateTimeRange range) {
    _ordersDateRange = range;
    notifyListeners();
    loadDashboardData(range: range);
  }

  void setCustomerDateRange(DateTimeRange range) {
    _customerDateRange = range;
    notifyListeners();
    loadDashboardData(range: range);
  }

  void setStatsDateRange(DateTimeRange range) {
    _statsDateRange = range;
    notifyListeners();
    loadDashboardData(range: range);
  }

  Future<void> loadDashboardData({DateTimeRange? range}) async {
    _isLoading = true;
    notifyListeners();
    try {
      final startStr = DateFormat('yyyy-MM-dd').format(range?.start ?? _salesDateRange.start);
      final endStr = DateFormat('yyyy-MM-dd').format(range?.end ?? _salesDateRange.end);
      final data = await APIService.instance.getDashboardReport(startDate: startStr, endDate: endStr);
      _reportData = data;
    } catch (e) {
      debugPrint('Error loading dashboard stats in DashboardController: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
