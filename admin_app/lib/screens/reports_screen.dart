import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../core/api_service.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../widgets/order_details_dialog.dart';
import 'staff_payroll_screen.dart';

// ─────────────────────────────────────────────────────────────
//  REPORTS SCREEN  — 6 tabs with PDF save
// ─────────────────────────────────────────────────────────────
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ── State ─────────────────────────────────────────────────
  int    _tab       = 0;
  bool   _loading   = false;
  bool   _pdfBusy   = false;
  String _err       = '';

  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to   = DateTime.now();

  List<Map<String, dynamic>> _orders      = [];
  List<Map<String, dynamic>> _usersReport = [];
  List<IngredientModel>      _ingredients = [];

  final _tabs = const ['Sales', 'By Cashier', 'By Item', 'Users', 'Raw Materials', 'All Orders'];
  final _curr = NumberFormat('#,##0.00', 'en_US');

  // ── Lifecycle ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // Defer load so the widget tree is fully built before hitting network
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _err = ''; });
    try {
      final fs  = DateFormat('yyyy-MM-dd').format(_from);
      final ts  = DateFormat('yyyy-MM-dd').format(_to);
      final ord = await ApiService.instance.getOrdersByDate(fs, ts);
      final usr = await ApiService.instance.getUsersReport(fs, ts);
      // Ingredients may fail — handle gracefully
      List<IngredientModel> ing = [];
      try { ing = await ApiService.instance.getIngredients(); } catch (_) {}
      if (!mounted) return;
      setState(() { _orders = ord; _usersReport = usr; _ingredients = ing; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = e.toString(); _loading = false; });
    }
  }

  // ── Date range picker ─────────────────────────────────────
  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary, onPrimary: Colors.black,
            surface: AppColors.bgCard, onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _from = picked.start; _to = picked.end; });
      _load();
    }
  }

  // ── Computed helpers ──────────────────────────────────────
  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  List<Map<String, dynamic>> get _paid =>
      _orders.where((o) => o['payment_status'] == 'paid').toList();

  Map<String, List<Map<String, dynamic>>> get _byCashier {
    final m = <String, List<Map<String, dynamic>>>{};
    for (final o in _paid) {
      final k = o['cashier_name']?.toString() ?? 'Unknown';
      m.putIfAbsent(k, () => []).add(o);
    }
    return m;
  }

  List<Map<String, dynamic>> get _itemStats {
    final m = <String, Map<String, dynamic>>{};
    for (final o in _paid) {
      if (o['items'] is List) {
        for (final it in (o['items'] as List)) {
          final itm = Map<String, dynamic>.from(it as Map);
          final name  = itm['product_name']?.toString() ?? '?';
          final qty   = int.tryParse(itm['quantity']?.toString() ?? '0') ?? 0;
          final price = double.tryParse(itm['price']?.toString() ?? '0') ?? 0.0;
          m[name] ??= {'name': name, 'qty': 0, 'revenue': 0.0};
          m[name]!['qty']     = (m[name]!['qty']     as int)    + qty;
          m[name]!['revenue'] = (m[name]!['revenue'] as double) + price * qty;
        }
      }
    }
    final lst = m.values.toList();
    lst.sort((a, b) {
      final aq = (a['qty'] as int? ?? 0);
      final bq = (b['qty'] as int? ?? 0);
      return bq.compareTo(aq);
    });
    return lst;
  }

  // ── PDF helpers ───────────────────────────────────────────
  String get _rangeStr =>
      '${DateFormat('yyyy-MM-dd').format(_from)} to ${DateFormat('yyyy-MM-dd').format(_to)}';

  pw.Widget _hdr(String title) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('HOTEL POS', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, letterSpacing: 1.2)),
      pw.SizedBox(height: 3),
      pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('Period: $_rangeStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      pw.Divider(thickness: 1.5, color: PdfColors.amber700),
      pw.SizedBox(height: 8),
    ]);

  pw.Widget _tbl(List<String> h, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: h, data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
        cellStyle: const pw.TextStyle(fontSize: 8),
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.amber50),
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300),
          verticalInside:   pw.BorderSide(color: PdfColors.grey300),
          left: pw.BorderSide(color: PdfColors.grey400), right: pw.BorderSide(color: PdfColors.grey400),
          top:  pw.BorderSide(color: PdfColors.grey400), bottom: pw.BorderSide(color: PdfColors.grey400),
        ),
      );

  pw.Widget _kv(String k, String v) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(children: [
      pw.SizedBox(width: 130, child: pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
      pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    ]));

  // PDF builders
  Future<Uint8List> _pdfSales() async {
    final total  = _paid.fold(0.0, (s, o) => s + _d(o['total']));
    final cash   = _paid.where((o) => o['payment_method'] == 'cash'  ).fold(0.0, (s, o) => s + _d(o['total']));
    final card   = _paid.where((o) => o['payment_method'] == 'card'  ).fold(0.0, (s, o) => s + _d(o['total']));
    final credit = _paid.where((o) => o['payment_method'] == 'credit').fold(0.0, (s, o) => s + _d(o['total']));
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _hdr('Sales Summary Report'),
      pw.Row(children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _kv('Total Revenue', 'LKR ${_curr.format(total)}'),
          _kv('Total Orders',  '${_orders.length}'),
          _kv('Paid Orders',   '${_paid.length}'),
        ])),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _kv('Cash',   'LKR ${_curr.format(cash)}'),
          _kv('Card',   'LKR ${_curr.format(card)}'),
          _kv('Credit', 'LKR ${_curr.format(credit)}'),
        ])),
      ]),
    ]));
    return doc.save();
  }

  Future<Uint8List> _pdfCashier() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _hdr('Orders by Cashier'),
      ..._byCashier.entries.expand((e) {
        final rev = e.value.fold(0.0, (s, o) => s + _d(o['total']));
        return [
          pw.Container(color: PdfColors.amber100, padding: const pw.EdgeInsets.all(5),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('${e.value.length} orders · LKR ${_curr.format(rev)}', style: const pw.TextStyle(fontSize: 10)),
            ])),
          pw.SizedBox(height: 4),
          _tbl(['Order #', 'Time', 'Type', 'Total (LKR)'], e.value.map((o) => [
            o['order_number']?.toString() ?? '',
            _ft(o['created_at']?.toString() ?? ''),
            _ty(o['order_type']),
            _curr.format(_d(o['total'])),
          ]).toList()),
          pw.SizedBox(height: 10),
        ];
      }),
    ]));
    return doc.save();
  }

  Future<Uint8List> _pdfItems() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _hdr('Sales by Menu Item'),
      _tbl(['#', 'Item', 'Qty Sold', 'Revenue (LKR)'],
        _itemStats.asMap().entries.map((e) => [
          '${e.key + 1}', e.value['name'].toString(),
          '${e.value['qty']}', _curr.format(e.value['revenue'] as double),
        ]).toList()),
    ]));
    return doc.save();
  }

  Future<Uint8List> _pdfUsers() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _hdr('Users Order Report'),
      _tbl(['Name', 'Username', 'Role', 'Orders', 'Paid', 'Revenue (LKR)'],
        _usersReport.map((u) => [
          u['name']?.toString() ?? '',
          u['username']?.toString() ?? '',
          u['role']?.toString() ?? '',
          '${u['total_orders'] ?? 0}',
          '${u['paid_orders'] ?? 0}',
          _curr.format(_d(u['total_revenue'])),
        ]).toList()),
    ]));
    return doc.save();
  }

  Future<Uint8List> _pdfRaw() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _hdr('Raw Materials Stock'),
      _tbl(['Ingredient', 'Stock', 'Unit', 'Min Level', 'Status'],
        _ingredients.map((i) => [
          i.name, i.stockQty.toStringAsFixed(2), i.unit,
          i.minStockLevel.toStringAsFixed(2), i.isLowStock ? 'LOW' : 'OK',
        ]).toList()),
    ]));
    return doc.save();
  }

  Future<Uint8List> _pdfAllOrders() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _hdr('All Orders'),
      _tbl(['Order #', 'Date', 'Cashier', 'Type', 'Method', 'Total (LKR)', 'Status'],
        _orders.map((o) => [
          o['order_number']?.toString() ?? '',
          _fd(o['created_at']?.toString() ?? ''),
          o['cashier_name']?.toString() ?? '',
          _ty(o['order_type']),
          (o['payment_method']?.toString() ?? 'cash').toUpperCase(),
          _curr.format(_d(o['total'])),
          (o['payment_status']?.toString() ?? '').toUpperCase(),
        ]).toList()),
    ]));
    return doc.save();
  }

  // ── Save PDF ──────────────────────────────────────────────
  Future<void> _save(Future<Uint8List> Function() builder, String name) async {
    if (_pdfBusy) return;
    setState(() => _pdfBusy = true);
    try {
      final bytes = await builder();
      Directory dir;
      try {
        final ext = await getExternalStorageDirectory();
        final dl  = Directory('${ext!.parent.parent.parent.parent.path}/Download');
        dir = await dl.exists() ? dl : await getApplicationDocumentsDirectory();
      } catch (_) {
        dir = await getApplicationDocumentsDirectory();
      }
      final ts   = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final file = File('${dir.path}/${name}_$ts.pdf');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      setState(() => _pdfBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('✅ PDF saved!', style: TextStyle(fontWeight: FontWeight.w700)),
          Text(file.path, style: const TextStyle(fontSize: 10)),
        ]),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _pdfBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PDF error: $e'), backgroundColor: AppColors.error));
    }
  }

  // ── Formatters ────────────────────────────────────────────
  String _ft(String r) { try { return DateFormat('HH:mm').format(DateTime.parse(r).toLocal()); } catch (_) { return r; } }
  String _fd(String r) { try { return DateFormat('yyyy-MM-dd').format(DateTime.parse(r).toLocal()); } catch (_) { return r; } }
  String _ty(dynamic t) { switch (t?.toString()) { case 'dine_in': return 'Dine In'; case 'takeaway': return 'Takeaway'; case 'delivery': return 'Delivery'; default: return t?.toString() ?? ''; } }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Reports & Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.badge_outlined, color: AppColors.primary),
            tooltip: 'Staff Attendance & Payroll',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffPayrollScreen()),
            ),
          ),
          if (_pdfBusy)
            const Padding(padding: EdgeInsets.only(right: 12),
              child: Center(child: SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))),
          TextButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.date_range_rounded, size: 15, color: AppColors.primary),
            label: Text('${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM').format(_to)}',
                style: const TextStyle(color: AppColors.primary, fontSize: 11)),
          ),
        ],
      ),
      body: Column(children: [
        // ── Scrollable tab pills ────────────────────────────
        Container(
          color: AppColors.bgPrimary,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: List.generate(_tabs.length, (i) {
              final sel = i == _tab;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.bgCardAlt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(_tabs[i], style: TextStyle(
                      color: sel ? Colors.black : AppColors.textSecondary,
                      fontSize: 12, fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    )),
                  ),
                ),
              );
            })),
          ),
        ),

        // ── Body ───────────────────────────────────────────
        Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _err.isNotEmpty
                ? _ErrView(msg: _err, onRetry: _load)
                : _buildBody()),
      ]),
    );
  }

  Widget _buildBody() {
    switch (_tab) {
      case 0: return _SalesTab(orders: _orders, paid: _paid, curr: _curr, toD: _d, from: _from, to: _to,
                  onSave: () => _save(_pdfSales, 'sales_report'));
      case 1: return _CashierTab(byCashier: _byCashier, curr: _curr, toD: _d, ty: _ty, ft: _ft,
                  onSave: () => _save(_pdfCashier, 'cashier_report'));
      case 2: return _ItemsTab(items: _itemStats, curr: _curr,
                  onSave: () => _save(_pdfItems, 'items_report'));
      case 3: return _UsersTab(users: _usersReport, curr: _curr, toD: _d,
                  onSave: () => _save(_pdfUsers, 'users_report'));
      case 4: return _RawTab(ingredients: _ingredients,
                  onSave: () => _save(_pdfRaw, 'raw_materials'));
      case 5: return _AllOrdersTab(orders: _orders, curr: _curr, toD: _d, ty: _ty, fd: _fd,
                  onSave: () => _save(_pdfAllOrders, 'all_orders'));
      default: return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  SALES TAB
// ─────────────────────────────────────────────────────────────
class _SalesTab extends StatelessWidget {
  final List<Map<String, dynamic>> orders, paid;
  final NumberFormat curr;
  final double Function(dynamic) toD;
  final DateTime from, to;
  final VoidCallback onSave;
  const _SalesTab({required this.orders, required this.paid, required this.curr,
    required this.toD, required this.from, required this.to, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final total  = paid.fold(0.0, (s, o) => s + toD(o['total']));
    final cash   = paid.where((o) => o['payment_method'] == 'cash'  ).fold(0.0, (s, o) => s + toD(o['total']));
    final card   = paid.where((o) => o['payment_method'] == 'card'  ).fold(0.0, (s, o) => s + toD(o['total']));
    final credit = paid.where((o) => o['payment_method'] == 'credit').fold(0.0, (s, o) => s + toD(o['total']));
    final dineIn = paid.where((o) => o['order_type'] == 'dine_in' ).length;
    final take   = paid.where((o) => o['order_type'] == 'takeaway').length;
    final del    = paid.where((o) => o['order_type'] == 'delivery').length;
    final days   = to.difference(from).inDays + 1;
    // Build day→revenue map safely
    final dayList  = List.generate(days, (i) => DateFormat('yyyy-MM-dd').format(from.add(Duration(days: i))));
    final revByDay = <String, double>{};
    for (final o in paid) {
      final raw = o['created_at']?.toString() ?? '';
      final d   = raw.length >= 10 ? raw.substring(0, 10) : '';
      if (d.isNotEmpty) revByDay[d] = (revByDay[d] ?? 0) + toD(o['total']);
    }
    final maxRev = revByDay.values.fold(0.0, (m, v) => v > m ? v : m);

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
      _SaveBar(label: 'Sales Summary', onSave: onSave),
      const SizedBox(height: 14),

      // Revenue hero
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A1400), Color(0xFF0D1120)],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total Revenue', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 6),
          Text('LKR ${curr.format(total)}',
              style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${paid.length} paid · ${orders.length} total · $days days',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ]),
      ).animate().fadeIn(duration: 300.ms),
      const SizedBox(height: 12),

      // Cash / Card / Credit
      Row(children: [
        Expanded(child: _StatCard('Cash',   'LKR ${curr.format(cash)}',   AppColors.success)),
        const SizedBox(width: 8),
        Expanded(child: _StatCard('Card',   'LKR ${curr.format(card)}',   AppColors.info)),
        const SizedBox(width: 8),
        Expanded(child: _StatCard('Credit', 'LKR ${curr.format(credit)}', AppColors.warning)),
      ]).animate().fadeIn(duration: 300.ms, delay: 60.ms),
      const SizedBox(height: 12),

      // Order counts
      Row(children: [
        Expanded(child: _NumChip('Total',  orders.length, AppColors.textSecondary)),
        const SizedBox(width: 8),
        Expanded(child: _NumChip('Paid',   paid.length,   AppColors.success)),
        const SizedBox(width: 8),
        Expanded(child: _NumChip('Unpaid', orders.where((o) => o['payment_status'] != 'paid' && o['status'] != 'cancelled').length, AppColors.warning)),
        const SizedBox(width: 8),
        Expanded(child: _NumChip('Cancel', orders.where((o) => o['status'] == 'cancelled').length, AppColors.error)),
      ]).animate().fadeIn(duration: 300.ms, delay: 100.ms),
      const SizedBox(height: 20),

      // Daily Revenue Bar Chart
      const Text('Daily Revenue', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Container(
        height: 200,
        padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
        decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: maxRev > 0 ? BarChart(BarChartData(
          maxY: maxRev * 1.25,
          gridData: FlGridData(show: true, drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 1)),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true, reservedSize: 48,
              getTitlesWidget: (v, _) => Text(
                v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
            )),
            bottomTitles: AxisTitles(sideTitles: SideTitles(
              showTitles: true,
              interval: (dayList.length / 5).ceilToDouble().clamp(1, 10),
              getTitlesWidget: (v, _) {
                final idx = v.toInt();
                if (idx < 0 || idx >= dayList.length) return const SizedBox();
                try {
                  return Padding(padding: const EdgeInsets.only(top: 4),
                    child: Text(DateFormat('d/M').format(DateTime.parse(dayList[idx])),
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 9)));
                } catch (_) { return const SizedBox(); }
              },
            )),
          ),
          barGroups: dayList.asMap().entries.map((e) {
            final rev = revByDay[e.value] ?? 0.0;
            return BarChartGroupData(x: e.key, barRods: [
              BarChartRodData(toY: rev, width: days > 14 ? 6 : 12,
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  colors: [AppColors.primary.withOpacity(0.5), AppColors.primary],
                  begin: Alignment.bottomCenter, end: Alignment.topCenter)),
            ]);
          }).toList(),
        )) : const Center(child: Text('No revenue data', style: TextStyle(color: AppColors.textMuted))),
      ).animate().fadeIn(duration: 400.ms, delay: 140.ms),
      const SizedBox(height: 20),

      // Order types
      const Text('Order Types', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: Column(children: [
          _TypeRow('Dine In', dineIn, paid.length, AppColors.success, Icons.restaurant_rounded),
          const SizedBox(height: 10),
          _TypeRow('Takeaway', take, paid.length, AppColors.info, Icons.takeout_dining_rounded),
          const SizedBox(height: 10),
          _TypeRow('Delivery', del, paid.length, AppColors.primary, Icons.delivery_dining_rounded),
        ]),
      ).animate().fadeIn(duration: 300.ms, delay: 180.ms),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  CASHIER TAB
