import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/theme.dart';
import '../providers/dashboard_provider.dart';
import '../providers/realtime_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/order_details_dialog.dart';
import '../core/update_service.dart';
import '../widgets/update_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _curr = NumberFormat('#,##0.00', 'en_US');
  final _num  = NumberFormat('#,##0',    'en_US');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAutoUpdate();
    });
  }

  Future<void> _checkAutoUpdate() async {
    try {
      final info = await UpdateService.instance.checkForUpdate(manual: false);
      if (info.hasUpdate && mounted) {
        UpdateDialog.show(context, info);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final auth = context.watch<AuthProvider>();
    final now  = DateFormat('EEEE, MMM d').format(DateTime.now());
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good Morning' : hour < 17 ? 'Good Afternoon' : 'Good Evening';

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.bgCard,
        onRefresh: () => dash.load(),
        child: CustomScrollView(slivers: [
          // ── App Bar ─────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            expandedHeight: 120,
            backgroundColor: AppColors.bgPrimary,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16, right: 16),
              title: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$greeting, ${auth.currentUser?.name.split(' ').first ?? 'Admin'}',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
                Text(now, style: const TextStyle(fontSize: 16, color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              ]),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [AppColors.bgPrimary, AppColors.bgDeep],
                      begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              ),
            ),
            actions: [
              if (dash.isLoading)
                const Padding(padding: EdgeInsets.only(right: 16),
                  child: Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))))
              else
                IconButton(icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
                    onPressed: () => dash.load()),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Revenue Hero (TAPPABLE) ──────────────────
                _RevenueHero(revenue: dash.todayRevenue, paid: dash.paidOrders, curr: _curr)
                    .animate().fadeIn(duration: 500.ms).slideY(begin: 0.1, end: 0),
                const SizedBox(height: 16),

                // ── Stat Cards ───────────────────────────────
                _buildStatRow(dash).animate().fadeIn(duration: 500.ms, delay: 100.ms),
                const SizedBox(height: 16),

                // ── Payment Breakdown ────────────────────────
                _buildPaymentBreakdown(dash).animate().fadeIn(duration: 500.ms, delay: 150.ms),
                const SizedBox(height: 16),

                // ── Top Products ─────────────────────────────
                if (dash.topProducts.isNotEmpty) ...[
                  _sectionTitle('Top Products Today'),
                  const SizedBox(height: 12),
                  _buildTopProducts(dash).animate().fadeIn(duration: 500.ms, delay: 200.ms),
                  const SizedBox(height: 16),
                ],

                // ── Table Grid ───────────────────────────────
                if (dash.tables.isNotEmpty) ...[
                  _sectionTitle('Table Status'),
                  const SizedBox(height: 12),
                  _buildTableGrid(dash).animate().fadeIn(duration: 500.ms, delay: 250.ms),
                  const SizedBox(height: 16),
                ],

                // ── Recent Orders ────────────────────────────
                if (dash.recentOrders.isNotEmpty) ...[
                  _sectionTitle('Recent Orders'),
                  const SizedBox(height: 12),
                  _buildRecentOrders(dash).animate().fadeIn(duration: 500.ms, delay: 300.ms),
                ],

                const SizedBox(height: 100),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStatRow(DashboardProvider dash) => Row(children: [
    Expanded(child: _statCard(label: 'Total Orders', value: _num.format(dash.totalOrders), icon: Icons.receipt_long_rounded, color: AppColors.info)),
    const SizedBox(width: 12),
    Expanded(child: _statCard(label: 'Active', value: _num.format(dash.unpaidOrders), icon: Icons.pending_actions_rounded, color: AppColors.warning)),
    const SizedBox(width: 12),
    Expanded(child: _statCard(label: 'Paid', value: _num.format(dash.paidOrders), icon: Icons.check_circle_outline_rounded, color: AppColors.success)),
  ]);

  Widget _statCard({required String label, required String value, required IconData icon, required Color color}) =>
    Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 10),
        Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ]),
    );

  Widget _buildPaymentBreakdown(DashboardProvider dash) {
    final total = dash.todayRevenue;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('Payment Breakdown'),
        const SizedBox(height: 16),
        _payRow('Cash',   dash.cashRevenue,   total, AppColors.success),
        const SizedBox(height: 10),
        _payRow('Card',   dash.cardRevenue,   total, AppColors.info),
        const SizedBox(height: 10),
        _payRow('Credit', dash.creditRevenue, total, AppColors.warning),
      ]),
    );
  }

  Widget _payRow(String label, double amount, double total, Color color) {
    final pct = total > 0 ? (amount / total) : 0.0;
    return Row(children: [
      SizedBox(width: 60, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
      const SizedBox(width: 8),
      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: pct.clamp(0.0, 1.0),
            backgroundColor: AppColors.bgCardAlt,
            valueColor: AlwaysStoppedAnimation(color), minHeight: 8))),
      const SizedBox(width: 10),
      Text('LKR ${NumberFormat('#,##0').format(amount)}',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _buildTopProducts(DashboardProvider dash) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(children: dash.topProducts.asMap().entries.map((e) {
      final i = e.key; final p = e.value;
      final color  = AppColors.chartColors[i % AppColors.chartColors.length];
      final maxQty = (dash.topProducts.first['qty'] as int).toDouble();
      final qty    = (p['qty'] as int).toDouble();
      return Padding(padding: EdgeInsets.only(bottom: i < dash.topProducts.length - 1 ? 14 : 0),
        child: Row(children: [
          Container(width: 24, height: 24,
            decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
            child: Center(child: Text('${i + 1}', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['name']?.toString() ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(value: maxQty > 0 ? (qty / maxQty) : 0,
                  backgroundColor: AppColors.bgCardAlt, valueColor: AlwaysStoppedAnimation(color), minHeight: 5)),
          ])),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${p['qty']} sold', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
            Text('LKR ${NumberFormat('#,##0').format(p['revenue'])}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ]),
        ]));
    }).toList()),
  );

  Widget _buildTableGrid(DashboardProvider dash) => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.1),
    itemCount: dash.tables.length,
    itemBuilder: (ctx, i) {
      final t = dash.tables[i];
      final status   = t['status']?.toString() ?? 'empty';
      final isActive = t['active_status'] == 'active';
      if (!isActive) return const SizedBox.shrink();
      Color color; IconData icon;
      switch (status) {
        case 'seated':  color = AppColors.error;   icon = Icons.people_rounded;  break;
        case 'billing': color = AppColors.warning; icon = Icons.receipt_rounded; break;
        default:        color = AppColors.success; icon = Icons.chair_rounded;
      }
      return Container(
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3))),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(t['table_number']?.toString() ?? '?',
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ]),
      );
    },
  );

  Widget _buildRecentOrders(DashboardProvider dash) => Container(
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border)),
    child: Column(children: dash.recentOrders.take(8).toList().asMap().entries.map((e) {
      final i = e.key; final o = e.value;
      final isPaid      = o['payment_status'] == 'paid';
      final isCancelled = o['status'] == 'cancelled';
      final orderType   = o['order_type']?.toString() ?? '';
      final total       = double.tryParse(o['total']?.toString() ?? '0') ?? 0;
      final sc = isCancelled ? AppColors.error : isPaid ? AppColors.success : AppColors.warning;
      return Column(children: [
        if (i > 0) const Divider(height: 1),
        InkWell(
          onTap: () {
            final orderId = o['id'] ?? o['order_id'] ?? o['order_number'];
            if (orderId != null) OrderDetailsDialog.show(context, orderId);
          },
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: sc.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Text('#${o['order_number'] ?? ''}', style: TextStyle(color: sc, fontSize: 11, fontWeight: FontWeight.w700))),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(orderType == 'dine_in' ? 'Dine In${o['table_number'] != null ? ' · T${o['table_number']}' : ''}' :
                     orderType == 'takeaway' ? 'Takeaway' : 'Delivery',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
                Text(isCancelled ? 'Cancelled' : isPaid ? 'Paid · ${o['payment_method']?.toString().toUpperCase() ?? ''}' : 'Active',
                    style: TextStyle(color: sc, fontSize: 11)),
              ])),
              Text('LKR ${_curr.format(total)}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            ])),
        ),
      ]);
    }).toList()),
  );

  Widget _sectionTitle(String t) => Text(t, style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700));
}

