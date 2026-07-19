import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../core/api_service.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();
  bool _loading = false;
  List<Map<String, dynamic>> _orders = [];
  final _curr = NumberFormat('#,##0.00', 'en_US');
  final _num = NumberFormat('#,##0', 'en_US');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; });
    try {
      final fromStr = DateFormat('yyyy-MM-dd').format(_from);
      final toStr = DateFormat('yyyy-MM-dd').format(_to);
      final data = await ApiService.instance.getOrdersByDate(fromStr, toStr);
      setState(() { _orders = data; _loading = false; });
    } catch (_) {
      setState(() { _loading = false; });
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateRange(_from, _to),
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

  // Computed stats from orders
  double get _totalRevenue => _paidOrders.fold(0, (s, o) =>
      s + (double.tryParse(o['total']?.toString() ?? '0') ?? 0));
  double get _cashRevenue => _paidOrders
      .where((o) => o['payment_method'] == 'cash')
      .fold(0, (s, o) => s + (double.tryParse(o['total']?.toString() ?? '0') ?? 0));
  double get _cardRevenue => _paidOrders
      .where((o) => o['payment_method'] == 'card')
      .fold(0, (s, o) => s + (double.tryParse(o['total']?.toString() ?? '0') ?? 0));
  double get _creditRevenue => _paidOrders
      .where((o) => o['payment_method'] == 'credit')
      .fold(0, (s, o) => s + (double.tryParse(o['total']?.toString() ?? '0') ?? 0));
  List<Map<String, dynamic>> get _paidOrders =>
      _orders.where((o) => o['payment_status'] == 'paid').toList();

  // Revenue per day
  Map<String, double> get _revenueByDay {
    final map = <String, double>{};
    for (final o in _paidOrders) {
      final date = o['created_at']?.toString().split('T').first ??
          o['created_at']?.toString().split(' ').first ?? '';
      final total = double.tryParse(o['total']?.toString() ?? '0') ?? 0;
      map[date] = (map[date] ?? 0) + total;
    }
    return map;
  }

  // Top products
  List<Map<String, dynamic>> get _topProducts {
    final map = <String, Map<String, dynamic>>{};
    for (final o in _paidOrders) {
      if (o['items'] is List) {
        for (final item in o['items'] as List) {
          final name = item['product_name']?.toString() ?? 'Unknown';
          final qty = (item['quantity'] as num?)?.toInt() ?? 1;
          final price = (item['price'] as num?)?.toDouble() ?? 0;
          map[name] ??= {'name': name, 'qty': 0, 'revenue': 0.0};
          map[name]!['qty'] = (map[name]!['qty'] as int) + qty;
          map[name]!['revenue'] =
              (map[name]!['revenue'] as double) + price * qty;
        }
      }
    }
    final list = map.values.toList()
      ..sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dayCount = _to.difference(_from).inDays + 1;
    final days = List.generate(dayCount, (i) =>
        DateFormat('yyyy-MM-dd').format(_from.add(Duration(days: i))));
    final revenueByDay = _revenueByDay;
    final chartSpots = days.asMap().entries.map((e) =>
        FlSpot(e.key.toDouble(), revenueByDay[e.value] ?? 0)).toList();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Sales Reports'),
        actions: [
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range_rounded, size: 16, color: AppColors.primary),
            label: Text(
              '${DateFormat('MMM d').format(_from)} – ${DateFormat('MMM d').format(_to)}',
              style: const TextStyle(color: AppColors.primary, fontSize: 13),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.bgCard,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  // Revenue hero
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A1400), Color(0xFF0D1120)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Total Revenue',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                        const SizedBox(height: 8),
                        Text('LKR ${_curr.format(_totalRevenue)}',
                            style: const TextStyle(
                                color: AppColors.primary, fontSize: 32,
                                fontWeight: FontWeight.w800, letterSpacing: -1)),
                        const SizedBox(height: 4),
                        Text('${_paidOrders.length} paid orders over $dayCount days',
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: 16),

                  // Payment breakdown
                  Row(children: [
                    Expanded(child: _miniCard('Cash', _cashRevenue, AppColors.success)),
                    const SizedBox(width: 10),
                    Expanded(child: _miniCard('Card', _cardRevenue, AppColors.info)),
                    const SizedBox(width: 10),
                    Expanded(child: _miniCard('Credit', _creditRevenue, AppColors.warning)),
                  ]).animate().fadeIn(duration: 400.ms, delay: 100.ms),

                  const SizedBox(height: 20),

                  // Revenue chart
                  if (chartSpots.length > 1) ...[
                    const Text('Revenue Trend',
                        style: TextStyle(color: AppColors.textPrimary,
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Container(
                      height: 220,
                      padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            getDrawingHorizontalLine: (v) => FlLine(
                              color: AppColors.border,
                              strokeWidth: 1,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 56,
                                getTitlesWidget: (v, m) => Text(
                                  v >= 1000
                                      ? '${(v / 1000).toStringAsFixed(0)}k'
                                      : v.toStringAsFixed(0),
                                  style: const TextStyle(
                                      color: AppColors.textMuted, fontSize: 10),
                                ),
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                interval: (chartSpots.length / 5).ceilToDouble().clamp(1, 10),
                                getTitlesWidget: (v, m) {
                                  final idx = v.toInt();
                                  if (idx < 0 || idx >= days.length) return const SizedBox();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      DateFormat('d/M').format(
                                          DateFormat('yyyy-MM-dd').parse(days[idx])),
                                      style: const TextStyle(
                                          color: AppColors.textMuted, fontSize: 9),
                                    ),
                                  );
                                },
                              ),
                            ),
                            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: chartSpots,
                              isCurved: true,
                              curveSmoothness: 0.35,
                              color: AppColors.primary,
                              barWidth: 2.5,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                gradient: LinearGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.2),
                                    AppColors.primary.withOpacity(0),
                                  ],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(duration: 500.ms, delay: 150.ms),
                    const SizedBox(height: 20),
                  ],

                  // Order type breakdown
                  const Text('Order Types',
                      style: TextStyle(color: AppColors.textPrimary,
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  _buildOrderTypes().animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  const SizedBox(height: 20),

                  // Top products
                  if (_topProducts.isNotEmpty) ...[
                    const Text('Top Products',
                        style: TextStyle(color: AppColors.textPrimary,
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    _buildTopProductsList().animate().fadeIn(duration: 400.ms, delay: 250.ms),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _miniCard(String label, double amount, Color color) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 6),
            Text('LKR ${_num.format(amount)}',
                style: TextStyle(
                    color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _buildOrderTypes() {
    final dineIn = _paidOrders.where((o) => o['order_type'] == 'dine_in').length;
    final takeaway = _paidOrders.where((o) => o['order_type'] == 'takeaway').length;
    final delivery = _paidOrders.where((o) => o['order_type'] == 'delivery').length;
    final total = _paidOrders.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _orderTypeRow('Dine In', dineIn, total, AppColors.success, Icons.restaurant_rounded),
          const SizedBox(height: 12),
          _orderTypeRow('Takeaway', takeaway, total, AppColors.info, Icons.takeout_dining_rounded),
          const SizedBox(height: 12),
          _orderTypeRow('Delivery', delivery, total, AppColors.primary, Icons.delivery_dining_rounded),
        ],
      ),
    );
  }

  Widget _orderTypeRow(String label, int count, int total, Color color, IconData icon) {
    final pct = total > 0 ? count / total : 0.0;
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        SizedBox(width: 70,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: AppColors.bgCardAlt,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 7,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text('$count', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildTopProductsList() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: _topProducts.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final color = AppColors.chartColors[i % AppColors.chartColors.length];
          return Column(
            children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(child: Text('${i + 1}',
                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(p['name']?.toString() ?? '',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${p['qty']} sold',
                            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                        Text('LKR ${_num.format(p['revenue'])}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class DateRange extends DateTimeRange {
  DateRange(DateTime start, DateTime end) : super(start: start, end: end);
}
