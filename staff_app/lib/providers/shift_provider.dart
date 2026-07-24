import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../models/models.dart';

class ShiftProvider extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  ShiftLogModel? _activeShift;
  List<ShiftLogModel> _history = [];
  Timer? _timer;
  int _liveSeconds = 0;

  bool get isLoading => _isLoading;
  String? get error => _error;
  ShiftLogModel? get activeShift => _activeShift;
  bool get isClockedIn => _activeShift != null;
  List<ShiftLogModel> get history => _history;
  int get liveSeconds => _liveSeconds;

  String get liveDurationFormatted {
    final sec = _liveSeconds < 0 ? 0 : _liveSeconds;
    final hrs = sec ~/ 3600;
    final mins = (sec % 3600) ~/ 60;
    final secs = sec % 60;
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.getShiftStatus();
      if (res['active_shift'] != null) {
        _activeShift = ShiftLogModel.fromJson(res['active_shift']);
        _startTimer();
      } else {
        _activeShift = null;
        _stopTimer();
      }

      if (res['history'] is List) {
        _history = (res['history'] as List)
            .map((item) => ShiftLogModel.fromJson(item))
            .toList();
      }

      _syncHomeWidget();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (_activeShift != null) {
      final diff = DateTime.now().difference(_activeShift!.clockIn).inSeconds;
      _liveSeconds = diff < 0 ? 0 : diff;
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_activeShift != null) {
          final d = DateTime.now().difference(_activeShift!.clockIn).inSeconds;
          _liveSeconds = d < 0 ? 0 : d;
          notifyListeners();
        }
      });
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _liveSeconds = 0;
  }

  Future<bool> clockIn() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.instance.clockIn();
      if (res['shift'] != null) {
        _activeShift = ShiftLogModel.fromJson(res['shift']);
        _startTimer();
      }
      await load();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> clockOut() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await ApiService.instance.clockOut();
      _activeShift = null;
      _stopTimer();
      await load();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  // Sync Shift Status to Android Home Screen Widget
  Future<void> _syncHomeWidget() async {
    try {
      final isSw = isClockedIn;
      final statusStr = isSw ? 'CLOCKED IN' : 'CLOCKED OUT';
      final timeStr = isSw
          ? 'Since ${DateFormat('hh:mm a').format(_activeShift!.clockIn)}'
          : 'Ready for shift';
      final btnStr = isSw ? 'CLOCK OUT' : 'CLOCK IN';

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('widget_status', statusStr);
      await prefs.setString('widget_time', timeStr);
      await prefs.setString('widget_button', btnStr);
      await prefs.setBool('widget_is_in', isSw);

      await HomeWidget.saveWidgetData<String>('widget_status', statusStr);
      await HomeWidget.saveWidgetData<String>('widget_time', timeStr);
      await HomeWidget.saveWidgetData<String>('widget_button', btnStr);
      await HomeWidget.saveWidgetData<bool>('widget_is_in', isSw);
      await HomeWidget.saveWidgetData<String>('api_base_url', ApiService.instance.baseUrl);
      if (ApiService.instance.token != null) {
        await HomeWidget.saveWidgetData<String>('auth_token', ApiService.instance.token!);
      }

      await HomeWidget.updateWidget(
        name: 'StaffShiftWidgetProvider',
        androidName: 'StaffShiftWidgetProvider',
      );
    } catch (e) {
      debugPrint('Error updating home widget: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