// ─────────────────────────────────────────────────────────────
//  REVENUE HERO — tappable, opens TransactionDetailSheet
// ─────────────────────────────────────────────────────────────
class _RevenueHero extends StatelessWidget {
  final double revenue;
  final int    paid;
  final NumberFormat curr;
  const _RevenueHero({required this.revenue, required this.paid, required this.curr});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _TransactionDetailSheet.show(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(colors: [Color(0xFF1A1400), Color(0xFF0D1120)],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.primaryGlow, borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.monetization_on_rounded, color: AppColors.primary, size: 20)),
            const SizedBox(width: 10),
            const Text("Today's Revenue",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
            const Spacer(),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('View Details', style: TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                SizedBox(width: 3),
                Icon(Icons.chevron_right_rounded, color: AppColors.primary, size: 14),
              ])),
          ]),
          const SizedBox(height: 14),
          Text('LKR ${curr.format(revenue)}',
              style: const TextStyle(color: AppColors.primary, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1)),
          const SizedBox(height: 4),
          Text('$paid paid orders today',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  TRANSACTION DETAIL BOTTOM SHEET
// ─────────────────────────────────────────────────────────────
class _TransactionDetailSheet extends StatefulWidget {
  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TransactionDetailSheet(),
    );
  }
  const _TransactionDetailSheet();
  @override
  State<_TransactionDetailSheet> createState() => _TransactionDetailSheetState();
}

