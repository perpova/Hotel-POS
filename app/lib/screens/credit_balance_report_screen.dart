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
              Expanded(flex: 2, child: _buildTableHeaderText('ACTION')),
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
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          if (c.outstandingBalance > 0) ...[
                            ElevatedButton.icon(
                              onPressed: () => _showPayCreditDialog(c),
                              icon: const Icon(Icons.account_balance_wallet, size: 14),
                              label: const Text('Pay', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ] else ...[
                            const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 20),
                            const SizedBox(width: 14),
                          ],
                          IconButton(
                            onPressed: () => _showCreditHistoryDialog(c),
                            icon: Icon(Icons.history_toggle_off, color: AppTheme.primary, size: 22),
                            tooltip: 'View Credit History',
                          ),
                        ],
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

  void _showCreditHistoryDialog(CustomerModel customer) {
    showDialog(
      context: context,
      builder: (context) {
        List<dynamic> localLedger = [];
        bool isLoadingLedger = true;
        String ledgerError = '';

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> fetchLedger() async {
              try {
                final data = await APIService.instance.getCustomerLedger(customer.id!);
                setDialogState(() {
                  localLedger = data;
                  isLoadingLedger = false;
                });
              } catch (e) {
                setDialogState(() {
                  ledgerError = e.toString();
                  isLoadingLedger = false;
                });
              }
            }

            if (isLoadingLedger && ledgerError.isEmpty) {
              fetchLedger();
            }

            final double outstandingBalance = localLedger.isEmpty
                ? 0.00
                : double.parse(localLedger.last['running_balance'].toString());

            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: Container(
                width: 800,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
                color: Colors.white,
                child: Column(
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      color: AppTheme.primary.withOpacity(0.05),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Credit History & Statement',
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${customer.name} | ${customer.phone}',
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (!isLoadingLedger && localLedger.isNotEmpty)
                                ElevatedButton.icon(
                                  onPressed: () => _printCustomerStatement(customer, localLedger),
                                  icon: const Icon(Icons.print, size: 14),
                                  label: const Text('Print Statement'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  ),
                                ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Expanded(
                      child: isLoadingLedger
                          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                          : ledgerError.isNotEmpty
                              ? Center(child: Text(ledgerError, style: GoogleFonts.inter(color: Colors.red)))
                              : localLedger.isEmpty
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.info_outline, size: 48, color: Color(0xFF94A3B8)),
                                          const SizedBox(height: 12),
                                          Text(
                                            'No transactions found for this customer.',
                                            style: GoogleFonts.inter(color: const Color(0xFF64748B)),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Column(
                                      children: [
                                        // Summary boxes
                                        Padding(
                                          padding: const EdgeInsets.all(20.0),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: _buildSummaryBox(
                                                  'Total Credit Purchases',
                                                  localLedger
                                                      .where((x) => x['type'] == 'purchase')
                                                      .fold(0.00, (sum, x) => sum + x['debit']),
                                                  Colors.blue,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: _buildSummaryBox(
                                                  'Total Paid Settle',
                                                  localLedger
                                                      .where((x) => x['type'] == 'payment')
                                                      .fold(0.00, (sum, x) => sum + x['credit']),
                                                  Colors.green,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Expanded(
                                                child: _buildSummaryBox(
                                                  'Outstanding Balance',
                                                  outstandingBalance,
                                                  outstandingBalance > 0 ? Colors.red : Colors.green,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // History table
                                        Expanded(
                                          child: SingleChildScrollView(
                                            padding: const EdgeInsets.symmetric(horizontal: 20),
                                            child: Table(
                                              border: TableBorder.all(color: const Color(0xFFF1F5F9)),
                                              columnWidths: const {
                                                0: FlexColumnWidth(2),
                                                1: FlexColumnWidth(3),
                                                2: FlexColumnWidth(2),
                                                3: FlexColumnWidth(2),
                                                4: FlexColumnWidth(2),
                                                5: FlexColumnWidth(1.5),
                                              },
                                              children: [
                                                TableRow(
                                                  decoration: const BoxDecoration(color: Color(0xFFF8FAFC)),
                                                  children: [
                                                    _buildTableHeaderCell('DATE'),
                                                    _buildTableHeaderCell('DESCRIPTION'),
                                                    _buildTableHeaderCell('DEBIT (+)', align: TextAlign.right),
                                                    _buildTableHeaderCell('CREDIT (-)', align: TextAlign.right),
                                                    _buildTableHeaderCell('BALANCE', align: TextAlign.right),
                                                    _buildTableHeaderCell('ACTION', align: TextAlign.center),
                                                  ],
                                                ),
                                                ...localLedger.map((item) {
                                                  final dateStr = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.parse(item['date']).toLocal());
                                                  final debitStr = item['debit'] > 0 ? 'LKR ${item['debit'].toStringAsFixed(2)}' : '-';
                                                  final creditStr = item['credit'] > 0 ? 'LKR ${item['credit'].toStringAsFixed(2)}' : '-';
                                                  final balanceStr = 'LKR ${item['running_balance'].toStringAsFixed(2)}';
                                                  final isPayment = item['type'] == 'payment';
                                                  
                                                  return TableRow(
                                                    children: [
                                                      _buildTableCell(dateStr),
                                                      _buildTableCell(item['description'].toString(), isBold: true),
                                                      _buildTableCell(debitStr, color: item['debit'] > 0 ? Colors.blue : null, align: TextAlign.right),
                                                      _buildTableCell(creditStr, color: item['credit'] > 0 ? Colors.green : null, align: TextAlign.right),
                                                      _buildTableCell(balanceStr, isBold: true, align: TextAlign.right),
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                                                        child: isPayment
                                                            ? Row(
                                                                mainAxisAlignment: MainAxisAlignment.center,
                                                                children: [
                                                                  IconButton(
                                                                    constraints: const BoxConstraints(),
                                                                    padding: EdgeInsets.zero,
                                                                    icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
                                                                    onPressed: () => _editSettlementDialog(context, customer, item, fetchLedger),
                                                                    tooltip: 'Edit Payment',
                                                                  ),
                                                                  const SizedBox(width: 8),
                                                                  IconButton(
                                                                    constraints: const BoxConstraints(),
                                                                    padding: EdgeInsets.zero,
                                                                    icon: const Icon(Icons.delete_forever, color: Colors.red, size: 16),
                                                                    onPressed: () => _confirmDeleteSettlement(context, customer, item, fetchLedger),
                                                                    tooltip: 'Void Payment',
                                                                  ),
                                                                ],
                                                              )
                                                            : const Center(
                                                                child: Text('-', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                                              ),
                                                      ),
                                                    ],
                                                  );
                                                }).toList(),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                      ],
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

  void _editSettlementDialog(
    BuildContext context,
    CustomerModel customer,
    dynamic item,
    VoidCallback refreshLedger,
  ) {
    final TextEditingController amountController = TextEditingController(
      text: item['credit'].toStringAsFixed(2),
    );
    String rawDesc = item['description'].toString().toLowerCase();
    String paymentMethod = 'cash';
    if (rawDesc.contains('card')) paymentMethod = 'card';
    if (rawDesc.contains('qr')) paymentMethod = 'qr';

    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSubDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text('Edit Payment Settlement', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EDIT AMOUNT (LKR) *',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.inter(fontSize: 13),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Please enter amount';
                        final double? amt = double.tryParse(val);
                        if (amt == null || amt <= 0) return 'Enter a positive amount';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PAYMENT METHOD *',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'qr', child: Text('LankaQR')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setSubDialogState(() {
                            paymentMethod = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setSubDialogState(() => isSaving = true);
                          try {
                            final double newAmt = double.parse(amountController.text.trim());
                            await APIService.instance.editCreditSettlement(item['id'], newAmt, paymentMethod);
                            
                            refreshLedger();
                            _loadCustomers();
                            
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Payment settlement updated successfully!'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to save edit: $e'), backgroundColor: const Color(0xFFEF4444)),
                              );
                            }
                          } finally {
                            setSubDialogState(() => isSaving = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  child: isSaving
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Save', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteSettlement(
    BuildContext context,
    CustomerModel customer,
    dynamic item,
    VoidCallback refreshLedger,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (context, setSubState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text('Void Payment Settlement?', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFFEF4444))),
              content: Text(
                'Are you sure you want to void/delete this payment of LKR ${item['credit'].toStringAsFixed(2)}? This will restore the customer\'s outstanding balance and delete any associated cash drawer log entry.',
                style: GoogleFonts.inter(fontSize: 13),
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: isDeleting
                      ? null
                      : () async {
                          setSubState(() => isDeleting = true);
                          try {
                            await APIService.instance.deleteCreditSettlement(item['id']);
                            refreshLedger();
                            _loadCustomers();
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Payment settlement voided successfully!'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to delete: $e'), backgroundColor: const Color(0xFFEF4444)),
                              );
                            }
                          } finally {
                            setSubState(() => isDeleting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                  child: isDeleting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Void Payment', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _printCustomerStatement(CustomerModel customer, List<dynamic> ledger) async {
    try {
      final doc = pw.Document();
      final font = await PdfGoogleFonts.interRegular();
      final fontBold = await PdfGoogleFonts.interBold();
      
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Matara Hotel', style: pw.TextStyle(font: fontBold, fontSize: 22)),
                        pw.Text('Credit Account Statement', style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Date: ${DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now())}', style: pw.TextStyle(font: font, fontSize: 10)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text('Customer Details:', style: pw.TextStyle(font: fontBold, fontSize: 12)),
                pw.Text('Name: ${customer.name}', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text('Phone: ${customer.phone}', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text('Current Outstanding Balance: LKR ${customer.outstandingBalance.toStringAsFixed(2)}', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.red700)),
                pw.SizedBox(height: 20),
                pw.Text('Transaction History:', style: pw.TextStyle(font: fontBold, fontSize: 12)),
                pw.SizedBox(height: 10),
                pw.Table.fromTextArray(
                  headers: ['Date', 'Description', 'Credit Added (+)', 'Credit Paid (-)', 'Running Balance'],
                  data: ledger.map((item) {
                    final dateStr = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.parse(item['date']).toLocal());
                    final debitStr = item['debit'] > 0 ? item['debit'].toStringAsFixed(2) : '-';
                    final creditStr = item['credit'] > 0 ? item['credit'].toStringAsFixed(2) : '-';
                    final balanceStr = item['running_balance'].toStringAsFixed(2);
                    return [
                      dateStr,
                      item['description'].toString(),
                      debitStr,
                      creditStr,
                      balanceStr
                    ];
                  }).toList(),
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(font: fontBold, fontSize: 9),
                  cellStyle: pw.TextStyle(font: font, fontSize: 9),
                  cellHeight: 22,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.centerRight,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Credit_Statement_${customer.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print statement: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Widget _buildSummaryBox(String title, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B), fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'LKR ${amount.toStringAsFixed(2)}',
            style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Text(
        text,
        textAlign: align,
        style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF475569)),
      ),
    );
  }

  Widget _buildTableCell(String text, {Color? color, bool isBold = false, TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        textAlign: align,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? AppTheme.textLightPrimary,
        ),
      ),
    );
  }

  void _showPayCreditDialog(CustomerModel customer) {
    final TextEditingController amountController = TextEditingController(
      text: customer.outstandingBalance.toStringAsFixed(2),
    );
    String paymentMethod = 'cash';
    final formKey = GlobalKey<FormState>();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Settle Credit Balance',
                style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CUSTOMER',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customer.name,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 16),
                    
                    Text(
                      'OUTSTANDING BALANCE',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'LKR ${customer.outstandingBalance.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFFEF4444)),
                    ),
                    const SizedBox(height: 16),
                    
                    Text(
                      'SETTLEMENT AMOUNT (LKR) *',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.inter(fontSize: 13),
                      validator: (val) {
                        if (val == null || val.isEmpty) return 'Please enter settlement amount';
                        final double? amt = double.tryParse(val);
                        if (amt == null || amt <= 0) return 'Please enter a valid positive amount';
                        if (amt > customer.outstandingBalance) return 'Cannot exceed outstanding balance';
                        return null;
                      },
                      decoration: const InputDecoration(
                        hintText: 'Enter amount to settle',
                      ),
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'PAYMENT METHOD *',
                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(value: 'qr', child: Text('LankaQR')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            paymentMethod = val;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: const Color(0xFF64748B)),
                  ),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          
                          setDialogState(() {
                            isSubmitting = true;
                          });

                          try {
                            final double settleAmt = double.parse(amountController.text.trim());
                            
                            await APIService.instance.settleCredit(customer.id!, settleAmt, paymentMethod);
                            
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Credit balance settled successfully!'),
                                  backgroundColor: Color(0xFF10B981),
                                ),
                              );
                            }
                            _loadCustomers();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to settle credit balance: $e'),
                                  backgroundColor: const Color(0xFFEF4444),
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) {
                              setDialogState(() {
                                isSubmitting = false;
                              });
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Confirm Settlement', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF475569), letterSpacing: 0.5),
    );
  }
}
