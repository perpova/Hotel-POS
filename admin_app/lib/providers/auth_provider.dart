import 'package:flutter/foundation.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  bool get isAuthenticated => _isAuthenticated;
  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String get baseUrl => ApiService.instance.baseUrl;

  Future<void> init() async {
    await ApiService.instance.init();
    if (ApiService.instance.isAuthenticated) {
      _isAuthenticated = true;
      _currentUser = ApiService.instance.currentUser;
    }
    notifyListeners();
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await ApiService.instance.login(username, password);
      _isAuthenticated = true;
      _currentUser = ApiService.instance.currentUser;
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
    await ApiService.instance.logout();
    _isAuthenticated = false;
    _currentUser = null;
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    await ApiService.instance.setBaseUrl(url);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