// ─────────────────────────────────────────────────────────────
class _CashierTab extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> byCashier;
  final NumberFormat curr;
  final double Function(dynamic) toD;
  final String Function(dynamic) ty;
  final String Function(String) ft;
  final VoidCallback onSave;
  const _CashierTab({required this.byCashier, required this.curr, required this.toD,
    required this.ty, required this.ft, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (byCashier.isEmpty) return _Empty('No cashier data for this period');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
      _SaveBar(label: 'Cashier Report', onSave: onSave),
      const SizedBox(height: 14),
      ...byCashier.entries.map((entry) {
        final rev = entry.value.fold(0.0, (s, o) => s + toD(o['total']));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppColors.bgCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border.all(color: AppColors.primary.withOpacity(0.3))),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.person_rounded, color: AppColors.primary, size: 16)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.key, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
                Text('${entry.value.length} orders · LKR ${curr.format(rev)}',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ])),
            ]),
          ),
          Container(
            decoration: BoxDecoration(color: AppColors.bgCard,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border.all(color: AppColors.border)),
            child: Column(children: entry.value.take(30).toList().asMap().entries.map((e) {
              final o = e.value;
              return Column(children: [
                if (e.key > 0) const Divider(height: 1),
                InkWell(
                  onTap: () {
                    final orderId = o['id'] ?? o['order_id'] ?? o['order_number'];
                    if (orderId != null) OrderDetailsDialog.show(context, orderId);
                  },
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o['order_number']?.toString() ?? '',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${ty(o['order_type'])} · ${ft(o['created_at']?.toString() ?? '')}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ])),
                      _PayBadge(o['payment_method']?.toString()),
                      const SizedBox(width: 8),
                      Text('LKR ${curr.format(toD(o['total']))}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                    ])),
                ),
              ]);
            }).toList()),
          ),
          const SizedBox(height: 14),
        ]);
      }),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  ITEMS TAB
