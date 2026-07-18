import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import '../pos_controller.dart';
import '../controllers/dashboard_controller.dart';
import '../theme.dart';
import '../api_service.dart';
import '../services/translation_service.dart';
import '../widgets/image_helper.dart';
import '../models/models.dart';

class PreOrdersScreen extends StatefulWidget {
  const PreOrdersScreen({Key? key}) : super(key: key);

  @override
  State<PreOrdersScreen> createState() => _PreOrdersScreenState();
}

class _PreOrdersScreenState extends State<PreOrdersScreen> {
  String _searchQuery = '';
  bool _isLoading = false;
  String _selectedFilterTab = 'active'; // 'active', 'history'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final controller = Provider.of<POSController>(context, listen: false);
    await controller.fetchPreOrders();
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    // Filter preorders based on search query and status tab
    final filtered = controller.preOrders.where((po) {
      final status = po['status'] ?? 'pending';
      final isTabMatch = _selectedFilterTab == 'active'
          ? status == 'pending'
          : (status == 'converted' || status == 'cancelled');
      if (!isTabMatch) return false;

      final name = (po['customer_name'] ?? '').toString().toLowerCase();
      final phone = (po['customer_phone'] ?? '').toString().toLowerCase();
      final num = (po['pre_order_number'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || phone.contains(q) || num.contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pre Orders'.tr(context),
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textLightPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage advance bookings, estimates, and customer reservations'.tr(context),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textLightSecondary,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _openPreOrderDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Create Pre Order'.tr(context)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab bar
            Row(
              children: [
                _buildTabButton('Active Pre-Orders', 'active'),
                const SizedBox(width: 8),
                _buildTabButton('History / Converted', 'history'),
              ],
            ),
            const SizedBox(height: 16),

            // Filter Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, color: Color(0xFF94A3B8), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                        _checkForBarcodeScan(val, controller);
                      },
                      onSubmitted: (val) {
                        _checkForBarcodeScan(val, controller);
                      },
                      style: GoogleFonts.inter(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by Customer, Phone, or Pre Order No...'.tr(context),
                        hintStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8), fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF64748B), size: 20),
                    onPressed: _loadData,
                    tooltip: 'Refresh Data',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Pre Orders List
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.history_toggle_off, size: 64, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No pre orders found'.tr(context),
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              itemBuilder: (context, index) {
                                final po = filtered[index];
                                return _buildPreOrderRow(po, controller);
                              },
                            ),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  String _getStatusLabel(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'converted':
        return 'Converted';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Widget _buildPreOrderRow(dynamic po, POSController controller) {
    final status = po['status'] ?? 'pending';
    final itemsList = po['items'] as List? ?? [];
    final date = DateTime.tryParse(po['received_date'] ?? '')?.toLocal() ?? DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd hh:mm a').format(date);

    Color badgeColor;
    Color textColor;
    if (status == 'converted') {
      badgeColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF15803D);
    } else if (status == 'cancelled') {
      badgeColor = const Color(0xFFF1F5F9);
      textColor = const Color(0xFF64748B);
    } else {
      badgeColor = const Color(0xFFFFECE5);
      textColor = const Color(0xFFE11D48);
    }

    // Short summary of items
    final summary = itemsList.map((i) => "${i['product_name']} x${i['quantity']}").join(', ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
      child: Row(
        children: [
          // Pre Order info block
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      po['pre_order_number'] ?? '',
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getStatusLabel(status).tr(context),
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.textLightSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Customer info block
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  po['customer_name'] ?? 'Walking Customer',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textLightPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  po['customer_phone'] ?? 'No Phone',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppTheme.textLightSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Received Date & Time block
          Expanded(
            flex: 2,
            child: Row(
              children: [
                const Icon(Icons.access_time_outlined, size: 16, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formattedDate,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textLightPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Pricing block
          Expanded(
            flex: 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'LKR ${double.parse(po['total'].toString()).toStringAsFixed(2)}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textLightPrimary,
                  ),
                ),
                if (double.parse(po['discount'].toString()) > 0)
                  Text(
                    '-LKR ${double.parse(po['discount'].toString()).toStringAsFixed(2)}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 24),

          // Action items
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // View details
              IconButton(
                icon: const Icon(Icons.visibility_outlined, color: Color(0xFF64748B)),
                tooltip: 'View Details',
                onPressed: () => _showPreOrderDetailsDialog(po, controller),
              ),
              if (status == 'pending') ...[
                // Load to POS
                IconButton(
                  icon: const Icon(Icons.point_of_sale_outlined, color: Colors.green),
                  tooltip: 'Load to POS Cart',
                  onPressed: () {
                    controller.loadPreOrderToCart(po);
                    controller.navigateToScreen(1); // Jump to POS
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Pre Order loaded into POS cart. Proceed to checkout.'.tr(context)),
                        backgroundColor: AppTheme.primary,
                      ),
                    );
                  },
                ),
                // Edit
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blue),
                  tooltip: 'Edit Pre Order',
                  onPressed: () => _openPreOrderDialog(preOrder: po),
                ),
              ],
              // Print Bill
              IconButton(
                icon: const Icon(Icons.print_outlined, color: Colors.orange),
                tooltip: 'Print Pre Order Bill',
                onPressed: () => _printPreOrderReceipt(po, controller),
              ),
              if (status == 'pending') ...[
                // Delete / Cancel
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Cancel Pre Order',
                  onPressed: () => _confirmCancel(po, controller),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _confirmCancel(dynamic po, POSController controller) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel Pre Order'.tr(context)),
        content: Text('Are you sure you want to cancel and delete this pre order? This cannot be undone.'.tr(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Keep'.tr(context)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoading = true);
              try {
                await controller.deletePreOrder(po['id']);
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Pre Order cancelled successfully.'.tr(this.context)), backgroundColor: AppTheme.primary),
                );
              } catch (e) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                );
              }
              setState(() => _isLoading = false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text('Cancel Order'.tr(context)),
          ),
        ],
      ),
    );
  }

