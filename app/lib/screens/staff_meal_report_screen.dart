import 'dart:async';
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
import '../services/translation_service.dart';

class StaffMealReportScreen extends StatefulWidget {
  const StaffMealReportScreen({Key? key}) : super(key: key);

  @override
  State<StaffMealReportScreen> createState() => _StaffMealReportScreenState();
}

class _StaffMealReportScreenState extends State<StaffMealReportScreen> {
  StreamSubscription? _wsSub;
  List<OrderModel> _staffOrders = [];
  List<UserModel> _allUsers = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Date Range Presets
  String _datePreset = 'today'; // 'all', 'today', 'weekly', 'monthly', 'yearly', 'custom'
  DateTime? _startDate;
  DateTime? _endDate;

  // Filters
  String? _selectedStaffId; // 'all' or specific user ID string
  String _searchQuery = '';
  final _searchController = TextEditingController();

  // Pagination Limit
  int _entriesLimit = 25;

  @override
  void initState() {
    super.initState();
    _loadData();
    _wsSub = APIService.instance.eventStream.listen((event) {
      final type = event['type']?.toString();
      if (type == 'database_synchronized' ||
          type == 'ws_reconnected' ||
          type == 'order_created' ||
          type == 'order_updated') {
        _loadData(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      final users = await APIService.instance.getUsers();
      final orders = await APIService.instance.getStaffMealOrders();

      if (mounted) {
        setState(() {
          _allUsers = users;
          _staffOrders = orders;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load staff meal report: $e';
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

  // Filtered Orders List
  List<OrderModel> get _filteredOrders {
    return _staffOrders.where((o) {
      if (!_isWithinDateRange(o.createdAt)) return false;

      if (_selectedStaffId != null && _selectedStaffId != 'all') {
        if (o.staffUserId?.toString() != _selectedStaffId) return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchNum = o.orderNumber.toLowerCase().contains(q);
        final matchStaff = (o.staffName ?? o.stewardName ?? '').toLowerCase().contains(q);
        final matchItems = o.items.any((i) => i.productName.toLowerCase().contains(q));
        if (!matchNum && !matchStaff && !matchItems) return false;
      }

      return true;
    }).toList();
  }

  // Stats Calculations
  double get _totalRegularValue {
    double total = 0.0;
    for (var o in _filteredOrders) {
      for (var item in o.items) {
        total += (item.price * item.quantity);
      }
    }
    return total;
  }

  int get _totalItemsIssued {
    int count = 0;
    for (var o in _filteredOrders) {
      for (var item in o.items) {
        count += item.quantity;
      }
    }
    return count;
  }

  int get _uniqueStaffCount {
    final staffIds = _filteredOrders.map((o) => o.staffUserId ?? o.stewardName).toSet();
    return staffIds.length;
  }

  // Pick Custom Date Range
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
              primary: const Color(0xFF9333EA),
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

  // Export CSV
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Order Number,Date & Time,Staff Member,Cashier / Issued By,Items,Total Items,Regular Menu Value (LKR),Status\n';
      for (var o in _filteredOrders) {
        final itemsStr = o.items.map((i) => '${i.productName} x${i.quantity}').join('; ');
        final regVal = o.items.fold(0.0, (s, i) => s + (i.price * i.quantity));
        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.tryParse(o.createdAt)?.toLocal() ?? DateTime.now());
        csvContent += '"${o.orderNumber}","$dateStr","${o.staffName ?? o.stewardName ?? 'Staff'}","${o.stewardName ?? 'Cashier'}","$itemsStr",${o.items.length},${regVal.toStringAsFixed(2)},"${o.status}"\n';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Staff Meal CSV Report',
        fileName: 'Staff_Meal_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsString(csvContent);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Staff Meal report exported to: $resultPath'), backgroundColor: const Color(0xFF9333EA)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('CSV Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Export PDF
  Future<void> _exportToPDF() async {
    try {
      final pdf = pw.Document();
      final data = _filteredOrders.take(_entriesLimit).map((o) {
        final itemsStr = o.items.map((i) => '${i.productName} x${i.quantity}').join(', ');
        final regVal = o.items.fold(0.0, (s, i) => s + (i.price * i.quantity));
        final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.tryParse(o.createdAt)?.toLocal() ?? DateTime.now());
        return [
          o.orderNumber,
          dateStr,
          o.staffName ?? o.stewardName ?? 'Staff',
          itemsStr,
          'LKR ${regVal.toStringAsFixed(2)}',
        ];
      }).toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Staff Meal Report', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} | Total Meals: ${_filteredOrders.length} | Items: $_totalItemsIssued'),
                pw.SizedBox(height: 16),
                pw.Table.fromTextArray(
                  headers: ['Order #', 'Date/Time', 'Staff Recipient', 'Items Issued', 'Regular Value'],
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  cellHeight: 24,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.centerLeft,
                    4: pw.Alignment.centerRight,
                  },
                ),
              ],
            );
          },
        ),
      );

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Staff Meal PDF Report',
        fileName: 'Staff_Meal_Report_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (resultPath != null) {
        final file = File(resultPath);
        await file.writeAsBytes(await pdf.save());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('PDF saved successfully to: $resultPath'), backgroundColor: const Color(0xFF9333EA)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;
    final displayList = filtered.take(_entriesLimit).toList();

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.restaurant_menu, color: Color(0xFF9333EA), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Staff Meal Report',
                          style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Reports', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Staff Meal Report', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF9333EA), fontWeight: FontWeight.w600)),
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
                    // Refresh Button
                    OutlinedButton.icon(
                      onPressed: () => _loadData(),
                      icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF9333EA)),
                      label: Text('Refresh', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF9333EA))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF9333EA)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Export Menu
                    PopupMenuButton<String>(
                      onSelected: (val) {
                        if (val == 'PDF') {
                          _exportToPDF();
                        } else if (val == 'CSV') {
                          _exportToCSV();
                        }
                      },
                      offset: const Offset(0, 45),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'PDF',
                          child: Row(
                            children: [
                              const Icon(Icons.picture_as_pdf_outlined, size: 16, color: Color(0xFF9333EA)),
                              const SizedBox(width: 8),
                              Text('Export PDF', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'CSV',
                          child: Row(
                            children: [
                              const Icon(Icons.table_view_outlined, size: 16, color: Color(0xFF9333EA)),
                              const SizedBox(width: 8),
                              Text('Export CSV', style: GoogleFonts.inter(fontSize: 13)),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF9333EA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        child: Row(
                          children: [
                            const Icon(Icons.download_outlined, size: 16, color: Colors.white),
                            const SizedBox(width: 8),
                            Text(
                              'Export Report',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down, size: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // KPI Stats Summary Cards
            Row(
              children: [
                Expanded(
                  child: _buildKpiCard(
                    title: 'Staff Meals Served',
                    value: '${filtered.length}',
                    subtitle: 'Total recorded meal issues',
                    icon: Icons.restaurant,
                    accentColor: const Color(0xFF9333EA),
                    bgColor: const Color(0xFFF3E8FF),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Total Items Issued',
                    value: '$_totalItemsIssued items',
                    subtitle: 'Food & beverage items',
                    icon: Icons.fastfood_outlined,
                    accentColor: const Color(0xFF2563EB),
                    bgColor: const Color(0xFFDBEAFE),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Menu Regular Value',
                    value: 'LKR ${_totalRegularValue.toStringAsFixed(2)}',
                    subtitle: 'Selling price total (Charged 0.00)',
                    icon: Icons.monetization_on_outlined,
                    accentColor: const Color(0xFF059669),
                    bgColor: const Color(0xFFD1FAE5),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Staff Recipients',
                    value: '$_uniqueStaffCount Members',
                    subtitle: 'Unique staff members served',
                    icon: Icons.badge_outlined,
                    accentColor: const Color(0xFFD97706),
                    bgColor: const Color(0xFFFEF3C7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Filters & Date Presets Bar
            Card(
              elevation: 0,
              color: AppTheme.cardLight,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Row(
                  children: [
                    // Search box
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) => setState(() => _searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search order #, staff name, item...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderLight)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderLight)),
                        ),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Staff member filter dropdown
                    Expanded(
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        value: _selectedStaffId ?? 'all',
                        decoration: InputDecoration(
                          labelText: 'Staff Recipient',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderLight)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.borderLight)),
                        ),
                        style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('All Staff Members')),
                          ..._allUsers.map((u) {
                            return DropdownMenuItem(value: u.id.toString(), child: Text('${u.name} (${u.role})'));
                          }),
                        ],
                        onChanged: (val) => setState(() => _selectedStaffId = val),
                      ),
                    ),
                    const SizedBox(width: 16),

                    // Period Presets
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildDatePresetChip('today', 'Today'),
                          const SizedBox(width: 6),
                          _buildDatePresetChip('weekly', 'Weekly'),
                          const SizedBox(width: 6),
                          _buildDatePresetChip('monthly', 'Monthly'),
                          const SizedBox(width: 6),
                          _buildDatePresetChip('all', 'All Time'),
                          const SizedBox(width: 6),
                          _buildDatePresetChip('custom', 'Custom'),
                        ],
                      ),
                    ),

                    if (_datePreset == 'custom') ...[
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: _selectCustomDateRange,
                        icon: const Icon(Icons.date_range, size: 16, color: Color(0xFF9333EA)),
                        label: Text(
                          _startDate == null || _endDate == null
                              ? 'Select Range'
                              : '${DateFormat('MM/dd').format(_startDate!)} - ${DateFormat('MM/dd').format(_endDate!)}',
                          style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: const Color(0xFF9333EA)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Main Data Table Card
            Expanded(
              child: Card(
                elevation: 0,
                color: AppTheme.cardLight,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: AppTheme.borderLight),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF9333EA)))
                    : _errorMessage.isNotEmpty
                        ? Center(child: Text(_errorMessage, style: GoogleFonts.inter(color: Colors.red)))
                        : displayList.isEmpty
                            ? _buildEmptyState()
                            : _buildStaffMealsTable(displayList),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required Color bgColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePresetChip(String key, String label) {
    final isSel = _datePreset == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: isSel ? FontWeight.bold : FontWeight.normal, color: isSel ? Colors.white : AppTheme.textLightPrimary)),
      selected: isSel,
      selectedColor: const Color(0xFF9333EA),
      backgroundColor: AppTheme.cardLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isSel ? const Color(0xFF9333EA) : AppTheme.borderLight)),
      onSelected: (val) {
        if (val) {
          setState(() {
            _datePreset = key;
            if (key == 'custom' && _startDate == null) {
              _selectCustomDateRange();
            }
          });
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3E8FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.restaurant_outlined, size: 48, color: Color(0xFF9333EA)),
          ),
          const SizedBox(height: 16),
          Text(
            'No Staff Meals Found',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Staff meal orders placed in POS will be displayed separately in this report.',
            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffMealsTable(List<OrderModel> orders) {
    return Column(
      children: [
        // Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            border: Border(bottom: BorderSide(color: AppTheme.borderLight)),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              Expanded(flex: 2, child: Text('Order #', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
              Expanded(flex: 2, child: Text('Date & Time', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
              Expanded(flex: 3, child: Text('Staff Member (Recipient)', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
              Expanded(flex: 4, child: Text('Items Issued', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
              Expanded(flex: 2, child: Text('Menu Regular Value', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
              Expanded(flex: 2, child: Text('Staff Price', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
              Expanded(flex: 2, child: Text('Status', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary))),
            ],
          ),
        ),

        // Table List
        Expanded(
          child: ListView.separated(
            itemCount: orders.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppTheme.borderLight),
            itemBuilder: (context, index) {
              final o = orders[index];
              final dateStr = DateFormat('MMM dd, yyyy  hh:mm a').format(DateTime.tryParse(o.createdAt)?.toLocal() ?? DateTime.now());
              final staffName = o.staffName ?? o.stewardName ?? 'Staff Member';
              final regularValue = o.items.fold(0.0, (sum, i) => sum + (i.price * i.quantity));

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    // Order Number
                    Expanded(
                      flex: 2,
                      child: Text(
                        o.orderNumber,
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF9333EA)),
                      ),
                    ),
                    // Date Time
                    Expanded(
                      flex: 2,
                      child: Text(
                        dateStr,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                      ),
                    ),
                    // Staff Member
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: const Color(0xFFF3E8FF),
                            child: Text(
                              staffName.isNotEmpty ? staffName[0].toUpperCase() : 'S',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF9333EA)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              staffName,
                              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Items List
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: o.items.map((item) {
                          return Text(
                            '• ${item.productName} x${item.quantity}',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightPrimary),
                            overflow: TextOverflow.ellipsis,
                          );
                        }).toList(),
                      ),
                    ),
                    // Menu Value
                    Expanded(
                      flex: 2,
                      child: Text(
                        'LKR ${regularValue.toStringAsFixed(2)}',
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary, decoration: TextDecoration.lineThrough),
                      ),
                    ),
                    // Staff Price (0.00)
                    Expanded(
                      flex: 2,
                      child: Text(
                        'LKR 0.00',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                      ),
                    ),
                    // Status Badge
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3E8FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD8B4FE)),
                        ),
                        child: Text(
                          'Staff Meal',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF9333EA)),
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