// ─────────────────────────────────────────────────────────────
class _ItemsTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final NumberFormat curr;
  final VoidCallback onSave;
  const _ItemsTab({required this.items, required this.curr, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _Empty('No item sales for this period');
    final maxQ = (int.tryParse(items[0]['qty']?.toString() ?? '0') ?? 1).toDouble();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
      _SaveBar(label: 'Item Sales Report', onSave: onSave),
      const SizedBox(height: 14),
      Container(
        decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border)),
        child: Column(children: items.asMap().entries.map((e) {
          final i     = e.key;
          final item  = e.value;
          final qty   = (int.tryParse(item['qty']?.toString() ?? '0') ?? 0).toDouble();
          final rev   = double.tryParse(item['revenue']?.toString() ?? '0') ?? 0.0;
          final color = AppColors.chartColors[i % AppColors.chartColors.length];
          return Column(children: [
            if (i > 0) const Divider(height: 1),
            Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(children: [
                Row(children: [
                  Container(width: 26, height: 26,
                    decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(7)),
                    child: Center(child: Text('${i + 1}',
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item['name']?.toString() ?? '',
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      overflow: TextOverflow.ellipsis)),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${item['qty']} sold', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                    Text('LKR ${curr.format(rev)}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ]),
                ]),
                const SizedBox(height: 6),
                ClipRRect(borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: maxQ > 0 ? qty / maxQ : 0,
                    backgroundColor: AppColors.bgCardAlt,
                    valueColor: AlwaysStoppedAnimation(color), minHeight: 5)),
              ]),
            ),
          ]);
        }).toList()),
      ).animate().fadeIn(duration: 300.ms),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  USERS REPORT TAB  — role-aware activity view