  // Pre-Order Creation / Edition Dialog
  void _openPreOrderDialog({dynamic preOrder}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _PreOrderWizard(
          preOrder: preOrder,
          onSave: () {
            _loadData();
          },
        );
      },
    );
  }

  // PDF Printing function for Pre-orders
  Future<void> _printPreOrderReceipt(dynamic po, POSController controller) async {
    final itemsList = po['items'] as List? ?? [];
    final double subtotal = double.parse(po['subtotal'].toString());
    final double discount = double.parse(po['discount'].toString());
    final double total = double.parse(po['total'].toString());
    final date = DateTime.tryParse(po['received_date'] ?? '')?.toLocal() ?? DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final size = MediaQuery.of(context).size;
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              backgroundColor: AppTheme.bgLight,
              child: Container(
                width: size.width * 0.8,
                constraints: const BoxConstraints(maxWidth: 780, maxHeight: 700),
                child: Column(
                  children: [
                    // Action headers
                    Container(
                      color: AppTheme.cardLight,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, size: 16),
                            label: Text('Close'.tr(context)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const Spacer(),
                          ElevatedButton.icon(
                            onPressed: () async {
                              try {
                                final bytes = await _generatePreOrderPdfBytes(po, controller);
                                await Printing.layoutPdf(
                                  onLayout: (format) async => bytes,
                                  name: 'PreOrder_${po['pre_order_number']}',
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to print: $e'), backgroundColor: Colors.red),
                                );
                              }
                            },
                            icon: const Icon(Icons.print, size: 16),
                            label: Text('Print Estimate'.tr(context)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Slip Preview
                    Expanded(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Center(
                            child: SizedBox(
                              width: 350,
                              child: _buildReceiptSlipPreview(po, controller),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReceiptSlipPreview(dynamic po, POSController controller) {
    final itemsList = po['items'] as List? ?? [];
    final double subtotal = double.parse(po['subtotal'].toString());
    final double discount = double.parse(po['discount'].toString());
    final double total = double.parse(po['total'].toString());
    final double advance = double.parse((po['advance_payment'] ?? 0.00).toString());
    final double balance = double.parse((po['balance_amount'] ?? 0.00).toString());
    final date = DateTime.tryParse(po['received_date'] ?? '')?.toLocal() ?? DateTime.now();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      color: AppTheme.cardLight,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'PRE-ORDER BILL / ESTIMATE',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
            ),
            const SizedBox(height: 12),
            Divider(color: AppTheme.dividerColor),
            const SizedBox(height: 8),
            _buildTextRow('Estimate No:', po['pre_order_number'] ?? ''),
            _buildTextRow('Due Date:', DateFormat('yyyy-MM-dd hh:mm a').format(date)),
            _buildTextRow('Customer:', po['customer_name'] ?? ''),
            _buildTextRow('Phone:', po['customer_phone'] ?? ''),
            _buildTextRow('Status:', (po['status'] ?? 'pending').toString().toUpperCase()),
            const SizedBox(height: 8),
            Divider(color: AppTheme.dividerColor),
            const SizedBox(height: 8),
            Text('Items:', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textLightPrimary)),
            const SizedBox(height: 6),
            ...itemsList.map((i) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        "${i['product_name']} x${i['quantity']}",
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightPrimary),
                      ),
                    ),
                    Text(
                      "LKR ${(double.parse(i['price'].toString()) * i['quantity']).toStringAsFixed(2)}",
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightPrimary),
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            Divider(color: AppTheme.dividerColor),
            const SizedBox(height: 8),
            _buildTextRow('Subtotal:', 'LKR ${subtotal.toStringAsFixed(2)}'),
            if (discount > 0)
              _buildTextRow('Discount:', '-LKR ${discount.toStringAsFixed(2)}', isDiscount: true),
            Divider(color: AppTheme.dividerColor),
            _buildTextRow('Total Payable:', 'LKR ${total.toStringAsFixed(2)}', isBold: true),
            _buildTextRow('Advance Paid:', 'LKR ${advance.toStringAsFixed(2)}'),
            if (po['status'] == 'converted') ...[
              _buildTextRow('Balance Settled:', 'LKR ${balance.toStringAsFixed(2)}'),
              Divider(color: AppTheme.dividerColor),
              _buildTextRow('Remaining Balance:', 'LKR 0.00', isBold: true),
            ] else ...[
              Divider(color: AppTheme.dividerColor),
              _buildTextRow('Balance Due:', 'LKR ${balance.toStringAsFixed(2)}', isBold: true),
            ],
            const SizedBox(height: 12),
            Center(
              child: SizedBox(
                height: 40,
                width: 180,
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: po['pre_order_number'] ?? '',
                  drawText: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                'Please present this estimate at checkout.'.tr(context),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 10, fontStyle: FontStyle.italic, color: AppTheme.textLightSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextRow(String label, String value, {bool isBold = false, bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: AppTheme.textLightPrimary)),
          Text(value, style: GoogleFonts.inter(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: isDiscount ? Colors.red : AppTheme.textLightPrimary)),
        ],
      ),
    );
  }

  Future<Uint8List> _generatePreOrderPdfBytes(dynamic po, POSController controller) async {
    final itemsList = po['items'] as List? ?? [];
    final double subtotal = double.parse(po['subtotal'].toString());
    final double discount = double.parse(po['discount'].toString());
    final double total = double.parse(po['total'].toString());
    final date = DateTime.tryParse(po['received_date'] ?? '')?.toLocal() ?? DateTime.now();

    final fontData = await rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf');
    final sinhalaFont = pw.Font.ttf(fontData);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: sinhalaFont,
        fontFallback: [pw.Font.helvetica()],
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'PRE-ORDER ESTIMATE',
                  style: pw.TextStyle(font: sinhalaFont, fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              _buildPdfRow('Est No:', po['pre_order_number'] ?? '', sinhalaFont),
              _buildPdfRow('Due Date:', DateFormat('yyyy-MM-dd hh:mm a').format(date), sinhalaFont),
              _buildPdfRow('Customer:', po['customer_name'] ?? '', sinhalaFont),
              _buildPdfRow('Phone:', po['customer_phone'] ?? '', sinhalaFont),
              _buildPdfRow('Status:', (po['status'] ?? 'pending').toString().toUpperCase(), sinhalaFont),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              pw.Text('Items:', style: pw.TextStyle(font: sinhalaFont, fontSize: 8, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 2),
              ...itemsList.map((i) {
                return pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        "${i['product_name']} x${i['quantity']}",
                        style: pw.TextStyle(font: sinhalaFont, fontSize: 8),
                      ),
                    ),
                    pw.Text(
                      "LKR ${(double.parse(i['price'].toString()) * i['quantity']).toStringAsFixed(2)}",
                      style: pw.TextStyle(font: sinhalaFont, fontSize: 8),
                    ),
                  ],
                );
              }).toList(),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              pw.SizedBox(height: 4),
              _buildPdfRow('Subtotal:', 'LKR ${subtotal.toStringAsFixed(2)}', sinhalaFont),
              if (discount > 0)
                _buildPdfRow('Discount:', '-LKR ${discount.toStringAsFixed(2)}', sinhalaFont),
              pw.Divider(thickness: 0.8),
              _buildPdfRow('Total Payable:', 'LKR ${total.toStringAsFixed(2)}', sinhalaFont, isBold: true),
              _buildPdfRow('Advance Paid:', 'LKR ${double.parse((po['advance_payment'] ?? 0.00).toString()).toStringAsFixed(2)}', sinhalaFont),
              if (po['status'] == 'converted') ...[
                _buildPdfRow('Balance Settled:', 'LKR ${double.parse((po['balance_amount'] ?? 0.00).toString()).toStringAsFixed(2)}', sinhalaFont, isBold: true),
                pw.Divider(thickness: 0.5),
                _buildPdfRow('Remaining Balance:', 'LKR 0.00 (PAID)', sinhalaFont, isBold: true),
              ] else ...[
                pw.Divider(thickness: 0.5),
                _buildPdfRow('Balance Due:', 'LKR ${double.parse((po['balance_amount'] ?? 0.00).toString()).toStringAsFixed(2)}', sinhalaFont, isBold: true),
              ],
              pw.SizedBox(height: 6),
              pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.code128(),
                  data: po['pre_order_number'] ?? '',
                  width: 150,
                  height: 30,
                  drawText: false,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  'Present at POS counter to complete checkout.',
                  style: pw.TextStyle(font: sinhalaFont, fontSize: 6, color: PdfColors.grey600),
                ),
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  pw.Widget _buildPdfRow(String label, String value, pw.Font font, {bool isBold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 8, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, String value) {
    final isSelected = _selectedFilterTab == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilterTab = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFECE5) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primary : const Color(0xFFE2E8F0),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label.tr(context),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppTheme.primary : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  void _checkForBarcodeScan(String val, POSController controller) {
    final cleaned = val.trim();
    if (cleaned.isEmpty) return;
    
    // Find pre-order with matching number
    dynamic match;
    for (var po in controller.preOrders) {
      if ((po['pre_order_number'] ?? '').toString().toLowerCase() == cleaned.toLowerCase()) {
        match = po;
        break;
      }
    }
    
    if (match != null) {
      // Clear search query so search bar resets
      setState(() {
        _searchQuery = '';
      });
      // Show details dialog!
      _showPreOrderDetailsDialog(match, controller);
    }
  }

  void _showPreOrderDetailsDialog(dynamic po, POSController controller) {
    final status = po['status'] ?? 'pending';
    final itemsList = po['items'] as List? ?? [];
    final date = DateTime.tryParse(po['received_date'] ?? '')?.toLocal() ?? DateTime.now();
    final formattedDate = DateFormat('yyyy-MM-dd hh:mm a').format(date);
    
    final subtotal = double.parse((po['subtotal'] ?? 0.0).toString());
    final discount = double.parse((po['discount'] ?? 0.0).toString());
    final total = double.parse((po['total'] ?? 0.0).toString());
    final advance = double.parse((po['advance_payment'] ?? 0.0).toString());
    final balance = double.parse((po['balance_amount'] ?? 0.0).toString());

    Color badgeColor;
    Color textColor;
    if (status == 'converted') {
      badgeColor = const Color(0xFFDCFCE7);
      textColor = const Color(0xFF15803D);
    } else if (status == 'cancelled') {
      badgeColor = const Color(0xFFF1F5F9);
      textColor = const Color(0xFF64748B);
    } else {
      badgeColor = const Color(0xFFFFECE5);
      textColor = const Color(0xFFE11D48);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              po['pre_order_number'] ?? '',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _getStatusLabel(status).tr(context),
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Divider(color: AppTheme.dividerColor),
              const SizedBox(height: 8),
              // Customer & Booking details
              _buildDialogInfoRow(Icons.person_outline, 'Customer Name', po['customer_name'] ?? ''),
              const SizedBox(height: 6),
              _buildDialogInfoRow(Icons.phone_outlined, 'Phone Number', po['customer_phone'] ?? ''),
              const SizedBox(height: 6),
              _buildDialogInfoRow(Icons.calendar_today_outlined, 'Due Date', formattedDate),
              const SizedBox(height: 16),
              
              Text(
                'Items Summary'.tr(context),
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textLightPrimary),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.borderLight),
                  borderRadius: BorderRadius.circular(8),
                  color: AppTheme.bgLight,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: itemsList.length,
                  separatorBuilder: (context, idx) => Divider(height: 1, color: AppTheme.dividerColor),
                  itemBuilder: (context, idx) {
                    final item = itemsList[idx];
                    final double itemPrice = double.parse((item['price'] ?? 0.0).toString());
                    final int itemQty = int.parse((item['quantity'] ?? 1).toString());
                    return ListTile(
                      dense: true,
                      title: Text(item['product_name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                      trailing: Text(
                        '$itemQty x LKR ${itemPrice.toStringAsFixed(2)} = LKR ${(itemPrice * itemQty).toStringAsFixed(2)}',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              
              // Totals breakdown
              _buildDialogTotalRow('Subtotal:', 'LKR ${subtotal.toStringAsFixed(2)}'),
              if (discount > 0)
                _buildDialogTotalRow('Discount:', '-LKR ${discount.toStringAsFixed(2)}', isDiscount: true),
              Divider(color: AppTheme.dividerColor),
              _buildDialogTotalRow('Total Estimate:', 'LKR ${total.toStringAsFixed(2)}', isBold: true),
              _buildDialogTotalRow('Advance Paid:', 'LKR ${advance.toStringAsFixed(2)}', isGreen: true),
              _buildDialogTotalRow('Balance Due:', 'LKR ${balance.toStringAsFixed(2)}', isBold: true, isRed: true),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'.tr(context)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _printPreOrderReceipt(po, controller);
            },
            icon: const Icon(Icons.print, size: 16),
            label: Text('Print Bill'.tr(context)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
          if (status == 'pending')
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                controller.loadPreOrderToCart(po);
                controller.navigateToScreen(1); // Jump to POS
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Pre Order loaded into POS cart. Proceed to checkout.'.tr(context)),
                    backgroundColor: AppTheme.primary,
                  ),
                );
              },
              icon: const Icon(Icons.shopping_cart, size: 16),
              label: Text('Load to POS'.tr(context)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDialogInfoRow(IconData icon, String label, String val) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textLightSecondary),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppTheme.textLightSecondary)),
        Text(val, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppTheme.textLightPrimary)),
      ],
    );
  }

  Widget _buildDialogTotalRow(String label, String val, {bool isBold = false, bool isDiscount = false, bool isGreen = false, bool isRed = false}) {
    Color col = AppTheme.textLightPrimary;
    if (isDiscount) col = Colors.red;
    if (isGreen) col = Colors.green;
    if (isRed) col = Colors.red[800]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label.tr(context), style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, fontSize: 12, color: AppTheme.textLightPrimary)),
          Text(val, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.w600, fontSize: isBold ? 13 : 12, color: col)),
        ],
      ),
    );
  }
}

