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

class ItemsReportScreen extends StatefulWidget {
  const ItemsReportScreen({Key? key}) : super(key: key);

  @override
  State<ItemsReportScreen> createState() => _ItemsReportScreenState();
}

class _ItemsReportScreenState extends State<ItemsReportScreen> {
  List<OrderModel> _orders = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Advanced Filters
  bool _isFilterExpanded = false;
  final _filterNameController = TextEditingController();
  final _filterCategoryController = TextEditingController();
  String _filterType = '--'; // '--', 'veg', 'non-veg'

  // Applied Filters State
  String _appliedName = '';
  String _appliedCategory = '';
  String _appliedType = '--';

  // Pagination Limit
  int _entriesLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _filterNameController.dispose();
    _filterCategoryController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
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
          _errorMessage = 'Failed to load items data: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Aggregated Items Sales List
  List<Map<String, dynamic>> get _aggregatedSales {
    Map<String, Map<String, dynamic>> salesMap = {};
    for (var o in _orders) {
      for (var item in o.items) {
        final prodName = item.productName;
        final isShortEat = item.isShortEat;
        
        if (!salesMap.containsKey(prodName)) {
          salesMap[prodName] = {
            'name': prodName,
            'category': isShortEat ? 'Short Eats' : 'Main Menu',
            'type': isShortEat ? 'Veg' : 'Non-Veg',
            'quantity': 0,
          };
        }
        salesMap[prodName]!['quantity'] = (salesMap[prodName]!['quantity'] as int) + item.quantity;
      }
    }

    // Apply Filters
    return salesMap.values.where((item) {
      final nameStr = item['name'].toString().toLowerCase();
      final matchName = _appliedName.isEmpty || nameStr.contains(_appliedName);

      final catStr = item['category'].toString().toLowerCase();
      final matchCat = _appliedCategory.isEmpty || catStr.contains(_appliedCategory);

      final typeStr = item['type'].toString().toLowerCase();
      final matchType = _appliedType == '--' || typeStr == _appliedType.toLowerCase();

      return matchName && matchCat && matchType;
    }).toList();
  }

  // Export to CSV
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Name,Category,Type,Quantity\n';
      int totalQty = 0;
      final list = _aggregatedSales.take(_entriesLimit);
      
      for (var i in list) {
        csvContent += '${i['name']},${i['category']},${i['type']},${i['quantity']}\n';
        totalQty += i['quantity'] as int;
      }
      csvContent += 'Total,,, $totalQty\n';

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Items Report',
        fileName: 'Items_Report.csv',
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

  // Print PDF Layout
  Future<void> _printList() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Name', 'Category', 'Type', 'Quantity'];
      final data = _aggregatedSales.take(_entriesLimit).map((i) {
        return [
          i['name'].toString(),
          i['category'].toString(),
          i['type'].toString(),
          i['quantity'].toString()
        ];
      }).toList();

      final totalQty = _aggregatedSales.take(_entriesLimit).fold(0, (sum, i) => sum + (i['quantity'] as int));
      data.add(['Total', '', '', totalQty.toString()]);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Items Sales Report',
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
                    2: pw.Alignment.center,
                    3: pw.Alignment.centerRight,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Items_Report',
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
    final list = _aggregatedSales;
    final displayList = list.take(_entriesLimit).toList();
    final totalSum = displayList.fold(0, (sum, i) => sum + (i['quantity'] as int));

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
                      'Items Report',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Items Report', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    // Entries Limit Dropdown
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

            // Advanced Filters
            if (_isFilterExpanded) ...[
              _buildFilterSection(),
              const SizedBox(height: 16),
            ],

            // Main Table Card
            Expanded(
              child: Card(
                elevation: 0,
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoading
                    ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _errorMessage.isNotEmpty
                        ? Center(child: Text(_errorMessage, style: GoogleFonts.inter(color: Colors.red)))
                        : displayList.isEmpty
                            ? _buildEmptyState()
                            : _buildTable(displayList, totalSum),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    return Card(
      elevation: 0,
      color: Colors.white,
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
                      _buildFieldLabel('NAME'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterNameController,
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
                      _buildFieldLabel('CATEGORY'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterCategoryController,
                        decoration: const InputDecoration(hintText: 'Enter category'),
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
                      _buildFieldLabel('TYPE'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _filterType,
                        items: const [
                          DropdownMenuItem(value: '--', child: Text('--')),
                          DropdownMenuItem(value: 'Veg', child: Text('Veg')),
                          DropdownMenuItem(value: 'Non-Veg', child: Text('Non-Veg')),
                        ],
                        onChanged: (val) => setState(() => _filterType = val!),
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
                      _appliedName = _filterNameController.text.trim().toLowerCase();
                      _appliedCategory = _filterCategoryController.text.trim().toLowerCase();
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
                      _filterNameController.clear();
                      _filterCategoryController.clear();
                      _filterType = '--';
                      
                      _appliedName = '';
                      _appliedCategory = '';
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

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
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
            'No item sales data available.',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<Map<String, dynamic>> list, int total) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Header
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 4, child: _buildTableHeaderText('NAME')),
              Expanded(flex: 3, child: _buildTableHeaderText('CATEGORY')),
              Expanded(flex: 2, child: _buildTableHeaderText('TYPE')),
              Expanded(flex: 2, child: _buildTableHeaderText('QUANTITY')),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final i = list[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text(i['name'].toString(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                    Expanded(flex: 3, child: Text(i['category'].toString(), style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)))),
                    Expanded(flex: 2, child: Text(i['type'].toString(), style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)))),
                    Expanded(flex: 2, child: Text(i['quantity'].toString(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                  ],
                ),
              );
            },
          ),
        ),
        // Total Footer Row
        const Divider(height: 1, color: Color(0xFFCBD5E1), thickness: 1.5),
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 4, child: Text('Total', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
              Expanded(flex: 3, child: const SizedBox.shrink()),
              Expanded(flex: 2, child: const SizedBox.shrink()),
              Expanded(flex: 2, child: Text('$total', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569), letterSpacing: 0.5),
    );
  }
}
