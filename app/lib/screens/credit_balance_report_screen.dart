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

class CreditBalanceReportScreen extends StatefulWidget {
  const CreditBalanceReportScreen({Key? key}) : super(key: key);

  @override
  State<CreditBalanceReportScreen> createState() => _CreditBalanceReportScreenState();
}

class _CreditBalanceReportScreenState extends State<CreditBalanceReportScreen> {
  List<CustomerModel> _customers = [];
  bool _isLoading = false;
  String _errorMessage = '';

  // Advanced Filters
  bool _isFilterExpanded = false;
  final _filterNameController = TextEditingController();
  final _filterEmailController = TextEditingController();
  final _filterPhoneController = TextEditingController();

  // Applied Filters State
  String _appliedName = '';
  String _appliedEmail = '';
  String _appliedPhone = '';

  // Pagination Limit
  int _entriesLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _filterNameController.dispose();
    _filterEmailController.dispose();
    _filterPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final custs = await APIService.instance.getCustomers();
      if (mounted) {
        setState(() {
          _customers = custs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load credit balances: $e';
          _isLoading = false;
        });
      }
    }
  }

  // Filtered List
  List<CustomerModel> get _filteredCustomers {
    return _customers.where((c) {
      final nameStr = c.name.toLowerCase();
      final matchName = _appliedName.isEmpty || nameStr.contains(_appliedName);

      final emailStr = (c.email ?? '').toLowerCase();
      final matchEmail = _appliedEmail.isEmpty || emailStr.contains(_appliedEmail);

      final phoneStr = c.phone;
      final matchPhone = _appliedPhone.isEmpty || phoneStr.contains(_appliedPhone);

      return matchName && matchEmail && matchPhone;
    }).toList();
  }

  // Export to CSV
  Future<void> _exportToCSV() async {
    try {
      String csvContent = 'Name,Email,Phone,Balance\n';
      for (var c in _filteredCustomers.take(_entriesLimit)) {
        csvContent += '${c.name},${c.email ?? "N/A"},${c.phone},${c.outstandingBalance}\n';
      }

      final resultPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Credit Balance Report',
        fileName: 'Credit_Balance_Report.csv',
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
      
      final headers = ['Name', 'Email', 'Phone', 'Balance'];
      final data = _filteredCustomers.take(_entriesLimit).map((c) {
        return [
          c.name,
          c.email ?? 'N/A',
          c.phone,
          c.outstandingBalance.toStringAsFixed(2)
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
                  'Credit Balance Report',
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
                    2: pw.Alignment.centerLeft,
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
        name: 'Credit_Balance_Report',
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
    final list = _filteredCustomers;
    final displayList = list.take(_entriesLimit).toList();

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
                      'Credit Balance Report',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Credit Balance Report', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
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
                      icon: const Icon(Icons.filter_alt_outlined, size: 14, color: AppTheme.primary),
                      label: Text('Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppTheme.primary),
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
                            const Icon(Icons.download_outlined, size: 14, color: AppTheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              'Export',
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.keyboard_arrow_down, size: 14, color: AppTheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Advanced Collapsible Filter Section
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
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
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
                        decoration: const InputDecoration(hintText: 'Enter customer name'),
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
                      _buildFieldLabel('EMAIL'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterEmailController,
                        decoration: const InputDecoration(hintText: 'Enter email'),
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
                      _buildFieldLabel('PHONE'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _filterPhoneController,
                        decoration: const InputDecoration(hintText: 'Enter phone'),
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
                      _appliedName = _filterNameController.text.trim().toLowerCase();
                      _appliedEmail = _filterEmailController.text.trim().toLowerCase();
                      _appliedPhone = _filterPhoneController.text.trim();
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
                      _filterEmailController.clear();
                      _filterPhoneController.clear();
                      
                      _appliedName = '';
                      _appliedEmail = '';
                      _appliedPhone = '';
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
            'No credit balances available.',
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<CustomerModel> list) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Table Header
        Container(
          color: const Color(0xFFF8FAFC),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Row(
            children: [
              Expanded(flex: 3, child: _buildTableHeaderText('NAME')),
              Expanded(flex: 3, child: _buildTableHeaderText('EMAIL')),
              Expanded(flex: 3, child: _buildTableHeaderText('PHONE')),
              Expanded(flex: 2, child: _buildTableHeaderText('BALANCE')),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.separated(
            itemCount: list.length,
            separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
            itemBuilder: (context, index) {
              final c = list[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: Text(c.name, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
                    Expanded(flex: 3, child: Text(c.email ?? 'N/A', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)))),
                    Expanded(flex: 3, child: Text(c.phone, style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)))),
                    Expanded(flex: 2, child: Text(c.outstandingBalance.toStringAsFixed(2), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary))),
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
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569), letterSpacing: 0.5),
    );
  }
}
