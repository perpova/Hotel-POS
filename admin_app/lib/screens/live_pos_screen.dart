import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/live_pos_provider.dart';
import '../providers/realtime_provider.dart';
import '../models/models.dart';

class LivePosScreen extends StatelessWidget {
  const LivePosScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<LivePosProvider>();
    final realtime = context.watch<RealtimeProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Live POS Monitor',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            Text(
              '${prov.activeCount} active · ${prov.paidCount} paid · ${prov.totalCount} total today',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          if (prov.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => prov.load(),
            ),
          // LIVE dot
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success, shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scaleXY(begin: 1, end: 1.6, duration: 700.ms)
                    .then()
                    .scaleXY(begin: 1.6, end: 1, duration: 700.ms),
                const SizedBox(width: 4),
                const Text('LIVE',
                    style: TextStyle(
                        color: AppColors.success, fontSize: 10,
                        fontWeight: FontWeight.w700, letterSpacing: 1)),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── REAL-TIME POS MIRROR ──────────────────────────────
          _LiveMirrorBanner(state: realtime.livePosState),

          // ── Filter chips ─────────────────────────────────────
          _buildFilters(prov),

          // ── Orders list ──────────────────────────────────────
          Expanded(
            child: prov.isLoading && prov.orders.isEmpty
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : prov.error != null
                    ? _buildError(prov)
                    : prov.orders.isEmpty
                        ? _buildEmpty()
                        : RefreshIndicator(
                            color: AppColors.primary,
                            backgroundColor: AppColors.bgCard,
                            onRefresh: () => prov.load(),
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                              itemCount: prov.orders.length,
                              itemBuilder: (ctx, i) =>
                                  _OrderCard(order: prov.orders[i])
                                      .animate(key: ValueKey(prov.orders[i].id))
                                      .fadeIn(duration: 300.ms)
                                      .slideX(begin: 0.05, end: 0),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(LivePosProvider prov) {
    final filters = [
      ('all', 'All'),
      ('active', 'Active'),
      ('paid', 'Paid'),
      ('cancelled', 'Cancelled'),
      ('dine_in', 'Dine In'),
      ('takeaway', 'Takeaway'),
    ];
    return Container(
      color: AppColors.bgPrimary,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((f) {
            final isSelected = prov.filter == f.$1;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => prov.setFilter(f.$1),
                child: AnimatedContainer(
                  duration: 200.ms,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.bgCardAlt,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
                  ),
                  child: Text(
                    f.$2,
                    style: TextStyle(
                      color: isSelected ? Colors.black : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildError(LivePosProvider prov) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 48),
            const SizedBox(height: 12),
            Text(prov.error ?? 'Connection error',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () => prov.load(), child: const Text('Retry')),
          ],
        ),
      );

  Widget _buildEmpty() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                color: AppColors.textMuted.withOpacity(0.4), size: 56),
            const SizedBox(height: 12),
            const Text('No orders today',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 16)),
            const SizedBox(height: 4),
            const Text('Orders will appear here in real time',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ],
        ),
      );
}

// ── LIVE MIRROR BANNER ─────────────────────────────────────────────────────
class _LiveMirrorBanner extends StatelessWidget {
  final Map<String, dynamic>? state;
  const _LiveMirrorBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    if (state == null) return const SizedBox.shrink();

