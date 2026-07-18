import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../models/models.dart';
import 'supplier_detail_screen.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loadingData = false;
  DateTime? _selectedLogsDate;
  DateTime? _selectedEodDate;

  // Data Caches
  Map<String, dynamic>? _eodData;
  List<ExpenseModel> _expenses = [];
  List<AuditLogModel> _logs = [];
  List _historicalReports = [];
  String _historicalPeriod = 'monthly';

  // Expense form inputs
  final _expenseTitleController = TextEditingController();
  final _expenseAmountController = TextEditingController();
  String _expenseCategory = 'ingredients';
  String _expenseSource = 'drawer';

  // Suppliers database
  List<SupplierModel> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadTabSpecificData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _expenseTitleController.dispose();
    _expenseAmountController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _loadTabSpecificData();
  }

  Future<void> _loadTabSpecificData() async {
    if (!mounted) return;
    setState(() => _loadingData = true);
    try {
      switch (_tabController.index) {
        case 0: // EOD Summary
          final String? dateParam = _selectedEodDate != null ? DateFormat('yyyy-MM-dd').format(_selectedEodDate!) : null;
          final eod = await APIService.instance.getEODSummary(date: dateParam);
          if (mounted) _eodData = eod;
          break;
        case 1: // Expenses
          final exp = await APIService.instance.getExpenses();
          if (mounted) _expenses = exp;
          break;
        case 2: // Suppliers
          final sups = await APIService.instance.getSuppliers();
          if (mounted) _suppliers = sups;
          break;
        case 3: // Historical Reports
          final hist = await APIService.instance.getHistoricalReport(_historicalPeriod);
          if (mounted) _historicalReports = hist;
          break;
        case 4: // Activity logs
          final String? dateParam = _selectedLogsDate != null ? DateFormat('yyyy-MM-dd').format(_selectedLogsDate!) : null;
          final lgs = await APIService.instance.getActivityLogs(date: dateParam);
          if (mounted) _logs = lgs;
          break;
      }
    } catch (e) {
      print('Error loading report tab details: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingData = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reports & Logs',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Reports & Logs', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Tab bar selector
            Container(
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textLightSecondary,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'End-of-Day Summary'),
                  Tab(text: 'Expenses'),
                  Tab(text: 'Supplier Balances'),
                  Tab(text: 'Historical Reports'),
                  Tab(text: 'User Activity Logs'),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Content Area
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildEODTab(),
                  _buildExpensesTab(),
                  _buildSuppliersTab(),
                  _buildHistoricalTab(),
                  _buildLogsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 1: END-OF-DAY SUMMARY (Replica of Screenshot 4)
  // ----------------------------------------------------
  Widget _buildEODTab() {
    if (_loadingData) return Center(child: CircularProgressIndicator(color: AppTheme.primary));
    
    final sales = _eodData?['sales'] as List? ?? [
      {'payment_method': 'cash', 'total': 12450.00, 'count': 12},
      {'payment_method': 'card', 'total': 8900.00, 'count': 5},
      {'payment_method': 'qr', 'total': 4500.00, 'count': 2},
      {'payment_method': 'credit', 'total': 14500.00, 'count': 3},
    ];

    final expenses = _eodData?['expenses'] as List? ?? [
      {'category': 'ingredients', 'total': 4500.00},
      {'category': 'utility', 'total': 1200.00},
    ];

    final creditSettlements = _eodData?['credit_settlements'] ?? 2500.00;

    double totalSales = sales.fold(0.00, (sum, item) => sum + (double.tryParse(item['total'].toString()) ?? 0.00));
    double totalExpenses = expenses.fold(0.00, (sum, item) => sum + (double.tryParse(item['total'].toString()) ?? 0.00));

    final dateStr = _selectedEodDate != null 
        ? DateFormat('yyyy-MM-dd').format(_selectedEodDate!) 
        : DateFormat('yyyy-MM-dd').format(DateTime.now());

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Summary for: $dateStr',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedEodDate ?? DateTime.now(),
                        firstDate: DateTime(2025),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedEodDate = picked;
                        });
                        _loadTabSpecificData();
                      }
                    },
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: Text(_selectedEodDate != null ? DateFormat('yyyy-MM-dd').format(_selectedEodDate!) : 'Select Date'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cardLight,
                      foregroundColor: AppTheme.primary,
                      elevation: 0,
                      side: BorderSide(color: AppTheme.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  if (_selectedEodDate != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.clear, color: AppTheme.danger),
                      onPressed: () {
                        setState(() {
                          _selectedEodDate = null;
                        });
                        _loadTabSpecificData();
                      },
                    ),
                  ],
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _printEodSummary,
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Print Summary'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sales Breakdown Card (Left Card with soft pink tint)
              Expanded(
                child: Card(
                  elevation: 0,
                  color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.08) : const Color(0xFFFFF5F5), // Dynamic pinkish tint
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sales Breakdown', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        Divider(height: 32, color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                        ...sales.map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${s['payment_method'].toString().toUpperCase()} (${s['count']} bills)', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                              Text('LKR ${(double.parse(s['total'].toString())).toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                            ],
                          ),
                        )).toList(),
                        Divider(height: 32, color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Gross Sales:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                            Text('LKR ${totalSales.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              
              // Expenses & Credit Settlements (Right Cards with soft pink tint)
              Expanded(
                child: Column(
                  children: [
                    Card(
                      elevation: 0,
                      color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.08) : const Color(0xFFFFF5F5), // Dynamic pinkish tint
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Expenses Summary', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            Divider(height: 32, color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                            if (expenses.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('No expenses recorded today.', style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                              )
                            else
                              ...expenses.map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e['category'].toString().toUpperCase(), style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary)),
                                    Text('LKR ${(double.parse(e['total'].toString())).toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                  ],
                                ),
                              )).toList(),
                            Divider(height: 32, color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Expenses:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                Text('LKR ${totalExpenses.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 0,
                      color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.08) : const Color(0xFFFFF5F5), // Dynamic pinkish tint
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Credit Settlements Received:', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                            Text('LKR ${creditSettlements.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: const Color(0xFF10B981))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 2: EXPENSES LOGS & ENTERING (Replica of Screenshot 5)
  // ----------------------------------------------------
  Widget _buildExpensesTab() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Expense entry form (40%)
        Expanded(
          flex: 2,
          child: Card(
            elevation: 0,
            color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.08) : const Color(0xFFFFF5F5),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Record Daily Expense', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                  const SizedBox(height: 20),
                  
                  _buildFieldLabel('EXPENSE TITLE / ITEM *'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _expenseTitleController,
                    decoration: const InputDecoration(hintText: 'e.g. Tomato supply'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildFieldLabel('AMOUNT (LKR) *'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _expenseAmountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'Enter amount'),
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildFieldLabel('CATEGORY *'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _expenseCategory,
                    dropdownColor: AppTheme.cardLight,
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    items: const [
                      DropdownMenuItem(value: 'ingredients', child: Text('Ingredients / Gas / Veg')),
                      DropdownMenuItem(value: 'salary', child: Text('Employee Salaries')),
                      DropdownMenuItem(value: 'utility', child: Text('Utility (Water/Elect)')),
                      DropdownMenuItem(value: 'rent', child: Text('Rent')),
                      DropdownMenuItem(value: 'other', child: Text('Other Expenses')),
                    ],
                    onChanged: (val) => setState(() => _expenseCategory = val!),
                  ),
                  const SizedBox(height: 16),
                  
                  _buildFieldLabel('PAID FROM *'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _expenseSource,
                    dropdownColor: AppTheme.cardLight,
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                    items: const [
                      DropdownMenuItem(value: 'drawer', child: Text('Drawer Cash (Logs Drawer Cashout)')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank Transfer / Check')),
                    ],
                    onChanged: (val) => setState(() => _expenseSource = val!),
                  ),
                  const SizedBox(height: 24),
                  
                  ElevatedButton(
                    onPressed: _handleSaveExpense,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Record Expense', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 24),
        
        // Right: Expense list (60%)
        Expanded(
          flex: 3,
          child: Card(
            elevation: 0,
            color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.08) : const Color(0xFFFFF5F5),
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Expense Logs', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loadingData
                        ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                        : _expenses.isEmpty
                            ? Center(
                                child: Text('No expenses recorded.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
                              )
                            : ListView.separated(
                                itemCount: _expenses.length,
                                separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.isDarkMode ? AppTheme.primary.withOpacity(0.2) : const Color(0xFFFFD1D1)),
                                itemBuilder: (context, index) {
                                  final e = _expenses[index];
                                  final dateFormatted = DateFormat('yyyy-MM-dd').format(DateTime.tryParse(e.expenseDate) ?? DateTime.now());
                                  
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(e.title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${e.category.toUpperCase()} | Date: $dateFormatted (${e.paymentSource.toUpperCase()})',
                                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          'LKR ${e.amount.toStringAsFixed(0)}',
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary),
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
          ),
        ),
      ],
    );
  }

  void _handleSaveExpense() async {
    final title = _expenseTitleController.text.trim();
    final amount = double.tryParse(_expenseAmountController.text) ?? 0.00;
    if (title.isEmpty || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid title and amount'), backgroundColor: AppTheme.danger),
      );
      return;
    }

    try {
      final data = {
        'title': title,
        'amount': amount,
        'category': _expenseCategory,
        'payment_source': _expenseSource,
        'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      };

      await APIService.instance.createExpense(data);
      
      _expenseTitleController.clear();
      _expenseAmountController.clear();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense logged successfully.'), backgroundColor: AppTheme.accent),
      );
      
      _loadTabSpecificData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary),
    );
  }

  // ----------------------------------------------------
  // TAB 3: SUPPLIER BALANCE REPORT
  // ----------------------------------------------------
  Widget _buildSuppliersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Supplier Outstanding & Deliveries',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            ElevatedButton.icon(
              onPressed: () => _showAddEditSupplierDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Supplier'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _loadingData
              ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : _suppliers.isEmpty
                  ? Center(
                      child: Text(
                        'No suppliers added yet.',
                        style: GoogleFonts.inter(color: AppTheme.textLightSecondary),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.45,
                      ),
                      itemCount: _suppliers.length,
                      itemBuilder: (context, index) {
                        final s = _suppliers[index];
                        return Card(
                          elevation: 0,
                          color: AppTheme.cardLight,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: AppTheme.borderLight),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SupplierDetailScreen(supplier: s),
                                ),
                              );
                              _loadTabSpecificData();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          s.name,
                                          style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _showAddEditSupplierDialog(supplier: s),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.delete, size: 16, color: AppTheme.danger),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () => _confirmDeleteSupplier(s),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const Spacer(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Delivery Cycle', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                                          const SizedBox(height: 4),
                                          Text(s.deliveryCycle, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textLightPrimary)),
                                        ],
                                      ),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('Outstanding Bal', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                                          const SizedBox(height: 4),
                                          Text('LKR ${s.outstandingBalance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  Divider(height: 20, color: AppTheme.dividerColor),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: () => _showPaySupplierDialog(s),
                                      icon: const Icon(Icons.payment, size: 14),
                                      label: const Text('Pay Supplier', style: TextStyle(fontSize: 12)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(vertical: 8),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _showAddEditSupplierDialog({SupplierModel? supplier}) {
    final isEdit = supplier != null;
    final nameController = TextEditingController(text: supplier?.name ?? '');
    final balanceController = TextEditingController(text: supplier != null ? supplier.outstandingBalance.toString() : '0.00');
    final deliveryController = TextEditingController(text: supplier?.deliveryCycle ?? 'Weekly');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.cardLight,
          title: Text(isEdit ? 'Edit Supplier' : 'Add Supplier', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: AppTheme.textLightPrimary),
                  decoration: const InputDecoration(labelText: 'Supplier Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: balanceController,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: AppTheme.textLightPrimary),
                  decoration: const InputDecoration(labelText: 'Outstanding Balance (LKR)'),
                  enabled: !isEdit,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deliveryController,
                  style: TextStyle(color: AppTheme.textLightPrimary),
                  decoration: const InputDecoration(labelText: 'Delivery Cycle (e.g. Weekly, Daily)'),
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
                final name = nameController.text.trim();
                final balance = double.tryParse(balanceController.text) ?? 0.00;
                final delivery = deliveryController.text.trim();

                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Name is required'), backgroundColor: AppTheme.danger),
                  );
                  return;
                }

                try {
                  if (isEdit) {
                    await APIService.instance.updateSupplier(supplier.id, {
                      'name': name,
                      'delivery_cycle': delivery,
                    });
                  } else {
                    await APIService.instance.createSupplier({
                      'name': name,
                      'outstanding_balance': balance,
                      'delivery_cycle': delivery,
                    });
                  }
                  Navigator.pop(context);
                  _loadTabSpecificData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(isEdit ? 'Supplier updated' : 'Supplier added'), backgroundColor: AppTheme.accent),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              child: Text(isEdit ? 'Update' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteSupplier(SupplierModel supplier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.cardLight,
          title: Text('Delete Supplier', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.danger)),
          content: Text('Are you sure you want to delete "${supplier.name}"? This action cannot be undone.', style: TextStyle(color: AppTheme.textLightPrimary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await APIService.instance.deleteSupplier(supplier.id);
                  Navigator.pop(context);
                  _loadTabSpecificData();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Supplier deleted'), backgroundColor: AppTheme.accent),
                  );
                } catch (e) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _showPaySupplierDialog(SupplierModel supplier) {
    final amountController = TextEditingController();
    final remarksController = TextEditingController();
    String paymentSource = 'drawer';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              title: Text('Pay Supplier - ${supplier.name}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outstanding: LKR ${supplier.outstandingBalance.toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: amountController,
                      style: TextStyle(color: AppTheme.textLightPrimary),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Payment Amount (LKR) *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: remarksController,
                      style: TextStyle(color: AppTheme.textLightPrimary),
                      decoration: const InputDecoration(labelText: 'Remarks / Invoice No'),
                    ),
                    const SizedBox(height: 16),
                    Text('PAID FROM', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: paymentSource,
                      dropdownColor: AppTheme.cardLight,
                      style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                      items: const [
                        DropdownMenuItem(value: 'drawer', child: Text('Drawer Cash (Logs Drawer Cashout)')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank Transfer / Check')),
                      ],
                      onChanged: (val) => setState(() => paymentSource = val!),
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
                    final amountStr = amountController.text.trim();
                    final amount = double.tryParse(amountStr) ?? 0.00;
                    final remarks = remarksController.text.trim();

                    if (amountStr.isEmpty || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid positive payment amount'), backgroundColor: AppTheme.danger),
                      );
                      return;
                    }

                    try {
                      await APIService.instance.paySupplier(supplier.id, amount, paymentSource, remarks);
                      Navigator.pop(context);
                      _loadTabSpecificData();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment recorded successfully'), backgroundColor: AppTheme.accent),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                  child: const Text('Pay'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------
  // TAB 4: HISTORICAL REPORTS
  // ----------------------------------------------------
  Widget _buildHistoricalTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Historical Sales Summaries',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            const Spacer(),
             ChoiceChip(
              label: Text('Monthly Summary', style: TextStyle(color: _historicalPeriod == 'monthly' ? Colors.white : AppTheme.textLightPrimary)),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.cardLight,
              selected: _historicalPeriod == 'monthly',
              onSelected: (val) {
                setState(() => _historicalPeriod = 'monthly');
                _loadTabSpecificData();
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('Yearly Summary', style: TextStyle(color: _historicalPeriod == 'yearly' ? Colors.white : AppTheme.textLightPrimary)),
              selectedColor: AppTheme.primary,
              backgroundColor: AppTheme.cardLight,
              selected: _historicalPeriod == 'yearly',
              onSelected: (val) {
                setState(() => _historicalPeriod = 'yearly');
                _loadTabSpecificData();
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            elevation: 0,
            color: AppTheme.cardLight,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppTheme.dividerColor),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _loadingData
                  ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _historicalReports.isEmpty
                      ? Center(child: Text('No historical summaries found.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                      : ListView.separated(
                          itemCount: _historicalReports.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                          itemBuilder: (context, index) {
                            final r = _historicalReports[index];
                            return ListTile(
                              leading: Icon(Icons.calendar_month, color: AppTheme.primary),
                              title: Text('Period: ${r['period']}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                              subtitle: Text('Total Orders: ${r['total_orders']} completed transactions.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                              trailing: Text('LKR ${(double.parse(r['revenue'].toString())).toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                            );
                          },
                        ),
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // TAB 5: USER ACTIVITY LOGS (AUDIT TRAIL)
  // ----------------------------------------------------
  Widget _buildLogsTab() {
    final hasLogs = _logs.isNotEmpty;
    final dateStr = _selectedLogsDate != null 
        ? DateFormat('yyyy-MM-dd').format(_selectedLogsDate!) 
        : 'All Logs';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'System Audit Log & Activity Trails',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Filtered by: $dateStr',
                  style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                ),
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedLogsDate ?? DateTime.now(),
                      firstDate: DateTime(2025),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() {
                        _selectedLogsDate = picked;
                      });
                      _loadTabSpecificData();
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 16),
                  label: Text(_selectedLogsDate != null ? DateFormat('yyyy-MM-dd').format(_selectedLogsDate!) : 'Select Date'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cardLight,
                    foregroundColor: AppTheme.primary,
                    elevation: 0,
                    side: BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                if (_selectedLogsDate != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear, color: AppTheme.danger),
                    onPressed: () {
                      setState(() {
                        _selectedLogsDate = null;
                      });
                      _loadTabSpecificData();
                    },
                  ),
                ],
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: hasLogs ? _printActivityLogs : null,
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Print Logs'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppTheme.isDarkMode ? Colors.grey[800] : Colors.grey[300],
                    disabledForegroundColor: AppTheme.isDarkMode ? Colors.grey[600] : Colors.grey[600],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            elevation: 0,
            color: AppTheme.cardLight,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppTheme.borderLight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: _loadingData
                  ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _logs.isEmpty
                      ? Center(child: Text('No audit logs available.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                      : ListView.separated(
                          itemCount: _logs.length,
                          separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                          itemBuilder: (context, index) {
                            final l = _logs[index];
                            final isDanger = l.actionType == 'delete_bill' || l.actionType == 'cancel_order';
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                children: [
                                  Icon(
                                    isDanger ? Icons.delete_forever : Icons.info_outline,
                                    color: isDanger ? AppTheme.danger : Colors.blue,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          l.details,
                                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'User: ${l.username ?? "Admin"} (${(l.role ?? "admin").toUpperCase()}) | Time: ${l.timestamp}',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Chip(
                                    label: Text(l.actionType.toUpperCase(), style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                    backgroundColor: AppTheme.primary.withOpacity(0.08),
                                    side: BorderSide.none,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _printActivityLogs() async {
    try {
      final doc = pw.Document();
      
      final headers = ['Time', 'User', 'Role', 'Action Type', 'Details'];
      
      final data = _logs.map((log) {
        return [
          log.timestamp.toString(),
          log.username ?? 'Admin',
          (log.role ?? 'admin').toUpperCase(),
          log.actionType.toUpperCase(),
          log.details
        ];
      }).toList();

      final dateStr = _selectedLogsDate != null 
          ? DateFormat('yyyy-MM-dd').format(_selectedLogsDate!) 
          : 'All Time (Last 100 Logs)';

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
                          'System Activity Logs & Audit Trail',
                          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Report Date / Scope: $dateStr'),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text('Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
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
                    1: pw.Alignment.centerLeft,
                    2: pw.Alignment.center,
                    3: pw.Alignment.center,
                    4: pw.Alignment.centerLeft,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Activity_Logs_${dateStr.replaceAll(' ', '_')}',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print activity logs: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _printEodSummary() async {
    try {
      final doc = pw.Document();

      final dateStr = _selectedEodDate != null 
          ? DateFormat('yyyy-MM-dd').format(_selectedEodDate!) 
          : DateFormat('yyyy-MM-dd').format(DateTime.now());

      final sales = _eodData?['sales'] as List? ?? [];
      final expenses = _eodData?['expenses'] as List? ?? [];
      final creditSettlements = _eodData?['credit_settlements'] ?? 0.00;

      double totalSales = sales.fold(0.00, (sum, item) => sum + (double.tryParse(item['total'].toString()) ?? 0.00));
      double totalExpenses = expenses.fold(0.00, (sum, item) => sum + (double.tryParse(item['total'].toString()) ?? 0.00));

      final salesHeaders = ['Payment Method / Count', 'Total Amount'];
      final salesData = sales.map((s) {
        return [
          '${s['payment_method'].toString().toUpperCase()} (${s['count']} bills)',
          'LKR ${(double.parse(s['total'].toString())).toStringAsFixed(2)}'
        ];
      }).toList();

      final expensesHeaders = ['Expense Category', 'Total Amount'];
      final expensesData = expenses.map((e) {
        return [
          e['category'].toString().toUpperCase(),
          'LKR ${(double.parse(e['total'].toString())).toStringAsFixed(2)}'
        ];
      }).toList();

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'End of Day (EOD) Financial Summary',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text('Report Date: $dateStr'),
                pw.Text('Generated At: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}'),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 15),

                pw.Text('1. Sales Breakdown', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Table.fromTextArray(
                  headers: salesHeaders,
                  data: salesData,
                  border: pw.TableBorder.all(color: PdfColors.grey300),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                  cellStyle: const pw.TextStyle(fontSize: 9),
                  cellHeight: 24,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.centerRight,
                  },
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Gross Sales:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text('LKR ${totalSales.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.red800)),
                  ],
                ),

                pw.SizedBox(height: 24),
                pw.Text('2. Expenses Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                expensesData.isEmpty 
                  ? pw.Text('No expenses recorded for this date.', style: const pw.TextStyle(fontSize: 9))
                  : pw.Table.fromTextArray(
                      headers: expensesHeaders,
                      data: expensesData,
                      border: pw.TableBorder.all(color: PdfColors.grey300),
                      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
                      cellStyle: const pw.TextStyle(fontSize: 9),
                      cellHeight: 24,
                      cellAlignments: {
                        0: pw.Alignment.centerLeft,
                        1: pw.Alignment.centerRight,
                      },
                    ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Total Expenses:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                    pw.Text('LKR ${totalExpenses.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.red800)),
                  ],
                ),

                pw.SizedBox(height: 24),
                pw.Text('3. Credit Settlements Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Credit Settlements Received:', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('LKR ${creditSettlements.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.green800)),
                  ],
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'EOD_Summary_${dateStr.replaceAll('-', '_')}',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print EOD summary: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }
}