// ─────────────────────────────────────────────────────────────
class _UsersTab extends StatefulWidget {
  final List<Map<String, dynamic>> users;
  final NumberFormat curr;
  final double Function(dynamic) toD;
  final VoidCallback onSave;
  const _UsersTab({required this.users, required this.curr, required this.toD, required this.onSave});
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  int? _expanded; // which user card is expanded

  Color _roleColor(String? role) {
    switch (role) {
      case 'admin':    return AppColors.error;
      case 'owner':    return AppColors.primary;
      case 'cashier':  return AppColors.success;
      case 'kitchen':  return AppColors.info;
      case 'waiter':   return const Color(0xFF8B5CF6);
      case 'delivery': return AppColors.warning;
      default:         return AppColors.textMuted;
    }
  }

  IconData _roleIcon(String? role) {
    switch (role) {
      case 'admin':    return Icons.admin_panel_settings_rounded;
      case 'owner':    return Icons.business_center_rounded;
      case 'cashier':  return Icons.point_of_sale_rounded;
      case 'kitchen':  return Icons.restaurant_rounded;
      case 'waiter':   return Icons.room_service_rounded;
      case 'delivery': return Icons.delivery_dining_rounded;
      default:         return Icons.person_rounded;
    }
  }

  bool _isKitchen(String? role) => role == 'kitchen';

