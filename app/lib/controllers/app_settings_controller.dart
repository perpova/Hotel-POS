import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hotel_pos/theme/theme.dart';
import 'package:hotel_pos/services/api_service.dart';

/// Holds company-wide settings that affect the entire app UI
/// (sidebar logo text, primary color, logo image, branches list).
class AppSettingsController extends ChangeNotifier {
  // ── Company ────────────────────────────────────────────────────────────────
  String _companyName = 'FoodKing';
  String _companyEmail = '';
  String _companyPhone = '';
  String _companyWebsite = '';
  String _companyCity = '';
  String _companyState = '';
  String _companyCountryCode = '';
  String _companyZipCode = '';
  String _companyAddress = '';

  // ── Theme ──────────────────────────────────────────────────────────────────
  Color _primaryColor = const Color(0xFFFF1B6B);
  String? _logoBase64;       // sidebar / header logo
  String? _faviconBase64;    // favicon / near-icon logo
  String? _footerLogoBase64;
  bool _cartOnLeft = false;
  bool _extendQueueScreen = false;
  bool _extendPosScreen = false;

  // ── Queue Screen Background ────────────────────────────────────────────────
  String _queueBgType = 'none'; // 'none' | 'image' | 'video'
  String? _queueBgImageBase64;
  String? _queueBgVideoUrl;
  String _queueBgVideoSource = 'link'; // 'link' | 'file'
  String? _queueBgVideoPath;
  double _queueBgOpacity = 0.8;
  bool _isListeningToEvents = false;
  bool _isApplyingWsUpdate = false;

  // ── Branches ───────────────────────────────────────────────────────────────
  List<BranchItem> _branches = [];

  // ── Getters ────────────────────────────────────────────────────────────────
  String get companyName     => _companyName;
  String get companyEmail    => _companyEmail;
  String get companyPhone    => _companyPhone;
  String get companyWebsite  => _companyWebsite;
  String get companyCity     => _companyCity;
  String get companyState    => _companyState;
  String get companyCountryCode => _companyCountryCode;
  String get companyZipCode  => _companyZipCode;
  String get companyAddress  => _companyAddress;

  Color  get primaryColor    => _primaryColor;
  String? get logoBase64     => _logoBase64;
  String? get faviconBase64  => _faviconBase64;
  String? get footerLogoBase64 => _footerLogoBase64;
  bool get cartOnLeft        => _cartOnLeft;
  bool get extendQueueScreen => _extendQueueScreen;
  bool get extendPosScreen   => _extendPosScreen;

  String get queueBgType => _queueBgType;
  String? get queueBgImageBase64 => _queueBgImageBase64;
  String? get queueBgVideoUrl => _queueBgVideoUrl;
  String get queueBgVideoSource => _queueBgVideoSource;
  String? get queueBgVideoPath => _queueBgVideoPath;
  double get queueBgOpacity => _queueBgOpacity;

  List<BranchItem> get branches => List.unmodifiable(_branches);

  // ── Init / Persistence ─────────────────────────────────────────────────────
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _companyName     = prefs.getString('company_name')     ?? 'FoodKing';
    _companyEmail    = prefs.getString('company_email')    ?? '';
    _companyPhone    = prefs.getString('company_phone')    ?? '';
    _companyWebsite  = prefs.getString('company_website')  ?? '';
    _companyCity     = prefs.getString('company_city')     ?? '';
    _companyState    = prefs.getString('company_state')    ?? '';
    _companyCountryCode = prefs.getString('company_country') ?? '';
    _companyZipCode  = prefs.getString('company_zip')      ?? '';
    _companyAddress  = prefs.getString('company_address')  ?? '';

    final colorHex = prefs.getString('primary_color');
    if (colorHex != null) {
      _primaryColor = Color(int.parse(colorHex));
      AppTheme.dynamicPrimaryValue = _primaryColor.value;
    }

