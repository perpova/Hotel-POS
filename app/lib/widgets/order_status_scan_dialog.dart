import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../theme.dart';
import '../pos_controller.dart';
import '../services/api_service.dart';

class OrderStatusScanDialog extends StatefulWidget {
  final OrderModel order;
  final String oldStatus;
  final String newStatus;
  final String statusChangeTime; // Formatted timestamp of barcode scan
  final String? cashierName;
  final String? stewardName;
  final String? tableName;

  const OrderStatusScanDialog({
    Key? key,
    required this.order,
    required this.oldStatus,
    required this.newStatus,
    required this.statusChangeTime,
    this.cashierName,
    this.stewardName,
    this.tableName,
  }) : super(key: key);

  static void show({
    required BuildContext context,
    required OrderModel order,
    required String oldStatus,
    required String newStatus,
    required String statusChangeTime,
    String? cashierName,
    String? stewardName,
    String? tableName,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => OrderStatusScanDialog(
        order: order,
        oldStatus: oldStatus,
        newStatus: newStatus,
        statusChangeTime: statusChangeTime,
        cashierName: cashierName,
        stewardName: stewardName,
        tableName: tableName,
      ),
    );
  }

  @override
  State<OrderStatusScanDialog> createState() => _OrderStatusScanDialogState();
}