  @override
  Widget build(BuildContext context) {
    final users = widget.users;
    if (users.isEmpty) return _Empty('No user data for this period');

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
      _SaveBar(label: 'User Activity Report', onSave: widget.onSave),
      const SizedBox(height: 14),

      ...users.asMap().entries.map((e) {
        final idx  = e.key;
        final u    = e.value;
        final role = u['role']?.toString() ?? '';
        final name = u['name']?.toString() ?? '?';
        final init = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
        final rClr = _roleColor(role);
        final isOpen = _expanded == idx;
        final isKitchen = _isKitchen(role);

        // kitchen: items_prepared list; others: orders_list
        final itemsList = (u['items_prepared'] is List)
            ? (u['items_prepared'] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];
        final ordersList = (u['orders_list'] is List)
            ? (u['orders_list'] as List).cast<Map<String, dynamic>>()
            : <Map<String, dynamic>>[];

        final totalOrders  = int.tryParse(u['total_orders']?.toString() ?? '0') ?? 0;
        final paidOrders   = int.tryParse(u['paid_orders']?.toString() ?? '0') ?? 0;
        final totalRev     = widget.toD(u['total_revenue']);
        final hasActivity  = isKitchen ? itemsList.isNotEmpty : ordersList.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hasActivity ? rClr.withOpacity(0.3) : AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

            // ── Card header — always visible ──────────────────
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: hasActivity ? () => setState(() => _expanded = isOpen ? null : idx) : null,
              child: Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Row(children: [
                  // Avatar
                  Container(width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: rClr.withOpacity(0.12), shape: BoxShape.circle,
                      border: Border.all(color: rClr.withOpacity(0.4), width: 1.5)),
                    child: Center(child: Text(init,
                        style: TextStyle(color: rClr, fontSize: 18, fontWeight: FontWeight.w800)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: rClr.withOpacity(0.12), borderRadius: BorderRadius.circular(5)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_roleIcon(role), color: rClr, size: 10),
                          const SizedBox(width: 3),
                          Text(role.toUpperCase(),
                              style: TextStyle(color: rClr, fontSize: 9, fontWeight: FontWeight.w700)),
                        ])),
                      const SizedBox(width: 6),
                      Text('@${u['username']?.toString() ?? ''}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ]),
                  ])),
                  // Right-side summary
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if (isKitchen) ...[
                      Text('${totalOrders} items', style: TextStyle(
                          color: hasActivity ? AppColors.info : AppColors.textMuted,
                          fontSize: 14, fontWeight: FontWeight.w800)),
                      Text('${itemsList.length} dishes', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ] else ...[
                      Text('LKR ${widget.curr.format(totalRev)}', style: TextStyle(
                          color: hasActivity ? AppColors.primary : AppColors.textMuted,
                          fontSize: 13, fontWeight: FontWeight.w800)),
                      Text('$paidOrders paid / $totalOrders orders',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ],
                    if (hasActivity) ...[
                      const SizedBox(height: 4),
                      Icon(isOpen ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: rClr, size: 16),
                    ],
                  ]),
                ]),
              ),
            ),

            // ── Expanded detail ───────────────────────────────
            if (isOpen && hasActivity) ...[
              const Divider(height: 1),
              if (isKitchen)
                _KitchenItemsDetail(items: itemsList, color: rClr)
              else
                _CashierOrdersDetail(orders: ordersList, curr: widget.curr, color: rClr),
            ],
          ]),
        ).animate(key: ValueKey(u['id'])).fadeIn(duration: 250.ms, delay: Duration(milliseconds: idx * 40));
      }),
    ]);
  }
}

