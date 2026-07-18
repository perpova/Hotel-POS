import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';

class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({Key? key}) : super(key: key);

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  List<OrderModel> _orders = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Advanced Filters
  bool _isFilterExpanded = false;
  final _filterIdController = TextEditingController();
  final _filterDateController = TextEditingController();
  final _filterPaymentTypeController = TextEditingController();
  String _filterStatus = '--'; // '--', 'paid', 'unpaid'

  // Applied Filters State
  String _appliedId = '';
  String _appliedPaymentType = '';
  String _appliedStatus = '--';
  String _appliedDate = '';

  // Date Range Presets
  String _datePreset = 'all'; // 'all', 'today', 'weekly', 'monthly', 'yearly', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

  // Pagination Limit
  int _entriesLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _filterIdController.dispose();
    _filterDateController.dispose();
    _filterPaymentTypeController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final ords = await APIService.instance.getOrders();
      if (mounted) {
        setState(() {
          _orders = ords;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load sales data: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Date Filtering Helper
  bool _isWithinDateRange(String dateStr) {
    final dateTime = DateTime.tryParse(dateStr);
    if (dateTime == null) return true;
    final localDateTime = dateTime.toLocal();

    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(hours: 23, minutes: 59, seconds: 59));

    switch (_datePreset) {
      case 'today':
        return localDateTime.isAfter(startOfToday) && localDateTime.isBefore(endOfToday);
      case 'weekly':
        final startOfWeek = startOfToday.subtract(const Duration(days: 7));
        return localDateTime.isAfter(startOfWeek) && localDateTime.isBefore(endOfToday);
      case 'monthly':
        final startOfMonth = startOfToday.subtract(const Duration(days: 30));
        return localDateTime.isAfter(startOfMonth) && localDateTime.isBefore(endOfToday);
      case 'yearly':
        final startOfYear = startOfToday.subtract(const Duration(days: 365));
        return localDateTime.isAfter(startOfYear) && localDateTime.isBefore(endOfToday);
      case 'custom':
        if (_startDate == null || _endDate == null) return true;
        final customEnd = DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59);
        return localDateTime.isAfter(_startDate!) && localDateTime.isBefore(customEnd);
      case 'all':
      default:
        return true;
    }
  }

  // Pick Custom Date Range picker
  Future<void> _selectCustomDateRange() async {
    final pickedRange = await showDateRangePicker(
      context: context,
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              surface: AppTheme.cardLight,
              onSurface: AppTheme.textLightPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedRange != null) {
      setState(() {
        _startDate = pickedRange.start;
        _endDate = pickedRange.end;
      });
    }
  }

  // Filtered Orders List
  List<OrderModel> get _filteredOrders {
    return _orders.where((o) {
      final orderIdStr = o.orderNumber.toLowerCase();
      
      final matchId = _appliedId.isEmpty || orderIdStr.contains(_appliedId);
      
      // Filter by dynamic date preset
      if (!_isWithinDateRange(o.createdAt)) return false;
      
      final dateFormatted = DateFormat('yyyy-MM-dd').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
      final matchDate = _appliedDate.isEmpty || dateFormatted.contains(_appliedDate);
      
      final payMethodStr = (o.paymentMethod ?? 'N/A').toLowerCase();
      final matchPayType = _appliedPaymentType.isEmpty || payMethodStr.contains(_appliedPaymentType);
      
      final matchStatus = _appliedStatus == '--' || o.paymentStatus.toLowerCase() == _appliedStatus;

      return matchId && matchPayType && matchStatus && matchDate;
    }).toList();
  }

  // Export to CSV
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Order ID,Date,Total,Discount,Delivery Charge,Payment Type,Payment Status\n';
      for (var o in _filteredOrders.take(_entriesLimit)) {
        final dateFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
        final deliveryCharge = o.orderType == 'delivery' ? 150.00 : 0.00;
        final payType = o.paymentMethod ?? 'N/A';
        csvContent += '${o.orderNumber},$dateFormatted,${o.total},${o.discount},$deliveryCharge,$payType,${o.paymentStatus}\n';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Sales Report',
        fileName: 'Sales_Report_${_datePreset.toUpperCase()}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsString(csvContent);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported successfully to: $resultPath'), backgroundColor: AppTheme.accent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Export PDF Report File
  Future<void> _exportToPDF() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Order ID', 'Date', 'Total', 'Discount', 'Delivery', 'Payment Type', 'Status'];
      final data = _filteredOrders.take(_entriesLimit).map((o) {
        final dateFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
        final deliveryCharge = o.orderType == 'delivery' ? '150.00' : '0.00';
        return [
          o.orderNumber.length > 12 ? o.orderNumber.substring(o.orderNumber.length - 8) : o.orderNumber,
          dateFormatted,
          o.total.toStringAsFixed(2),
          o.discount.toStringAsFixed(2),
          deliveryCharge,
          o.paymentMethod ?? 'N/A',
          o.paymentStatus
        ];
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Sales Report (${_datePreset.toUpperCase()})',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                if (_datePreset == 'custom' && _startDate != null && _endDate != null)
                  pw.Text('Period: ${DateFormat('yyyy-MM-dd').format(_startDate!)} to ${DateFormat('yyyy-MM-dd').format(_endDate!)}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 25,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.center,
                    6: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export PDF Report',
        fileName: 'Sales_Report_${_datePreset.toUpperCase()}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsBytes(await doc.save());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF saved successfully to: $resultPath'), backgroundColor: AppTheme.accent),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export PDF failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // Print PDF Layout
  Future<void> _printList() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Order ID', 'Date', 'Total', 'Discount', 'Delivery', 'Payment Type', 'Status'];
      final data = _filteredOrders.take(_entriesLimit).map((o) {
        final dateFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
        final deliveryCharge = o.orderType == 'delivery' ? '150.00' : '0.00';
        return [
          o.orderNumber.length > 12 ? o.orderNumber.substring(o.orderNumber.length - 8) : o.orderNumber,
          dateFormatted,
          o.total.toStringAsFixed(2),
          o.discount.toStringAsFixed(2),
          deliveryCharge,
          o.paymentMethod ?? 'N/A',
          o.paymentStatus
        ];
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Sales Report',
                  style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 10),
                pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 25,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.center,
                    6: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Sales_Report',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _filteredOrders;
    final displayList = filteredList.take(_entriesLimit).toList();

    // Stats calculations
    final totalOrders = filteredList.length;
    final totalEarnings = filteredList.fold(0.00, (sum, o) => sum + o.total);
    final totalDiscounts = filteredList.fold(0.00, (sum, o) => sum + o.discount);
    final totalDeliveryCharges = filteredList.fold(0.00, (sum, o) => sum + (o.orderType == 'delivery' ? 150.00 : 0.00));

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales Report',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Sales Report', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Entries Limit Dropdown
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.borderLight),
                        borderRadius: BorderRadius.circular(8),
                        color: AppTheme.cardLight,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      height: 42,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          dropdownColor: AppTheme.cardLight,
                          value: _entriesLimit,
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                          items: const [
                            DropdownMenuItem(value: 10, child: Text('10')),
                            DropdownMenuItem(value: 25, child: Text('25')),
                            DropdownMenuItem(value: 50, child: Text('50')),
                            DropdownMenuItem(value: 100, child: Text('100')),
                          ],
                          onChanged: (val) => setState(() => _entriesLimit = val!),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Filter Toggle Button
                    OutlinedButton.icon(
                      onPressed: () => setState(() => _isFilterExpanded = !_isFilterExpanded),
                      icon: Icon(Icons.filter_alt_outlined, size: 14, color: AppTheme.primary),
                      label: Text('Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppTheme.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Export Popup Button
                    PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'PDF') {
                          _exportToPDF();
                        } else if (val == 'Print') {
                          _printList();
                        } else if (val == 'XLS') {
                          _exportToCSV();
                        }
                      },
                      offset: const Offset(0, 45),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'PDF',
                          child: Row(
                            children: [
                              const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Text('Export PDF', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'Print',
                          child: Row(
                            children: [
                              const Icon(Icons.print_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Text('Print Report', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'XLS',
                          child: Row(
                            children: [
                              const Icon(Icons.table_view_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Text('Export CSV', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.primary),
                          borderRadius: BorderRadius.circular(8),
                          color: AppTheme.cardLight,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.download_outlined, size: 14, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Export',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildDateFilterCard(),
            const SizedBox(height: 24),

            // Statistics Counters Row Cards
            Row(
              children: [
                Expanded(child: _buildStatCard('Total Orders', '$totalOrders', Icons.inventory_2_outlined, Colors.blue)),
                const SizedBox(width: 16),
                Expanded(child: _buildStatCard('Total Earnings', 'LKR ${totalEarnings.toStringAsFixed(2)}', Icons.monetization_on_outlined, const Color(0xFF10B981))),
                const SizedBox(width: 16),
                Expanded(child: _buildStatCard('Total Discounts', 'LKR ${totalDiscounts.toStringAsFixed(2)}', Icons.local_offer_outlined, Colors.orange)),
                const SizedBox(width: 16),
                Expanded(child: _buildStatCard('Total Delivery Charges', 'LKR ${totalDeliveryCharges.toStringAsFixed(2)}', Icons.local_shipping_outlined, Colors.purple)),
              ],
            ),
            const SizedBox(height: 24),

            // Advanced Collapsible Filter section
            if (_isFilterExpanded) ...[
              _buildFilterSection(),
              const SizedBox(height: 16),
            ],

            // Main Table Card
            Expanded(
              child: Card(
                elevation: 0,
                color: AppTheme.cardLight,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: AppTheme.borderLight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _errorMessage.isNotEmpty
                        ? Center(child: Text(_errorMessage, style: GoogleFonts.inter(color: Colors.red)))
                        : displayList.isEmpty
                            ? _buildEmptyState()
                            : _buildTable(displayList),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                const SizedBox(height: 6),
                Text(value, style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('ORDER ID'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterIdController,
                        decoration: const InputDecoration(hintText: 'Enter order number'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('DATE (YYYY-MM-DD)'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterDateController,
                        decoration: const InputDecoration(hintText: 'e.g. 2026-06-28'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('PAYMENT TYPE'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterPaymentTypeController,
                        decoration: const InputDecoration(hintText: 'e.g. cash, card'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('PAYMENT STATUS'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _filterStatus,
                        dropdownColor: AppTheme.cardLight,
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                        items: const [
                          DropdownMenuItem(value: '--', child: Text('--')),
                          DropdownMenuItem(value: 'paid', child: Text('Paid')),
                          DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                        ],
                        onChanged: (val) => setState(() => _filterStatus = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _appliedId = _filterIdController.text.trim().toLowerCase();
                      _appliedDate = _filterDateController.text.trim();
                      _appliedPaymentType = _filterPaymentTypeController.text.trim().toLowerCase();
                      _appliedStatus = _filterStatus;
                    });
                  },
                  icon: const Icon(Icons.search, size: 14),
                  label: const Text('Search'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _filterIdController.clear();
                      _filterDateController.clear();
                      _filterPaymentTypeController.clear();
                      _filterStatus = '--';
                      
                      _appliedId = '';
                      _appliedDate = '';
                      _appliedPaymentType = '';
                      _appliedStatus = '--';
                    });
                  },
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.textLightSecondary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.folder_open, size: 54, color: Color(0xFFFDA4AF)),
          const SizedBox(height: 16),
          Text(
            'No sales records available.',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<OrderModel> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Header
        Container(
          color: AppTheme.bgLight,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildTableHeaderText('ORDER ID')),
              Expanded(flex: 4, child: _buildTableHeaderText('DATE')),
              Expanded(flex: 2, child: _buildTableHeaderText('TOTAL')),
              Expanded(flex: 2, child: _buildTableHeaderText('DISCOUNT')),
              Expanded(flex: 3, child: _buildTableHeaderText('DELIVERY CHARGE')),
              Expanded(flex: 3, child: _buildTableHeaderText('PAYMENT TYPE')),
              Expanded(flex: 2, child: _buildTableHeaderText('PAYMENT STATUS')),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
            itemBuilder: (context, index) {
              final o = list[index];
              final dateFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(o.createdAt) ?? DateTime.now()).toLocal());
              final deliveryCharge = o.orderType == 'delivery' ? 150.00 : 0.00;
              final isPaid = o.paymentStatus.toLowerCase() == 'paid';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  children: [
                    // ORDER ID
                    Expanded(
                      flex: 3,
                      child: Text(
                        o.orderNumber.length > 12 ? o.orderNumber.substring(o.orderNumber.length - 8) : o.orderNumber,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                      ),
                    ),
                    // DATE
                    Expanded(
                      flex: 4,
                      child: Text(
                        dateFormatted,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // TOTAL
                    Expanded(
                      flex: 2,
                      child: Text(
                        o.total.toStringAsFixed(2),
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // DISCOUNT
                    Expanded(
                      flex: 2,
                      child: Text(
                        o.discount.toStringAsFixed(2),
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // DELIVERY CHARGE
                    Expanded(
                      flex: 3,
                      child: Text(
                        deliveryCharge.toStringAsFixed(2),
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // PAYMENT TYPE
                    Expanded(
                      flex: 3,
                      child: Text(
                        (o.paymentMethod ?? 'N/A').toUpperCase(),
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // PAYMENT STATUS
                    Expanded(
                      flex: 2,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isPaid ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isPaid ? 'Paid' : 'Unpaid',
                            style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: isPaid ? const Color(0xFF137333) : const Color(0xFFC5221F)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5),
    );
  }

  Widget _buildDateFilterCard() {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                'Report Period:',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
              const SizedBox(width: 16),
              _buildDatePresetChip('all', 'All Time'),
              const SizedBox(width: 8),
              _buildDatePresetChip('today', 'Today (Daily)'),
              const SizedBox(width: 8),
              _buildDatePresetChip('weekly', 'Weekly'),
              const SizedBox(width: 8),
              _buildDatePresetChip('monthly', 'Monthly'),
              const SizedBox(width: 8),
              _buildDatePresetChip('yearly', 'Yearly'),
              const SizedBox(width: 8),
              _buildDatePresetChip('custom', 'Custom Range'),
              if (_datePreset == 'custom') ...[
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _selectCustomDateRange,
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(
                    _startDate == null || _endDate == null
                        ? 'Select Range'
                        : '${DateFormat('yyyy-MM-dd').format(_startDate!)} to ${DateFormat('yyyy-MM-dd').format(_endDate!)}',
                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePresetChip(String presetKey, String label) {
    final isSelected = _datePreset == presetKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : AppTheme.textLightPrimary)),
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.bgLight,
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _datePreset = presetKey;
            if (presetKey != 'custom') {
              _startDate = null;
              _endDate = null;
            } else if (_startDate == null || _endDate == null) {
              _selectCustomDateRange();
            }
          });
        }
      },
    );
  }
}