    _logoBase64       = prefs.getString('logo_base64');
    _faviconBase64    = prefs.getString('favicon_base64');
    _footerLogoBase64 = prefs.getString('footer_logo_base64');
    _cartOnLeft       = prefs.getBool('cart_on_left') ?? false;
    _extendQueueScreen = prefs.getBool('extend_queue_screen') ?? false;
    _extendPosScreen   = prefs.getBool('extend_pos_screen') ?? false;

    _queueBgType       = prefs.getString('queue_bg_type') ?? 'none';
    _queueBgImageBase64 = prefs.getString('queue_bg_image');
    _queueBgVideoUrl   = prefs.getString('queue_bg_video_url');
    _queueBgVideoSource = prefs.getString('queue_bg_video_source') ?? 'link';
    _queueBgVideoPath   = prefs.getString('queue_bg_video_path');
    _queueBgOpacity    = prefs.getDouble('queue_bg_opacity') ?? 0.8;

    final branchJson = prefs.getString('branches_json');
    if (branchJson != null) {
      final List decoded = jsonDecode(branchJson);
      _branches = decoded.map((e) => BranchItem.fromJson(e)).toList();
    } else {
      // default demo branches
      _branches = [
        BranchItem(id: 1, name: 'Main Branch', city: 'Colombo', state: 'Western', status: 'Active'),
      ];
    }

