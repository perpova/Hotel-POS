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

class RawMaterialsScreen extends StatefulWidget {
  const RawMaterialsScreen({Key? key}) : super(key: key);

  @override
  State<RawMaterialsScreen> createState() => _RawMaterialsScreenState();
}

class _RawMaterialsScreenState extends State<RawMaterialsScreen> {
  // Raw Ingredient Stock Controllers
  List<IngredientModel> _ingredients = [];
  List<dynamic> _logs = [];
  IngredientModel? _selectedIngredient;
  
  final _ingChangeController = TextEditingController();
  final _ingReasonController = TextEditingController();
  String _ingType = 'purchase'; // 'purchase', 'adjustment', 'wastage'

  // New Ingredient Creation Controllers
  final _newIngNameController = TextEditingController();
  String _newIngUnit = 'kg'; // 'kg', 'units', 'liters', 'grams'
  
  bool _loading = false;

  // Log Filtering & Pagination
  int _entriesLimit = 10;
  bool _isFilterExpanded = false;
  final _filterIngredientController = TextEditingController();
  final _filterDateController = TextEditingController();
  String _filterType = '--'; // '--', 'purchase', 'adjustment', 'wastage'

  // Applied Filters State
  String _appliedIngredient = '';
  String _appliedDate = '';
  String _appliedType = '--';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _ingChangeController.dispose();
    _ingReasonController.dispose();
    _newIngNameController.dispose();
    _filterIngredientController.dispose();
    _filterDateController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final ings = await APIService.instance.getIngredients();
      final logsData = await APIService.instance.getIngredientStockLogs();
      if (mounted) {
        setState(() {
          _ingredients = ings;
          _logs = logsData;
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

  // Filtered logs getter
  List<dynamic> get _filteredLogs {
    return _logs.where((l) {
      final nameStr = (l['ingredient_name'] ?? '').toString().toLowerCase();
      final matchIngredient = _appliedIngredient.isEmpty || nameStr.contains(_appliedIngredient);

      final typeStr = (l['type'] ?? '').toString().toLowerCase();
      final matchType = _appliedType == '--' || typeStr == _appliedType.toLowerCase();

      final timestampStr = (l['timestamp'] ?? '').toString();
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
        fileName: 'Ingredient_Stock_Logs.csv',
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    
    final userRole = APIService.instance.currentUser?.role ?? 'cashier';
    final hasSeniorAccess = userRole == 'admin' || userRole == 'owner';

    final displayLogs = _filteredLogs.take(_entriesLimit).toList();

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
                      'Raw Materials Stock',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Raw Materials', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Limit Dropdown
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      height: 42,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _entriesLimit,
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
                        if (val == 'Print') {
                          _printList();
                        } else if (val == 'XLS') {
                          _exportToCSV();
                        }
                      },
                      offset: const Offset(0, 45),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'Print',
                          child: Row(
                            children: [
                              const Icon(Icons.print_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Text('Print', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'XLS',
                          child: Row(
                            children: [
                              const Icon(Icons.table_view_outlined, size: 16, color: Color(0xFF64748B)),
                              const SizedBox(width: 8),
                              Text('XLS', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.primary),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
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

            // Top overview circles/row
            _buildOverviewRow(),
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
                              flex: 2,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
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
                              child: _buildLogsCard(displayLogs),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildAdjustmentFormCard(hasSeniorAccess),
                              const SizedBox(height: 24),
                              _buildCreateIngredientCard(hasSeniorAccess),
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
  Widget _buildOverviewRow() {
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
  
          return Container(
            width: 180,
            margin: const EdgeInsets.only(right: 12),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                            style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
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
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
  Widget _buildAdjustmentFormCard(bool hasSeniorAccess) {
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
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
              items: [
                ..._ingredients.map((i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${i.name} | Current: ${i.stockQty} ${i.unit}',
                        style: const TextStyle(fontSize: 12),
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
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
              items: const [
                DropdownMenuItem(value: 'kg', child: Text('Kilogram (kg)')),
                DropdownMenuItem(value: 'units', child: Text('Units / Pieces')),
                DropdownMenuItem(value: 'liters', child: Text('Liters (L)')),
                DropdownMenuItem(value: 'grams', child: Text('Grams (g)')),
              ],
              onChanged: (val) => setState(() => _newIngUnit = val!),
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
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                      child: Text('No adjustment history logged.', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
                    ),
                  )
                : Column(
                    children: [
                      // Table header
                      Container(
                        color: const Color(0xFFF8FAFC),
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
                        separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
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
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    l['recorder_name'] ?? 'Admin',
                                    style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                                  ),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: Text(
                                    timeFormatted,
                                    style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
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
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569), letterSpacing: 0.5),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
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
    if (name.isEmpty) return;

    try {
      await APIService.instance.createIngredient(name, _newIngUnit);
      
      _newIngNameController.clear();
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
}
