import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ApiService {
  static final ApiService instance = ApiService._internal();
  ApiService._internal();

  // Base URL — defaults to localhost/LAN IP, configurable
  String _baseUrl = 'http://192.168.1.100:3000';
  String? _token;

  String get baseUrl => _baseUrl;
  String? get token => _token;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('api_base_url') ?? 'http://192.168.1.100:3000';
    _token = prefs.getString('auth_token');
  }

  Future<void> setBaseUrl(String url) async {
    var formatted = url.trim().replaceAll(RegExp(r'/*$'), '');
    if (formatted.isNotEmpty && !formatted.startsWith('http://') && !formatted.startsWith('https://')) {
      formatted = 'http://$formatted';
    }
    _baseUrl = formatted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', _baseUrl);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    if (token == null) {
      await prefs.remove('auth_token');
    } else {
      await prefs.setString('auth_token', token);
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  // Login staff user
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token']?.toString();
        await setToken(token);
        return data;
      } else {
        final err = jsonDecode(response.body);
        throw Exception(err['error'] ?? 'Invalid username or password');
      }
    } catch (e) {
      if (e.toString().contains('TimeoutException') || e.toString().contains('SocketException')) {
        throw Exception('Cannot connect to server at $_baseUrl. Check Wi-Fi or Server IP.');
      }
      rethrow;
    }
  }

  // GET Staff Shift Status
  Future<Map<String, dynamic>> getShiftStatus() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/staff/shift-status'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to load shift status');
  }

  // POST Clock In
  Future<Map<String, dynamic>> clockIn() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/staff/clock-in'),
      headers: _headers,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Clock in failed');
  }

  // POST Clock Out
  Future<Map<String, dynamic>> clockOut() async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/staff/clock-out'),
      headers: _headers,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return data;
    }
    throw Exception(data['error'] ?? 'Clock out failed');
  }

  // GET My Orders / Prepared Items (Role Aware)
  Future<List<Map<String, dynamic>>> getMyActivity(String role, int userId) async {
    if (role == 'kitchen') {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/users/$userId/prepared-items'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } else {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/orders/today'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data);
        return list.where((o) => o['cashier_id'] == userId || o['steward_name']?.toString().toLowerCase() == role.toLowerCase()).toList();
      }
      return [];
    }
  }

  Future<Map<String, dynamic>> getMyAttendanceReport(int userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/staff/attendance/summary?user_id=$userId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      if (data.isNotEmpty) return Map<String, dynamic>.from(data.first);
    }
    throw Exception('Failed to load attendance report');
  }

  Future<Map<String, dynamic>> getMySalaryBreakdown(int userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/staff/payroll/calculate?user_id=$userId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Failed to calculate salary');
  }

  Future<List<Map<String, dynamic>>> getMyAdvances(int userId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/api/staff/advances?user_id=$userId'),
      headers: _headers,
    );
    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return List<Map<String, dynamic>>.from(data);
    }
    return [];
  }
}
