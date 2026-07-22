import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/api_service.dart';
import '../core/theme.dart';

class OrderDetailsDialog extends StatefulWidget {
  final dynamic orderId;

  const OrderDetailsDialog({Key? key, required this.orderId}) : super(key: key);

  static void show(BuildContext context, dynamic orderId) {
    showDialog(
      context: context,
      builder: (ctx) => OrderDetailsDialog(orderId: orderId),
    );
  }

  @override
  State<OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<OrderDetailsDialog> {
  bool _loading = true;
  String _err = '';
  Map<String, dynamic>? _order;

  final _curr = NumberFormat('#,##0.00', 'en_US');

  @override
  void initState() {
    super.initState();
    _loadOrder();
  }

  Future<void> _loadOrder() async {
    setState(() {
      _loading = true;
      _err = '';
    });
    try {
      final res = await ApiService.instance.getOrderDetails(widget.orderId);
      if (mounted) {
        setState(() {
          _order = res;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _err = e.toString();
          _loading = false;
        });
      }
    }
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.all(18),
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.primary)))
            : _err.isNotEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 36),
                        const SizedBox(height: 10),
                        Text(_err, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        ElevatedButton(
                          onPressed: _loadOrder,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _order == null
                    ? const Center(child: Text('Order not found'))
                    : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final o = _order!;
    final String orderNum = o['order_number']?.toString() ?? 'N/A';
    final String orderType = o['order_type']?.toString() ?? 'dine_in';
    final String status = o['status']?.toString() ?? 'completed';
    final String payStatus = o['payment_status']?.toString() ?? 'paid';
    final String payMethod = o['payment_method']?.toString() ?? 'cash';
    final String cashier = o['cashier_name'] ?? o['created_by_name'] ?? 'Staff';
    final String createdAt = o['created_at']?.toString() ?? '';
    final int? tableNum = o['table_number'] is int ? o['table_number'] : int.tryParse(o['table_number']?.toString() ?? '');
    final String? custName = o['customer_name'];
    final String? custPhone = o['customer_phone'];

    final List items = o['items'] is List ? o['items'] : [];

    final double subtotal = _parseDouble(o['subtotal']);
    final double discount = _parseDouble(o['discount']);
    final double tax = _parseDouble(o['tax']);
    final double serviceCharge = _parseDouble(o['service_charge']);
    final double grandTotal = _parseDouble(o['total']);

    final bool isPaid = payStatus == 'paid';
    final bool isCancelled = status == 'cancelled';
    final Color statusColor = isCancelled ? AppColors.error : (isPaid ? AppColors.success : AppColors.warning);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '#$orderNum',
                          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor.withOpacity(0.3)),
                        ),
                        child: Text(
                          isCancelled ? 'CANCELLED' : (isPaid ? 'PAID' : 'UNPAID'),
                          style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Order Type: ${orderType.toUpperCase().replaceAll('_', ' ')}${tableNum != null ? ' (Table $tableNum)' : ''}',
                    style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20, color: AppColors.textMuted),
              onPressed: () => Navigator.pop(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const Divider(height: 16, color: AppColors.border),

        // Order Meta Details Container (2-row responsive grid)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgDeep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildMetaCol('Cashier / Staff', cashier)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetaCol('Payment Method', payMethod.toUpperCase())),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: AppColors.border),
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildMetaCol(
                      'Date & Time',
                      createdAt.length >= 16 ? createdAt.substring(0, 16).replaceAll('T', ' ') : (createdAt.isNotEmpty ? createdAt : 'N/A'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetaCol(
                      'Table / Type',
                      tableNum != null ? 'Table $tableNum' : orderType.toUpperCase().replaceAll('_', ' '),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (custName != null && custName.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_rounded, size: 15, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Customer: $custName ${custPhone != null && custPhone.isNotEmpty ? '($custPhone)' : ''}',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Ordered Items List Header
        Text(
          'ORDERED ITEMS (${items.length})',
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textMuted, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),

        // Ordered Items List
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: items.isEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(16), child: Text('No item details available', style: GoogleFonts.inter(fontSize: 12, color: AppColors.textMuted))))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
                    itemBuilder: (ctx, i) {
                      final item = items[i];
                      final name = item['product_name'] ?? item['name'] ?? 'Item';
                      final qty = _parseDouble(item['quantity']);
                      final unitPrice = _parseDouble(item['unit_price'] ?? item['price']);
                      final total = _parseDouble(item['subtotal'] ?? item['total_price'] ?? (qty * unitPrice));
                      final notes = item['notes']?.toString();

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${qty.toInt()}x',
                                style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (notes != null && notes.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text('Note: $notes', style: GoogleFonts.inter(fontSize: 10, color: AppColors.warning)),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'LKR ${_curr.format(total)}',
                                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                                ),
                                Text(
                                  '@ LKR ${_curr.format(unitPrice)}',
                                  style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),

        // Financial Calculation Summary
        _buildSummaryRow('Subtotal', subtotal),
        if (discount > 0) _buildSummaryRow('Discount (-)', discount, color: AppColors.error),
        if (tax > 0) _buildSummaryRow('Tax (+)', tax),
        if (serviceCharge > 0) _buildSummaryRow('Service Charge (+)', serviceCharge),
        const Divider(height: 14, color: AppColors.border),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('GRAND TOTAL', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary)),
            Text(
              'LKR ${_curr.format(grandTotal > 0 ? grandTotal : subtotal)}',
              style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.primary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetaCol(String label, String val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(
          val,
          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double amt, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
          Text('LKR ${_curr.format(amt)}', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary)),
        ],
      ),
    );
  }
}
