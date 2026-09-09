import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api_service.dart';

class DashboardController extends ChangeNotifier {
  Map<String, dynamic>? _reportData;
  bool _isLoading = false;
  String _selectedBranch = 'Mirpur-1 (Main)';
  String _selectedLanguage = 'English';

  DashboardController() {
    _loadSavedLanguage();
  }

  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLang = prefs.getString('app_language');
      if (savedLang != null && (savedLang == 'English' || savedLang == 'Sinhala')) {
        _selectedLanguage = savedLang;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading saved language: $e');
    }
  }

  static DateTimeRange _defaultTodayRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return DateTimeRange(start: today, end: today);
  }

  // Date ranges for individual panels
  DateTimeRange _salesDateRange = _defaultTodayRange();
  DateTimeRange _ordersDateRange = _defaultTodayRange();
  DateTimeRange _customerDateRange = _defaultTodayRange();
  DateTimeRange _statsDateRange = _defaultTodayRange();

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

  void setLanguage(String lang) async {
    if (_selectedLanguage != lang) {
      _selectedLanguage = lang;
      notifyListeners();
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_language', lang);
      } catch (e) {
        debugPrint('Error saving language preference: $e');
      }
    }
  }

  void setDateRange(DateTimeRange range) {
    _salesDateRange = range;
    _ordersDateRange = range;
    _customerDateRange = range;
    _statsDateRange = range;
    notifyListeners();
    loadDashboardData(range: range);
  }

  void setSalesDateRange(DateTimeRange range) => setDateRange(range);
  void setOrdersDateRange(DateTimeRange range) => setDateRange(range);
  void setCustomerDateRange(DateTimeRange range) => setDateRange(range);
  void setStatsDateRange(DateTimeRange range) => setDateRange(range);

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
