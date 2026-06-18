import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../api_service.dart';
import '../models.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({Key? key}) : super(key: key);

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _loadingData = false;

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

  // Supplier mock database
  final List<Map<String, dynamic>> _suppliers = [
    {'name': 'Aliya Flour Suppliers', 'outstanding': 45000.00, 'delivery': 'Weekly (Monday)'},
    {'name': 'Coca-Cola Beverages', 'outstanding': 18500.00, 'delivery': 'Weekly (Thursday)'},
    {'name': 'Keells Meat Providers', 'outstanding': 120000.00, 'delivery': 'Daily'},
    {'name': 'Prima Flour Co.', 'outstanding': 0.00, 'delivery': 'Bi-weekly'},
  ];

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
          final eod = await APIService.instance.getEODSummary();
          if (mounted) _eodData = eod;
          break;
        case 1: // Expenses
          final exp = await APIService.instance.getExpenses();
          if (mounted) _expenses = exp;
          break;
        case 2: // Suppliers
          // Supplier database remains local mock
          break;
        case 3: // Historical Reports
          final hist = await APIService.instance.getHistoricalReport(_historicalPeriod);
          if (mounted) _historicalReports = hist;
          break;
        case 4: // Activity logs
          final lgs = await APIService.instance.getActivityLogs();
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
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: Colors.white,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textLightSecondary,
            indicatorColor: AppTheme.primary,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'End-of-Day Summary'),
              Tab(text: 'Expenses'),
              Tab(text: 'Supplier Balances'),
              Tab(text: 'Historical Reports'),
              Tab(text: 'User Activity Logs'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEODTab(),
          _buildExpensesTab(),
          _buildSuppliersTab(),
          _buildHistoricalTab(),
          _buildLogsTab(),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 1: END-OF-DAY SUMMARY
  // ----------------------------------------------------
  Widget _buildEODTab() {
    if (_loadingData) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Today\'s Summary: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sales Breakdown Card
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Sales Breakdown', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        const Divider(height: 24),
                        ...sales.map((s) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${s['payment_method'].toString().toUpperCase()} (${s['count']} bills)', style: GoogleFonts.inter(fontSize: 13)),
                              Text('LKR ${(double.parse(s['total'].toString())).toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )).toList(),
                        const Divider(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Total Gross Sales:', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            Text('LKR ${totalSales.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              // Expenses & Credit settlements
              Expanded(
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Expenses Summary', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.danger)),
                            const Divider(height: 24),
                            if (expenses.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('No expenses recorded today.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                              )
                            else
                              ...expenses.map((e) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(e['category'].toString().toUpperCase(), style: GoogleFonts.inter(fontSize: 13)),
                                    Text('LKR ${(double.parse(e['total'].toString())).toStringAsFixed(2)}', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              )).toList(),
                            const Divider(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Total Expenses:', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                                Text('LKR ${totalExpenses.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.danger)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Credit Settlements Received:', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                            Text('LKR ${creditSettlements.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.accent)),
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
  // TAB 2: EXPENSES LOGS & ENTERING
  // ----------------------------------------------------
  Widget _buildExpensesTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Expense entry form (40%)
          Expanded(
            flex: 2,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Record Daily Expense', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(controller: _expenseTitleController, decoration: const InputDecoration(labelText: 'Expense Title / Item')),
                    const SizedBox(height: 12),
                    TextField(controller: _expenseAmountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (LKR)')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _expenseCategory,
                      decoration: const InputDecoration(labelText: 'Category'),
                      items: const [
                        DropdownMenuItem(value: 'ingredients', child: Text('Ingredients / Gas / Veg')),
                        DropdownMenuItem(value: 'salary', child: Text('Employee Salaries')),
                        DropdownMenuItem(value: 'utility', child: Text('Utility (Water/Elect)')),
                        DropdownMenuItem(value: 'rent', child: Text('Rent')),
                        DropdownMenuItem(value: 'other', child: Text('Other Expenses')),
                      ],
                      onChanged: (val) => setState(() => _expenseCategory = val!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _expenseSource,
                      decoration: const InputDecoration(labelText: 'Paid From'),
                      items: const [
                        DropdownMenuItem(value: 'drawer', child: Text('Drawer Cash (Logs Drawer Cashout)')),
                        DropdownMenuItem(value: 'bank', child: Text('Bank Transfer / Check')),
                      ],
                      onChanged: (val) => setState(() => _expenseSource = val!),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _handleSaveExpense,
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                      child: const Text('Record Expense'),
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
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expense Logs', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _loadingData
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                          : _expenses.isEmpty
                              ? Center(
                                  child: Text('No expenses recorded.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)),
                                )
                              : ListView.builder(
                                  itemCount: _expenses.length,
                                  itemBuilder: (context, index) {
                                    final e = _expenses[index];
                                    return ListTile(
                                      title: Text(e.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text('${e.category.toUpperCase()} | Date: ${e.expenseDate} (${e.paymentSource.toUpperCase()})'),
                                      trailing: Text('LKR ${e.amount.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.danger)),
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
      ),
    );
  }

  void _handleSaveExpense() async {
    final title = _expenseTitleController.text.trim();
    final amount = double.tryParse(_expenseAmountController.text) ?? 0.00;
    if (title.isEmpty || amount <= 0) return;

    try {
      final data = {
        'title': title,
        'amount': amount,
        'category': _expenseCategory,
        'payment_source': _expenseSource,
        'expense_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      };

      await APIService.instance.createExpense(data);
      if (mounted) {
        _expenseTitleController.clear();
        _expenseAmountController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense logged successfully.')),
        );
        _loadTabSpecificData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  // ----------------------------------------------------
  // TAB 3: SUPPLIER BALANCE REPORT
  // ----------------------------------------------------
  Widget _buildSuppliersTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supplier Outstanding & Deliveries',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 2.2,
              ),
              itemCount: _suppliers.length,
              itemBuilder: (context, index) {
                final s = _suppliers[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s['name'], style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Delivery Cycle:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                                Text(s['delivery'], style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Outstanding Bal:', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                                Text('LKR ${s['outstanding'].toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 4: HISTORICAL REPORTS
  // ----------------------------------------------------
  Widget _buildHistoricalTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Historical Sales Summaries',
                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              ChoiceChip(
                label: const Text('Monthly Summary'),
                selected: _historicalPeriod == 'monthly',
                onSelected: (val) {
                  setState(() => _historicalPeriod = 'monthly');
                  _loadTabSpecificData();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Yearly Summary'),
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
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _loadingData
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _historicalReports.isEmpty
                        ? const Center(child: Text('No historical summaries found.'))
                        : ListView.builder(
                            itemCount: _historicalReports.length,
                            itemBuilder: (context, index) {
                              final r = _historicalReports[index];
                              return ListTile(
                                leading: const Icon(Icons.calendar_month, color: AppTheme.primary),
                                title: Text('Period: ${r['period']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Total Orders: ${r['total_orders']} completed transactions.'),
                                trailing: Text('LKR ${(double.parse(r['revenue'].toString())).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                              );
                            },
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 5: USER ACTIVITY LOGS (AUDIT TRAIL)
  // ----------------------------------------------------
  Widget _buildLogsTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Audit Log & Activity Trails',
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _loadingData
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : _logs.isEmpty
                        ? const Center(child: Text('No audit logs available.'))
                        : ListView.builder(
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              final l = _logs[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: const BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      l.actionType == 'delete_bill' ? Icons.delete_forever : Icons.info_outline,
                                      color: l.actionType == 'delete_bill' ? AppTheme.danger : AppTheme.secondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            l.details,
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'User: ${l.username ?? "Admin"} (${(l.role ?? "admin").toUpperCase()}) | Time: ${l.timestamp}',
                                            style: const TextStyle(fontSize: 11, color: AppTheme.textLightSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Chip(
                                      label: Text(l.actionType.toUpperCase(), style: const TextStyle(fontSize: 9)),
                                      backgroundColor: AppTheme.primary.withOpacity(0.08),
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
      ),
    );
  }
}