// ── Kitchen: Prepared Items Detail ────────────────────────────
class _KitchenItemsDetail extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Color color;
  const _KitchenItemsDetail({required this.items, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxQty = items.isNotEmpty
        ? (int.tryParse(items[0]['qty']?.toString() ?? '1') ?? 1).toDouble()
        : 1.0;

    return Column(children: [
      // Header row
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Row(children: [
          const Expanded(child: Text('ITEM NAME', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700))),
          Text('QTY', style: const TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
        ])),
      const Divider(height: 1),
      ...items.asMap().entries.map((e) {
        final i    = e.key;
        final item = e.value;
        final qty  = int.tryParse(item['qty']?.toString() ?? '0') ?? 0;
        final pct  = maxQty > 0 ? qty / maxQty : 0.0;
        final clr  = AppColors.chartColors[i % AppColors.chartColors.length];
        return Column(children: [
          if (i > 0) const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 24, height: 24,
                  decoration: BoxDecoration(color: clr.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                  child: Center(child: Text('${i + 1}',
                      style: TextStyle(color: clr, fontSize: 10, fontWeight: FontWeight.w700)))),
                const SizedBox(width: 10),
                Expanded(child: Text(item['name']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: clr.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                  child: Text('× $qty', style: TextStyle(color: clr, fontSize: 13, fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 6),
              ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct.clamp(0.0, 1.0),
                  backgroundColor: AppColors.bgCardAlt,
                  valueColor: AlwaysStoppedAnimation(clr),
                  minHeight: 4)),
            ])),
        ]);
      }),
      const SizedBox(height: 6),
    ]);
  }
}