class _TransactionDetailSheetState extends State<_TransactionDetailSheet> {
  bool   _loading = false;
  String _err     = '';
  DateTime _from  = DateTime.now();
  DateTime _to    = DateTime.now();

  Map<String, dynamic> _data = {
    'total_revenue': 0, 'by_cash': 0, 'by_card': 0, 'by_credit': 0,
    'count': 0, 'transactions': []
  };

  final _curr = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _err = ''; });
    try {
      final fs = DateFormat('yyyy-MM-dd').format(_from);
      final ts = DateFormat('yyyy-MM-dd').format(_to);
      final d  = await ApiService.instance.getTransactions(fs, ts);
      if (!mounted) return;
      setState(() { _data = d; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _err = e.toString(); _loading = false; });
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.dark(
          primary: AppColors.primary, onPrimary: Colors.black,
          surface: AppColors.bgCard, onSurface: AppColors.textPrimary,
        )),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() { _from = picked.start; _to = picked.end; });
      _load();
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

  String _ft(String r) { try { return DateFormat('HH:mm').format(DateTime.parse(r).toLocal()); } catch (_) { return r; } }
  String _fd(String r) { try { return DateFormat('d MMM').format(DateTime.parse(r).toLocal()); } catch (_) { return r; } }
  String _ty(dynamic t) { switch (t?.toString()) { case 'dine_in': return 'Dine In'; case 'takeaway': return 'Takeaway'; default: return t?.toString() ?? ''; } }

  @override
  Widget build(BuildContext context) {
    final txns = _data['transactions'];
    final list = txns is List ? txns.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];
    final total  = _d(_data['total_revenue']);
    final byCash = _d(_data['by_cash']);
    final byCard = _d(_data['by_card']);
    final byCredit = _d(_data['by_credit']);
    final isSingleDay = _from.year == _to.year && _from.month == _to.month && _from.day == _to.day;
    final rangeLabel = isSingleDay
        ? DateFormat('d MMM yyyy').format(_from)
        : '${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM').format(_to)}';

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.bgPrimary,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          // Handle
          Container(margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),

          // Header row
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Transaction Details', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(rangeLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ])),
              // Date range button
              GestureDetector(
                onTap: _pickRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                      color: AppColors.bgCard, borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.date_range_rounded, color: AppColors.primary, size: 15),
                    const SizedBox(width: 5),
                    Text(rangeLabel, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          Expanded(child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _err.isNotEmpty
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 40),
                      const SizedBox(height: 8),
                      Text(_err, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Retry')),
                    ]))
                  : ListView(controller: ctrl, padding: const EdgeInsets.fromLTRB(16, 0, 16, 40), children: [
                      // ── Summary Cards ─────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1A1400), Color(0xFF0D1120)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Total Revenue', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          const SizedBox(height: 6),
                          Text('LKR ${_curr.format(total)}',
                              style: const TextStyle(color: AppColors.primary, fontSize: 28, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${list.length} transactions', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // Cash / Card / Credit breakdown
                      Row(children: [
                        Expanded(child: _SummCard('Cash', byCash, AppColors.success, Icons.money_rounded)),
                        const SizedBox(width: 8),
                        Expanded(child: _SummCard('Card', byCard, AppColors.info, Icons.credit_card_rounded)),
                        const SizedBox(width: 8),
                        Expanded(child: _SummCard('Credit', byCredit, AppColors.warning, Icons.account_balance_rounded)),
                      ]),
                      const SizedBox(height: 20),

                      // ── Transactions List ─────────────────
                      Row(children: [
                        const Text('All Transactions', style: TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${list.length} records', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ]),
                      const SizedBox(height: 10),

                      if (list.isEmpty)
                        Container(padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12)),
                          child: const Center(child: Text('No transactions for this period',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 13))))
                      else
                        Container(
                          decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.border)),
                          child: Column(children: list.asMap().entries.map((e) {
                            final i = e.key; final t = e.value;
                            final method = t['payment_method']?.toString() ?? 'cash';
                            final mc = method == 'card' ? AppColors.info : method == 'credit' ? AppColors.warning : AppColors.success;
                            return Column(children: [
                              if (i > 0) const Divider(height: 1),
                              InkWell(
                                onTap: () {
                                  final orderId = t['id'] ?? t['order_id'] ?? t['order_number'];
                                  if (orderId != null) OrderDetailsDialog.show(context, orderId);
                                },
                                child: Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                  child: Row(children: [
                                    // Method icon
                                    Container(width: 34, height: 34,
                                      decoration: BoxDecoration(color: mc.withOpacity(0.12), borderRadius: BorderRadius.circular(9)),
                                      child: Icon(method == 'card' ? Icons.credit_card_rounded :
                                                  method == 'credit' ? Icons.account_balance_rounded : Icons.money_rounded,
                                        color: mc, size: 17)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('#${t['order_number'] ?? ''}',
                                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
                                      Text('${_ty(t['order_type'])} · ${t['cashier_name'] ?? 'N/A'} · ${isSingleDay ? _ft(t['created_at']?.toString() ?? '') : _fd(t['created_at']?.toString() ?? '')}',
                                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                    ])),
                                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                                      Text('LKR ${_curr.format(_d(t['total']))}',
                                          style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                                      Container(margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: mc.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                                        child: Text(method.toUpperCase(), style: TextStyle(color: mc, fontSize: 8, fontWeight: FontWeight.w700))),
                                    ]),
                                  ])),
                              ),
                            ]);
                          }).toList()),
                        ),
                    ]),
          ),
        ]),
      ),
    );
  }
}

class _SummCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color  color;
  final IconData icon;
  const _SummCard(this.label, this.amount, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 6),
      Text('LKR ${NumberFormat('#,##0').format(amount)}',
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w800)),
    ]),
  );
}
