import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class AuthProvider extends ChangeNotifier {
  StaffUserModel? _user;
  bool _isLoading = false;
  String? _error;

  StaffUserModel? get user => _user;
  bool get isAuthenticated => _user != null && ApiService.instance.token != null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> init() async {
    await ApiService.instance.init();
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString('saved_user');
    if (userJson != null && ApiService.instance.token != null) {
      try {
        _user = StaffUserModel.fromJson(jsonDecode(userJson));
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.login(username, password);
      final userMap = res['user'] as Map<String, dynamic>;
      _user = StaffUserModel.fromJson(userMap);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('saved_user', jsonEncode(userMap));

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _user = null;
    await ApiService.instance.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_user');
    notifyListeners();
  }
}
