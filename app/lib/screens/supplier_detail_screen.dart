import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';

class SupplierDetailScreen extends StatefulWidget {
  final SupplierModel supplier;
  const SupplierDetailScreen({Key? key, required this.supplier}) : super(key: key);

  @override
  State<SupplierDetailScreen> createState() => _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends State<SupplierDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late SupplierModel _currentSupplier;
  List<SupplierLedgerEntryModel> _ledger = [];
  List<SupplierDeliveryModel> _deliveries = [];
  List<SupplierPaymentModel> _payments = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _currentSupplier = widget.supplier;
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // Reload supplier info to get latest balance
      final sups = await APIService.instance.getSuppliers();
      final updatedSup = sups.firstWhere((s) => s.id == widget.supplier.id, orElse: () => _currentSupplier);
      
      final ledgerData = await APIService.instance.getSupplierLedger(widget.supplier.id);
      final deliveriesData = await APIService.instance.getSupplierDeliveries(widget.supplier.id);
      final paymentsData = await APIService.instance.getSupplierPayments(widget.supplier.id);

      setState(() {
        _currentSupplier = updatedSup;
        _ledger = ledgerData;
        _deliveries = deliveriesData;
        _payments = paymentsData;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  double get _openingBalance {
    double debitsSum = 0.0;
    double creditsSum = 0.0;
    for (var entry in _ledger) {
      debitsSum += entry.debit;
      creditsSum += entry.credit;
    }
    return _currentSupplier.outstandingBalance - debitsSum + creditsSum;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      appBar: AppBar(
        backgroundColor: AppTheme.cardLight,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppTheme.textLightPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${_currentSupplier.name} Details',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppTheme.textLightPrimary),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderSummary(),
                  const SizedBox(height: 24),
                  _buildTabBarSection(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLedgerTab(),
                        _buildDeliveriesTab(),
                        _buildPaymentsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderSummary() {
    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentSupplier.name,
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.isDarkMode ? Colors.blue.withOpacity(0.12) : const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Delivery Cycle: ${_currentSupplier.deliveryCycle}',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.isDarkMode ? Colors.blue[200] : Colors.blue[800]),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Outstanding Balance',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  'LKR ${_currentSupplier.outstandingBalance.toStringAsFixed(2)}',
                  style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary),
                ),
              ],
            ),
            const SizedBox(width: 24),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _showLogDeliveryDialog,
                  icon: const Icon(Icons.add_shopping_cart, size: 16),
                  label: const Text('Log Delivery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _printLedgerReport,
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Print Ledger'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF475569),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBarSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardLight,
        border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: AppTheme.primary,
        unselectedLabelColor: AppTheme.textLightSecondary,
        indicatorColor: AppTheme.primary,
        indicatorWeight: 3,
        labelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Transaction Ledger'),
          Tab(text: 'Supply Deliveries'),
          Tab(text: 'Payment History'),
        ],
      ),
    );
  }

  Widget _buildLedgerTab() {
    final openingBal = _openingBalance;
    double runningBalance = openingBal;

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppTheme.bgLight,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _buildTableHeaderText('DATE')),
                  Expanded(flex: 2, child: _buildTableHeaderText('TYPE')),
                  Expanded(flex: 6, child: _buildTableHeaderText('DESCRIPTION')),
                  Expanded(flex: 3, child: _buildTableHeaderText('DEBIT (SUPPLY)')),
                  Expanded(flex: 3, child: _buildTableHeaderText('CREDIT (PAY)')),
                  Expanded(flex: 3, child: _buildTableHeaderText('RUNNING BAL')),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _ledger.length + 1,
              separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text('-', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.isDarkMode ? Colors.grey[800] : Colors.grey[200],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'OPENING',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.isDarkMode ? Colors.grey[400] : Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 6,
                          child: Text(
                            'Opening Balance',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('-', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text('-', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'LKR ${openingBal.toStringAsFixed(2)}',
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final entry = _ledger[index - 1];
                runningBalance = runningBalance + entry.debit - entry.credit;

                final dateFormatted = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(entry.date) ?? DateTime.now());
                final isDelivery = entry.type == 'delivery';

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(dateFormatted, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDelivery 
                                  ? (AppTheme.isDarkMode ? const Color(0xFFC5221F).withOpacity(0.2) : const Color(0xFFFCE8E6)) 
                                  : (AppTheme.isDarkMode ? const Color(0xFF137333).withOpacity(0.2) : const Color(0xFFE6F4EA)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isDelivery ? 'SUPPLY' : 'PAY',
                              style: GoogleFonts.inter(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isDelivery 
                                    ? (AppTheme.isDarkMode ? const Color(0xFFE57373) : const Color(0xFFC5221F)) 
                                    : (AppTheme.isDarkMode ? const Color(0xFF81C784) : const Color(0xFF137333)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 6,
                        child: Text(
                          entry.description,
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          entry.debit > 0 ? 'LKR ${entry.debit.toStringAsFixed(2)}' : '-',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.isDarkMode ? const Color(0xFFE57373) : const Color(0xFFC5221F), fontWeight: entry.debit > 0 ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          entry.credit > 0 ? 'LKR ${entry.credit.toStringAsFixed(2)}' : '-',
                          style: GoogleFonts.inter(fontSize: 13, color: AppTheme.isDarkMode ? const Color(0xFF81C784) : const Color(0xFF137333), fontWeight: entry.credit > 0 ? FontWeight.bold : FontWeight.normal),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          'LKR ${runningBalance.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
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
    );
  }

  Widget _buildDeliveriesTab() {
    if (_deliveries.isEmpty) {
      return Center(
        child: Text('No item deliveries logged yet.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
      );
    }

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppTheme.bgLight,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _buildTableHeaderText('DELIVERY DATE')),
                  Expanded(flex: 5, child: _buildTableHeaderText('ITEM NAME')),
                  Expanded(flex: 3, child: _buildTableHeaderText('QUANTITY')),
                  Expanded(flex: 4, child: _buildTableHeaderText('TOTAL COST')),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _deliveries.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                final del = _deliveries[index];
                final dateFormatted = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(del.deliveryDate) ?? DateTime.now());

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(dateFormatted, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                      ),
                      Expanded(
                        flex: 5,
                        child: Text(del.itemName, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text('${del.quantity.toStringAsFixed(1)} ${del.unit}', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'LKR ${del.totalAmount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
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
    );
  }

  Widget _buildPaymentsTab() {
    if (_payments.isEmpty) {
      return Center(
        child: Text('No payments recorded yet.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
      );
    }

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppTheme.borderLight),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppTheme.bgLight,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Row(
                children: [
                  Expanded(flex: 3, child: _buildTableHeaderText('PAYMENT DATE')),
                  Expanded(flex: 3, child: _buildTableHeaderText('SOURCE')),
                  Expanded(flex: 6, child: _buildTableHeaderText('REMARKS')),
                  Expanded(flex: 4, child: _buildTableHeaderText('AMOUNT PAID')),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _payments.length,
              separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
              itemBuilder: (context, index) {
                final pay = _payments[index];
                final dateFormatted = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(pay.paymentDate) ?? DateTime.now());

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(dateFormatted, style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(pay.paymentSource.toUpperCase(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textLightSecondary)),
                      ),
                      Expanded(
                        flex: 6,
                        child: Text(pay.remarks ?? 'N/A', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          'LKR ${pay.amount.toStringAsFixed(2)}',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
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
    );
  }

  Widget _buildTableHeaderText(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary, letterSpacing: 0.5),
    );
  }

  void _showLogDeliveryDialog() {
    final itemNameController = TextEditingController();
    final quantityController = TextEditingController();
    final totalAmountController = TextEditingController();
    String unit = 'kg';
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              title: Text('Log Item Delivery', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: itemNameController,
                      style: TextStyle(color: AppTheme.textLightPrimary),
                      decoration: const InputDecoration(labelText: 'Item / Product Name *', hintText: 'e.g. Flour Bag, Potatoes'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: quantityController,
                            style: TextStyle(color: AppTheme.textLightPrimary),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Qty *'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: unit,
                            dropdownColor: AppTheme.cardLight,
                            style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                            decoration: const InputDecoration(labelText: 'Unit'),
                            items: const [
                              DropdownMenuItem(value: 'kg', child: Text('kg')),
                              DropdownMenuItem(value: 'units', child: Text('units')),
                              DropdownMenuItem(value: 'liters', child: Text('liters')),
                              DropdownMenuItem(value: 'grams', child: Text('grams')),
                            ],
                            onChanged: (val) => setState(() => unit = val!),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: totalAmountController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.textLightPrimary),
                      decoration: const InputDecoration(labelText: 'Total Cost Amount (LKR) *'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Delivery Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary)),
                        TextButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: selectedDate,
                              firstDate: DateTime(2025),
                              lastDate: DateTime.now(),
                            );
                            if (picked != null) {
                              setState(() => selectedDate = picked);
                            }
                          },
                          icon: const Icon(Icons.calendar_month, size: 16),
                          label: const Text('Change'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final itemName = itemNameController.text.trim();
                    final qtyStr = quantityController.text.trim();
                    final totalAmtStr = totalAmountController.text.trim();
                    final qty = double.tryParse(qtyStr) ?? 0.00;
                    final totalAmt = double.tryParse(totalAmtStr) ?? 0.00;

                    if (itemName.isEmpty || qtyStr.isEmpty || qty <= 0 || totalAmtStr.isEmpty || totalAmt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please fill all fields with positive values'), backgroundColor: AppTheme.danger),
                      );
                      return;
                    }

                    try {
                      await APIService.instance.createSupplierDelivery(_currentSupplier.id, {
                        'item_name': itemName,
                        'quantity': qty,
                        'unit': unit,
                        'total_amount': totalAmt,
                        'delivery_date': DateFormat('yyyy-MM-dd').format(selectedDate),
                      });
                      Navigator.pop(context);
                      _loadData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Delivery logged and outstanding balance updated!'), backgroundColor: AppTheme.accent),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  child: const Text('Log'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _printLedgerReport() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Date', 'Type', 'Description', 'Debit (Supply)', 'Credit (Pay)', 'Running Bal'];
      final openingBal = _openingBalance;
      double runningBal = openingBal;

      final List<List<String>> data = [];
      data.add([
        '-',
        'OPENING',
        'Opening Balance',
        '-',
        '-',
        'LKR ${openingBal.toStringAsFixed(2)}'
      ]);

      for (var entry in _ledger) {
        runningBal = runningBal + entry.debit - entry.credit;
        final dateFormatted = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(entry.date) ?? DateTime.now());
        
        data.add([
          dateFormatted,
          entry.type.toUpperCase(),
          entry.description,
          entry.debit > 0 ? 'LKR ${entry.debit.toStringAsFixed(2)}' : '-',
          entry.credit > 0 ? 'LKR ${entry.credit.toStringAsFixed(2)}' : '-',
          'LKR ${runningBal.toStringAsFixed(2)}'
        ]);
      }

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
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
                        pw.Text(
                          'Supplier Transaction Ledger Statement',
                          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Supplier Name: ${_currentSupplier.name}'),
                        pw.Text('Delivery Cycle: ${_currentSupplier.deliveryCycle}'),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Outstanding Balance',
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'LKR ${_currentSupplier.outstandingBalance.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text('Statement Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 20),
                pw.Table.fromTextArray(
                  headers: headers,
                  data: data,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  cellHeight: 24,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.centerRight,
                    4: pw.Alignment.centerRight,
                    5: pw.Alignment.centerRight,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Supplier_Ledger_${_currentSupplier.name.replaceAll(' ', '_')}',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate report: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }
}