// ── Cashier/Admin/Waiter: Orders Detail ───────────────────────
class _CashierOrdersDetail extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final NumberFormat curr;
  final Color color;
  const _CashierOrdersDetail({required this.orders, required this.curr, required this.color});

  String _ft(String? raw) {
    try { return DateFormat('dd-MM-yyyy  hh:mm a').format(DateTime.parse(raw!).toLocal()); } catch (_) { return raw ?? ''; }
  }
  String _ty(String? t) {
    switch (t) { case 'dine_in': return 'Dine In'; case 'takeaway': return 'Takeaway'; default: return t ?? ''; }
  }

  @override
  Widget build(BuildContext context) {
    final shown = orders.take(30).toList(); // cap at 30 rows
    return Column(children: [
      // Column headers
      Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: Row(children: [
          const SizedBox(width: 80, child: Text('ORDER ID', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          const Expanded(child: Text('TYPE / DATE', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700))),
          const SizedBox(width: 65, child: Text('STATUS', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700))),
          const Text('TOTAL', style: TextStyle(color: AppColors.textMuted, fontSize: 9, fontWeight: FontWeight.w700)),
        ])),
      const Divider(height: 1),
      ...shown.asMap().entries.map((e) {
        final i = e.key;
        final o = e.value;
        final isPaid = o['payment_status'] == 'paid';
        final status = o['status']?.toString().toUpperCase() ?? (isPaid ? 'PAID' : 'UNPAID');
        final total  = double.tryParse(o['total']?.toString() ?? '0') ?? 0;
        final sc     = status == 'DELIVERED' || isPaid ? AppColors.success : (status == 'CANCELLED' ? AppColors.error : AppColors.warning);
        return Column(children: [
          if (i > 0) const Divider(height: 1),
          Padding(padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
            child: Row(children: [
              // Order badge
              Container(width: 80,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(color: sc.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
                child: Text('#${o['order_number'] ?? ''}',
                    style: TextStyle(color: sc, fontSize: 9, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_ty(o['order_type']?.toString())} · ${o['items_qty'] ?? 0} items',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
                Text(_ft(o['created_at']?.toString()),
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
              ])),
              Container(
                width: 65,
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                  child: Text(status, style: TextStyle(color: sc, fontSize: 8, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                ),
              ),
              const SizedBox(width: 6),
              Text('LKR ${curr.format(total)}',
                  style: TextStyle(color: isPaid ? AppColors.primary : AppColors.textMuted,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ])),
        ]);
      }),
      if (orders.length > 30)
        Padding(padding: const EdgeInsets.all(10),
          child: Text('+ ${orders.length - 30} more orders (see PDF for full list)',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10), textAlign: TextAlign.center)),
      const SizedBox(height: 6),
    ]);
  }
}




// ─────────────────────────────────────────────────────────────
//  RAW MATERIALS TAB
// ─────────────────────────────────────────────────────────────

class _RawTab extends StatelessWidget {
  final List<IngredientModel> ingredients;
  final VoidCallback onSave;
  const _RawTab({required this.ingredients, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (ingredients.isEmpty) return _Empty('No ingredients data found');
    final low = ingredients.where((i) => i.isLowStock).length;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 100), children: [
      _SaveBar(label: 'Raw Materials Report', onSave: onSave),
      const SizedBox(height: 12),
      if (low > 0)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withOpacity(0.3))),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Text('$low item${low > 1 ? 's' : ''} low on stock',
                style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ).animate().fadeIn(duration: 250.ms),

      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(color: AppColors.bgCardAlt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        child: const Row(children: [
          Expanded(flex: 3, child: Text('Ingredient', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(flex: 2, child: Text('Stock', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 50, child: Text('Status', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
        ]),
      ),
      Container(
        decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
            border: Border.all(color: AppColors.border)),
        child: Column(children: ingredients.asMap().entries.map((e) {
          final i   = e.key;
          final ing = e.value;
          final lw  = ing.isLowStock;
          return Column(children: [
            if (i > 0) const Divider(height: 1),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(children: [
                Expanded(flex: 3, child: Text(ing.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                Expanded(flex: 2, child: Text('${ing.stockQty.toStringAsFixed(1)} ${ing.unit}',
                    style: TextStyle(color: lw ? AppColors.error : AppColors.textSecondary,
                      fontSize: 12, fontWeight: lw ? FontWeight.w700 : FontWeight.w400))),
                Container(width: 50, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: (lw ? AppColors.error : AppColors.success).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5)),
                  child: Text(lw ? 'LOW' : 'OK',
                    style: TextStyle(color: lw ? AppColors.error : AppColors.success,
                      fontSize: 9, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
              ])),
          ]);
        }).toList()),
      ).animate().fadeIn(duration: 300.ms, delay: 60.ms),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  ALL ORDERS TAB
// ─────────────────────────────────────────────────────────────
class _AllOrdersTab extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final NumberFormat curr;
  final double Function(dynamic) toD;
  final String Function(dynamic) ty;
  final String Function(String) fd;
  final VoidCallback onSave;
  const _AllOrdersTab({required this.orders, required this.curr, required this.toD,
    required this.ty, required this.fd, required this.onSave});
  @override
  State<_AllOrdersTab> createState() => _AllOrdersTabState();
}

class _AllOrdersTabState extends State<_AllOrdersTab> {
  String _q = '';
  String _f = 'all';

  List<Map<String, dynamic>> get _filtered => widget.orders.where((o) {
    final no = o['order_number']?.toString().toLowerCase() ?? '';
    final cn = o['cashier_name']?.toString().toLowerCase() ?? '';
    final ok = _q.isEmpty || no.contains(_q.toLowerCase()) || cn.contains(_q.toLowerCase());
    final ps = o['payment_status']?.toString() ?? '';
    final st = o['status']?.toString() ?? '';
    final fk = _f == 'all' ||
        (_f == 'paid'      && ps == 'paid') ||
        (_f == 'unpaid'    && ps != 'paid' && st != 'cancelled') ||
        (_f == 'cancelled' && st == 'cancelled');
    return ok && fk;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Column(children: [
      Container(color: AppColors.bgPrimary, padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(children: [
          Expanded(child: TextField(
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search order # or cashier...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.search_rounded, size: 18, color: AppColors.textMuted),
              isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
            ),
            onChanged: (v) => setState(() => _q = v),
          )),
          const SizedBox(width: 8),
          DropdownButton<String>(value: _f,
            dropdownColor: AppColors.bgCard,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'all',       child: Text('All')),
              DropdownMenuItem(value: 'paid',      child: Text('Paid')),
              DropdownMenuItem(value: 'unpaid',    child: Text('Unpaid')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: (v) => setState(() => _f = v!)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: _SaveBar(label: 'All Orders (${list.length})', onSave: widget.onSave)),
      Expanded(child: list.isEmpty
          ? _Empty('No orders match the filter')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final o = list[i];
                final paid      = o['payment_status'] == 'paid';
                final cancelled = o['status'] == 'cancelled';
                final sc = cancelled ? AppColors.error : paid ? AppColors.success : AppColors.warning;
                return InkWell(
                  onTap: () {
                    final orderId = o['id'] ?? o['order_id'] ?? o['order_number'];
                    if (orderId != null) OrderDetailsDialog.show(context, orderId);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(o['order_number']?.toString() ?? '',
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 12)),
                          const SizedBox(width: 6),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: sc.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                            child: Text(cancelled ? 'CANCELLED' : paid ? 'PAID' : 'UNPAID',
                                style: TextStyle(color: sc, fontSize: 8, fontWeight: FontWeight.w700))),
                        ]),
                        const SizedBox(height: 2),
                        Text('${widget.ty(o['order_type'])} · ${o['cashier_name'] ?? ''} · ${widget.fd(o['created_at']?.toString() ?? '')}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                      ])),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('LKR ${widget.curr.format(widget.toD(o['total']))}',
                            style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                        _PayBadge(o['payment_method']?.toString()),
                      ]),
                    ]),
                  ),
                ).animate(key: ValueKey(o['id'])).fadeIn(duration: 180.ms);
              }),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────────────────────
class _SaveBar extends StatelessWidget {
  final String label;
  final VoidCallback onSave;
  const _SaveBar({required this.label, required this.onSave});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border)),
    child: Row(children: [
      const Icon(Icons.picture_as_pdf_rounded, color: AppColors.error, size: 20),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
      ElevatedButton.icon(
        onPressed: onSave,
        icon: const Icon(Icons.download_rounded, size: 14),
        label: const Text('Save PDF', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary, foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
      ),
    ]),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final Color color;
  const _StatCard(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _NumChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _NumChip(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(children: [
      Text('$value', style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
      Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
    ]),
  );
}

class _TypeRow extends StatelessWidget {
  final String label;
  final int count, total;
  final Color color;
  final IconData icon;
  const _TypeRow(this.label, this.count, this.total, this.color, this.icon);
  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 8),
      SizedBox(width: 70, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct, backgroundColor: AppColors.bgCardAlt,
            valueColor: AlwaysStoppedAnimation(color), minHeight: 7))),
      const SizedBox(width: 10),
      Text('$count', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _PayBadge extends StatelessWidget {
  final String? method;
  const _PayBadge(this.method);
  @override
  Widget build(BuildContext context) {
    final m = method?.toLowerCase() ?? 'cash';
    final c = m == 'card' ? AppColors.info : m == 'credit' ? AppColors.warning : AppColors.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
      child: Text(m.toUpperCase(), style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.w700)),
    );
  }
}

class _ErrView extends StatelessWidget {
  final String msg;
  final VoidCallback onRetry;
  const _ErrView({required this.msg, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 52),
      const SizedBox(height: 12),
      Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      ElevatedButton.icon(onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Retry')),
    ]),
  ));
}

class _Empty extends StatelessWidget {
  final String msg;
  const _Empty(this.msg);
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.bar_chart_rounded, size: 52, color: AppColors.textMuted.withOpacity(0.3)),
    const SizedBox(height: 12),
    Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
  ]));
}