    final fmt = NumberFormat('#,##0.00', 'en_US');
    final items = (state!['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    final total = (state!['total'] as num?)?.toDouble() ?? 0;
    final subtotal = (state!['subtotal'] as num?)?.toDouble() ?? 0;
    final discount = (state!['discount'] as num?)?.toDouble() ?? 0;
    final receivedAmount = (state!['received_amount'] as num?)?.toDouble();
    final cashier = state!['cashier']?.toString() ?? 'Cashier';
    final orderType = state!['order_type']?.toString() ?? '';
    final table = state!['table']?.toString();
    final tsStr = state!['timestamp']?.toString() ?? '';
    DateTime? ts;
    try { ts = DateTime.parse(tsStr).toLocal(); } catch (_) {}

    final isPaying = receivedAmount != null && receivedAmount > 0;
    final change = isPaying ? (receivedAmount! - total).clamp(0.0, double.infinity) : 0.0;

    return AnimatedSize(
      duration: 300.ms,
      curve: Curves.easeInOut,
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isPaying
                ? [const Color(0xFF0A1F0A), const Color(0xFF0D1120)]
                : [const Color(0xFF1A1000), const Color(0xFF0D1120)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isPaying
                ? AppColors.success.withOpacity(0.5)
                : AppColors.primary.withOpacity(0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: (isPaying ? AppColors.success : AppColors.primary).withOpacity(0.1),
              blurRadius: 20, offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  // Pulsing dot
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(
                      color: isPaying ? AppColors.success : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .scaleXY(begin: 1, end: 1.8, duration: 600.ms)
                      .then()
                      .scaleXY(begin: 1.8, end: 1, duration: 600.ms),
                  const SizedBox(width: 6),
                  Text(
                    isPaying ? 'PAYMENT IN PROGRESS' : 'CASHIER SCREEN LIVE',
                    style: TextStyle(
                      color: isPaying ? AppColors.success : AppColors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  // Order type badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bgCardAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      orderType == 'dine_in'
                          ? 'Dine In${table != null ? ' · T$table' : ''}'
                          : orderType == 'takeaway' ? 'Takeaway' : 'Delivery',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 10),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.person_outline_rounded, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 3),
                  Text(cashier,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),

            // ── Item list ──────────────────────────────────────
            if (items.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...items.take(6).toList().asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                final name = item['product_name']?.toString() ?? '';
                final qty = (item['quantity'] as num?)?.toInt() ?? 1;
                final price = (item['price'] as num?)?.toDouble() ?? 0;
                final status = item['status']?.toString() ?? 'pending';
                final color = AppColors.chartColors[i % AppColors.chartColors.length];
                final isPreparing = status == 'preparing';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Center(
                          child: Text('$qty',
                              style: TextStyle(
                                  color: color, fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(name,
                            style: TextStyle(
                              color: isPreparing
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              decoration: isPreparing
                                  ? TextDecoration.none
                                  : TextDecoration.none,
                            ),
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isPreparing)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.info.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('KDS',
                              style: TextStyle(
                                  color: AppColors.info, fontSize: 8,
                                  fontWeight: FontWeight.w700)),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        'LKR ${fmt.format(price * qty)}',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }),
              if (items.length > 6)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                  child: Text('+${items.length - 6} more items',
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 11)),
                ),
            ] else
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Text('Cart is empty',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),

            // ── Totals / Payment area ───────────────────────────
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  if (discount > 0) ...[
                    _summaryRow('Subtotal', 'LKR ${fmt.format(subtotal)}',
                        AppColors.textSecondary),
                    const SizedBox(height: 4),
                    _summaryRow('Discount', '- LKR ${fmt.format(discount)}',
                        AppColors.warning),
                    const Divider(height: 12, color: Color(0xFF2A2A3A)),
                  ],
                  _summaryRow('TOTAL', 'LKR ${fmt.format(total)}',
                      AppColors.primary, big: true),

                  if (isPaying) ...[
                    const Divider(height: 14, color: Color(0xFF2A2A3A)),
                    _summaryRow(
                      'RECEIVED',
                      'LKR ${fmt.format(receivedAmount!)}',
                      AppColors.success, big: true,
                    ),
                    const SizedBox(height: 4),
                    _summaryRow(
                      'CHANGE',
                      'LKR ${fmt.format(change)}',
                      change > 0 ? AppColors.success : AppColors.textMuted,
                    ),
                  ],
                ],
              ),
            ),

            // Timestamp
            if (ts != null)
              Padding(
                padding: const EdgeInsets.only(right: 14, bottom: 8),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Updated ${DateFormat('HH:mm:ss').format(ts)}',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 9),
                  ),
                ),
              ),
          ],
        ),
      ).animate(key: ValueKey(state.hashCode)).fadeIn(duration: 200.ms),
    );
  }

  Widget _summaryRow(String label, String value, Color color,
      {bool big = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(
              color: big ? color : AppColors.textSecondary,
              fontSize: big ? 13 : 12,
              fontWeight: big ? FontWeight.w700 : FontWeight.w400,
              letterSpacing: big ? 0.5 : 0,
            )),
        Text(value,
            style: TextStyle(
              color: color,
              fontSize: big ? 15 : 12,
              fontWeight: big ? FontWeight.w800 : FontWeight.w500,
            )),
      ],
    );
  }
}

