import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../pos_controller.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';

// ─────────────────────────────────────────────────────
// Custom TextInputFormatter to strip leading zeroes
// ─────────────────────────────────────────────────────
class _StripLeadingZeroFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > 1 && newValue.text.startsWith('0')) {
      final cleaned = newValue.text.replaceFirst(RegExp(r'^0+'), '');
      final text = cleaned.isEmpty ? '0' : cleaned;
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    return newValue;
  }
}

// ─────────────────────────────────────────────────────
// _SessionItem — data returned from backend per product
// ─────────────────────────────────────────────────────
class _SessionItem {
  final int productId;
  final String productName;
  final String? sinhalaName;
  final List<int> additions;
  final int totalAdded;
  final int soldQty;
  final int remaining;       // system: totalAdded - soldQty
  final String countString;  // e.g. "6+15+10"

  _SessionItem({
    required this.productId,
    required this.productName,
    this.sinhalaName,
    required this.additions,
    required this.totalAdded,
    required this.soldQty,
    required this.remaining,
    required this.countString,
  });

  factory _SessionItem.fromJson(Map<String, dynamic> j) {
    final additionsRaw = (j['additions'] as List?) ?? [];
    final additions = additionsRaw.map<int>((a) => int.tryParse(a['qty'].toString()) ?? 0).toList();
    return _SessionItem(
      productId: j['product_id'] ?? 0,
      productName: j['product_name'] ?? '',
      sinhalaName: j['sinhala_name'],
      additions: additions,
      totalAdded: int.tryParse(j['total_added'].toString()) ?? 0,
      soldQty: int.tryParse(j['sold_qty'].toString()) ?? 0,
      remaining: int.tryParse(j['remaining'].toString()) ?? 0,
      countString: j['count_string'] ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────
// _DisplayItem — merges a tracked product + optional session entry
// This drives each ROW in the table (all tracked items always visible)
// ─────────────────────────────────────────────────────
class _DisplayItem {
  final ProductModel product;
  final _SessionItem? sessionItem;

  _DisplayItem({required this.product, this.sessionItem});

  int get productId   => product.id;
  String get name     => product.name;
  String? get sinhala => product.sinhalaName;
  bool get hasEntries => sessionItem != null && sessionItem!.totalAdded > 0;
  int get totalAdded  => sessionItem?.totalAdded ?? 0;
  int get soldQty     => sessionItem?.soldQty ?? 0;
  int get sysRemaining => sessionItem?.remaining ?? 0;
  String get countString => hasEntries ? (sessionItem!.countString) : '—';
}

// ─────────────────────────────────────────────────────
// _SessionData — one user's session card
// ─────────────────────────────────────────────────────
class _SessionData {
  final int? sessionId;
  final String? userDisplayName;
  final String? userName;
  final String? userRole;
  final DateTime? loginAt;
  final DateTime? logoutAt;
  final bool isActive;
  final List<_SessionItem> items;
  final Map<int, int> snapshot; // manual remaining at close: productId → count

  _SessionData({
    this.sessionId,
    this.userDisplayName,
    this.userName,
    this.userRole,
    this.loginAt,
    this.logoutAt,
    this.isActive = true,
    required this.items,
    this.snapshot = const {},
  });
}

// ─────────────────────────────────────────────────────
// Main Widget
// ─────────────────────────────────────────────────────
class POSStockScreen extends StatefulWidget {
  const POSStockScreen({Key? key}) : super(key: key);

  @override
  State<POSStockScreen> createState() => _POSStockScreenState();
}

class _POSStockScreenState extends State<POSStockScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _wsSub;

  // ── Session state ──────────────────────────────────
  _SessionData? _currentSession;
  List<_SessionData> _allSessions = [];
  bool _sessionLoading = false;
  bool _allSessionsLoading = false;
  bool _isClosingSession = false;

  // ── Inline add state (per-product-id controllers) ──
  final Map<int, TextEditingController> _rowQtyControllers = {};
  int? _addingProductId;

  // ── Close-session dialog state ─────────────────────
  final Map<int, TextEditingController> _snapshotCtrls = {};
  final Map<int, FocusNode> _snapshotFocusNodes = {};

  // ── Admin logs (old adjustment system) ────────────
  List<dynamic> _logs = [];
  bool _logsLoading = false;
  int _entriesLimit = 25;
  String _datePreset = 'today';
  DateTime? _startDate;
  DateTime? _endDate;
  String _searchQuery = '';

  // ── Admin all-sessions filter ──────────────────────
  String _sessionsFilterDate = DateFormat('yyyy-MM-dd').format(DateTime.now());

  // ── Stock adjustment form (admin) ──────────────────
  ProductModel? _selectedStockProduct;
  final _stockChangeController = TextEditingController();
  final _stockReasonController = TextEditingController();
  String _stockType = 'purchase';

  // ─────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _initSession();
    if (_canViewAllSessions) {
      _loadAllSessions();
    }
    if (_canAdjustStock) {
      _loadLogs();
    }
    _wsSub = APIService.instance.eventStream.listen((event) {
      final type = event['type']?.toString() ?? '';
      if (type.startsWith('pos_stock_session') || type == 'database_synchronized') {
        _refreshSession(silent: true);
        if (_canViewAllSessions) _loadAllSessions(silent: true);
      }
      if (type == 'stock_updated' || type == 'product_updated') {
        if (_canAdjustStock) _loadLogs(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _tabController.dispose();
    _stockChangeController.dispose();
    _stockReasonController.dispose();
    for (final c in _rowQtyControllers.values) c.dispose();
    for (final c in _snapshotCtrls.values) c.dispose();
    for (final fn in _snapshotFocusNodes.values) fn.dispose();
    _snapshotFocusNodes.clear();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────
  String get _userRole => (APIService.instance.currentUser?.role ?? 'cashier').toLowerCase();
  bool get _isAdmin => _userRole == 'admin' || _userRole == 'owner';

  // Permission flags controlled directly by Role & Permissions system settings:
  bool get _canViewAllSessions => APIService.instance.isPosStockAllSessionsAllowed();
  bool get _canViewCalculatedDetails => APIService.instance.isPosStockCalculatedDetailsAllowed();
  bool get _canAdjustStock => APIService.instance.isPosStockAdjustmentAllowed();
  bool get _canAddStock => APIService.instance.canCreateInPage('POS Stock');


  int get _tabCount {
    int count = 1;
    if (_canViewAllSessions) count++;
    if (_canAdjustStock) count++;
    return count;
  }


  TextEditingController _rowCtrl(int productId) =>
      _rowQtyControllers.putIfAbsent(productId, () => TextEditingController(text: ''));


  /// Build merged list: ALL track_stock products + overlay session data
  List<_DisplayItem> _buildDisplayItems(POSController controller) {
    final sessionMap = <int, _SessionItem>{};
    if (_currentSession != null) {
      for (final item in _currentSession!.items) {
        sessionMap[item.productId] = item;
      }
    }
    return controller.products
        .where((p) => p.trackStock && p.status == 'active')
        .map((p) => _DisplayItem(product: p, sessionItem: sessionMap[p.id]))
        .toList();
  }

  // ─────────────────────────────────────────────────────
  // DATA LOADING
  // ─────────────────────────────────────────────────────
  Future<void> _initSession() async {
    setState(() => _sessionLoading = true);
    try {
      await APIService.instance.openStockSession();
      await _refreshSession();
    } catch (_) {
      try { await _refreshSession(); } catch (_) {}
    } finally {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  Future<void> _refreshSession({bool silent = false}) async {
    if (!silent && mounted) setState(() => _sessionLoading = true);
    try {
      final data = await APIService.instance.getCurrentStockSession();
      final sessionRaw = data['session'];
      final itemsRaw = (data['items'] as List?) ?? [];
      final items = itemsRaw.map((i) => _SessionItem.fromJson(Map<String, dynamic>.from(i))).toList();
      // Parse snapshot if present
      Map<int, int> snapshot = {};
      if (sessionRaw != null && sessionRaw['remaining_snapshot'] != null) {
        try {
          final raw = jsonDecode(sessionRaw['remaining_snapshot'].toString()) as Map;
          snapshot = raw.map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, int.tryParse(v.toString()) ?? 0));
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _currentSession = _SessionData(
            sessionId: sessionRaw?['id'],
            userDisplayName: APIService.instance.currentUser?.name,
            loginAt: sessionRaw != null ? DateTime.tryParse(sessionRaw['login_at']?.toString() ?? '') : null,
            logoutAt: sessionRaw?['logout_at'] != null ? DateTime.tryParse(sessionRaw['logout_at'].toString()) : null,
            isActive: sessionRaw?['status'] == 'active',
            items: items,
            snapshot: snapshot,
          );
          _sessionLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _sessionLoading = false);
    }
  }

  Future<void> _loadAllSessions({bool silent = false}) async {
    if (!silent) setState(() => _allSessionsLoading = true);
    try {
      final raw = await APIService.instance.getAllStockSessions(date: _sessionsFilterDate);
      final sessions = raw.map((s) {
        final itemsRaw = (s['items'] as List?) ?? [];
        final items = itemsRaw.map((i) => _SessionItem.fromJson(Map<String, dynamic>.from(i))).toList();
        Map<int, int> snapshot = {};
        if (s['remaining_snapshot'] != null) {
          try {
            final parsed = jsonDecode(s['remaining_snapshot'].toString()) as Map;
            snapshot = parsed.map((k, v) => MapEntry(int.tryParse(k.toString()) ?? 0, int.tryParse(v.toString()) ?? 0));
          } catch (_) {}
        }
        return _SessionData(
          sessionId: s['id'],
          userDisplayName: s['user_name'] ?? s['username'],
          userName: s['username'],
          userRole: s['user_role'],
          loginAt: DateTime.tryParse(s['login_at']?.toString() ?? ''),
          logoutAt: s['logout_at'] != null ? DateTime.tryParse(s['logout_at'].toString()) : null,
          isActive: s['status'] == 'active',
          items: items,
          snapshot: snapshot,
        );
      }).toList();
      if (mounted) setState(() { _allSessions = sessions; _allSessionsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _allSessionsLoading = false);
    }
  }

  Future<void> _loadLogs({bool silent = false}) async {
    if (!silent) setState(() => _logsLoading = true);
    try {
      final data = await APIService.instance.getProductStockLogs();
      if (mounted) setState(() { _logs = data; _logsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _logsLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────

  /// Inline add from a table row — no dropdown needed
  Future<void> _handleInlineAdd(int productId, String productName) async {
    final ctrl = _rowCtrl(productId);
    final qty = int.tryParse(ctrl.text.trim()) ?? 0;
    if (qty <= 0) {
      _showSnack('Enter a quantity > 0', isError: true);
      return;
    }
    setState(() => _addingProductId = productId);
    try {
      await APIService.instance.addToStockSession(productId, qty);
      ctrl.text = '1';
      await _refreshSession();
      _showSnack('+$qty "$productName" added to your session!');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _addingProductId = null);
    }
  }

  /// Show the Close Session dialog — user enters physical count per item
  Future<void> _showCloseSessionDialog(List<_DisplayItem> displayItems) async {
    if (_currentSession?.sessionId == null) {
      _showSnack('No active session to close.', isError: true);
      return;
    }
    // Initialize snapshot controllers & focus nodes with 0 as default
    for (final c in _snapshotCtrls.values) c.dispose();
    _snapshotCtrls.clear();
    for (final fn in _snapshotFocusNodes.values) fn.dispose();
    _snapshotFocusNodes.clear();

    for (final item in displayItems) {
      final fn = FocusNode();
      final ctrl = TextEditingController(text: '');

      // Auto-select text on focus if non-empty
      fn.addListener(() {
        if (fn.hasFocus && ctrl.text.isNotEmpty) {
          ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
        }
      });

      _snapshotCtrls[item.productId] = ctrl;
      _snapshotFocusNodes[item.productId] = fn;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _buildCloseSessionDialog(ctx, displayItems),
    );

    if (confirmed == true) {
      await _submitSnapshot();
    }
  }

  Future<void> _submitSnapshot() async {
    final sessionId = _currentSession?.sessionId;
    if (sessionId == null) return;
    setState(() => _isClosingSession = true);
    try {
      final manualRemaining = <int, int>{};
      for (final entry in _snapshotCtrls.entries) {
        manualRemaining[entry.key] = int.tryParse(entry.value.text) ?? 0;
      }
      await APIService.instance.saveSessionSnapshot(sessionId, manualRemaining);
      await _refreshSession();
      if (_isAdmin) await _loadAllSessions(silent: true);
      _showSnack('Session closed. Physical counts recorded.');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isClosingSession = false);
    }
  }

  Future<void> _handleAdjustStock(POSController controller) async {
    if (_selectedStockProduct == null) return;
    final qty = int.tryParse(_stockChangeController.text) ?? 0;
    final reason = _stockReasonController.text.trim();
    if (qty == 0 || reason.isEmpty) {
      _showSnack('Fill in qty and reason.', isError: true);
      return;
    }
    try {
      await APIService.instance.adjustStock(_selectedStockProduct!.id, qty, _stockType, reason);
      _stockChangeController.clear();
      _stockReasonController.clear();
      setState(() => _selectedStockProduct = null);
      await controller.reloadEnvironment();
      _loadLogs();
      _showSnack('Stock adjustment saved.');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(fontSize: 13)),
      backgroundColor: isError ? AppTheme.danger : const Color(0xFF10B981),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      margin: const EdgeInsets.all(16),
    ));
  }

  bool _isWithinDateRange(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return true;
    final local = dt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayEnd = today.add(const Duration(hours: 23, minutes: 59, seconds: 59));
    switch (_datePreset) {
      case 'today':   return local.isAfter(today) && local.isBefore(todayEnd);
      case 'weekly':  return local.isAfter(today.subtract(const Duration(days: 7)));
      case 'monthly': return local.isAfter(today.subtract(const Duration(days: 30)));
      case 'yearly':  return local.isAfter(today.subtract(const Duration(days: 365)));
      case 'custom':
        if (_startDate == null || _endDate == null) return true;
        final end = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        return local.isAfter(_startDate!) && local.isBefore(end);
      default: return true;
    }
  }

  // ─────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final views = <Widget>[
      _buildMySessionTab(controller),
      if (_canViewAllSessions) _buildAllSessionsTab(controller),
      if (_canAdjustStock) _buildStockAdjustTab(controller),
    ];
    final hasTabs = views.length > 1;

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (hasTabs) _buildTabBar(),
          Expanded(
            child: hasTabs
                ? TabBarView(
                    controller: _tabController,
                    children: views,
                  )
                : _buildMySessionTab(controller),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('POS Stock Register',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            const SizedBox(height: 2),
            Row(children: [
              Text('Dashboard', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
              Icon(Icons.chevron_right, size: 13, color: AppTheme.textLightSecondary),
              Text('POS Stock', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primary, fontWeight: FontWeight.w600)),
            ]),
          ]),
          Row(children: [
            _buildLiveChip(),
            const SizedBox(width: 12),
            if (_canViewCalculatedDetails) _buildExportButton(),
          ]),
        ],
      ),
    );
  }

  Widget _buildLiveChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(width: 7, height: 7, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(DateFormat('dd MMM, hh:mm a').format(DateTime.now()),
            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
      ]),
    );
  }

  Widget _buildExportButton() {
    return PopupMenuButton<String>(
      onSelected: (v) { if (v == 'PDF') _exportToPDF(); else _exportToCSV(); },
      offset: const Offset(0, 42),
      itemBuilder: (_) => [
        PopupMenuItem(value: 'PDF', child: Row(children: [const Icon(Icons.picture_as_pdf_outlined, size: 16), const SizedBox(width: 8), Text('Export PDF', style: GoogleFonts.inter(fontSize: 13))])),
        PopupMenuItem(value: 'CSV', child: Row(children: [const Icon(Icons.table_view_outlined, size: 16), const SizedBox(width: 8), Text('Export CSV', style: GoogleFonts.inter(fontSize: 13))])),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(border: Border.all(color: AppTheme.primary), borderRadius: BorderRadius.circular(8), color: AppTheme.cardLight),
        child: Row(children: [
          Icon(Icons.download_outlined, size: 14, color: AppTheme.primary),
          const SizedBox(width: 6),
          Text('Export', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
          Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.primary),
        ]),
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = <Tab>[
      const Tab(text: 'My Session'),
      if (_canViewAllSessions) const Tab(text: 'All Sessions'),
      if (_canAdjustStock) const Tab(text: 'Stock Adjustment'),
    ];
    if (tabs.length <= 1) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      decoration: BoxDecoration(color: AppTheme.cardLight, border: Border.all(color: AppTheme.borderLight), borderRadius: BorderRadius.circular(10)),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(8)),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: AppTheme.textLightSecondary,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 12),
        padding: const EdgeInsets.all(4),
        tabs: tabs,
      ),
    );
  }


  // ─────────────────────────────────────────────────────
  // TAB 1 — MY SESSION (visible to ALL users)
  // Shows ALL track_stock items in table with inline add per row
  // ─────────────────────────────────────────────────────
  Widget _buildMySessionTab(POSController controller) {
    final displayItems = _buildDisplayItems(controller);
    final isActive = _currentSession?.isActive ?? false;
    final loginAt = _currentSession?.loginAt;
    final sessionId = _currentSession?.sessionId;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Session info bar ──────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.cardLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderLight),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.menu_book_rounded, color: AppTheme.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  isActive ? 'Session Active' : (sessionId != null ? 'Session Closed' : 'No Session'),
                  style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                if (loginAt != null)
                  Text(
                    'Started: ${DateFormat('dd MMM yyyy, hh:mm a').format(loginAt.toLocal())}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                  ),
              ]),
              const Spacer(),
              // Hint chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Text('Enter qty in each row → click +Add',
                    style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: const Color(0xFF10B981))),
              ),
              const SizedBox(width: 14),
              // Close session button
              if (isActive)
                ElevatedButton.icon(
                  onPressed: _isClosingSession ? null : () => _showCloseSessionDialog(displayItems),
                  icon: _isClosingSession
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.logout_rounded, size: 16),
                  label: Text(_isClosingSession ? 'Closing...' : 'Close & Record Remaining',
                      style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    elevation: 0,
                  ),
                ),
              if (!isActive && sessionId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: AppTheme.bgLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.borderLight)),
                  child: Text('Session closed. Physical counts recorded.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                ),
            ]),
          ),
          const SizedBox(height: 20),

          // ── Main register table ────────────────────────
          _buildRegisterTable(
            displayItems: displayItems,
            isActive: isActive,
            loginAt: loginAt,
            logoutAt: _currentSession?.logoutAt,
            sessionSnapshot: _currentSession?.snapshot ?? {},
            title: 'My Stock Register — ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────
  // THE MAIN REGISTER TABLE
  // Shows ALL tracked products; each row has inline add
  // ─────────────────────────────────────────────────────
  Widget _buildRegisterTable({
    required List<_DisplayItem> displayItems,
    required bool isActive,
    DateTime? loginAt,
    DateTime? logoutAt,
    Map<int, int> sessionSnapshot = const {},
    String title = 'Stock Register',
  }) {
    final hasSnapshot = sessionSnapshot.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.borderLight),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Table title bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primary,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(13), topRight: Radius.circular(13)),
            ),
            child: Row(children: [
              const Icon(Icons.table_rows_outlined, color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white))),
              if (loginAt != null) ...[
                Icon(Icons.login, size: 12, color: Colors.white70), const SizedBox(width: 4),
                Text(DateFormat('hh:mm a').format(loginAt.toLocal()), style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
              ],
              if (logoutAt != null) ...[
                const SizedBox(width: 10),
                Icon(Icons.logout, size: 12, color: Colors.white70), const SizedBox(width: 4),
                Text(DateFormat('hh:mm a').format(logoutAt.toLocal()), style: GoogleFonts.inter(fontSize: 10, color: Colors.white70)),
              ],
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: isActive ? const Color(0xFF10B981) : Colors.white24, borderRadius: BorderRadius.circular(20)),
                child: Text(isActive ? 'ACTIVE' : 'CLOSED', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ]),
          ),

          // ── Column headers ──
          Container(
            color: AppTheme.bgLight,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            child: Row(children: [
              _th('#', flex: 1, center: true),
              _th('ITEM NAME', flex: 5),
              _th('COUNT', flex: 3, center: true, tooltip: 'Each addition (e.g. 6+15)'),
              _th('TOTAL', flex: 2, center: true),
              if (_canViewCalculatedDetails) _th('SOLD\n(POS)', flex: 2, center: true),
              if (_canViewCalculatedDetails) _th('REMAINING', flex: 3, center: true),
              if (hasSnapshot && _canViewCalculatedDetails) _th('ACTUAL\nCOUNT', flex: 2, center: true),
              if (hasSnapshot && _canViewCalculatedDetails) _th('SHORT', flex: 2, center: true),
              if (isActive && _canAddStock) _th('ADD QTY', flex: 4, center: true),
            ]),
          ),
          const Divider(height: 1),

          // ── Rows ──
          if (_sessionLoading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (displayItems.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Column(children: [
                Icon(Icons.inventory_2_outlined, size: 36, color: AppTheme.textLightSecondary.withOpacity(0.4)),
                const SizedBox(height: 12),
                Text('No items with "Track Stock Level in POS" enabled.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary), textAlign: TextAlign.center),
              ])),
            )
          else
            ...displayItems.asMap().entries.map((e) =>
              _buildRow(e.key, e.value, isActive: isActive, snapshot: sessionSnapshot, hasSnapshot: hasSnapshot)),

          // ── Totals row ──
          if (displayItems.isNotEmpty)
            _buildTotalsRow(displayItems, hasSnapshot: hasSnapshot, snapshot: sessionSnapshot),
        ],
      ),
    );
  }

  // ── One data row ─────────────────────────────────────
  Widget _buildRow(int idx, _DisplayItem item, {
    required bool isActive,
    Map<int, int> snapshot = const {},
    bool hasSnapshot = false,
  }) {
    final isEven = idx.isEven;
    final rem = item.sysRemaining;
    final addingThis = _addingProductId == item.productId;

    Color remColor;
    if (rem < 0) remColor = const Color(0xFFEF4444);
    else if (rem == 0 && !item.hasEntries) remColor = AppTheme.textLightSecondary;
    else if (rem < 5) remColor = const Color(0xFFF59E0B);
    else remColor = const Color(0xFF10B981);

    final actualCount = snapshot[item.productId];
    final shortage = actualCount != null ? rem - actualCount : null;

    return Container(
      color: isEven ? Colors.transparent : AppTheme.bgLight.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.borderLight.withOpacity(0.5)))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // # ──
          Expanded(flex: 1, child: Text('${idx + 1}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary), textAlign: TextAlign.center)),
          // Item name ──
          Expanded(flex: 5, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(item.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
              if (item.sinhala != null && item.sinhala!.isNotEmpty)
                Text(item.sinhala!, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
            ],
          )),
          // Count ──
          Expanded(flex: 3, child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: item.hasEntries ? AppTheme.primary.withOpacity(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.countString,
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold,
                    color: item.hasEntries ? AppTheme.primary : AppTheme.textLightSecondary),
                textAlign: TextAlign.center,
              ),
            ),
          )),
          // Total ──
          Expanded(flex: 2, child: Text('${item.totalAdded}',
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              textAlign: TextAlign.center)),
          // Sold (Calculated details) ──
          if (_canViewCalculatedDetails)
            Expanded(flex: 2, child: Text(
              item.soldQty > 0 ? '-${item.soldQty}' : (item.soldQty == 0 ? '0' : '${item.soldQty}'),
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600,
                  color: item.soldQty > 0 ? const Color(0xFFEF4444) : AppTheme.textLightSecondary),
              textAlign: TextAlign.center,
            )),
          // System Remaining (Calculated details) ──
          if (_canViewCalculatedDetails)
            Expanded(flex: 3, child: Center(
              child: (!item.hasEntries && item.soldQty == 0)
                  ? Text('—', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary.withOpacity(0.4)), textAlign: TextAlign.center)
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: remColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                      child: Text('$rem',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: remColor),
                          textAlign: TextAlign.center),
                    ),
            )),
          // Actual count snapshot (Calculated details) ──
          if (hasSnapshot && _canViewCalculatedDetails)
            Expanded(flex: 2, child: Center(
              child: actualCount != null
                  ? Text('$actualCount', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary), textAlign: TextAlign.center)
                  : Text('—', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary.withOpacity(0.3)), textAlign: TextAlign.center),
            )),
          // Shortage (Calculated details) ──
          if (hasSnapshot && _canViewCalculatedDetails)
            Expanded(flex: 2, child: Center(
              child: shortage != null
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: shortage > 0 ? const Color(0xFFFEE2E2) : (shortage < 0 ? const Color(0xFFDCFCE7) : AppTheme.bgLight),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        shortage > 0 ? '-$shortage' : (shortage < 0 ? '+${-shortage}' : '0'),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold,
                            color: shortage > 0 ? const Color(0xFFEF4444) : (shortage < 0 ? const Color(0xFF10B981) : AppTheme.textLightSecondary)),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const SizedBox(),
            )),
          // Add qty (active session only) ──
          if (isActive && _canAddStock)
            Expanded(flex: 4, child: _buildInlineAdd(item.productId, item.name, addingThis)),
        ],
      ),
    );
  }

  Widget _buildInlineAdd(int productId, String name, bool addingThis) {
    final ctrl = _rowCtrl(productId);
    return Row(
      children: [
        // Decrement
        _miniQtyBtn(icon: Icons.remove, onTap: () {
          final v = int.tryParse(ctrl.text) ?? 0;
          if (v > 1) {
            ctrl.text = '${v - 1}';
          } else {
            ctrl.text = '';
          }
        }),
        const SizedBox(width: 5),
        // Input
        SizedBox(
          width: 52,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              _StripLeadingZeroFormatter(),
            ],
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
            textInputAction: TextInputAction.done,
            onTap: () {
              if (ctrl.text.isNotEmpty) {
                ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
              }
            },
            onChanged: (val) {
              if (val.length > 1 && val.startsWith('0')) {
                final cleaned = val.replaceFirst(RegExp(r'^0+'), '');
                ctrl.value = TextEditingValue(
                  text: cleaned,
                  selection: TextSelection.collapsed(offset: cleaned.length),
                );
              }
            },
            onSubmitted: (_) {
              if (!addingThis) _handleInlineAdd(productId, name);
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: '1',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary.withOpacity(0.4)),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.borderLight)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.borderLight)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
              filled: true, fillColor: AppTheme.bgLight,
            ),
          ),
        ),
        const SizedBox(width: 5),
        // Increment
        _miniQtyBtn(icon: Icons.add, primary: true, onTap: () {
          final v = int.tryParse(ctrl.text) ?? 0;
          ctrl.text = '${v + 1}';
        }),
        const SizedBox(width: 6),
        // Add button
        SizedBox(
          height: 34,
          child: ElevatedButton(
            onPressed: addingThis ? null : () => _handleInlineAdd(productId, name),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              elevation: 0,
            ),
            child: addingThis
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text('+Add', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _miniQtyBtn({required IconData icon, bool primary = false, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28, height: 28,
        decoration: BoxDecoration(
          color: primary ? AppTheme.primary : AppTheme.bgLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: primary ? AppTheme.primary : AppTheme.borderLight),
        ),
        child: Icon(icon, size: 14, color: primary ? Colors.white : AppTheme.textLightPrimary),
      ),
    );
  }

  // ── Totals row ───────────────────────────────────────
  Widget _buildTotalsRow(List<_DisplayItem> items, {bool hasSnapshot = false, Map<int, int> snapshot = const {}}) {
    final totalAdded    = items.fold<int>(0, (s, i) => s + i.totalAdded);
    final totalSold     = items.fold<int>(0, (s, i) => s + i.soldQty);
    final totalSysRem   = items.fold<int>(0, (s, i) => s + i.sysRemaining);
    final totalActual   = (hasSnapshot && _canViewCalculatedDetails) ? items.fold<int>(0, (s, i) => s + (snapshot[i.productId] ?? i.sysRemaining)) : 0;
    final totalShort    = (hasSnapshot && _canViewCalculatedDetails) ? totalSysRem - totalActual : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.06),
        border: Border(top: BorderSide(color: AppTheme.primary.withOpacity(0.2), width: 1.5)),
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(13), bottomRight: Radius.circular(13)),
      ),
      child: Row(children: [
        Expanded(flex: 1, child: const SizedBox()),
        Expanded(flex: 5, child: Text('TOTALS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5))),
        Expanded(flex: 3, child: const SizedBox()),
        Expanded(flex: 2, child: Text('$totalAdded', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary), textAlign: TextAlign.center)),
        if (_canViewCalculatedDetails)
          Expanded(flex: 2, child: Text(totalSold > 0 ? '-$totalSold' : '0', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)), textAlign: TextAlign.center)),
        if (_canViewCalculatedDetails)
          Expanded(flex: 3, child: Text('$totalSysRem', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: totalSysRem >= 0 ? const Color(0xFF10B981) : AppTheme.danger), textAlign: TextAlign.center)),
        if (hasSnapshot && _canViewCalculatedDetails) ...[
          Expanded(flex: 2, child: Text('$totalActual', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary), textAlign: TextAlign.center)),
          Expanded(flex: 2, child: Text(totalShort > 0 ? '-$totalShort' : '$totalShort', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: totalShort > 0 ? const Color(0xFFEF4444) : const Color(0xFF10B981)), textAlign: TextAlign.center)),
        ],
      ]),
    );
  }

  // ─────────────────────────────────────────────────────
  // CLOSE SESSION DIALOG — Enter physical counts
  // ─────────────────────────────────────────────────────
  Widget _buildCloseSessionDialog(BuildContext ctx, List<_DisplayItem> items) {
    return StatefulBuilder(builder: (ctx, setLocal) {
      return Dialog(
        backgroundColor: AppTheme.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
        child: SizedBox(
          width: 750,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dialog header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(0.08),
                  border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(15), topRight: Radius.circular(15)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFEF4444).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.inventory_rounded, color: Color(0xFFEF4444), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Close Session — Record Physical Count', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                    Text('Enter the actual remaining quantity you physically counted for each item.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                  ]),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx, false)),
                ]),
              ),

              // Table header
              Container(
                color: AppTheme.bgLight,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                child: Row(children: [
                  _th('#', flex: 1, center: true),
                  _th('ITEM NAME', flex: 5),
                  if (_canViewCalculatedDetails) _th('SYSTEM REMAINING\n(Calculated)', flex: 3, center: true),
                  _th('PHYSICAL COUNT\n(Enter actual qty)', flex: 4, center: true),
                  if (_canViewCalculatedDetails) _th('SHORTAGE', flex: 2, center: true),
                ]),
              ),
              const Divider(height: 1),

              // Scrollable item rows
              Flexible(
                child: SingleChildScrollView(
                  child: Column(children: [
                    ...items.asMap().entries.map((e) {
                      final i = e.key;
                      final item = e.value;
                      final sysRem = item.sysRemaining;
                      final ctrl = _snapshotCtrls[item.productId]!;
                      final focusNode = _snapshotFocusNodes[item.productId]!;
                      final isLast = i == items.length - 1;

                      return StatefulBuilder(builder: (_, setRow) {
                        final actual = int.tryParse(ctrl.text) ?? 0;
                        final short  = sysRem - actual;
                        return Container(
                          color: i.isEven ? Colors.transparent : AppTheme.bgLight.withOpacity(0.5),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          child: Row(children: [
                            Expanded(flex: 1, child: Text('${i + 1}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary), textAlign: TextAlign.center)),
                            Expanded(flex: 5, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(item.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (item.sinhala != null && item.sinhala!.isNotEmpty)
                                Text(item.sinhala!, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
                            ])),
                            if (_canViewCalculatedDetails)
                              Expanded(flex: 3, child: Text('$sysRem', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)), textAlign: TextAlign.center)),
                            Expanded(flex: 4, child: Center(
                              child: SizedBox(
                                width: 100,
                                child: TextField(
                                  controller: ctrl,
                                  focusNode: focusNode,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    _StripLeadingZeroFormatter(),
                                  ],
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold),
                                  textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    hintText: '0',
                                    hintStyle: GoogleFonts.inter(fontSize: 15, color: AppTheme.textLightSecondary.withOpacity(0.4)),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.primary, width: 1.5)),
                                    filled: true, fillColor: AppTheme.bgLight,
                                  ),
                                  onTap: () {
                                    if (ctrl.text.isNotEmpty) {
                                      ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length);
                                    }
                                  },
                                  onChanged: (val) {
                                    if (val.length > 1 && val.startsWith('0')) {
                                      final cleaned = val.replaceFirst(RegExp(r'^0+'), '');
                                      final newText = cleaned.isEmpty ? '0' : cleaned;
                                      ctrl.value = TextEditingValue(
                                        text: newText,
                                        selection: TextSelection.collapsed(offset: newText.length),
                                      );
                                    }
                                    setRow(() {});
                                  },
                                  onSubmitted: (_) {
                                    if (!isLast) {
                                      final nextProductId = items[i + 1].productId;
                                      _snapshotFocusNodes[nextProductId]?.requestFocus();
                                    } else {
                                      Navigator.pop(ctx, true);
                                    }
                                  },
                                ),
                              ),
                            )),
                            if (_canViewCalculatedDetails)
                              Expanded(flex: 2, child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: short > 0 ? const Color(0xFFFEE2E2) : (short < 0 ? const Color(0xFFDCFCE7) : AppTheme.bgLight),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    short == 0 ? '0' : (short > 0 ? '-$short' : '+${-short}'),
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: short > 0 ? const Color(0xFFEF4444) : (short < 0 ? const Color(0xFF10B981) : AppTheme.textLightSecondary)),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              )),
                          ]),
                        );
                      });
                    }),
                  ]),
                ),
              ),

              // Footer info + buttons
              Container(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                decoration: BoxDecoration(
                  color: AppTheme.bgLight,
                  border: Border(top: BorderSide(color: AppTheme.borderLight)),
                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(15), bottomRight: Radius.circular(15)),
                ),
                child: Row(children: [
                  if (_canViewCalculatedDetails)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        const Icon(Icons.info_outline, size: 14, color: Color(0xFF856404)),
                        const SizedBox(width: 6),
                        Text('Shortage = System Remaining − Physical Count.\nNegative = surplus.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF856404))),
                      ]),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.textLightSecondary, side: BorderSide(color: AppTheme.borderLight), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                    child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text('Confirm & Close Session', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      elevation: 0,
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
      );
    });
  }

  // ─────────────────────────────────────────────────────
  // TAB 2 — ALL SESSIONS (Admin)
  // ─────────────────────────────────────────────────────
  Widget _buildAllSessionsTab(POSController controller) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildSessionsFilterBar(),
        const SizedBox(height: 20),
        if (_allSessionsLoading)
          const Center(child: Padding(padding: EdgeInsets.all(60), child: CircularProgressIndicator()))
        else if (_allSessions.isEmpty)
          _emptyState('No sessions found for $_sessionsFilterDate', Icons.event_busy_outlined)
        else
          ..._allSessions.map((session) {
            final name = session.userDisplayName ?? 'Unknown';
            final role = session.userRole ?? '';
            final loginStr = session.loginAt != null ? DateFormat('hh:mm a').format(session.loginAt!.toLocal()) : '—';
            final logoutStr = session.logoutAt != null ? DateFormat('hh:mm a').format(session.logoutAt!.toLocal()) : '—';

            // Build display items for this session (items only — no inline add for past sessions)
            final sessionItemMap = {for (var i in session.items) i.productId: i};
            final displayItems = controller.products
                .where((p) => p.trackStock && p.status == 'active')
                .map((p) => _DisplayItem(product: p, sessionItem: sessionItemMap[p.id]))
                .toList();

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Session user header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: session.isActive ? const Color(0xFF10B981).withOpacity(0.08) : AppTheme.bgLight,
                    border: Border.all(color: session.isActive ? const Color(0xFF10B981).withOpacity(0.3) : AppTheme.borderLight),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
                  ),
                  child: Row(children: [
                    CircleAvatar(
                      radius: 17, backgroundColor: AppTheme.primary.withOpacity(0.15),
                      child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary)),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textLightPrimary)),
                      Text('${role.toUpperCase()} · Login: $loginStr → ${session.isActive ? "Still Active" : "Logout: $logoutStr"}',
                          style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
                    ]),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: session.isActive ? const Color(0xFF10B981).withOpacity(0.12) : AppTheme.bgLight,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: session.isActive ? const Color(0xFF10B981) : AppTheme.borderLight),
                      ),
                      child: Text(session.isActive ? '● ACTIVE' : '✓ CLOSED',
                          style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: session.isActive ? const Color(0xFF10B981) : AppTheme.textLightSecondary)),
                    ),
                    const SizedBox(width: 10),
                    Text('${session.items.length} entries', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                  ]),
                ),
                // Register table for this session
                _buildRegisterTable(
                  displayItems: displayItems,
                  isActive: false,
                  loginAt: session.loginAt,
                  logoutAt: session.logoutAt,
                  sessionSnapshot: session.snapshot,
                  title: '$name\'s Register',
                ),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _buildSessionsFilterBar() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.cardLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.borderLight)),
      child: Row(children: [
        Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.primary),
        const SizedBox(width: 8),
        Text('Date:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 10),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(context: context,
                initialDate: DateTime.tryParse(_sessionsFilterDate) ?? DateTime.now(),
                firstDate: DateTime(2024), lastDate: DateTime.now());
            if (picked != null) { setState(() => _sessionsFilterDate = DateFormat('yyyy-MM-dd').format(picked)); _loadAllSessions(); }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: AppTheme.bgLight, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.borderLight)),
            child: Row(children: [
              Text(_sessionsFilterDate, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6), Icon(Icons.edit_calendar_outlined, size: 14, color: AppTheme.primary),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () { setState(() => _sessionsFilterDate = DateFormat('yyyy-MM-dd').format(DateTime.now())); _loadAllSessions(); },
          icon: const Icon(Icons.today, size: 14), label: const Text('Today'),
          style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.primary), foregroundColor: AppTheme.primary, textStyle: GoogleFonts.inter(fontSize: 12), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        ),
        const Spacer(),
        if (_allSessionsLoading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
        else Text('${_allSessions.length} session(s)', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
        const SizedBox(width: 10),
        IconButton(onPressed: () => _loadAllSessions(), icon: Icon(Icons.refresh, size: 18, color: AppTheme.primary), tooltip: 'Refresh', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30)),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────
  // TAB 3 — STOCK ADJUSTMENT (Admin)
  // ─────────────────────────────────────────────────────
  Widget _buildStockAdjustTab(POSController controller) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    final filteredLogs = _logs.where((l) => _isWithinDateRange((l['timestamp'] ?? '').toString())).take(_entriesLimit).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildDateChips(),
        const SizedBox(height: 20),
        if (isDesktop)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 1, child: _buildAdjustForm(controller)),
            const SizedBox(width: 24),
            Expanded(flex: 1, child: _buildStockLevelList(controller)),
          ])
        else ...[
          _buildAdjustForm(controller),
          const SizedBox(height: 20),
          _buildStockLevelList(controller),
        ],
        const SizedBox(height: 20),
        _buildLogsTable(filteredLogs),
      ]),
    );
  }

  Widget _buildDateChips() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.cardLight, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.borderLight)),
      child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        Text('Period:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(width: 10),
        for (final p in [['all', 'All Time'], ['today', 'Today'], ['weekly', 'Weekly'], ['monthly', 'Monthly'], ['yearly', 'Yearly'], ['custom', 'Custom']]) ...[
          const SizedBox(width: 6),
          ChoiceChip(
            label: Text(p[1], style: TextStyle(fontSize: 12, color: _datePreset == p[0] ? Colors.white : AppTheme.textLightPrimary)),
            selected: _datePreset == p[0], selectedColor: AppTheme.primary, backgroundColor: AppTheme.bgLight,
            onSelected: (v) { if (v) setState(() { _datePreset = p[0]; if (p[0] == 'custom') _pickRange(); }); },
          ),
        ],
        if (_datePreset == 'custom' && _startDate != null && _endDate != null) ...[
          const SizedBox(width: 10),
          Text('${DateFormat('MMM d').format(_startDate!)} – ${DateFormat('MMM d').format(_endDate!)}',
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
        ],
      ])),
    );
  }

  Future<void> _pickRange() async {
    final range = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (range != null) setState(() { _startDate = range.start; _endDate = range.end; });
  }

  Widget _buildAdjustForm(POSController controller) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.cardLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.tune_outlined, color: AppTheme.primary, size: 18), const SizedBox(width: 8),
          Text('Manual Stock Adjustment', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 4),
        Text('Admin only — modifies global stock permanently.', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
        const SizedBox(height: 16),
        _label('SELECT PRODUCT *'), const SizedBox(height: 6),
        DropdownButtonFormField<ProductModel>(
          value: _selectedStockProduct != null && controller.products.contains(_selectedStockProduct) ? _selectedStockProduct : null,
          dropdownColor: AppTheme.cardLight,
          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
          hint: Text('Choose product...', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
          items: controller.products.where((p) => p.trackStock).map((p) => DropdownMenuItem(value: p, child: Text('${p.name} | Stock: ${p.stockQty}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (p) => setState(() => _selectedStockProduct = p),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('CHANGE QTY *'), const SizedBox(height: 6),
            TextField(controller: _stockChangeController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g. 100, -5'), style: GoogleFonts.inter(fontSize: 13)),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label('TYPE *'), const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _stockType, dropdownColor: AppTheme.cardLight, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
              items: const [
                DropdownMenuItem(value: 'purchase', child: Text('Purchase')),
                DropdownMenuItem(value: 'adjustment', child: Text('Correction')),
                DropdownMenuItem(value: 'wastage', child: Text('Wastage')),
              ],
              onChanged: (v) => setState(() => _stockType = v!),
            ),
          ])),
        ]),
        const SizedBox(height: 12),
        _label('REASON / REMARKS *'), const SizedBox(height: 6),
        TextField(controller: _stockReasonController, decoration: const InputDecoration(hintText: 'e.g. weekly batch, spoiled'), style: GoogleFonts.inter(fontSize: 13)),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => _handleAdjustStock(controller),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0),
          child: Text('Apply Adjustment', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }

  Widget _buildStockLevelList(POSController controller) {
    final products = controller.products.where((p) => p.trackStock && p.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    return Container(
      height: 350, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.cardLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Current Stock Levels', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 16), hintText: 'Search...'), style: GoogleFonts.inter(fontSize: 13), onChanged: (v) => setState(() => _searchQuery = v)),
        const SizedBox(height: 12),
        Expanded(child: ListView.separated(
          itemCount: products.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.dividerColor),
          itemBuilder: (_, i) {
            final p = products[i];
            final isLow = p.stockQty <= p.minStockLevel;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(p.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (isLow) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), margin: const EdgeInsets.only(right: 8), decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)), child: Text('LOW', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFC5221F)))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: isLow ? const Color(0xFFFEE2E2) : AppTheme.bgLight, borderRadius: BorderRadius.circular(4)),
                  child: Text('${p.stockQty}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: isLow ? const Color(0xFFC5221F) : AppTheme.textLightPrimary)),
                ),
              ]),
            );
          },
        )),
      ]),
    );
  }

  Widget _buildLogsTable(List<dynamic> logs) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.cardLight, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderLight)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Text('Stock Adjustment Logs', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold)),
            const Spacer(),
            DropdownButtonHideUnderline(child: DropdownButton<int>(
              value: _entriesLimit,
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightPrimary),
              items: const [DropdownMenuItem(value: 10, child: Text('10')), DropdownMenuItem(value: 25, child: Text('25')), DropdownMenuItem(value: 50, child: Text('50')), DropdownMenuItem(value: 100, child: Text('100'))],
              onChanged: (v) => setState(() => _entriesLimit = v!),
            )),
          ]),
        ),
        if (_logsLoading)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
        else if (logs.isEmpty)
          Padding(padding: const EdgeInsets.all(40), child: Center(child: Text('No logs found.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary))))
        else ...[
          Container(color: AppTheme.bgLight, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
            child: Row(children: [_th('PRODUCT', flex: 3), _th('CHANGE', flex: 2, center: true), _th('TYPE', flex: 2), _th('REASON', flex: 3), _th('RECORDER', flex: 2), _th('DATE & TIME', flex: 3)])),
          ...logs.asMap().entries.map((e) {
            final l = e.value;
            final ch = double.tryParse(l['change_qty'].toString()) ?? 0.0;
            final isPos = ch > 0;
            final time = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
            final type = l['type'].toString().toLowerCase();
            Color bc, tc; String badge;
            switch (type) {
              case 'purchase': bc = const Color(0xFFE6F4EA); tc = const Color(0xFF137333); badge = 'PURCHASE'; break;
              case 'sale':     bc = const Color(0xFFFFF0F5); tc = AppTheme.primary;       badge = 'SALE'; break;
              case 'wastage':  bc = const Color(0xFFFCE8E6); tc = const Color(0xFFC5221F); badge = 'WASTAGE'; break;
              default:         bc = const Color(0xFFE8F0FE); tc = const Color(0xFF1A73E8); badge = 'CORRECTION';
            }
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
              decoration: BoxDecoration(color: e.key.isEven ? Colors.transparent : AppTheme.bgLight.withOpacity(0.5), border: Border(bottom: BorderSide(color: AppTheme.dividerColor, width: 0.5))),
              child: Row(children: [
                Expanded(flex: 3, child: Text(l['product_name'] ?? 'N/A', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text('${isPos ? '+' : ''}${ch.toStringAsFixed(0)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: isPos ? const Color(0xFF137333) : const Color(0xFFC5221F)), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: bc, borderRadius: BorderRadius.circular(4)), child: Text(badge, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: tc)))),
                Expanded(flex: 3, child: Text(l['reason'] ?? '', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(l['recorder_name'] ?? 'Admin', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 3, child: Text(time, style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary))),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  // ─── Shared helpers ───────────────────────────────────
  Widget _th(String text, {int flex = 1, bool center = false, String? tooltip}) {
    Widget w = Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.4), textAlign: center ? TextAlign.center : TextAlign.left);
    if (tooltip != null) w = Tooltip(message: tooltip, child: w);
    return Expanded(flex: flex, child: w);
  }

  Widget _label(String text) => Text(text, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary));

  Widget _emptyState(String msg, IconData icon) => Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Column(children: [
    Icon(icon, size: 40, color: AppTheme.textLightSecondary.withOpacity(0.4)), const SizedBox(height: 12),
    Text(msg, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary), textAlign: TextAlign.center),
  ])));

  // ─── Export ───────────────────────────────────────────
  Future<void> _exportToCSV() async {
    try {
      String csv = 'Cashier,Item,Count,Total Added,Sold (POS),System Remaining,Physical Count,Shortage,Date\n';
      for (final s in _allSessions) {
        for (final item in s.items) {
          final actual = s.snapshot[item.productId] ?? item.remaining;
          final short  = item.remaining - actual;
          csv += '${s.userDisplayName},${item.productName},${item.countString},${item.totalAdded},${item.soldQty},${item.remaining},$actual,$short,$_sessionsFilterDate\n';
        }
      }
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Export CSV', fileName: 'POS_Stock_$_sessionsFilterDate.csv', type: FileType.custom, allowedExtensions: ['csv']);
      if (path != null) { await File(path).writeAsString(csv); _showSnack('Exported to $path'); }
    } catch (e) { _showSnack('Export failed: $e', isError: true); }
  }

  Future<void> _exportToPDF() async {
    try {
      final doc = pw.Document();
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('POS Stock Sessions — $_sessionsFilterDate', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 14),
          for (final s in _allSessions) ...[
            pw.Text('${s.userDisplayName} (${s.userRole})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
            pw.SizedBox(height: 4),
            pw.Table.fromTextArray(
              headers: ['Item', 'Count', 'Total', 'Sold', 'Sys.Rem', 'Actual', 'Short'],
              data: s.items.map((i) {
                final actual = s.snapshot[i.productId] ?? i.remaining;
                return [i.productName, i.countString, '${i.totalAdded}', '${i.soldQty}', '${i.remaining}', '$actual', '${i.remaining - actual}'];
              }).toList(),
              border: pw.TableBorder.all(color: PdfColors.grey300),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 14),
          ],
        ]),
      ));
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Export PDF', fileName: 'POS_Stock_$_sessionsFilterDate.pdf', type: FileType.custom, allowedExtensions: ['pdf']);
      if (path != null) { await File(path).writeAsBytes(await doc.save()); _showSnack('PDF saved to $path'); }
    } catch (e) { _showSnack('Export failed: $e', isError: true); }
  }
}
