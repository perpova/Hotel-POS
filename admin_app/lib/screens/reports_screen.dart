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

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int _tabIndex = 0;
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();
  bool _loading = false;
  bool _pdfLoading = false;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  List<IngredientModel> _ingredients = [];

  final _tabs = ['Sales', 'By Cashier', 'By Item', 'Raw Materials', 'All Orders'];
  final _curr = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_from);
      final toStr   = DateFormat('yyyy-MM-dd').format(_to);
      final orders  = await ApiService.instance.getOrdersByDate(fromStr, toStr);
      final ings    = await ApiService.instance.getIngredients();
      if (!mounted) return;
      setState(() {
        _orders      = orders;
        _ingredients = ings;
        _loading     = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: now,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primary,
            onPrimary: Colors.black,
            surface: AppColors.bgCard,
            onSurface: AppColors.textPrimary,
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

  // ── Computed ──────────────────────────────────────────────────
  double _toD(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  List<Map<String, dynamic>> get _paid =>
      _orders.where((o) => o['payment_status'] == 'paid').toList();

  double get _totalRevenue => _paid.fold(0.0, (s, o) => s + _toD(o['total']));

  Map<String, List<Map<String, dynamic>>> get _byCashier {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final o in _paid) {
      final name = o['cashier_name']?.toString() ?? 'Unknown';
      map.putIfAbsent(name, () => []).add(o);
    }
    return map;
  }

  List<Map<String, dynamic>> get _itemStats {
    final map = <String, Map<String, dynamic>>{};
    for (final o in _paid) {
      if (o['items'] is List) {
        for (final item in o['items'] as List) {
          final name  = item['product_name']?.toString() ?? '?';
          final qty   = (item['quantity']  as num?)?.toInt()    ?? 1;
          final price = (item['price']     as num?)?.toDouble() ?? 0;
          map[name] ??= {'name': name, 'qty': 0, 'revenue': 0.0};
          map[name]!['qty']     = (map[name]!['qty']     as int)    + qty;
          map[name]!['revenue'] = (map[name]!['revenue'] as double) + price * qty;
        }
      }
    }
    return map.values.toList()
      ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
  }

  // ── PDF Save ──────────────────────────────────────────────────
  Future<void> _savePdf(Future<Uint8List> Function() builder, String name) async {
    setState(() => _pdfLoading = true);
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
      setState(() => _pdfLoading = false);
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
      setState(() => _pdfLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF error: $e'), backgroundColor: AppColors.error));
    }
  }

  // ── PDF Builders ──────────────────────────────────────────────
  pw.Widget _pdfHeader(String title) {
    final range = '${DateFormat('yyyy-MM-dd').format(_from)} to ${DateFormat('yyyy-MM-dd').format(_to)}';
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('HOTEL POS', style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600, letterSpacing: 1.5)),
      pw.SizedBox(height: 4),
      pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
      pw.Text('Period: $range', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
      pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      pw.Divider(thickness: 1.5, color: PdfColors.amber700),
      pw.SizedBox(height: 8),
    ]);
  }

  pw.Widget _pdfTable(List<String> headers, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: headers, data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9, color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
        cellStyle: const pw.TextStyle(fontSize: 8),
        rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.amber50),
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: PdfColors.grey300),
          verticalInside:   pw.BorderSide(color: PdfColors.grey300),
          left: pw.BorderSide(color: PdfColors.grey400),
          right: pw.BorderSide(color: PdfColors.grey400),
          top: pw.BorderSide(color: PdfColors.grey400),
          bottom: pw.BorderSide(color: PdfColors.grey400),
        ),
      );

  Future<Uint8List> _buildSalesPdf() async {
    final doc = pw.Document();
    final cash   = _paid.where((o) => o['payment_method'] == 'cash'  ).fold(0.0, (s, o) => s + _toD(o['total']));
    final card   = _paid.where((o) => o['payment_method'] == 'card'  ).fold(0.0, (s, o) => s + _toD(o['total']));
    final credit = _paid.where((o) => o['payment_method'] == 'credit').fold(0.0, (s, o) => s + _toD(o['total']));
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _pdfHeader('Sales Summary Report'),
      pw.Row(children: [
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _kv('Total Revenue', 'LKR ${_curr.format(_totalRevenue)}'),
          _kv('Total Orders',  '${_orders.length}'),
          _kv('Paid Orders',   '${_paid.length}'),
        ])),
        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          _kv('Cash',   'LKR ${_curr.format(cash)}'),
          _kv('Card',   'LKR ${_curr.format(card)}'),
          _kv('Credit', 'LKR ${_curr.format(credit)}'),
        ])),
      ]),
      pw.SizedBox(height: 12),
    ]));
    return doc.save();
  }

  Future<Uint8List> _buildCashierPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _pdfHeader('Orders by Cashier'),
      ..._byCashier.entries.expand((e) {
        final rev = e.value.fold(0.0, (s, o) => s + _toD(o['total']));
        return [
          pw.Container(color: PdfColors.amber100, padding: const pw.EdgeInsets.all(5),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(e.key, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.Text('${e.value.length} orders · LKR ${_curr.format(rev)}', style: const pw.TextStyle(fontSize: 10)),
            ])),
          pw.SizedBox(height: 4),
          _pdfTable(['Order #', 'Time', 'Type', 'Total (LKR)'],
            e.value.map((o) => [
              o['order_number']?.toString() ?? '',
              _fmtTime(o['created_at']?.toString() ?? ''),
              _typeStr(o['order_type']),
              _curr.format(_toD(o['total'])),
            ]).toList()),
          pw.SizedBox(height: 10),
        ];
      }),
    ]));
    return doc.save();
  }

  Future<Uint8List> _buildItemsPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _pdfHeader('Sales by Menu Item'),
      _pdfTable(['#', 'Item', 'Qty Sold', 'Revenue (LKR)'],
        _itemStats.asMap().entries.map((e) => [
          '${e.key + 1}', e.value['name'].toString(),
          '${e.value['qty']}', _curr.format(e.value['revenue']),
        ]).toList()),
    ]));
    return doc.save();
  }

  Future<Uint8List> _buildRawPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _pdfHeader('Raw Materials Stock'),
      _pdfTable(['Ingredient', 'Stock', 'Unit', 'Min Level', 'Status'],
        _ingredients.map((i) => [
          i.name, i.stockQty.toStringAsFixed(2), i.unit,
          i.minStockLevel.toStringAsFixed(2), i.isLowStock ? 'LOW' : 'OK',
        ]).toList()),
    ]));
    return doc.save();
  }

  Future<Uint8List> _buildAllOrdersPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(32), build: (c) => [
      _pdfHeader('All Orders'),
      _pdfTable(['Order #', 'Date', 'Cashier', 'Type', 'Method', 'Total (LKR)', 'Status'],
        _orders.map((o) => [
          o['order_number']?.toString() ?? '',
          _fmtDate(o['created_at']?.toString() ?? ''),
          o['cashier_name']?.toString() ?? '',
          _typeStr(o['order_type']),
          (o['payment_method']?.toString() ?? 'cash').toUpperCase(),
          _curr.format(_toD(o['total'])),
          (o['payment_status']?.toString() ?? '').toUpperCase(),
        ]).toList()),
    ]));
    return doc.save();
  }

  pw.Widget _kv(String k, String v) => pw.Padding(padding: const pw.EdgeInsets.only(bottom: 3), child:
    pw.Row(children: [
      pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700))),
      pw.Text(v, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
    ]));

  String _fmtTime(String raw) {
    try { return DateFormat('HH:mm').format(DateTime.parse(raw).toLocal()); } catch (_) { return raw; }
  }
  String _fmtDate(String raw) {
    try { return DateFormat('yyyy-MM-dd').format(DateTime.parse(raw).toLocal()); } catch (_) { return raw; }
  }
  String _typeStr(dynamic t) {
    switch (t?.toString()) {
      case 'dine_in':  return 'Dine In';
      case 'takeaway': return 'Takeaway';
      case 'delivery': return 'Delivery';
      default:         return t?.toString() ?? '';
    }
  }

  // ── UI ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          if (_pdfLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))),
            ),
          TextButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_month_rounded, size: 15, color: AppColors.primary),
            label: Text(
              '${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM').format(_to)}',
              style: const TextStyle(color: AppColors.primary, fontSize: 11),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab row ────────────────────────────────────────────
          Container(
            color: AppColors.bgPrimary,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: List.generate(_tabs.length, (i) {
                  final sel = i == _tabIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _tabIndex = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary : AppColors.bgCardAlt,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.primary : AppColors.border),
                        ),
                        child: Text(_tabs[i], style: TextStyle(
                          color: sel ? Colors.black : AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                        )),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : _error != null
                    ? _buildError()
                    : _buildTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildError() => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 48),
    const SizedBox(height: 12),
    Text(_error ?? 'Load error', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
    const SizedBox(height: 16),
    ElevatedButton(onPressed: _load, child: const Text('Retry')),
  ]));

  Widget _buildTab() {
    switch (_tabIndex) {
      case 0: return _SalesTab(orders: _orders, paid: _paid, curr: _curr, toD: _toD, from: _from, to: _to,
                  onSave: () => _savePdf(_buildSalesPdf, 'sales_report'));
      case 1: return _CashierTab(byCashier: _byCashier, curr: _curr, toD: _toD,
                  typeStr: _typeStr, fmtTime: _fmtTime,
                  onSave: () => _savePdf(_buildCashierPdf, 'cashier_report'));
      case 2: return _ItemsTab(itemStats: _itemStats, curr: _curr,
                  onSave: () => _savePdf(_buildItemsPdf, 'items_report'));
      case 3: return _RawTab(ingredients: _ingredients,
                  onSave: () => _savePdf(_buildRawPdf, 'raw_materials'));
      case 4: return _AllOrdersTab(orders: _orders, curr: _curr, toD: _toD,
                  typeStr: _typeStr, fmtDate: _fmtDate,
                  onSave: () => _savePdf(_buildAllOrdersPdf, 'all_orders'));
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
    final total   = paid.fold(0.0, (s, o) => s + toD(o['total']));
    final cash    = paid.where((o) => o['payment_method'] == 'cash'  ).fold(0.0, (s, o) => s + toD(o['total']));
    final card    = paid.where((o) => o['payment_method'] == 'card'  ).fold(0.0, (s, o) => s + toD(o['total']));
    final credit  = paid.where((o) => o['payment_method'] == 'credit').fold(0.0, (s, o) => s + toD(o['total']));
    final dineIn  = paid.where((o) => o['order_type'] == 'dine_in' ).length;
    final take    = paid.where((o) => o['order_type'] == 'takeaway').length;
    final del     = paid.where((o) => o['order_type'] == 'delivery').length;
    final days    = to.difference(from).inDays + 1;
    // Build day list + revenue per day map
    final dayList  = List.generate(days, (i) => DateFormat('yyyy-MM-dd').format(from.add(Duration(days: i))));
    final revByDay = <String, double>{};
    for (final o in paid) {
      final raw = o['created_at']?.toString() ?? '';
      final d   = raw.length >= 10 ? raw.substring(0, 10) : '';
      if (d.isNotEmpty) revByDay[d] = (revByDay[d] ?? 0) + toD(o['total']);
    }
    final maxRev = revByDay.values.fold(0.0, (m, v) => v > m ? v : m);

    return RefreshIndicator(
      color: AppColors.primary, backgroundColor: AppColors.bgCard,
      onRefresh: () async {},
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
        children: [
          _SaveBar(label: 'Sales Summary Report', onSave: onSave),
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
          ).animate().fadeIn(duration: 350.ms),

          const SizedBox(height: 12),

          // Payment method cards
          Row(children: [
            Expanded(child: _StatCard('Cash',   'LKR ${curr.format(cash)}',   AppColors.success)),
            const SizedBox(width: 8),
            Expanded(child: _StatCard('Card',   'LKR ${curr.format(card)}',   AppColors.info)),
            const SizedBox(width: 8),
            Expanded(child: _StatCard('Credit', 'LKR ${curr.format(credit)}', AppColors.warning)),
          ]).animate().fadeIn(duration: 350.ms, delay: 80.ms),

          const SizedBox(height: 12),

          // Order status row
          Row(children: [
            Expanded(child: _NumChip('Total',     orders.length, AppColors.textSecondary)),
            const SizedBox(width: 8),
            Expanded(child: _NumChip('Paid',      paid.length,   AppColors.success)),
            const SizedBox(width: 8),
            Expanded(child: _NumChip('Cancelled', orders.where((o) => o['status'] == 'cancelled').length, AppColors.error)),
          ]).animate().fadeIn(duration: 350.ms, delay: 120.ms),

          const SizedBox(height: 20),

          // ── Daily Revenue Chart ──────────────────────────
          const Text('Daily Revenue', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (dayList.length > 1 && maxRev > 0)
            Container(
              height: 200,
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: BarChart(
                BarChartData(
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
                          final dt = DateFormat('yyyy-MM-dd').parse(dayList[idx]);
                          return Padding(padding: const EdgeInsets.only(top: 4),
                            child: Text(DateFormat('d/M').format(dt),
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 9)));
                        } catch (_) { return const SizedBox(); }
                      },
                    )),
                  ),
                  barGroups: dayList.asMap().entries.map((e) {
                    final rev = revByDay[e.value] ?? 0.0;
                    return BarChartGroupData(x: e.key, barRods: [
                      BarChartRodData(
                        toY: rev, width: days > 14 ? 6 : 12,
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: [AppColors.primary.withOpacity(0.6), AppColors.primary],
                          begin: Alignment.bottomCenter, end: Alignment.topCenter),
                      ),
                    ]);
                  }).toList(),
                ),
              ),
            ).animate().fadeIn(duration: 400.ms, delay: 140.ms)
          else
            Container(
              height: 80,
              decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border)),
              child: const Center(child: Text('No revenue data to chart',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
            ),
          const SizedBox(height: 20),

          const Text('Order Types', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border)),
            child: Column(children: [
              _TypeRow('Dine In',   dineIn, paid.length, AppColors.success, Icons.restaurant_rounded),
              const SizedBox(height: 10),
              _TypeRow('Takeaway',  take,   paid.length, AppColors.info,    Icons.takeout_dining_rounded),
              const SizedBox(height: 10),
              _TypeRow('Delivery',  del,    paid.length, AppColors.primary, Icons.delivery_dining_rounded),
            ]),
          ).animate().fadeIn(duration: 350.ms, delay: 160.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CASHIER TAB
// ─────────────────────────────────────────────────────────────
class _CashierTab extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> byCashier;
  final NumberFormat curr;
  final double Function(dynamic) toD;
  final String Function(dynamic) typeStr;
  final String Function(String) fmtTime;
  final VoidCallback onSave;

  const _CashierTab({required this.byCashier, required this.curr, required this.toD,
    required this.typeStr, required this.fmtTime, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (byCashier.isEmpty) return _EmptyMsg('No cashier data for this period');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        _SaveBar(label: 'Cashier Report', onSave: onSave),
        const SizedBox(height: 14),
        ...byCashier.entries.map((entry) {
          final rev = entry.value.fold(0.0, (s, o) => s + toD(o['total']));
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
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
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: entry.value.take(30).toList().asMap().entries.map((e) {
                final o = e.value;
                return Column(children: [
                  if (e.key > 0) const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(o['order_number']?.toString() ?? '',
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('${typeStr(o['order_type'])} · ${fmtTime(o['created_at']?.toString() ?? '')}',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                      ])),
                      _PayBadge(o['payment_method']?.toString()),
                      const SizedBox(width: 8),
                      Text('LKR ${curr.format(toD(o['total']))}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                ]);
              }).toList()),
            ),
            const SizedBox(height: 14),
          ]);
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ITEMS TAB
// ─────────────────────────────────────────────────────────────
class _ItemsTab extends StatelessWidget {
  final List<Map<String, dynamic>> itemStats;
  final NumberFormat curr;
  final VoidCallback onSave;

  const _ItemsTab({required this.itemStats, required this.curr, required this.onSave});

  @override
  Widget build(BuildContext context) {
    if (itemStats.isEmpty) return _EmptyMsg('No item sales data');
    final maxQty = itemStats.isNotEmpty ? (itemStats[0]['qty'] as int).toDouble() : 1.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        _SaveBar(label: 'Item Sales Report', onSave: onSave),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Column(children: itemStats.asMap().entries.map((e) {
            final i    = e.key;
            final item = e.value;
            final qty  = (item['qty'] as int).toDouble();
            final color = AppColors.chartColors[i % AppColors.chartColors.length];
            return Column(children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
                      Text('LKR ${curr.format(item['revenue'])}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    ]),
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: qty / maxQty,
                        backgroundColor: AppColors.bgCardAlt,
                        valueColor: AlwaysStoppedAnimation(color), minHeight: 5)),
                ]),
              ),
            ]);
          }).toList()),
        ).animate().fadeIn(duration: 350.ms),
      ],
    );
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
    if (ingredients.isEmpty) return _EmptyMsg('No ingredients found');
    final low = ingredients.where((i) => i.isLowStock).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
      children: [
        _SaveBar(label: 'Raw Materials Report', onSave: onSave),
        const SizedBox(height: 12),
        if (low > 0)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
              const SizedBox(width: 8),
              Text('$low item${low > 1 ? 's' : ''} low on stock',
                  style: const TextStyle(color: AppColors.error, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ).animate().fadeIn(duration: 250.ms),
        Container(
          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border)),
          child: Column(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(color: AppColors.bgCardAlt,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14))),
              child: const Row(children: [
                Expanded(flex: 3, child: Text('Ingredient', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text('Stock', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 50, child: Text('Status', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600))),
              ]),
            ),
            ...ingredients.asMap().entries.map((e) {
              final i   = e.key;
              final ing = e.value;
              final low = ing.isLowStock;
              return Column(children: [
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(children: [
                    Expanded(flex: 3, child: Text(ing.name,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                    Expanded(flex: 2, child: Text('${ing.stockQty.toStringAsFixed(1)} ${ing.unit}',
                        style: TextStyle(color: low ? AppColors.error : AppColors.textSecondary,
                            fontSize: 12, fontWeight: low ? FontWeight.w700 : FontWeight.w400))),
                    Container(width: 50, padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                          color: (low ? AppColors.error : AppColors.success).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(5)),
                      child: Text(low ? 'LOW' : 'OK',
                          style: TextStyle(color: low ? AppColors.error : AppColors.success,
                              fontSize: 9, fontWeight: FontWeight.w700),
                          textAlign: TextAlign.center)),
                  ]),
                ),
              ]);
            }),
          ]),
        ).animate().fadeIn(duration: 350.ms, delay: 80.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  ALL ORDERS TAB
// ─────────────────────────────────────────────────────────────
class _AllOrdersTab extends StatefulWidget {
  final List<Map<String, dynamic>> orders;
  final NumberFormat curr;
  final double Function(dynamic) toD;
  final String Function(dynamic) typeStr;
  final String Function(String) fmtDate;
  final VoidCallback onSave;

  const _AllOrdersTab({required this.orders, required this.curr, required this.toD,
    required this.typeStr, required this.fmtDate, required this.onSave});

  @override
  State<_AllOrdersTab> createState() => _AllOrdersTabState();
}

class _AllOrdersTabState extends State<_AllOrdersTab> {
  String _search = '';
  String _filter = 'all';

  List<Map<String, dynamic>> get _filtered => widget.orders.where((o) {
    final no = o['order_number']?.toString().toLowerCase() ?? '';
    final cs = o['cashier_name']?.toString().toLowerCase()  ?? '';
    final ok = _search.isEmpty || no.contains(_search.toLowerCase()) || cs.contains(_search.toLowerCase());
    final ps = o['payment_status']?.toString() ?? '';
    final st = o['status']?.toString() ?? '';
    final fk = _filter == 'all' ||
        (_filter == 'paid'      && ps == 'paid') ||
        (_filter == 'unpaid'    && ps != 'paid' && st != 'cancelled') ||
        (_filter == 'cancelled' && st == 'cancelled');
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
            onChanged: (v) => setState(() => _search = v),
          )),
          const SizedBox(width: 8),
          DropdownButton<String>(value: _filter,
            dropdownColor: AppColors.bgCard,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 'all',       child: Text('All')),
              DropdownMenuItem(value: 'paid',      child: Text('Paid')),
              DropdownMenuItem(value: 'unpaid',    child: Text('Unpaid')),
              DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
            ],
            onChanged: (v) => setState(() => _filter = v!)),
        ]),
      ),
      Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        child: _SaveBar(label: 'All Orders (${list.length})', onSave: widget.onSave)),
      Expanded(child: list.isEmpty
          ? _EmptyMsg('No orders match the filter')
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 100),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final o = list[i];
                final isPaid      = o['payment_status'] == 'paid';
                final isCancelled = o['status'] == 'cancelled';
                final sc = isCancelled ? AppColors.error : isPaid ? AppColors.success : AppColors.warning;
                return Container(
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
                          child: Text(isCancelled ? 'CANCELLED' : isPaid ? 'PAID' : 'UNPAID',
                              style: TextStyle(color: sc, fontSize: 8, fontWeight: FontWeight.w700))),
                      ]),
                      const SizedBox(height: 2),
                      Text('${widget.typeStr(o['order_type'])} · ${o['cashier_name'] ?? ''} · ${widget.fmtDate(o['created_at']?.toString() ?? '')}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                    ])),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('LKR ${widget.curr.format(widget.toD(o['total']))}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                      _PayBadge(o['payment_method']?.toString()),
                    ]),
                  ]),
                ).animate(key: ValueKey(o['id'])).fadeIn(duration: 200.ms);
              }),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────
//  SHARED SMALL WIDGETS
// ─────────────────────────────────────────────────────────────
class _SaveBar extends StatelessWidget {
  final String label;
  final VoidCallback onSave;
  const _SaveBar({required this.label, required this.onSave});

  @override
  Widget build(BuildContext context) {
    return Container(
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

class _EmptyMsg extends StatelessWidget {
  final String msg;
  const _EmptyMsg(this.msg);

  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.bar_chart_rounded, size: 52, color: AppColors.textMuted.withOpacity(0.3)),
    const SizedBox(height: 12),
    Text(msg, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
  ]));
}