class _OrderStatusScanDialogState extends State<OrderStatusScanDialog> {
  late String _currentStatus;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.newStatus;
  }

  Future<void> _updateStatus(String targetStatus) async {
    if (_isUpdating || widget.order.id == null) return;
    setState(() => _isUpdating = true);

    try {
      final api = APIService.instance;
      final isoNow = DateTime.now().toIso8601String();
      await api.updateOrderOnline(widget.order.id!, {
        'status': targetStatus,
        'updated_at': isoNow,
      });

      if (mounted) {
        final posController = Provider.of<POSController>(context, listen: false);
        await posController.reloadEnvironment();
      }

      setState(() {
        _currentStatus = targetStatus;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order #${widget.order.orderNumber} status changed to ${targetStatus.toUpperCase()}'),
            backgroundColor: targetStatus == 'cancelled' ? Colors.red : const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update order status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  void _confirmCancelOrder() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            Text('Cancel Order?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to cancel Order #${widget.order.orderNumber}? This will set the order status to CANCELLED.',
          style: GoogleFonts.inter(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('No, Keep Order'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus('cancelled');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Yes, Cancel Order'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDarkMode;
    final isStatusChanged = widget.oldStatus.toLowerCase() != _currentStatus.toLowerCase();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 620,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Bar with Icon and Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _currentStatus == 'cancelled'
                        ? Colors.red.withOpacity(0.15)
                        : (isStatusChanged
                            ? const Color(0xFF10B981).withOpacity(0.15)
                            : const Color(0xFF3B82F6).withOpacity(0.15)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _currentStatus == 'cancelled'
                        ? Icons.cancel_outlined
                        : (isStatusChanged ? Icons.published_with_changes_rounded : Icons.info_outline_rounded),
                    color: _currentStatus == 'cancelled'
                        ? Colors.red
                        : (isStatusChanged ? const Color(0xFF10B981) : const Color(0xFF3B82F6)),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentStatus == 'cancelled'
                            ? 'Order Cancelled'
                            : (isStatusChanged ? 'Order Status Updated!' : 'Order Details & Barcode Info'),
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppTheme.textLightPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Barcode Scanned Order Tracking',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF94A3B8) : AppTheme.textLightSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
                  hoverColor: Colors.red.withOpacity(0.1),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Divider(height: 1, color: isDark ? const Color(0xFF334155) : AppTheme.borderLight),
            const SizedBox(height: 16),

            // Scrollable Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Change Transition Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDark
                              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                              : [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Current Status: ',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF94A3B8) : AppTheme.textLightSecondary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildStatusBadge(_currentStatus, isDark, isHighlight: true),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Status Change Time Display
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time_filled_rounded, color: AppTheme.accent, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  'Scan & Status Change Time: ',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  widget.statusChangeTime,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Action Status Change Buttons for Cashier
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CHANGE ORDER STATUS:',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildStatusActionButton('PREPARING', 'preparing', Colors.orange, Icons.soup_kitchen_rounded),
                              _buildStatusActionButton('PREPARED', 'prepared', AppTheme.accent, Icons.done_all_rounded),
                              _buildStatusActionButton('DELIVERED', 'delivered', const Color(0xFF10B981), Icons.local_shipping_rounded),
                              OutlinedButton.icon(
                                onPressed: _isUpdating ? null : _confirmCancelOrder,
                                icon: const Icon(Icons.cancel_rounded, size: 16),
                                label: const Text('CANCEL ORDER'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                  side: const BorderSide(color: Colors.red, width: 1.5),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Order Info Grid (Order #, Type, Cashier, Waiter, Table/Token)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B).withOpacity(0.6) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoItem(
                                  'Order Number',
                                  widget.order.orderNumber,
                                  Icons.receipt_long_rounded,
                                  isDark,
                                  isBold: true,
                                ),
                              ),
                              Expanded(
                                child: _buildInfoItem(
                                  'Barcode Identifier',
                                  widget.order.barcode.isNotEmpty ? widget.order.barcode : widget.order.orderNumber,
                                  Icons.qr_code_rounded,
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildInfoItem(
                                  'Order Type',
                                  widget.order.orderType.toUpperCase().replaceAll('_', ' '),
                                  Icons.restaurant_rounded,
                                  isDark,
                                ),
                              ),
                              Expanded(
                                child: _buildInfoItem(
                                  'Table / Token',
                                  widget.tableName ?? (widget.order.tableId != null ? 'Table ${widget.order.tableId}' : 'Token #${_getQueueTokenNumber(widget.order)}'),
                                  Icons.table_restaurant_rounded,
                                  isDark,
                                ),
                              ),
                            ],
                          ),
                          if (widget.cashierName != null || widget.stewardName != null || widget.order.stewardName != null) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildInfoItem(
                                    'Cashier',
                                    widget.cashierName ?? 'Staff #${widget.order.cashierId}',
                                    Icons.person_pin_rounded,
                                    isDark,
                                  ),
                                ),
                                Expanded(
                                  child: _buildInfoItem(
                                    'Steward / Waiter',
                                    widget.stewardName ?? widget.order.stewardName ?? 'Unassigned',
                                    Icons.badge_rounded,
                                    isDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Order Items Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'ORDER ITEMS DETAILS',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            letterSpacing: 0.8,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${widget.order.items.fold(0, (sum, i) => sum + i.quantity)} Items',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Items List Container
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B).withOpacity(0.4) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF334155).withOpacity(0.5) : const Color(0xFFF1F5F9),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: Text('Item', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))),
                                ),
                                Expanded(
                                  flex: 1,
                                  child: Text('Qty', textAlign: TextAlign.center, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('Price', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('Total', textAlign: TextAlign.right, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569))),
                                ),
                              ],
                            ),
                          ),

                          // Table Rows
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: widget.order.items.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                            itemBuilder: (context, index) {
                              final item = widget.order.items[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 4,
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.productName,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark ? Colors.white : AppTheme.textLightPrimary,
                                                ),
                                              ),
                                              if (item.productSinhalaName != null && item.productSinhalaName!.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.productSinhalaName!,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: Text(
                                            '${item.quantity}',
                                            textAlign: TextAlign.center,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : AppTheme.textLightPrimary,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            '${item.price.toStringAsFixed(2)}',
                                            textAlign: TextAlign.right,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          flex: 2,
                                          child: Text(
                                            'LKR ${(item.price * item.quantity).toStringAsFixed(2)}',
                                            textAlign: TextAlign.right,
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : AppTheme.textLightPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (item.notes != null && item.notes!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.note_alt_outlined, size: 12, color: AppTheme.accent),
                                          const SizedBox(width: 4),
                                          Text(
                                            item.notes!,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: AppTheme.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Financial Summary Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Subtotal', style: GoogleFonts.inter(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                              Text('LKR ${widget.order.subtotal.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, color: isDark ? Colors.white : AppTheme.textLightPrimary)),
                            ],
                          ),
                          if (widget.order.discount > 0) ...[
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Discount', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFFEF4444))),
                                Text('- LKR ${widget.order.discount.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
                              ],
                            ),
                          ],
                          Divider(height: 18, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('TOTAL ORDER AMOUNT', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: isDark ? Colors.white : AppTheme.textLightPrimary)),
                              Text(
                                'LKR ${widget.order.total.toStringAsFixed(2)}',
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.accent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text('Payment Status: ', style: GoogleFonts.inter(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: widget.order.paymentStatus == 'paid' ? const Color(0xFF10B981).withOpacity(0.2) : AppTheme.warning.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      widget.order.paymentStatus.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: widget.order.paymentStatus == 'paid' ? const Color(0xFF10B981) : AppTheme.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.order.paymentMethod != null && widget.order.paymentMethod!.isNotEmpty)
                                Text(
                                  'Paid by ${widget.order.paymentMethod!.toUpperCase()}',
                                  style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Actions Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Close'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusActionButton(String label, String statusKey, Color color, IconData icon) {
    final isSelected = _currentStatus.toLowerCase() == statusKey.toLowerCase();
    return ElevatedButton.icon(
      onPressed: _isUpdating || isSelected ? null : () => _updateStatus(statusKey),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? color : color.withOpacity(0.15),
        foregroundColor: isSelected ? Colors.white : color,
        elevation: isSelected ? 2 : 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildStatusBadge(String status, bool isDark, {bool isHighlight = false}) {
    Color bg = Colors.grey.withOpacity(0.2);
    Color txt = Colors.grey;
    String label = status.toUpperCase();

    switch (status.toLowerCase()) {
      case 'pending':
        bg = AppTheme.warning.withOpacity(0.2);
        txt = AppTheme.warning;
        label = 'PENDING';
        break;
      case 'preparing':
        bg = Colors.orange.withOpacity(0.2);
        txt = Colors.orange;
        label = 'PREPARING';
        break;
      case 'prepared':
        bg = AppTheme.accent.withOpacity(0.2);
        txt = AppTheme.accent;
        label = 'READY / PREPARED';
        break;
      case 'delivered':
        bg = const Color(0xFF10B981).withOpacity(0.2);
        txt = const Color(0xFF10B981);
        label = 'DELIVERED';
        break;
      case 'cancelled':
        bg = Colors.red.withOpacity(0.2);
        txt = Colors.red;
        label = 'CANCELLED';
        break;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: EdgeInsets.symmetric(horizontal: isHighlight ? 14 : 10, vertical: isHighlight ? 8 : 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: isHighlight ? Border.all(color: txt, width: 1.5) : null,
        boxShadow: isHighlight
            ? [BoxShadow(color: txt.withOpacity(0.3), blurRadius: 8, spreadRadius: 1)]
            : null,
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: isHighlight ? 13 : 11,
          fontWeight: FontWeight.bold,
          color: txt,
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String val, IconData icon, bool isDark, {bool isBold = false}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(fontSize: 10, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
              ),
              Text(
                val,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: isDark ? Colors.white : AppTheme.textLightPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getQueueTokenNumber(OrderModel order) {
    if (order.id == null) return '000';
    final idStr = order.id.toString();
    if (idStr.length >= 3) {
      return idStr.substring(idStr.length - 3);
    }
    return idStr.padLeft(3, '0');
  }
}
