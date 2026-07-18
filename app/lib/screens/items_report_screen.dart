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
  List<ProductModel> _products = [];
  List<IngredientModel> _ingredients = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Active Report Tab: 'sales' (default), 'pos_stock', 'raw_stock'
  String _activeTab = 'sales';

  // Date Range Presets
  String _datePreset = 'all'; // 'all', 'today', 'weekly', 'monthly', 'yearly', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

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
      final results = await Future.wait([
        APIService.instance.getOrders(),
        APIService.instance.getProducts(),
        APIService.instance.getIngredients(),
      ]);

      final rawOrders = results[0] as List<OrderModel>;
      final populatedOrders = await Future.wait(rawOrders.map((o) async {
        try {
          final items = await APIService.instance.getOrderItems(o.id!);
          return OrderModel(
            id: o.id,
            orderNumber: o.orderNumber,
            tableId: o.tableId,
            orderType: o.orderType,
            deliveryPlatform: o.deliveryPlatform,
            customerId: o.customerId,
            stewardName: o.stewardName,
            status: o.status,
            paymentStatus: o.paymentStatus,
            paymentMethod: o.paymentMethod,
            subtotal: o.subtotal,
            discount: o.discount,
            total: o.total,
            cashierId: o.cashierId,
            shiftId: o.shiftId,
            kotPrinted: o.kotPrinted,
            ackPrinted: o.ackPrinted,
            cardTxReference: o.cardTxReference,
            barcode: o.barcode,
            createdAt: o.createdAt,
            updatedAt: o.updatedAt,
            receivedAmount: o.receivedAmount,
            changeAmount: o.changeAmount,
            items: items,
          );
        } catch (_) {
          return o;
        }
      }));

      if (mounted) {
        setState(() {
          _orders = populatedOrders;
          _products = results[1] as List<ProductModel>;
          _ingredients = results[2] as List<IngredientModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load report data: $e';
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

  // Aggregated Items Sales List
  List<Map<String, dynamic>> get _aggregatedSales {
    Map<String, Map<String, dynamic>> salesMap = {};
    for (var o in _orders) {
      if (!_isWithinDateRange(o.createdAt)) continue;

      for (var item in o.items) {
        final baseName = item.productName;
        final notes = item.notes;
        String? size;
        if (notes != null && notes.isNotEmpty) {
          final parts = notes.split(' | ');
          for (var part in parts) {
            if (part.trim().startsWith('Size: ')) {
              size = part.trim().replaceFirst('Size: ', '').trim();
              break;
            }
          }
        }

        final prodName = size != null && size.isNotEmpty ? "$baseName ($size)" : baseName;
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

  // Filtered Products
  List<ProductModel> get _filteredProducts {
    return _products.where((p) {
      final matchName = _appliedName.isEmpty || p.name.toLowerCase().contains(_appliedName);
      final matchCat = _appliedCategory.isEmpty || p.categoryId.toString().toLowerCase().contains(_appliedCategory);
      final matchType = _appliedType == '--' || p.itemType.toLowerCase() == _appliedType.toLowerCase();
      return matchName && matchCat && matchType;
    }).toList();
  }

  // Filtered Ingredients
  List<IngredientModel> get _filteredIngredients {
    return _ingredients.where((i) {
      final matchName = _appliedName.isEmpty || i.name.toLowerCase().contains(_appliedName);
      return matchName;
    }).toList();
  }

  // Export to CSV
  Future<void> _exportToCSV() async {
    try {
      String csvContent = '';
      String filename = '';

      if (_activeTab == 'sales') {
        csvContent = 'Name,Category,Type,Quantity\n';
        int totalQty = 0;
        final list = _aggregatedSales.take(_entriesLimit);
        for (var i in list) {
          csvContent += '${i['name']},${i['category']},${i['type']},${i['quantity']}\n';
          totalQty += i['quantity'] as int;
        }
        csvContent += 'Total,,, $totalQty\n';
        filename = 'Items_Sales_Report_${_datePreset.toUpperCase()}.csv';
      } else if (_activeTab == 'pos_stock') {
        csvContent = 'Product Name,Category ID,Stock Qty,Min Stock,Status\n';
        final list = _filteredProducts.take(_entriesLimit);
        for (var p in list) {
          final isLow = p.trackStock && p.stockQty <= p.minStockLevel;
          csvContent += '${p.name},${p.categoryId},${p.stockQty},${p.minStockLevel},${isLow ? 'LOW STOCK' : 'OK'}\n';
        }
        filename = 'POS_Items_Stock_Report.csv';
      } else {
        csvContent = 'Ingredient Name,Unit,Stock Qty,Min Alert Level,Status\n';
        final list = _filteredIngredients.take(_entriesLimit);
        for (var ing in list) {
          final isLow = ing.stockQty <= ing.minStockLevel;
          csvContent += '${ing.name},${ing.unit},${ing.stockQty},${ing.minStockLevel},${isLow ? 'DEPLETED' : 'OK'}\n';
        }
        filename = 'Raw_Ingredients_Stock_Report.csv';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export CSV Report',
        fileName: filename,
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

  // Build PDF document shared helper
  Future<pw.Document> _buildPDFDoc() async {
    final doc = pw.Document();
    
    if (_activeTab == 'sales') {
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
                pw.Text('Items Sales Report (${_datePreset.toUpperCase()})', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
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
                    2: pw.Alignment.center,
                    3: pw.Alignment.centerRight,
                  },
                ),
              ],
            );
          },
        ),
      );
    } else if (_activeTab == 'pos_stock') {
      final headers = ['Product Name', 'Category ID', 'Stock Qty', 'Min Stock', 'Status'];
      final data = _filteredProducts.take(_entriesLimit).map((p) {
        final isLow = p.trackStock && p.stockQty <= p.minStockLevel;
        return [
          p.name,
          p.categoryId.toString(),
          p.stockQty.toString(),
          p.minStockLevel.toString(),
          isLow ? 'LOW STOCK' : 'OK'
        ];
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('POS Products Stock Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 25,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );
    } else {
      final headers = ['Ingredient Name', 'Unit', 'Stock Qty', 'Min Alert', 'Status'];
      final data = _filteredIngredients.take(_entriesLimit).map((ing) {
        final isLow = ing.stockQty <= ing.minStockLevel;
        return [
          ing.name,
          ing.unit,
          ing.stockQty.toStringAsFixed(1),
          ing.minStockLevel.toStringAsFixed(1),
          isLow ? 'DEPLETED' : 'OK'
        ];
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Raw Materials Stock Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 25,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );
    }
    return doc;
  }

  // Save PDF Report File
  Future<void> _exportToPDF() async {
    try {
      final doc = await _buildPDFDoc();
      final filename = _activeTab == 'sales' 
          ? 'Items_Sales_Report_${_datePreset.toUpperCase()}.pdf' 
          : _activeTab == 'pos_stock' 
              ? 'POS_Stock_Report.pdf' 
              : 'Raw_Ingredients_Stock_Report.pdf';

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export PDF Report',
        fileName: filename,
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
      final doc = await _buildPDFDoc();
      final filename = _activeTab == 'sales' 
          ? 'Items_Sales_Report_${_datePreset.toUpperCase()}' 
          : _activeTab == 'pos_stock' 
              ? 'POS_Stock_Report' 
              : 'Raw_Ingredients_Stock_Report';

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: filename,
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
    dynamic displayList;
    int salesTotalSum = 0;

    if (_activeTab == 'sales') {
      final list = _aggregatedSales;
      displayList = list.take(_entriesLimit).toList();
      salesTotalSum = (displayList as List).fold(0, (sum, i) => sum + (i['quantity'] as int));
    } else if (_activeTab == 'pos_stock') {
      displayList = _filteredProducts.take(_entriesLimit).toList();
    } else {
      displayList = _filteredIngredients.take(_entriesLimit).toList();
    }

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
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
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
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
            const SizedBox(height: 20),

            // Tab Selector Chips
            Row(
              children: [
                _buildTabChip('sales', 'Item Sales Quantities'),
                const SizedBox(width: 12),
                _buildTabChip('pos_stock', 'POS Products Stock'),
                const SizedBox(width: 12),
                _buildTabChip('raw_stock', 'Raw Materials Stock'),
              ],
            ),
            const SizedBox(height: 20),

            // Date Period presets selector (Only shown for Sales Quantities)
            if (_activeTab == 'sales') ...[
              _buildDateFilterCard(),
              const SizedBox(height: 20),
            ],

            // Advanced Filters Section
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
                        : (displayList as List).isEmpty
                            ? _buildEmptyState()
                            : _buildActiveTable(displayList, salesTotalSum),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String tabKey, String label) {
    final isSelected = _activeTab == tabKey;
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : AppTheme.textLightPrimary)),
      selectedColor: AppTheme.primary,
      backgroundColor: AppTheme.cardLight,
      selected: isSelected,
      onSelected: (val) {
        if (val) {
          setState(() {
            _activeTab = tabKey;
            // Clear current filters when switching tabs to avoid confusion
            _filterNameController.clear();
            _filterCategoryController.clear();
            _filterType = '--';
            _appliedName = '';
            _appliedCategory = '';
            _appliedType = '--';
          });
        }
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

  Widget _buildFilterSection() {
    final showExtraFilters = _activeTab != 'raw_stock';
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
                      _buildFieldLabel('NAME'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterNameController,
                        style: TextStyle(color: AppTheme.textLightPrimary),
                        decoration: const InputDecoration(hintText: 'Enter search name'),
                      ),
                    ],
                  ),
                ),
                if (showExtraFilters) ...[
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('CATEGORY'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _filterCategoryController,
                          style: TextStyle(color: AppTheme.textLightPrimary),
                          decoration: const InputDecoration(hintText: 'Enter category'),
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
                          dropdownColor: AppTheme.cardLight,
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
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
            'No report data available.',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTable(List<dynamic> list, int total) {
    if (_activeTab == 'sales') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppTheme.bgLight,
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
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                final i = list[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(i['name'].toString(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                      Expanded(flex: 3, child: Text(i['category'].toString(), style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary))),
                      Expanded(flex: 2, child: Text(i['type'].toString(), style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary))),
                      Expanded(flex: 2, child: Text(i['quantity'].toString(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                    ],
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: AppTheme.dividerColor, thickness: 1.5),
          Container(
            color: AppTheme.bgLight,
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
    } else if (_activeTab == 'pos_stock') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppTheme.bgLight,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Row(
              children: [
                Expanded(flex: 4, child: _buildTableHeaderText('PRODUCT NAME')),
                Expanded(flex: 2, child: _buildTableHeaderText('CATEGORY ID')),
                Expanded(flex: 2, child: _buildTableHeaderText('STOCK QTY')),
                Expanded(flex: 2, child: _buildTableHeaderText('MIN STOCK')),
                Expanded(flex: 2, child: _buildTableHeaderText('STATUS')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                final p = list[index] as ProductModel;
                final isLow = p.trackStock && p.stockQty <= p.minStockLevel;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(p.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                      Expanded(flex: 2, child: Text('ID: ${p.categoryId}', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary))),
                      Expanded(
                        flex: 2, 
                        child: Text(
                          p.stockQty.toString(), 
                          style: GoogleFonts.inter(
                            fontSize: 13, 
                            fontWeight: FontWeight.bold, 
                            color: isLow ? AppTheme.danger : AppTheme.textLightPrimary,
                          ),
                        ),
                      ),
                      Expanded(flex: 2, child: Text(p.minStockLevel.toString(), style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary))),
                      Expanded(
                        flex: 2, 
                        child: Text(
                          isLow ? 'LOW STOCK' : 'OK', 
                          style: GoogleFonts.inter(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold, 
                            color: isLow ? AppTheme.danger : Colors.green,
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
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppTheme.bgLight,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            child: Row(
              children: [
                Expanded(flex: 4, child: _buildTableHeaderText('INGREDIENT NAME')),
                Expanded(flex: 2, child: _buildTableHeaderText('UNIT')),
                Expanded(flex: 2, child: _buildTableHeaderText('STOCK QTY')),
                Expanded(flex: 2, child: _buildTableHeaderText('MIN ALERT LEVEL')),
                Expanded(flex: 2, child: _buildTableHeaderText('STATUS')),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                final ing = list[index] as IngredientModel;
                final isLow = ing.stockQty <= ing.minStockLevel;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(flex: 4, child: Text(ing.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                      Expanded(flex: 2, child: Text(ing.unit, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary))),
                      Expanded(
                        flex: 2, 
                        child: Text(
                          ing.stockQty.toStringAsFixed(1), 
                          style: GoogleFonts.inter(
                            fontSize: 13, 
                            fontWeight: FontWeight.bold, 
                            color: isLow ? AppTheme.danger : AppTheme.textLightPrimary,
                          ),
                        ),
                      ),
                      Expanded(flex: 2, child: Text(ing.minStockLevel.toStringAsFixed(1), style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary))),
                      Expanded(
                        flex: 2, 
                        child: Text(
                          isLow ? 'DEPLETED' : 'OK', 
                          style: GoogleFonts.inter(
                            fontSize: 12, 
                            fontWeight: FontWeight.bold, 
                            color: isLow ? AppTheme.danger : Colors.green,
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
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5),
    );
  }
}