    if (!_isListeningToEvents) {
      _isListeningToEvents = true;
      APIService.instance.eventStream.listen((event) async {
        if (event['type'] == 'settings_updated' && event['settings'] != null) {
          _isApplyingWsUpdate = true;
          try {
            updateFromMap(event['settings']);
          } finally {
            _isApplyingWsUpdate = false;
          }
        }
      });
    }

    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('company_name',    _companyName);
    await prefs.setString('company_email',   _companyEmail);
    await prefs.setString('company_phone',   _companyPhone);
    await prefs.setString('company_website', _companyWebsite);
    await prefs.setString('company_city',    _companyCity);
    await prefs.setString('company_state',   _companyState);
    await prefs.setString('company_country', _companyCountryCode);
    await prefs.setString('company_zip',     _companyZipCode);
    await prefs.setString('company_address', _companyAddress);
    await prefs.setString('primary_color',   _primaryColor.value.toString());
    if (_logoBase64       != null) await prefs.setString('logo_base64',        _logoBase64!);
    if (_faviconBase64    != null) await prefs.setString('favicon_base64',     _faviconBase64!);
    if (_footerLogoBase64 != null) await prefs.setString('footer_logo_base64', _footerLogoBase64!);
    await prefs.setString('branches_json', jsonEncode(_branches.map((b) => b.toJson()).toList()));
  }

  // ── Company update ─────────────────────────────────────────────────────────
  Future<void> saveCompany({
    required String name,
    required String email,
    required String phone,
    required String website,
    required String city,
    required String state,
    required String countryCode,
    required String zipCode,
    required String address,
  }) async {
    _companyName     = name.trim().isEmpty ? 'FoodKing' : name.trim();
    _companyEmail    = email;
    _companyPhone    = phone;
    _companyWebsite  = website;
    _companyCity     = city;
    _companyState    = state;
    _companyCountryCode = countryCode;
    _companyZipCode  = zipCode;
    _companyAddress  = address;
    await _save();
    notifyListeners();
  }

  // ── Theme update ───────────────────────────────────────────────────────────
  Future<void> saveTheme({
    Color? primaryColor,
    String? logoBase64,
    String? faviconBase64,
    String? footerLogoBase64,
  }) async {
    if (primaryColor   != null) {
      _primaryColor      = primaryColor;
      AppTheme.dynamicPrimaryValue = primaryColor.value;
    }
    if (logoBase64     != null) _logoBase64         = logoBase64;
    if (faviconBase64  != null) _faviconBase64      = faviconBase64;
    if (footerLogoBase64 != null) _footerLogoBase64 = footerLogoBase64;
    await _save();
    notifyListeners();
  }

  // ── Queue Screen Background update ──────────────────────────────────────────
  Future<void> saveQueueBackground({
    required String type,
    String? imageBase64,
    String? videoUrl,
    String? videoSource,
    String? videoPath,
    double? opacity,
  }) async {
    _queueBgType = type;
    if (imageBase64 != null) _queueBgImageBase64 = imageBase64;
    if (videoUrl != null) _queueBgVideoUrl = videoUrl;
    if (videoSource != null) _queueBgVideoSource = videoSource;
    if (videoPath != null) _queueBgVideoPath = videoPath;
    if (opacity != null) _queueBgOpacity = opacity;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('queue_bg_type', _queueBgType);
    if (_queueBgImageBase64 != null) {
      await prefs.setString('queue_bg_image', _queueBgImageBase64!);
    }
    if (_queueBgVideoUrl != null) {
      await prefs.setString('queue_bg_video_url', _queueBgVideoUrl!);
    }
    await prefs.setString('queue_bg_video_source', _queueBgVideoSource);
    if (_queueBgVideoPath != null) {
      await prefs.setString('queue_bg_video_path', _queueBgVideoPath!);
    }
    await prefs.setDouble('queue_bg_opacity', _queueBgOpacity);
    notifyListeners();
  }

  // ── Branch CRUD ────────────────────────────────────────────────────────────
  Future<void> addBranch(BranchItem branch) async {
    final newId = _branches.isEmpty ? 1 : _branches.map((b) => b.id).reduce((a, b) => a > b ? a : b) + 1;
    _branches.add(branch.copyWith(id: newId));
    await _save();
    notifyListeners();
  }

  Future<void> updateBranch(BranchItem updated) async {
    final idx = _branches.indexWhere((b) => b.id == updated.id);
    if (idx != -1) {
      _branches[idx] = updated;
      await _save();
      notifyListeners();
    }
  }

  Future<void> deleteBranch(int id) async {
    _branches.removeWhere((b) => b.id == id);
    await _save();
    notifyListeners();
  }

  // ── Layout position toggle ──
  Future<void> toggleCartPosition() async {
    _cartOnLeft = !_cartOnLeft;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cart_on_left', _cartOnLeft);
    notifyListeners();
  }

  Future<void> toggleExtendQueueScreen() async {
    _extendQueueScreen = !_extendQueueScreen;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('extend_queue_screen', _extendQueueScreen);
    notifyListeners();
  }

  Future<void> toggleExtendPosScreen() async {
    _extendPosScreen = !_extendPosScreen;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('extend_pos_screen', _extendPosScreen);
    notifyListeners();
  }

  Map<String, dynamic> toMap() {
    return {
      'queueBgType': _queueBgType,
      'queueBgImageBase64': _queueBgImageBase64,
      'queueBgVideoUrl': _queueBgVideoUrl,
      'queueBgVideoSource': _queueBgVideoSource,
      'queueBgVideoPath': _queueBgVideoPath,
      'queueBgOpacity': _queueBgOpacity,
    };
  }

  void updateFromMap(Map<String, dynamic> map) async {
    bool changed = false;

    if (map.containsKey('queueBgType') && _queueBgType != map['queueBgType']) {
      _queueBgType = map['queueBgType'] ?? 'none';
      changed = true;
    }
    if (map.containsKey('queueBgImageBase64') && _queueBgImageBase64 != map['queueBgImageBase64']) {
      _queueBgImageBase64 = map['queueBgImageBase64'];
      changed = true;
    }
    if (map.containsKey('queueBgVideoUrl') && _queueBgVideoUrl != map['queueBgVideoUrl']) {
      _queueBgVideoUrl = map['queueBgVideoUrl'];
      changed = true;
    }
    if (map.containsKey('queueBgVideoSource') && _queueBgVideoSource != map['queueBgVideoSource']) {
      _queueBgVideoSource = map['queueBgVideoSource'] ?? 'link';
      changed = true;
    }
    if (map.containsKey('queueBgVideoPath') && _queueBgVideoPath != map['queueBgVideoPath']) {
      _queueBgVideoPath = map['queueBgVideoPath'];
      changed = true;
    }
    if (map.containsKey('queueBgOpacity')) {
      final double newOpacity = double.tryParse(map['queueBgOpacity'].toString()) ?? 0.8;
      if (_queueBgOpacity != newOpacity) {
        _queueBgOpacity = newOpacity;
        changed = true;
      }
    }

    if (!changed) return;

    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('queue_bg_type', _queueBgType);
      if (_queueBgImageBase64 != null) {
        await prefs.setString('queue_bg_image', _queueBgImageBase64!);
      }
      if (_queueBgVideoUrl != null) {
        await prefs.setString('queue_bg_video_url', _queueBgVideoUrl!);
      }
      await prefs.setString('queue_bg_video_source', _queueBgVideoSource);
      if (_queueBgVideoPath != null) {
        await prefs.setString('queue_bg_video_path', _queueBgVideoPath!);
      }
      await prefs.setDouble('queue_bg_opacity', _queueBgOpacity);
    } catch (_) {}
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (!_isApplyingWsUpdate) {
      try {
        APIService.instance.sendWebSocketMessage({
          'type': 'settings_updated',
          'settings': toMap(),
        });
      } catch (_) {}
    }
  }
}