// ── ORDER CARD ─────────────────────────────────────────────────────────────
class _OrderCard extends StatefulWidget {
  final OrderSummary order;
  const _OrderCard({required this.order});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;
  final _fmt = NumberFormat('#,##0.00', 'en_US');

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (o.isCancelled) {
      statusColor = AppColors.error;
      statusLabel = 'CANCELLED';
      statusIcon = Icons.cancel_outlined;
    } else if (o.isPaid) {
      statusColor = AppColors.success;
      statusLabel = 'PAID';
      statusIcon = Icons.check_circle_outline;
    } else {
      statusColor = AppColors.warning;
      statusLabel = 'ACTIVE';
      statusIcon = Icons.pending_outlined;
    }

    Color typeColor;
    IconData typeIcon;
    switch (o.orderType) {
      case 'takeaway':
        typeColor = AppColors.info;
        typeIcon = Icons.takeout_dining_rounded;
        break;
      case 'delivery':
        typeColor = AppColors.primary;
        typeIcon = Icons.delivery_dining_rounded;
        break;
      default:
        typeColor = AppColors.success;
        typeIcon = Icons.restaurant_rounded;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: AnimatedContainer(
          duration: 250.ms,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _expanded
                  ? statusColor.withOpacity(0.4)
                  : AppColors.border,
            ),
            boxShadow: _expanded
                ? [
                    BoxShadow(
                        color: statusColor.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [],
          ),
          child: Column(
            children: [
              // Header row
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(typeIcon, color: typeColor, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('#${o.orderNumber}',
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, color: statusColor, size: 10),
                                    const SizedBox(width: 3),
                                    Text(statusLabel,
                                        style: TextStyle(
                                            color: statusColor,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 0.5)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${o.displayType}${o.tableNumber != null ? ' · Table ${o.tableNumber}' : ''}',
                            style: const TextStyle(
                                color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'LKR ${_fmt.format(o.total)}',
                          style: TextStyle(
                              color: o.isPaid
                                  ? AppColors.success
                                  : AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w700),
                        ),
                        if (o.paymentMethod != null && o.isPaid)
                          Text(o.paymentMethod!.toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.textMuted, fontSize: 10)),
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: AppColors.textMuted,
                          size: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Expanded items
              if (_expanded && o.items.isNotEmpty) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ORDER ITEMS',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10,
                              letterSpacing: 1,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      ...o.items.map((item) {
                        final qty = item['quantity'] ?? 1;
                        final name = item['product_name']?.toString() ?? '';
                        final price =
                            double.tryParse(item['price']?.toString() ?? '0') ?? 0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: AppColors.bgCardAlt,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Center(
                                  child: Text('$qty',
                                      style: const TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(name,
                                    style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 13)),
                              ),
                              Text('LKR ${_fmt.format(price * qty)}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                            ],
                          ),
                        );
                      }),
                      if (o.discount > 0) ...[
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Discount',
                                style: TextStyle(
                                    color: AppColors.textSecondary, fontSize: 12)),
                            Text('- LKR ${_fmt.format(o.discount)}',
                                style: const TextStyle(
                                    color: AppColors.warning, fontSize: 12)),
                          ],
                        ),
                      ],
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TOTAL',
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5)),
                          Text('LKR ${_fmt.format(o.total)}',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