// Dialog Pre-Order Wizard component
class _PreOrderWizard extends StatefulWidget {
  final dynamic preOrder;
  final VoidCallback onSave;

  const _PreOrderWizard({Key? key, this.preOrder, required this.onSave}) : super(key: key);

  @override
  State<_PreOrderWizard> createState() => _PreOrderWizardState();
}

class _PreOrderWizardState extends State<_PreOrderWizard> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameCtrl = TextEditingController();
  final _customerPhoneCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0.00');
  final _advancePayCtrl = TextEditingController(text: '0.00');

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 12, minute: 0);

  List<Map<String, dynamic>> _wizardCart = [];
  String _productSearch = '';
  CustomerModel? _selectedCustomer;

  double get _subtotal {
    return _wizardCart.fold(0.0, (sum, item) => sum + (item['price'] * item['quantity']));
  }

  double get _discount {
    return double.tryParse(_discountCtrl.text) ?? 0.0;
  }

  double get _total {
    final tot = _subtotal - _discount;
    return tot < 0 ? 0.0 : tot;
  }

  @override
  void initState() {
    super.initState();
    if (widget.preOrder != null) {
      _customerNameCtrl.text = widget.preOrder['customer_name'] ?? '';
      _customerPhoneCtrl.text = widget.preOrder['customer_phone'] ?? '';
      _discountCtrl.text = double.parse(widget.preOrder['discount'].toString()).toStringAsFixed(2);
      _advancePayCtrl.text = double.parse((widget.preOrder['advance_payment'] ?? 0.00).toString()).toStringAsFixed(2);
      
      final date = DateTime.tryParse(widget.preOrder['received_date'] ?? '')?.toLocal() ?? DateTime.now();
      _selectedDate = DateTime(date.year, date.month, date.day);
      _selectedTime = TimeOfDay(hour: date.hour, minute: date.minute);

      final items = widget.preOrder['items'] as List? ?? [];
      for (var i in items) {
        _wizardCart.add({
          'product_id': i['product_id'],
          'product_name': i['product_name'],
          'price': double.parse(i['price'].toString()),
          'quantity': i['quantity'],
          'notes': i['notes'] ?? '',
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.preOrder != null) {
        final custId = widget.preOrder['customer_id'];
        if (custId != null) {
          final controller = Provider.of<POSController>(context, listen: false);
          try {
            final match = controller.customers.firstWhere((c) => c.id == custId);
            setState(() {
              _selectedCustomer = match;
            });
          } catch (_) {}
        }
      }
    });
  }

  void _createNewCustomerDialog(POSController controller) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final limitCtrl = TextEditingController(text: '0.00');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Register New Customer'.tr(context)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: 'Customer Name *'.tr(context)),
                  validator: (val) => val == null || val.isEmpty ? 'Required'.tr(context) : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: InputDecoration(labelText: 'Phone Number *'.tr(context)),
                  validator: (val) => val == null || val.isEmpty ? 'Required'.tr(context) : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: limitCtrl,
                  decoration: InputDecoration(labelText: 'Credit Limit (Optional)'.tr(context)),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'.tr(context)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final double limit = double.tryParse(limitCtrl.text) ?? 0.0;
                  final payload = {
                    'name': nameCtrl.text,
                    'phone': phoneCtrl.text,
                    'birthday': null,
                    'credit_limit': limit,
                  };
                  
                  CustomerModel? newCust;
                  if (controller.isOnline) {
                    newCust = await APIService.instance.createCustomer(payload);
                  } else {
                    newCust = CustomerModel(
                      id: DateTime.now().millisecondsSinceEpoch,
                      name: nameCtrl.text,
                      phone: phoneCtrl.text,
                      creditLimit: limit,
                      outstandingBalance: 0.0,
                    );
                    controller.customers.add(newCust);
                  }
                  
                  await controller.reloadEnvironment();
                  
                  final match = controller.customers.firstWhere(
                    (c) => c.phone == phoneCtrl.text || c.name == nameCtrl.text,
                    orElse: () => newCust ?? controller.customers.first,
                  );
                  
                  setState(() {
                    _selectedCustomer = match;
                    _customerNameCtrl.text = match.name;
                    _customerPhoneCtrl.text = match.phone;
                  });
                  
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Customer registered and selected successfully!'.tr(context))),
                    );
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save customer: $e'), backgroundColor: Colors.red),
                  );
                }
              },
              child: Text('Save'.tr(context)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;

    // Filter products based on search term in wizard
    final filteredProducts = controller.products.where((p) {
      return p.name.toLowerCase().contains(_productSearch.toLowerCase()) ||
          (p.sinhalaName != null && p.sinhalaName!.toLowerCase().contains(_productSearch.toLowerCase()));
    }).toList();

    return AlertDialog(
      backgroundColor: AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.preOrder == null ? 'Create Pre Order'.tr(context) : 'Edit Pre Order'.tr(context),
        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
      ),
      content: Container(
        width: size.width * 0.85,
        height: size.height * 0.8,
        child: Form(
          key: _formKey,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Panel: Form Info & Cart
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Customer info
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<CustomerModel?>(
                            value: _selectedCustomer,
                            decoration: InputDecoration(
                              labelText: 'Select Registered Customer (Optional)'.tr(context),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              DropdownMenuItem<CustomerModel?>(
                                value: null,
                                child: Text('Manual / Walking Customer'.tr(context)),
                              ),
                              ...controller.customers.map((c) => DropdownMenuItem<CustomerModel?>(
                                value: c,
                                child: Text('${c.name} (${c.phone})'),
                              )),
                            ],
                            onChanged: (CustomerModel? val) {
                              setState(() {
                                _selectedCustomer = val;
                                if (val != null) {
                                  _customerNameCtrl.text = val.name;
                                  _customerPhoneCtrl.text = val.phone;
                                }
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _createNewCustomerDialog(controller),
                          icon: const Icon(Icons.person_add, size: 16),
                          label: Text('New Customer'.tr(context)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueGrey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _customerNameCtrl,
                            decoration: InputDecoration(
                              labelText: 'Customer Name *'.tr(context),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (val) => val == null || val.isEmpty ? 'Required'.tr(context) : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _customerPhoneCtrl,
                            decoration: InputDecoration(
                              labelText: 'Phone Number *'.tr(context),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                            validator: (val) => val == null || val.isEmpty ? 'Required'.tr(context) : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Date & Time pickers
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Received Date *'.tr(context),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                                  const Icon(Icons.calendar_today, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            onTap: _pickTime,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Received Time *'.tr(context),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(_selectedTime.format(context)),
                                  const Icon(Icons.access_time, size: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Active Wizard Cart list
                    Text(
                      'Ordered Items'.tr(context),
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.borderLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _wizardCart.isEmpty
                            ? Center(child: Text('No items added. Select from right panel.'.tr(context), style: TextStyle(color: AppTheme.textLightSecondary)))
                            : ListView.separated(
                                itemCount: _wizardCart.length,
                                separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                                itemBuilder: (context, index) {
                                  final item = _wizardCart[index];
                                  return ListTile(
                                    title: Text(item['product_name'], style: TextStyle(color: AppTheme.textLightPrimary, fontWeight: FontWeight.bold)),
                                    subtitle: Text("LKR ${item['price'].toStringAsFixed(2)}", style: TextStyle(color: AppTheme.textLightSecondary)),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                                          onPressed: () {
                                            setState(() {
                                              if (item['quantity'] > 1) {
                                                item['quantity']--;
                                              } else {
                                                _wizardCart.removeAt(index);
                                              }
                                            });
                                          },
                                        ),
                                        SizedBox(
                                          width: 60,
                                          height: 30,
                                          child: Builder(
                                            builder: (context) {
                                              final ctrl = TextEditingController(text: '${item['quantity']}');
                                              ctrl.selection = TextSelection.fromPosition(TextPosition(offset: ctrl.text.length));
                                              return TextFormField(
                                                controller: ctrl,
                                                keyboardType: TextInputType.number,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textLightPrimary),
                                                decoration: InputDecoration(
                                                  contentPadding: EdgeInsets.zero,
                                                  border: const OutlineInputBorder(),
                                                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.borderLight)),
                                                ),
                                                onChanged: (val) {
                                                  final q = int.tryParse(val) ?? 0;
                                                  item['quantity'] = q;
                                                  setState(() {});
                                                },
                                                onTap: () {
                                                  if (ctrl.text == '0' || ctrl.text == '1') {
                                                    ctrl.clear();
                                                  }
                                                },
                                              );
                                            }
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                                          onPressed: () {
                                            setState(() {
                                              item['quantity']++;
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Right Panel: Product catalog & Total summaries
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    // Search Catalog
                    TextField(
                      onChanged: (val) {
                        setState(() {
                          _productSearch = val;
                        });
                      },
                      decoration: InputDecoration(
                        hintText: 'Search products...'.tr(context),
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Products List
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.borderLight),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          itemCount: filteredProducts.length,
                          itemBuilder: (context, index) {
                            final p = filteredProducts[index];
                            return ListTile(
                              title: Text(p.name, style: TextStyle(color: AppTheme.textLightPrimary, fontWeight: FontWeight.bold)),
                              subtitle: Text("LKR ${p.price.toStringAsFixed(2)}", style: TextStyle(color: AppTheme.textLightSecondary)),
                              trailing: const Icon(Icons.add, color: Colors.blue),
                              onTap: () {
                                final existingIdx = _wizardCart.indexWhere((item) => item['product_id'] == p.id);
                                setState(() {
                                  if (existingIdx != -1) {
                                    _wizardCart[existingIdx]['quantity']++;
                                  } else {
                                    _wizardCart.add({
                                      'product_id': p.id,
                                      'product_name': p.name,
                                      'price': p.price,
                                      'quantity': 1,
                                      'notes': '',
                                    });
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Summary Calculations
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          _buildSummaryRow('Subtotal:', 'LKR ${_subtotal.toStringAsFixed(2)}'),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Discount (Fixed):'.tr(context), style: TextStyle(fontSize: 12, color: AppTheme.textLightPrimary)),
                              SizedBox(
                                width: 100,
                                height: 32,
                                child: TextFormField(
                                  controller: _discountCtrl,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(fontSize: 12, color: AppTheme.textLightPrimary),
                                  textAlign: TextAlign.end,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    border: const OutlineInputBorder(),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.borderLight)),
                                  ),
                                  onTap: () {
                                    if (_discountCtrl.text == '0.00' || _discountCtrl.text == '0.0' || _discountCtrl.text == '0') {
                                      _discountCtrl.clear();
                                    }
                                  },
                                  onChanged: (_) {
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Advance Paid:'.tr(context), style: TextStyle(fontSize: 12, color: AppTheme.textLightPrimary)),
                              SizedBox(
                                width: 100,
                                height: 32,
                                child: TextFormField(
                                  controller: _advancePayCtrl,
                                  keyboardType: TextInputType.number,
                                  style: TextStyle(fontSize: 12, color: AppTheme.textLightPrimary),
                                  textAlign: TextAlign.end,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    border: const OutlineInputBorder(),
                                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.borderLight)),
                                  ),
                                  onTap: () {
                                    if (_advancePayCtrl.text == '0.00' || _advancePayCtrl.text == '0.0' || _advancePayCtrl.text == '0') {
                                      _advancePayCtrl.clear();
                                    }
                                  },
                                  onChanged: (_) {
                                    setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 16, color: AppTheme.dividerColor),
                          _buildSummaryRow('Total Estimate:', 'LKR ${_total.toStringAsFixed(2)}', isBold: true),
                          const SizedBox(height: 4),
                          _buildSummaryRow(
                            'Balance Due:',
                            'LKR ${(_total - (double.tryParse(_advancePayCtrl.text) ?? 0.0) < 0 ? 0.0 : _total - (double.tryParse(_advancePayCtrl.text) ?? 0.0)).toStringAsFixed(2)}',
                            isBold: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr(context)),
        ),
        ElevatedButton(
          onPressed: _wizardCart.isEmpty ? null : _savePreOrder,
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
          child: Text('Save Pre Order'.tr(context)),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label.tr(context), style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: AppTheme.textLightPrimary)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: AppTheme.textLightPrimary)),
      ],
    );
  }

  Future<void> _savePreOrder() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = Provider.of<POSController>(context, listen: false);
    final combinedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final double advPaid = double.tryParse(_advancePayCtrl.text) ?? 0.00;
    final double balDue = _total - advPaid < 0 ? 0.00 : _total - advPaid;

    final payload = {
      'customer_id': _selectedCustomer?.id,
      'customer_name': _customerNameCtrl.text,
      'customer_phone': _customerPhoneCtrl.text,
      'received_date': combinedDateTime.toIso8601String(),
      'subtotal': _subtotal,
      'discount': _discount,
      'total': _total,
      'advance_payment': advPaid,
      'balance_amount': balDue,
      'items': _wizardCart,
    };

    try {
      if (widget.preOrder == null) {
        await controller.createPreOrder(payload);
      } else {
        await controller.updatePreOrder(widget.preOrder['id'], payload);
      }
      widget.onSave();
      Navigator.pop(this.context);
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Pre Order saved successfully!'.tr(this.context)), backgroundColor: AppTheme.accent),
      );
    } catch (e) {
      ScaffoldMessenger.of(this.context).showSnackBar(
        SnackBar(content: Text('Error saving pre order: $e'), backgroundColor: Colors.red),
      );
    }
  }
}
