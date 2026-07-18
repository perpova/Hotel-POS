import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import '../services/local_db.dart';

class POSStockScreen extends StatefulWidget {
  const POSStockScreen({Key? key}) : super(key: key);

  @override
  State<POSStockScreen> createState() => _POSStockScreenState();
}

class _POSStockScreenState extends State<POSStockScreen> {
  ProductModel? _selectedStockProduct;
  final _stockChangeController = TextEditingController();
  final _stockReasonController = TextEditingController();
  String _stockType = 'purchase'; // 'purchase', 'adjustment', 'wastage'
  
  List<dynamic> _logs = [];
  bool _loading = false;
  
  // Search query for POS product list
  String _searchQuery = '';

  // Log Filtering & Pagination
  int _entriesLimit = 10;
  bool _isFilterExpanded = false;
  final _filterProductController = TextEditingController();
  final _filterDateController = TextEditingController();
  String _filterType = '--'; // '--', 'purchase', 'sale', 'adjustment', 'wastage'

  // Applied Filters State
  String _appliedProduct = '';
  String _appliedType = '--';
  String _appliedDate = '';

  // Date Range Presets
  String _datePreset = 'all'; // 'all', 'today', 'weekly', 'monthly', 'yearly', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _stockChangeController.dispose();
    _stockReasonController.dispose();
    _filterProductController.dispose();
    _filterDateController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final logsData = await APIService.instance.getProductStockLogs();
      if (mounted) {
        setState(() {
          _logs = logsData;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        print('Error loading product stock logs: $e');
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

  // Filtered logs list getter
  List<dynamic> get _filteredLogs {
    return _logs.where((l) {
      final nameStr = (l['product_name'] ?? '').toString().toLowerCase();
      final matchProduct = _appliedProduct.isEmpty || nameStr.contains(_appliedProduct);

      final typeStr = (l['type'] ?? '').toString().toLowerCase();
      final matchType = _appliedType == '--' || typeStr == _appliedType.toLowerCase();

      final timestampStr = (l['timestamp'] ?? '').toString();
      if (!_isWithinDateRange(timestampStr)) return false;

      final dateFormatted = DateFormat('yyyy-MM-dd').format((DateTime.tryParse(timestampStr) ?? DateTime.now()).toLocal());
      final matchDate = _appliedDate.isEmpty || dateFormatted.contains(_appliedDate);

      return matchProduct && matchType && matchDate;
    }).toList();
  }

  // Export logs to CSV
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Product,Change,Log Type,Reason,Recorder,Date & Time\n';
      for (var l in _filteredLogs.take(_entriesLimit)) {
        final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
        final isPositive = changeVal > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
        
        csvContent += '${l['product_name']},${isPositive ? "+" : ""}$changeVal,${l['type'].toString().toUpperCase()},${l['reason']},${l['recorder_name'] ?? "Admin"},$timeFormatted\n';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export POS Product Stock Logs',
        fileName: 'POS_Stock_Logs_${_datePreset.toUpperCase()}.csv',
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

  // Export PDF ledger file
  Future<void> _exportToPDF() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Product', 'Change', 'Log Type', 'Reason', 'Recorder', 'Date & Time'];
      final data = _filteredLogs.take(_entriesLimit).map((l) {
        final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
        final isPositive = changeVal > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
        
        return [
          (l['product_name'] ?? 'N/A').toString(),
          '${isPositive ? "+" : ""}${changeVal.toStringAsFixed(0)}',
          l['type'].toString().toUpperCase(),
          (l['reason'] ?? '').toString(),
          (l['recorder_name'] ?? 'Admin').toString(),
          timeFormatted
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
                  'POS Stock Ledger Report (${_datePreset.toUpperCase()})',
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
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.center,
                    3: pw.Alignment.centerLeft,
                    4: pw.Alignment.centerLeft,
                    5: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export PDF Report',
        fileName: 'POS_Stock_Logs_${_datePreset.toUpperCase()}.pdf',
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

  // Print PDF ledger
  Future<void> _printList() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Product', 'Change', 'Log Type', 'Reason', 'Recorder', 'Date & Time'];
      final data = _filteredLogs.take(_entriesLimit).map((l) {
        final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
        final isPositive = changeVal > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
        
        return [
          (l['product_name'] ?? 'N/A').toString(),
          '${isPositive ? "+" : ""}${changeVal.toStringAsFixed(0)}',
          l['type'].toString().toUpperCase(),
          (l['reason'] ?? '').toString(),
          (l['recorder_name'] ?? 'Admin').toString(),
          timeFormatted
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
                  'POS Stock Ledger Report',
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
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.center,
                    3: pw.Alignment.centerLeft,
                    4: pw.Alignment.centerLeft,
                    5: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'POS_Product_Stock_Logs',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Widget _buildWarningBanner(List<ProductModel> lowStock) {
    if (lowStock.isEmpty) return const SizedBox.shrink();
    final names = lowStock.map((p) => '${p.name} (${p.stockQty})').take(5).join(', ');
    final suffix = lowStock.length > 5 ? ' and ${lowStock.length - 5} more' : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: AppTheme.isDarkMode ? const Color(0xFF7F1D1D) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.isDarkMode ? const Color(0xFFEF4444) : const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'POS Low Stock / Depleted Warning!',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.isDarkMode ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The following POS items are running low or depleted: $names$suffix. Please replenish stock immediately.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppTheme.isDarkMode ? const Color(0xFFFEE2E2) : const Color(0xFFB91C1C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    
    final userRole = APIService.instance.currentUser?.role ?? 'cashier';
    final hasSeniorAccess = userRole == 'admin' || userRole == 'owner';

    // Filter products list based on search query and trackStock
    final filteredProducts = controller.products.where((p) {
      if (!p.trackStock) return false;
      return p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.sinhalaName ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final displayLogs = _filteredLogs.take(_entriesLimit).toList();
    final lowStockProducts = controller.products.where((p) => p.trackStock && p.stockQty <= p.minStockLevel).toList();

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Container(
        padding: const EdgeInsets.all(24),
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
                      'POS Stock Management',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('POS Stock', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Limit Dropdown
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

            // Warning Banner for low stock
            _buildWarningBanner(lowStockProducts),

            // Collapsible filters
            if (_isFilterExpanded) ...[
              _buildFilterSection(),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                _buildAdjustmentFormCard(controller, hasSeniorAccess),
                                const SizedBox(height: 24),
                                _buildLogsCard(displayLogs),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 2,
                          child: _buildStockListCard(filteredProducts),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildAdjustmentFormCard(controller, hasSeniorAccess),
                          const SizedBox(height: 24),
                          _buildStockListCard(filteredProducts),
                          const SizedBox(height: 24),
                          _buildLogsCard(displayLogs),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // FILTER SECTION
  // ----------------------------------------------------
  Widget _buildFilterSection() {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
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
                      _buildFieldLabel('PRODUCT NAME'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterProductController,
                        decoration: const InputDecoration(hintText: 'Enter product name'),
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
                      _buildFieldLabel('LOG TYPE'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _filterType,
                        dropdownColor: AppTheme.cardLight,
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                        items: const [
                          DropdownMenuItem(value: '--', child: Text('--')),
                          DropdownMenuItem(value: 'purchase', child: Text('Purchase')),
                          DropdownMenuItem(value: 'sale', child: Text('Sale')),
                          DropdownMenuItem(value: 'adjustment', child: Text('Correction')),
                          DropdownMenuItem(value: 'wastage', child: Text('Wastage')),
                        ],
                        onChanged: (val) => setState(() => _filterType = val!),
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
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _appliedProduct = _filterProductController.text.trim().toLowerCase();
                      _appliedDate = _filterDateController.text.trim();
                      _appliedType = _filterType;
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
                      _filterProductController.clear();
                      _filterDateController.clear();
                      _filterType = '--';
                      
                      _appliedProduct = '';
                      _appliedDate = '';
                      _appliedType = '--';
                    });
                  },
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Clear'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF475569),
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

  // ----------------------------------------------------
  // ADJUSTMENT INPUT FORM
  // ----------------------------------------------------
  Widget _buildAdjustmentFormCard(POSController controller, bool hasSeniorAccess) {
    if (!hasSeniorAccess) {
      return Card(
        color: AppTheme.danger.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.danger)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: AppTheme.danger, size: 32),
              const SizedBox(height: 12),
              Text(
                'POS Stock entering and adjustments are locked. Only Admins or Owners can make adjustments to POS stock levels.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.danger, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('POS Items Stock Corrections', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              ],
            ),
            const SizedBox(height: 20),

            _buildFieldLabel('SELECT PRODUCT *'),
            const SizedBox(height: 6),
             DropdownButtonFormField<ProductModel>(
              value: _selectedStockProduct != null && controller.products.contains(_selectedStockProduct) && _selectedStockProduct!.trackStock ? _selectedStockProduct : null,
              dropdownColor: AppTheme.cardLight,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
              items: [
                ...controller.products.where((p) => p.trackStock).map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        '${p.name} ${p.sinhalaName != null ? "(${p.sinhalaName})" : ""} | Current: ${p.stockQty}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textLightPrimary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: (p) => setState(() => _selectedStockProduct = p),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('STOCK CHANGE QTY *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _stockChangeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'e.g. 100, -5'),
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
                      _buildFieldLabel('LOG TYPE *'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _stockType,
                        dropdownColor: AppTheme.cardLight,
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                        items: const [
                          DropdownMenuItem(value: 'purchase', child: Text('New Purchase / Input')),
                          DropdownMenuItem(value: 'adjustment', child: Text('Correction / Count')),
                          DropdownMenuItem(value: 'wastage', child: Text('Wastage / Spoiled')),
                        ],
                        onChanged: (val) => setState(() => _stockType = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildFieldLabel('REASON / REMARKS *'),
            const SizedBox(height: 6),
            TextField(
              controller: _stockReasonController,
              decoration: const InputDecoration(hintText: 'e.g. weekly batch input, spoiled food'),
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: () => _handleAdjustStock(controller),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Update POS Inventory Level', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // LIST OF CURRENT STOCK LEVELS
  // ----------------------------------------------------
  Widget _buildStockListCard(List<ProductModel> products) {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Current POS Stock Levels', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            const SizedBox(height: 12),
            // Search Input
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search products by name...',
              ),
              style: GoogleFonts.inter(fontSize: 13),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
            const SizedBox(height: 16),
            
            // Stock List
            Container(
              height: 400,
              child: products.isEmpty
                  ? Center(child: Text('No matching products found.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                  : ListView.separated(
                      itemCount: products.length,
                      separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                      itemBuilder: (context, index) {
                        final p = products[index];
                        final isLowStock = p.stockQty <= p.minStockLevel;
                        
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (p.sinhalaName != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        p.sinhalaName!,
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Row(
                                children: [
                                  if (isLowStock) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFCE8E6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        'LOW STOCK',
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: const Color(0xFFC5221F)),
                                      ),
                                    ),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isLowStock ? const Color(0xFFFCE8E6) : AppTheme.bgLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${p.stockQty}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isLowStock ? const Color(0xFFC5221F) : AppTheme.textLightPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // TRANSACTION LOGS LEDGER
  // ----------------------------------------------------
  Widget _buildLogsCard(List<dynamic> logsList) {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'POS Stock Transaction Logs',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            const SizedBox(height: 16),

            logsList.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(
                      child: Text('No adjustment history logged.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
                    ),
                  )
                : Column(
                    children: [
                      // Table header
                      Container(
                        color: AppTheme.bgLight,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: _buildTableHeaderText('PRODUCT')),
                            Expanded(flex: 2, child: _buildTableHeaderText('CHANGE')),
                            Expanded(flex: 3, child: _buildTableHeaderText('LOG TYPE')),
                            Expanded(flex: 3, child: _buildTableHeaderText('REASON')),
                            Expanded(flex: 3, child: _buildTableHeaderText('RECORDER')),
                            Expanded(flex: 4, child: _buildTableHeaderText('DATE & TIME')),
                          ],
                        ),
                      ),
                      // List rows
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logsList.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                        itemBuilder: (context, index) {
                          final l = logsList[index];
                          final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
                          final isPositive = changeVal > 0;
                          final timeFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
                          
                          Color badgeColor;
                          Color badgeTextColor;
                          String badgeLabel;
                          
                          switch (l['type'].toString().toLowerCase()) {
                            case 'purchase':
                              badgeColor = const Color(0xFFE6F4EA);
                              badgeTextColor = const Color(0xFF137333);
                              badgeLabel = 'PURCHASE';
                              break;
                            case 'sale':
                              badgeColor = const Color(0xFFFFF0F5);
                              badgeTextColor = AppTheme.primary;
                              badgeLabel = 'SALE';
                              break;
                            case 'wastage':
                              badgeColor = const Color(0xFFFCE8E6);
                              badgeTextColor = const Color(0xFFC5221F);
                              badgeLabel = 'WASTAGE';
                              break;
                            default:
                              badgeColor = const Color(0xFFE8F0FE);
                              badgeTextColor = const Color(0xFF1A73E8);
                              badgeLabel = 'CORRECTION';
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l['product_name'] ?? 'N/A',
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${isPositive ? "+" : ""}${changeVal.toStringAsFixed(0)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: isPositive ? const Color(0xFF137333) : const Color(0xFFC5221F),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(4)),
                                      child: Text(
                                        badgeLabel,
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: badgeTextColor),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l['reason'] ?? '',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l['recorder_name'] ?? 'Admin',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    timeFormatted,
                                    style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
    );
  }

  void _handleAdjustStock(POSController controller) async {
    if (_selectedStockProduct == null) return;
    final qty = int.tryParse(_stockChangeController.text) ?? 0;
    final reason = _stockReasonController.text.trim();
    if (qty == 0 || reason.isEmpty) return;

    try {
      if (controller.isOnline) {
        await APIService.instance.adjustStock(_selectedStockProduct!.id, qty, _stockType, reason);
      } else {
        await LocalDB.instance.saveStockLogOffline(_selectedStockProduct!.id, qty, _stockType, reason, APIService.instance.currentUser?.id ?? 1);
      }
      
      _stockChangeController.clear();
      _stockReasonController.clear();
      _selectedStockProduct = null;
      await controller.reloadEnvironment();
      _loadLogs();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('POS Stock level adjusted and activity logged.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
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
