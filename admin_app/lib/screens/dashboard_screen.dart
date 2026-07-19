import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/theme.dart';
import '../providers/dashboard_provider.dart';
import '../providers/realtime_provider.dart';
import '../providers/auth_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _currFmt = NumberFormat('#,##0.00', 'en_US');
  final _numFmt = NumberFormat('#,##0', 'en_US');

  @override
  Widget build(BuildContext context) {
    final dash = context.watch<DashboardProvider>();
    final auth = context.watch<AuthProvider>();
    final now = DateFormat('EEEE, MMM d').format(DateTime.now());
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good Morning'
        : hour < 17
            ? 'Good Afternoon'
            : 'Good Evening';

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.bgCard,
        onRefresh: () => dash.load(),
        child: CustomScrollView(
          slivers: [
            // ── App Bar ───────────────────────────────────────────────
            SliverAppBar(
              pinned: true,
              expandedHeight: 120,
              backgroundColor: AppColors.bgPrimary,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding:
                    const EdgeInsets.only(left: 20, bottom: 16, right: 16),
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$greeting, ${auth.currentUser?.name.split(' ').first ?? 'Admin'}',
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w400),
                    ),
                    Text(
                      now,
                      style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.bgPrimary, AppColors.bgDeep],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              actions: [
                if (dash.isLoading)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      ),
                    ),
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.textSecondary),
                    onPressed: () => dash.load(),
                  ),
              ],
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Revenue Hero ─────────────────────────────────
                    _buildRevenueHero(dash)
                        .animate()
                        .fadeIn(duration: 500.ms)
                        .slideY(begin: 0.1, end: 0),

                    const SizedBox(height: 16),

                    // ── Stat Cards ───────────────────────────────────
                    _buildStatRow(dash)
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 100.ms),

                    const SizedBox(height: 16),

                    // ── Payment Breakdown ────────────────────────────
                    _buildPaymentBreakdown(dash)
                        .animate()
                        .fadeIn(duration: 500.ms, delay: 150.ms),

                    const SizedBox(height: 16),

                    // ── Top Products ─────────────────────────────────
                    if (dash.topProducts.isNotEmpty) ...[
                      _sectionTitle('Top Products Today'),
                      const SizedBox(height: 12),
                      _buildTopProducts(dash)
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 200.ms),
                      const SizedBox(height: 16),
                    ],

                    // ── Table Grid ───────────────────────────────────
                    if (dash.tables.isNotEmpty) ...[
                      _sectionTitle('Table Status'),
                      const SizedBox(height: 12),
                      _buildTableGrid(dash)
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 250.ms),
                      const SizedBox(height: 16),
                    ],

                    // ── Recent Orders ────────────────────────────────
                    if (dash.recentOrders.isNotEmpty) ...[
                      _sectionTitle('Recent Orders'),
                      const SizedBox(height: 12),
                      _buildRecentOrders(dash)
                          .animate()
                          .fadeIn(duration: 500.ms, delay: 300.ms),
                    ],

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRevenueHero(DashboardProvider dash) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1400), Color(0xFF0D1120)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryGlow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.monetization_on_rounded,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Today\'s Revenue',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'LKR ${_currFmt.format(dash.todayRevenue)}',
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${dash.paidOrders} paid orders',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(DashboardProvider dash) {
    return Row(
      children: [
        Expanded(
          child: _statCard(
            label: 'Total Orders',
            value: _numFmt.format(dash.totalOrders),
            icon: Icons.receipt_long_rounded,
            color: AppColors.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            label: 'Active',
            value: _numFmt.format(dash.unpaidOrders),
            icon: Icons.pending_actions_rounded,
            color: AppColors.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statCard(
            label: 'Paid',
            value: _numFmt.format(dash.paidOrders),
            icon: Icons.check_circle_outline_rounded,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }

  Widget _statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdown(DashboardProvider dash) {
    final total = dash.todayRevenue;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Payment Breakdown'),
          const SizedBox(height: 16),
          _payRow('Cash', dash.cashRevenue, total, AppColors.success),
          const SizedBox(height: 10),
          _payRow('Card', dash.cardRevenue, total, AppColors.info),
          const SizedBox(height: 10),
          _payRow('Credit', dash.creditRevenue, total, AppColors.warning),
        ],
      ),
    );
  }

  Widget _payRow(String label, double amount, double total, Color color) {
    final pct = total > 0 ? (amount / total) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: AppColors.bgCardAlt,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'LKR ${NumberFormat('#,##0').format(amount)}',
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildTopProducts(DashboardProvider dash) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: dash.topProducts.asMap().entries.map((e) {
          final i = e.key;
          final p = e.value;
          final color = AppColors.chartColors[i % AppColors.chartColors.length];
          final maxQty = (dash.topProducts.first['qty'] as int).toDouble();
          final qty = (p['qty'] as int).toDouble();
          return Padding(
            padding: EdgeInsets.only(
                bottom: i < dash.topProducts.length - 1 ? 14 : 0),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p['name']?.toString() ?? '',
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: maxQty > 0 ? (qty / maxQty) : 0,
                          backgroundColor: AppColors.bgCardAlt,
                          valueColor: AlwaysStoppedAnimation(color),
                          minHeight: 5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${p['qty']} sold',
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'LKR ${NumberFormat('#,##0').format(p['revenue'])}',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableGrid(DashboardProvider dash) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.1,
      ),
      itemCount: dash.tables.length,
      itemBuilder: (ctx, i) {
        final t = dash.tables[i];
        final status = t['status']?.toString() ?? 'empty';
        final isActive = t['active_status'] == 'active';
        if (!isActive) return const SizedBox.shrink();

        Color color;
        IconData icon;
        switch (status) {
          case 'seated':
            color = AppColors.error;
            icon = Icons.people_rounded;
            break;
          case 'billing':
            color = AppColors.warning;
            icon = Icons.receipt_rounded;
            break;
          default:
            color = AppColors.success;
            icon = Icons.chair_rounded;
        }

        return Container(
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 4),
              Text(
                t['table_number']?.toString() ?? '?',
                style: TextStyle(
                    color: color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecentOrders(DashboardProvider dash) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: dash.recentOrders.take(8).toList().asMap().entries.map((e) {
          final i = e.key;
          final o = e.value;
          final isPaid = o['payment_status'] == 'paid';
          final isCancelled = o['status'] == 'cancelled';
          final orderType = o['order_type']?.toString() ?? '';
          final total = double.tryParse(o['total']?.toString() ?? '0') ?? 0;

          Color statusColor;
          if (isCancelled) statusColor = AppColors.error;
          else if (isPaid) statusColor = AppColors.success;
          else statusColor = AppColors.warning;

          return Column(
            children: [
              if (i > 0) const Divider(height: 1),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${o['order_number']?.toString() ?? ''}',
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            orderType == 'dine_in'
                                ? 'Dine In${o['table_number'] != null ? ' · T${o['table_number']}' : ''}'
                                : orderType == 'takeaway'
                                    ? 'Takeaway'
                                    : 'Delivery',
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                          ),
                          Text(
                            isCancelled
                                ? 'Cancelled'
                                : isPaid
                                    ? 'Paid · ${o['payment_method']?.toString().toUpperCase() ?? ''}'
                                    : 'Active',
                            style: TextStyle(
                                color: statusColor, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      'LKR ${_currFmt.format(total)}',
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
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

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700),
      );
}