// ── BranchItem model ──────────────────────────────────────────────────────────
class BranchItem {
  final int id;
  final String name;
  final String email;
  final String phone;
  final String city;
  final String state;
  final String zipCode;
  final String address;
  final String status; // 'Active' | 'Inactive'
  final double? latitude;
  final double? longitude;
  final String? imageBase64;

  const BranchItem({
    required this.id,
    required this.name,
    this.email = '',
    this.phone = '',
    required this.city,
    required this.state,
    this.zipCode = '',
    this.address = '',
    this.status = 'Active',
    this.latitude,
    this.longitude,
    this.imageBase64,
  });

  BranchItem copyWith({
    int? id,
    String? name,
    String? email,
    String? phone,
    String? city,
    String? state,
    String? zipCode,
    String? address,
    String? status,
    double? latitude,
    double? longitude,
    String? imageBase64,
  }) =>
      BranchItem(
        id:          id          ?? this.id,
        name:        name        ?? this.name,
        email:       email       ?? this.email,
        phone:       phone       ?? this.phone,
        city:        city        ?? this.city,
        state:       state       ?? this.state,
        zipCode:     zipCode     ?? this.zipCode,
        address:     address     ?? this.address,
        status:      status      ?? this.status,
        latitude:    latitude    ?? this.latitude,
        longitude:   longitude   ?? this.longitude,
        imageBase64: imageBase64 ?? this.imageBase64,
      );

  factory BranchItem.fromJson(Map<String, dynamic> j) => BranchItem(
        id:          j['id']          ?? 0,
        name:        j['name']        ?? '',
        email:       j['email']       ?? '',
        phone:       j['phone']       ?? '',
        city:        j['city']        ?? '',
        state:       j['state']       ?? '',
        zipCode:     j['zip_code']    ?? '',
        address:     j['address']     ?? '',
        status:      j['status']      ?? 'Active',
        latitude:    j['latitude'] != null ? double.tryParse(j['latitude'].toString()) : null,
        longitude:   j['longitude'] != null ? double.tryParse(j['longitude'].toString()) : null,
        imageBase64: j['image_base64'],
      );

  Map<String, dynamic> toJson() => {
        'id':           id,
        'name':         name,
        'email':        email,
        'phone':        phone,
        'city':         city,
        'state':        state,
        'zip_code':     zipCode,
        'address':      address,
        'status':       status,
        'latitude':     latitude,
        'longitude':    longitude,
        'image_base64': imageBase64,
      };
}
