import 'dart:async';
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
import '../services/translation_service.dart';

class RawMaterialsScreen extends StatefulWidget {
  const RawMaterialsScreen({Key? key}) : super(key: key);

  @override
  State<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends State<RawMaterialsScreen> {
  StreamSubscription? _wsSub;

  // Raw Ingredient Stock Controllers
  List<IngredientModel> _ingredients = [];
  List<dynamic> _logs = [];
  IngredientModel? _selectedIngredient;
  
  final _ingChangeController = TextEditingController();
  final _ingReasonController = TextEditingController();
  String _ingType = 'purchase'; // 'purchase', 'adjustment', 'wastage'

  // New Ingredient Creation Controllers
  final _newIngNameController = TextEditingController();
  final _newIngMinStockController = TextEditingController();
  String _newIngUnit = 'kg'; // 'kg', 'units', 'liters', 'grams'
  
  bool _loading = false;

  // Overnight Prepped Stock state
  ProductModel? _selectedPreppedProduct;
  final _prepQtyController = TextEditingController();
  final _prepNotesController = TextEditingController();
  bool _isSavingPrep = false;

  // Prepped & Cooked Items Table State
  List<PreppedItemModel> _preppedItems = [];
  List<PreppedItemLogModel> _preppedLogs = [];
  final Map<int, TextEditingController> _preppedQtyControllers = {};
  final Map<int, FocusNode> _preppedFocusNodes = {};
  bool _savingPreppedCount = false;

  // Log Filtering & Pagination
  int _entriesLimit = 10;
  bool _isFilterExpanded = false;
  final _filterIngredientController = TextEditingController();
  final _filterDateController = TextEditingController();
  String _filterType = '--'; // '--', 'purchase', 'adjustment', 'wastage'

  // Applied Filters State
  String _appliedIngredient = '';
  String _appliedType = '--';
  String _appliedDate = '';

  // Date Range Presets
  String _datePreset = 'all'; // 'all', 'today', 'weekly', 'monthly', 'yearly', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadData();
    _wsSub = APIService.instance.eventStream.listen((event) {
      final type = event['type']?.toString();
      if (type == 'database_synchronized' ||
          type == 'ws_reconnected' ||
          type == 'ingredient_stock_updated' ||
          type == 'ingredient_created' ||
          type == 'ingredient_updated' ||
          type == 'prepped_stock_updated') {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ingChangeController.dispose();
    _ingReasonController.dispose();
    _newIngNameController.dispose();
    _newIngMinStockController.dispose();
    _filterIngredientController.dispose();
    _filterDateController.dispose();
    _prepQtyController.dispose();
    _prepNotesController.dispose();
    for (var ctrl in _preppedQtyControllers.values) ctrl.dispose();
    for (var fn in _preppedFocusNodes.values) fn.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent && _ingredients.isEmpty) {
      setState(() => _loading = true);
    }
    try {
      final ings = await APIService.instance.getIngredients();
      final logsData = await APIService.instance.getIngredientStockLogs();
      List<PreppedItemModel> prepped = [];
      List<PreppedItemLogModel> preppedLogs = [];
      try {
        prepped = await APIService.instance.getPreppedItems();
        preppedLogs = await APIService.instance.getPreppedItemLogs();
      } catch (pe) {
        print('Error loading prepped items: $pe');
      }

      if (mounted) {
        setState(() {
          _ingredients = ings;
          _logs = logsData;
          _preppedItems = prepped;
          _preppedLogs = preppedLogs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        print('Error loading raw ingredients data: $e');
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

  // Filtered logs getter
  List<dynamic> get _filteredLogs {
    return _logs.where((l) {
      final nameStr = (l['ingredient_name'] ?? '').toString().toLowerCase();
      final matchIngredient = _appliedIngredient.isEmpty || nameStr.contains(_appliedIngredient);

      final typeStr = (l['type'] ?? '').toString().toLowerCase();
      final matchType = _appliedType == '--' || typeStr == _appliedType.toLowerCase();

      final timestampStr = (l['timestamp'] ?? '').toString();
      if (!_isWithinDateRange(timestampStr)) return false;

      final dateFormatted = DateFormat('yyyy-MM-dd').format((DateTime.tryParse(timestampStr) ?? DateTime.now()).toLocal());
      final matchDate = _appliedDate.isEmpty || dateFormatted.contains(_appliedDate);

      return matchIngredient && matchType && matchDate;
    }).toList();
  }

  // Export logs to CSV spreadsheet
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Ingredient,Change,Log Type,Reason,Recorder,Date & Time\n';
      for (var l in _filteredLogs.take(_entriesLimit)) {
        final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
        final isPositive = changeVal > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
        
        csvContent += '${l['ingredient_name']},${isPositive ? "+" : ""}$changeVal,${l['type'].toString().toUpperCase()},${l['reason']},${l['recorder_name'] ?? "Admin"},$timeFormatted\n';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Ingredient Transaction Logs',
        fileName: 'Ingredient_Stock_Logs_${_datePreset.toUpperCase()}.csv',
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

  // Export PDF transaction log file
  Future<void> _exportToPDF() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Ingredient', 'Change', 'Log Type', 'Reason', 'Recorder', 'Date & Time'];
      final data = _filteredLogs.take(_entriesLimit).map((l) {
        final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
        final isPositive = changeVal > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
        
        return [
          (l['ingredient_name'] ?? 'N/A').toString(),
          '${isPositive ? "+" : ""}${changeVal.toStringAsFixed(1)}',
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
                  'Ingredient Stock Log (${_datePreset.toUpperCase()})',
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
        fileName: 'Ingredient_Stock_Logs_${_datePreset.toUpperCase()}.pdf',
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

  // Print PDF transaction log
  Future<void> _printList() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Ingredient', 'Change', 'Log Type', 'Reason', 'Recorder', 'Date & Time'];
      final data = _filteredLogs.take(_entriesLimit).map((l) {
        final changeVal = double.tryParse(l['change_qty'].toString()) ?? 0.00;
        final isPositive = changeVal > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l['timestamp']) ?? DateTime.now()).toLocal());
        
        return [
          (l['ingredient_name'] ?? 'N/A').toString(),
          '${isPositive ? "+" : ""}${changeVal.toStringAsFixed(1)}',
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
                  'Ingredient Stock Log',
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
        name: 'Ingredient_Stock_Logs',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Widget _buildWarningBanner(List<IngredientModel> lowStock) {
    if (lowStock.isEmpty) return const SizedBox.shrink();
    final names = lowStock.map((i) => '${i.name} (${i.stockQty.toStringAsFixed(1)} ${i.unit})').join(', ');
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
                  'Depleted / Negative Stock Warning!'.tr(context),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.isDarkMode ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The following ingredients are out of stock or negative: $names. Please update stock level immediately to prevent recipe deduction errors.'.tr(context),
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

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppTheme.danger : AppTheme.accent,
    ));
  }

  Future<void> _handleRecordPreppedStock() async {
    if (_selectedPreppedProduct == null) {
      _showSnack('Please select a POS product item (e.g. Fish Roll).', isError: true);
      return;
    }
    final qty = double.tryParse(_prepQtyController.text.trim()) ?? 0.0;
    if (qty <= 0) {
      _showSnack('Please enter a valid quantity (> 0).', isError: true);
      return;
    }

    setState(() => _isSavingPrep = true);
    try {
      final productName = _selectedPreppedProduct!.name;
      final rawName = '$productName (Prepped Raw)';

      // 1. Check if ingredient already exists for this prepped product
      IngredientModel? targetIng;
      for (var ing in _ingredients) {
        if (ing.name.toLowerCase() == rawName.toLowerCase() || ing.name.toLowerCase() == productName.toLowerCase()) {
          targetIng = ing;
          break;
        }
      }

      // 2. Create raw ingredient if not present
      if (targetIng == null) {
        await APIService.instance.createIngredient(
          rawName,
          'units',
          minStockLevel: 5,
        );
        // Reload ingredients list
        await _loadData();
        for (var ing in _ingredients) {
          if (ing.name.toLowerCase() == rawName.toLowerCase()) {
            targetIng = ing;
            break;
          }
        }
      }

      if (targetIng != null) {
        final notes = _prepNotesController.text.trim();
        final reasonStr = 'Overnight / Pre-fried batch entry for $productName${notes.isNotEmpty ? ' ($notes)' : ''}';

        await APIService.instance.adjustIngredientStock(
          targetIng.id,
          qty,
          'purchase',
          reasonStr,
        );
      }

      _prepQtyController.clear();
      _prepNotesController.clear();
      setState(() => _selectedPreppedProduct = null);

      await _loadData();
      _showSnack('Recorded $qty units of prepped stock for "$productName" into Raw Materials Inventory!');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _isSavingPrep = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    
    final userRole = APIService.instance.currentUser?.role ?? 'cashier';
    final hasSeniorAccess = userRole == 'admin' || userRole == 'owner';

    final displayLogs = _filteredLogs.take(_entriesLimit).toList();
    final lowStockIngredients = _ingredients.where((i) => i.stockQty <= i.minStockLevel).toList();

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
                      'Raw Materials Stock'.tr(context),
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard'.tr(context), style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Raw Materials'.tr(context), style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
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
                      label: Text('Filter'.tr(context), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
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
            _buildWarningBanner(lowStockIngredients),

            // Top overview circles/row
            _buildOverviewRow(hasSeniorAccess),
            const SizedBox(height: 24),

            // Collapsible advanced filters
            if (_isFilterExpanded) ...[
              _buildFilterSection(),
              const SizedBox(height: 16),
            ],

            Expanded(
              child: _loading
                  ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildPreppedItemsCard(hasSeniorAccess),
                                    const SizedBox(height: 24),
                                    _buildPreppedStockFormCard(controller, hasSeniorAccess),
                                    const SizedBox(height: 24),
                                    _buildAdjustmentFormCard(hasSeniorAccess),
                                    const SizedBox(height: 24),
                                    _buildCreateIngredientCard(hasSeniorAccess),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildPreppedItemLogsCard(_preppedLogs.take(_entriesLimit).toList()),
                                    const SizedBox(height: 24),
                                    _buildLogsCard(displayLogs),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildPreppedItemsCard(hasSeniorAccess),
                              const SizedBox(height: 24),
                              _buildPreppedStockFormCard(controller, hasSeniorAccess),
                              const SizedBox(height: 24),
                              _buildAdjustmentFormCard(hasSeniorAccess),
                              const SizedBox(height: 24),
                              _buildCreateIngredientCard(hasSeniorAccess),
                              const SizedBox(height: 24),
                              _buildPreppedItemLogsCard(_preppedLogs.take(_entriesLimit).toList()),
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
  // OVERVIEW CARDS ROW
  // ----------------------------------------------------
  Widget _buildOverviewRow(bool hasSeniorAccess) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _ingredients.map((i) {
          Color cardColor;
          IconData icon;
          
          switch (i.name.toLowerCase()) {
            case 'rice':
              cardColor = Colors.amber;
              icon = Icons.rice_bowl_outlined;
              break;
            case 'egg':
              cardColor = Colors.orange;
              icon = Icons.egg_outlined;
              break;
            case 'chicken':
              cardColor = Colors.red;
              icon = Icons.restaurant_outlined;
              break;
            case 'oil':
              cardColor = Colors.blue;
              icon = Icons.opacity;
              break;
            case 'flour':
              cardColor = Colors.brown;
              icon = Icons.bakery_dining_outlined;
              break;
            default:
              cardColor = AppTheme.primary;
              icon = Icons.shopping_basket_outlined;
          }
   
          final isDepleted = i.stockQty <= i.minStockLevel;
          return GestureDetector(
            onTap: hasSeniorAccess ? () => _showEditIngredientDialog(i) : null,
            child: Container(
              width: 180,
              margin: const EdgeInsets.only(right: 12),
              child: Card(
                elevation: 0,
                color: isDepleted ? (AppTheme.isDarkMode ? const Color(0xFF7F1D1D) : const Color(0xFFFEF2F2)) : AppTheme.cardLight,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: isDepleted ? const Color(0xFFFCA5A5) : (AppTheme.isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0)), width: isDepleted ? 1.5 : 1.0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cardColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: cardColor, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(i.name, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Text(
                              '${i.stockQty.toStringAsFixed(1)} ${i.unit}',
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isDepleted ? const Color(0xFFDC2626) : AppTheme.textLightPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
                      _buildFieldLabel('INGREDIENT NAME'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterIngredientController,
                        decoration: const InputDecoration(hintText: 'Enter ingredient name'),
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
                      _appliedIngredient = _filterIngredientController.text.trim().toLowerCase();
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
                      _filterIngredientController.clear();
                      _filterDateController.clear();
                      _filterType = '--';
                      
                      _appliedIngredient = '';
                      _appliedDate = '';
                      _appliedType = '--';
                    });
                  },
                  icon: const Icon(Icons.clear, size: 14),
                  label: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // PREPPED & COOKED ITEMS STOCK TABLE CARD
  // ----------------------------------------------------
  Widget _buildPreppedItemsCard(bool hasSeniorAccess) {
    final canAccessPrepped = APIService.instance.isPreppedItemsTableAllowed();
    final canManageUnits = APIService.instance.canManagePreppedItemUnits();

    if (!canAccessPrepped) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.primary.withOpacity(0.4), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.soup_kitchen_outlined, color: AppTheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Newly Purchased Items Stock'.tr(context),
                              style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                            ),
                            Text(
                              'Record & monitor daily purchased items, stock entries, and inventory levels'.tr(context),
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (canManageUnits)
                  ElevatedButton.icon(
                    onPressed: _showAddPreppedItemDialog,
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: Text('Add New Item & Unit'.tr(context), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Prepped items table
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Table header
                  Container(
                    color: AppTheme.bgLight,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: _buildTableHeaderText('PREPPED ITEM')),
                        Expanded(flex: 1, child: _buildTableHeaderText('UNIT')),
                        Expanded(flex: 2, child: _buildTableHeaderText('CURRENT STOCK')),
                        Expanded(flex: 5, child: _buildTableHeaderText('COUNT ENTRY (+ / -)')),
                        if (canManageUnits)
                          Expanded(flex: 1, child: _buildTableHeaderText('ACTIONS')),
                      ],
                    ),
                  ),
                  _preppedItems.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Center(
                            child: Text('No prepped items registered.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _preppedItems.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                          itemBuilder: (context, index) {
                            final item = _preppedItems[index];
                            final rowCtrl = _preppedQtyControllers.putIfAbsent(item.id, () => TextEditingController(text: '1'));
                            final rowNode = _preppedFocusNodes.putIfAbsent(item.id, () => FocusNode());
                            final isBoiledEgg = item.name.toLowerCase().contains('egg') || item.name.toLowerCase().contains('බිත්තර');

                            void submitAndFocusNext(double changeQty, String type, {bool deductRawEgg = false}) {
                              _handleAdjustPreppedStock(item, changeQty, type, deductRawEgg: deductRawEgg);
                              if (index + 1 < _preppedItems.length) {
                                final nextItem = _preppedItems[index + 1];
                                final nextNode = _preppedFocusNodes[nextItem.id];
                                final nextCtrl = _preppedQtyControllers[nextItem.id];
                                if (nextNode != null) {
                                  nextNode.requestFocus();
                                  if (nextCtrl != null) {
                                    nextCtrl.selection = TextSelection(baseOffset: 0, extentOffset: nextCtrl.text.length);
                                  }
                                }
                              }
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name.tr(context),
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                        ),
                                        if (item.sinhalaName != null && item.sinhalaName!.isNotEmpty)
                                          Text(
                                            item.sinhalaName!,
                                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppTheme.bgLight,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: AppTheme.borderLight),
                                        ),
                                        child: Text(
                                          item.unit,
                                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${item.currentStock.toStringAsFixed(0)} ${item.unit}',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: item.currentStock <= item.minStockLevel ? const Color(0xFFDC2626) : AppTheme.textLightPrimary,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 5,
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 58,
                                          height: 36,
                                          child: TextField(
                                            controller: rowCtrl,
                                            focusNode: rowNode,
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                            textInputAction: TextInputAction.next,
                                            onTap: () {
                                              rowCtrl.selection = TextSelection(baseOffset: 0, extentOffset: rowCtrl.text.length);
                                            },
                                            onSubmitted: (val) {
                                              final qty = double.tryParse(val) ?? 1.0;
                                              submitAndFocusNext(qty, 'addition');
                                            },
                                            decoration: InputDecoration(
                                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                              border: const OutlineInputBorder(),
                                              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.primary, width: 2)),
                                            ),
                                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        ElevatedButton(
                                          onPressed: () {
                                            final qty = double.tryParse(rowCtrl.text) ?? 1.0;
                                            submitAndFocusNext(qty, 'addition');
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF10B981),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: const Text('+ Add', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 4),
                                        OutlinedButton(
                                          onPressed: () {
                                            final qty = double.tryParse(rowCtrl.text) ?? 1.0;
                                            submitAndFocusNext(-qty, 'deduction');
                                          },
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: AppTheme.danger,
                                            side: const BorderSide(color: AppTheme.danger),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: const Text('- Less', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        if (isBoiledEgg) ...[
                                          const SizedBox(width: 6),
                                          ElevatedButton(
                                            onPressed: () => submitAndFocusNext(60.0, 'addition', deductRawEgg: true),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.orange,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                            ),
                                            child: const Text('+60 Boiled', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  if (canManageUnits)
                                    Expanded(
                                      flex: 1,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          IconButton(
                                            icon: Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary),
                                            onPressed: () => _showEditPreppedItemDialog(item),
                                            tooltip: 'Edit Unit / Item',
                                          ),
                                          IconButton(
                                            icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                                            onPressed: () => _confirmDeletePreppedItem(item),
                                            tooltip: 'Delete Item',
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAdjustPreppedStock(PreppedItemModel item, double changeQty, String type, {bool deductRawEgg = false}) async {
    try {
      final isBoiledEgg = item.name.toLowerCase().contains('egg') || item.name.toLowerCase().contains('බිත්තර');
      final reasonStr = type == 'addition'
          ? 'Prepped stock addition (+${changeQty.toStringAsFixed(0)} ${item.unit})${deductRawEgg || isBoiledEgg ? ' [Raw Egg Deducted]' : ''}'
          : 'Prepped stock usage/deduction (${changeQty.toStringAsFixed(0)} ${item.unit})';

      await APIService.instance.adjustPreppedItemStock(item.id, changeQty, type, reasonStr, deductRawEgg: deductRawEgg || isBoiledEgg);
      await _loadData();
      _showSnack('${type == "addition" ? "+" : ""}${changeQty.toStringAsFixed(0)} ${item.name} stock updated successfully!');
    } catch (e) {
      _showSnack(e.toString(), isError: true);
    }
  }

  void _showAddPreppedItemDialog() {
    final nameCtrl = TextEditingController();
    final sinhalaCtrl = TextEditingController();
    final minStockCtrl = TextEditingController(text: '5.0');
    String selectedUnit = 'units';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.add_circle_outline, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Add Prepped Item & Unit'.tr(context), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('PREPPED ITEM NAME *'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(hintText: 'e.g. Cutlets, Pastry'),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 16),
                    _buildFieldLabel('SINHALA NAME (OPTIONAL)'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: sinhalaCtrl,
                      decoration: const InputDecoration(hintText: 'e.g. කට්ලට්ස්'),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 16),
                    _buildFieldLabel('MEASUREMENT UNIT *'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedUnit,
                      dropdownColor: AppTheme.cardLight,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                      items: const [
                        DropdownMenuItem(value: 'units', child: Text('Units / Pieces')),
                        DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                        DropdownMenuItem(value: 'grams', child: Text('Grams (g)')),
                        DropdownMenuItem(value: 'liters', child: Text('Liters (L)')),
                        DropdownMenuItem(value: 'packs', child: Text('Packs / Batches')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedUnit = val!),
                    ),
                    const SizedBox(height: 16),
                    _buildFieldLabel('MIN STOCK ALERT LEVEL'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: minStockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'e.g. 5.0'),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final minStock = double.tryParse(minStockCtrl.text.trim()) ?? 5.0;

                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    try {
                      await APIService.instance.createPreppedItem(name, selectedUnit, sinhalaName: sinhalaCtrl.text.trim(), minStockLevel: minStock);
                      await _loadData();
                      _showSnack('New prepped item "$name" created successfully!');
                    } catch (e) {
                      setState(() => _loading = false);
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  child: const Text('Create Item'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditPreppedItemDialog(PreppedItemModel item) {
    final nameCtrl = TextEditingController(text: item.name);
    final sinhalaCtrl = TextEditingController(text: item.sinhalaName ?? '');
    final minStockCtrl = TextEditingController(text: item.minStockLevel.toStringAsFixed(0));
    String selectedUnit = item.unit;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.edit_outlined, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Edit Prepped Item & Unit'.tr(context), style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('PREPPED ITEM NAME *'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 16),
                    _buildFieldLabel('SINHALA NAME'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: sinhalaCtrl,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 16),
                    _buildFieldLabel('MEASUREMENT UNIT *'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedUnit,
                      dropdownColor: AppTheme.cardLight,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                      items: const [
                        DropdownMenuItem(value: 'units', child: Text('Units / Pieces')),
                        DropdownMenuItem(value: 'kg', child: Text('Kilograms (kg)')),
                        DropdownMenuItem(value: 'grams', child: Text('Grams (g)')),
                        DropdownMenuItem(value: 'liters', child: Text('Liters (L)')),
                        DropdownMenuItem(value: 'packs', child: Text('Packs / Batches')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedUnit = val!),
                    ),
                    const SizedBox(height: 16),
                    _buildFieldLabel('MIN STOCK ALERT LEVEL'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: minStockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final minStock = double.tryParse(minStockCtrl.text.trim()) ?? 5.0;

                    Navigator.pop(ctx);
                    setState(() => _loading = true);
                    try {
                      await APIService.instance.updatePreppedItem(item.id, name, selectedUnit, minStock, sinhalaName: sinhalaCtrl.text.trim());
                      await _loadData();
                      _showSnack('Prepped item "$name" updated successfully!');
                    } catch (e) {
                      setState(() => _loading = false);
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeletePreppedItem(PreppedItemModel item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardLight,
        title: Text('Delete Prepped Item', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
        content: Text('Are you sure you want to delete ${item.name}? This cannot be undone.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _loading = true);
              try {
                await APIService.instance.deletePreppedItem(item.id);
                await _loadData();
                _showSnack('${item.name} deleted successfully.');
              } catch (e) {
                setState(() => _loading = false);
                _showSnack(e.toString(), isError: true);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreppedItemLogsCard(List<PreppedItemLogModel> logsList) {
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Newly Purchased Item Logs'.tr(context),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                OutlinedButton.icon(
                  onPressed: _exportPreppedPDF,
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 14),
                  label: const Text('PDF Log'),
                  style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: BorderSide(color: AppTheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            logsList.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40.0),
                    child: Center(
                      child: Text('No prepped item adjustment logs found.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
                    ),
                  )
                : Column(
                    children: [
                      Container(
                        color: AppTheme.bgLight,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(flex: 3, child: _buildTableHeaderText('PREPPED ITEM')),
                            Expanded(flex: 2, child: _buildTableHeaderText('CHANGE')),
                            Expanded(flex: 3, child: _buildTableHeaderText('LOG TYPE')),
                            Expanded(flex: 3, child: _buildTableHeaderText('REASON')),
                            Expanded(flex: 3, child: _buildTableHeaderText('RECORDER')),
                            Expanded(flex: 4, child: _buildTableHeaderText('DATE & TIME')),
                          ],
                        ),
                      ),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: logsList.length,
                        separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                        itemBuilder: (context, index) {
                          final l = logsList[index];
                          final isPositive = l.changeQty > 0;
                          final timeFormatted = DateFormat('hh:mm a, dd-MM-yyyy').format((DateTime.tryParse(l.timestamp) ?? DateTime.now()).toLocal());

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l.preppedItemName,
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${isPositive ? "+" : ""}${l.changeQty.toStringAsFixed(0)}',
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
                                      decoration: BoxDecoration(
                                        color: isPositive ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        l.type.toUpperCase(),
                                        style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: isPositive ? const Color(0xFF137333) : const Color(0xFFC5221F)),
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l.reason ?? '',
                                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l.recorderName,
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

  Future<void> _exportPreppedPDF() async {
    try {
      final doc = pw.Document();
      final headers = ['Prepped Item', 'Change Qty', 'Log Type', 'Reason', 'Recorder', 'Date & Time'];
      final data = _preppedLogs.take(50).map((l) {
        final isPositive = l.changeQty > 0;
        final timeFormatted = DateFormat('yyyy-MM-dd HH:mm').format((DateTime.tryParse(l.timestamp) ?? DateTime.now()).toLocal());
        return [
          l.preppedItemName,
          '${isPositive ? "+" : ""}${l.changeQty.toStringAsFixed(0)}',
          l.type.toUpperCase(),
          l.reason ?? '',
          l.recorderName,
          timeFormatted,
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
                  'Prepped & Cooked Items Stock Report',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 16),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 25,
                ),
              ],
            );
          },
        ),
      );

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Prepped Stock PDF Report',
        fileName: 'Prepped_Stock_Logs_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsBytes(await doc.save());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Prepped Stock PDF saved to: $resultPath'), backgroundColor: AppTheme.accent),
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

  // ----------------------------------------------------
  // OVERNIGHT PREPPED UNFRIED STOCK FORM CARD
  // ----------------------------------------------------
  Widget _buildPreppedStockFormCard(POSController controller, bool hasSeniorAccess) {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.soup_kitchen_outlined, color: AppTheme.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Record Overnight / Prepped Unfried Items',
                          style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                      Text('Record raw prepared items (e.g. Unfried Rolls) into Raw Material Inventory before frying',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildFieldLabel('SELECT POS PRODUCT (TRACK STOCK CHECKED) *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<ProductModel>(
              value: _selectedPreppedProduct != null && controller.products.contains(_selectedPreppedProduct) ? _selectedPreppedProduct : null,
              dropdownColor: AppTheme.cardLight,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
              hint: Text('Choose POS stock item (e.g. Fish Roll, Egg Roti)...', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
              items: controller.products.where((p) => p.trackStock).map((p) {
                final rawName = '${p.name} (Prepped Raw)'.toLowerCase();
                final existingIng = _ingredients.firstWhere(
                  (i) => i.name.toLowerCase() == rawName || i.name.toLowerCase() == p.name.toLowerCase(),
                  orElse: () => IngredientModel(id: 0, name: '', unit: '', stockQty: 0, minStockLevel: 0),
                );
                final rawStockStr = existingIng.id != 0 ? '${existingIng.stockQty.toStringAsFixed(0)} units' : '0 units';
                return DropdownMenuItem(
                  value: p,
                  child: Text('${p.name} | Raw Prepped Stock: $rawStockStr', style: const TextStyle(fontSize: 12)),
                );
              }).toList(),
              onChanged: (prod) => setState(() => _selectedPreppedProduct = prod),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('PREPARED QTY *'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _prepQtyController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(hintText: 'e.g. 50'),
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
                      _buildFieldLabel('PREP REMARKS / NOTES'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _prepNotesController,
                        decoration: const InputDecoration(hintText: 'e.g. Night shift batch'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            ElevatedButton.icon(
              onPressed: _isSavingPrep ? null : _handleRecordPreppedStock,
              icon: _isSavingPrep
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_isSavingPrep ? 'Saving Prepped Stock...' : 'Save Prepped Stock to Raw Materials',
                  style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildAdjustmentFormCard(bool hasSeniorAccess) {
    if (!hasSeniorAccess) {
      return Card(
        color: AppTheme.danger.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: AppTheme.danger)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, color: AppTheme.danger, size: 32),
              const SizedBox(height: 12),
              Text(
                'Stock entering and adjustments are locked. Only Admins or Owners can make adjustments to raw ingredients stock levels.',
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
                const Icon(Icons.edit_note, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text('Stock Entering & Corrections', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              ],
            ),
            const SizedBox(height: 20),

            _buildFieldLabel('SELECT INGREDIENT *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<IngredientModel>(
              value: _selectedIngredient,
              dropdownColor: AppTheme.cardLight,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
              items: [
                ..._ingredients.map((i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${i.name} | Current: ${i.stockQty} ${i.unit}',
                        style: TextStyle(fontSize: 12, color: AppTheme.textLightPrimary),
                      ),
                    )),
              ],
              onChanged: (ing) => setState(() => _selectedIngredient = ing),
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
                        controller: _ingChangeController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'e.g. 50, -5'),
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
                        value: _ingType,
                        dropdownColor: AppTheme.cardLight,
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                        items: const [
                          DropdownMenuItem(value: 'purchase', child: Text('New Purchase / Input')),
                          DropdownMenuItem(value: 'adjustment', child: Text('Correction / Count')),
                          DropdownMenuItem(value: 'wastage', child: Text('Wastage / Spoiled')),
                        ],
                        onChanged: (val) => setState(() => _ingType = val!),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildFieldLabel('REASON / REMARK *'),
            const SizedBox(height: 6),
            TextField(
              controller: _ingReasonController,
              decoration: const InputDecoration(hintText: 'e.g. weekly supply, egg breakage'),
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _handleAdjustIngredientStock,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Update Ingredient Stock Level', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // CREATE NEW INGREDIENT FORM CARD
  // ----------------------------------------------------
  Widget _buildCreateIngredientCard(bool hasSeniorAccess) {
    if (!hasSeniorAccess) return const SizedBox.shrink();

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
                Icon(Icons.add_circle_outline, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Add New Raw Ingredient', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              ],
            ),
            const SizedBox(height: 20),

            _buildFieldLabel('INGREDIENT NAME *'),
            const SizedBox(height: 6),
            TextField(
              controller: _newIngNameController,
              decoration: const InputDecoration(hintText: 'e.g. Sugar, Cardamom'),
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 16),

            _buildFieldLabel('MEASUREMENT UNIT *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _newIngUnit,
              dropdownColor: AppTheme.cardLight,
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
              items: const [
                DropdownMenuItem(value: 'kg', child: Text('Kilogram (kg)')),
                DropdownMenuItem(value: 'units', child: Text('Units / Pieces')),
                DropdownMenuItem(value: 'liters', child: Text('Liters (L)')),
                DropdownMenuItem(value: 'grams', child: Text('Grams (g)')),
              ],
              onChanged: (val) => setState(() => _newIngUnit = val!),
            ),
            _buildFieldLabel('LOW STOCK ALERT COUNT *'),
            const SizedBox(height: 6),
            TextField(
              controller: _newIngMinStockController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'e.g. 10.0, 50.0'),
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _handleCreateIngredient,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Create Ingredient', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // ADJUSTMENT LOGS LEDGER
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
              'Ingredient Transaction Logs',
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
                            Expanded(flex: 3, child: _buildTableHeaderText('INGREDIENT')),
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
                              badgeColor = AppTheme.isDarkMode ? const Color(0xFF137333).withOpacity(0.2) : const Color(0xFFE6F4EA);
                              badgeTextColor = AppTheme.isDarkMode ? const Color(0xFF81C784) : const Color(0xFF137333);
                              badgeLabel = 'PURCHASE';
                              break;
                            case 'wastage':
                              badgeColor = AppTheme.isDarkMode ? const Color(0xFFC5221F).withOpacity(0.2) : const Color(0xFFFCE8E6);
                              badgeTextColor = AppTheme.isDarkMode ? const Color(0xFFE57373) : const Color(0xFFC5221F);
                              badgeLabel = 'WASTAGE';
                              break;
                            default:
                              badgeColor = AppTheme.isDarkMode ? const Color(0xFF1A73E8).withOpacity(0.2) : const Color(0xFFE8F0FE);
                              badgeTextColor = AppTheme.isDarkMode ? const Color(0xFF64B5F6) : const Color(0xFF1A73E8);
                              badgeLabel = 'CORRECTION';
                          }

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l['ingredient_name'] ?? 'N/A',
                                    style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    '${isPositive ? "+" : ""}${changeVal.toStringAsFixed(1)}',
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

  void _handleAdjustIngredientStock() async {
    if (_selectedIngredient == null) return;
    final qty = double.tryParse(_ingChangeController.text) ?? 0.0;
    final reason = _ingReasonController.text.trim();
    if (qty == 0.0 || reason.isEmpty) return;

    try {
      await APIService.instance.adjustIngredientStock(_selectedIngredient!.id, qty, _ingType, reason);
      
      _ingChangeController.clear();
      _ingReasonController.clear();
      _selectedIngredient = null;
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Raw ingredient stock level adjusted and activity logged.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _handleCreateIngredient() async {
    final name = _newIngNameController.text.trim();
    final minStockStr = _newIngMinStockController.text.trim();
    if (name.isEmpty) return;
    final minStock = double.tryParse(minStockStr) ?? 0.0;

    try {
      await APIService.instance.createIngredient(name, _newIngUnit, minStockLevel: minStock);
      
      _newIngNameController.clear();
      _newIngMinStockController.clear();
      setState(() => _newIngUnit = 'kg');
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('New ingredient created successfully!'), backgroundColor: AppTheme.accent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _showEditIngredientDialog(IngredientModel ingredient) {
    final nameCtrl = TextEditingController(text: ingredient.name);
    final minStockCtrl = TextEditingController(text: ingredient.minStockLevel.toStringAsFixed(1));
    String selectedUnit = ingredient.unit;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Icon(Icons.edit_outlined, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Edit Ingredient', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('INGREDIENT NAME *'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(hintText: 'e.g. Sugar, Cardamom'),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildFieldLabel('MEASUREMENT UNIT *'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedUnit,
                      dropdownColor: AppTheme.cardLight,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                      items: const [
                        DropdownMenuItem(value: 'kg', child: Text('Kilogram (kg)')),
                        DropdownMenuItem(value: 'units', child: Text('Units / Pieces')),
                        DropdownMenuItem(value: 'liters', child: Text('Liters (L)')),
                        DropdownMenuItem(value: 'grams', child: Text('Grams (g)')),
                      ],
                      onChanged: (val) => setDialogState(() => selectedUnit = val!),
                    ),
                    const SizedBox(height: 16),
                    
                    _buildFieldLabel('LOW STOCK ALERT COUNT *'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: minStockCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: 'e.g. 10.0, 50.0'),
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (confirmContext) {
                            return AlertDialog(
                              backgroundColor: AppTheme.cardLight,
                              title: Text('Delete Ingredient', style: TextStyle(color: AppTheme.textLightPrimary)),
                              content: Text('Are you sure you want to delete ${ingredient.name}? This will permanently remove it from stock records.', style: TextStyle(color: AppTheme.textLightPrimary)),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(confirmContext),
                                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    Navigator.pop(confirmContext); // Close confirm
                                    Navigator.pop(context); // Close edit dialog
                                    setState(() => _loading = true);
                                    try {
                                      await APIService.instance.deleteIngredient(ingredient.id);
                                      await _loadData();
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('${ingredient.name} deleted successfully.'), backgroundColor: AppTheme.danger),
                                        );
                                      }
                                    } catch (e) {
                                      setState(() => _loading = false);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Failed to delete ingredient: $e'), backgroundColor: AppTheme.danger),
                                        );
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                                  child: const Text('Delete', style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            );
                          },
                        );
                      },
                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                      label: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger, fontWeight: FontWeight.bold)),
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            final minStockStr = minStockCtrl.text.trim();
                            if (name.isEmpty) return;
                            final minStock = double.tryParse(minStockStr) ?? 0.0;

                            Navigator.pop(context); // Close dialog
                            setState(() => _loading = true);
                            try {
                              await APIService.instance.updateIngredient(ingredient.id, name, selectedUnit, minStock);
                              await _loadData();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Ingredient updated successfully!'), backgroundColor: AppTheme.accent),
                                );
                              }
                            } catch (e) {
                              setState(() => _loading = false);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to update ingredient: $e'), backgroundColor: AppTheme.danger),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
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
