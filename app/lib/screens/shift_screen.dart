import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../controllers/dashboard_controller.dart';
import '../models/models.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({Key? key}) : super(key: key);

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  final TextEditingController _openingBalanceController = TextEditingController(text: '5000.00');
  final TextEditingController _actualCashController = TextEditingController();
  final TextEditingController _cashInOutAmountController = TextEditingController();
  final TextEditingController _cashInOutReasonController = TextEditingController();

  int? _lastShiftId;
  double _cashSales = 0.0;
  double _expectedDrawerBalance = 0.0;
  bool _loadingShiftData = false;
  List<OrderModel> _shiftOrders = [];
  double _cardSales = 0.0;
  double _qrSales = 0.0;
  double _creditSales = 0.0;
  int _totalOrdersCount = 0;

  List<SupplierModel> _suppliers = [];
  SupplierModel? _selectedSupplier;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
  }

  Future<void> _fetchSuppliers() async {
    try {
      final sups = await APIService.instance.getSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = sups;
        });
      }
    } catch (e) {
      print('Error fetching suppliers in shift screen: $e');
    }
  }

  Future<void> _loadShiftData(POSController controller) async {
    if (controller.activeShift == null) return;
    setState(() => _loadingShiftData = true);
    try {
      final sales = await controller.getShiftCashSales();
      final expected = await controller.getExpectedDrawerBalance();
      setState(() {
        _cashSales = sales;
        _expectedDrawerBalance = expected;
        _loadingShiftData = false;
      });
    } catch (e) {
      setState(() => _loadingShiftData = false);
      print('Error loading shift data: $e');
    }
  }

  @override
  void dispose() {
    _openingBalanceController.dispose();
    _actualCashController.dispose();
    _cashInOutAmountController.dispose();
    _cashInOutReasonController.dispose();
    super.dispose();
  }



  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;

    // Automatically load logs when shift is detected
    if (controller.activeShift != null && controller.activeShift!.id != _lastShiftId) {
      _lastShiftId = controller.activeShift!.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.fetchDrawerLogs();
        _loadShiftData(controller);
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Container(
        padding: const EdgeInsets.all(24),
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
                      'Shifts & Cash Drawer'.tr(context),
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard'.tr(context), style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Shifts & Cash'.tr(context), style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            Expanded(
              child: controller.activeShift == null
                  ? _buildOpenShiftLayout(controller)
                  : isDesktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildShiftDetailsArea(controller),
                                    const SizedBox(height: 24),
                                    _buildCashDrawerLogsCard(controller),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              flex: 2,
                              child: _buildShiftCloseArea(controller),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildShiftDetailsArea(controller),
                              const SizedBox(height: 16),
                              _buildCashDrawerLogsCard(controller),
                              const SizedBox(height: 16),
                              _buildShiftCloseArea(controller),
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
  // LAYOUT: OPEN SHIFT
  // ----------------------------------------------------
  Widget _buildOpenShiftLayout(POSController controller) {
    return Center(
      child: Container(
        width: 420,
        child: Card(
          elevation: 0,
          color: AppTheme.cardLight,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.borderLight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Icon(Icons.lock_open, size: 30, color: AppTheme.primary),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Open Daily Shift'.tr(context),
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Setup starting cash balance in drawer.'.tr(context),
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _openingBalanceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Starting Cash Balance (LKR) *'.tr(context),
                    hintText: '5000.00',
                  ),
                  style: GoogleFonts.inter(fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () async {
                    final balance = double.tryParse(_openingBalanceController.text) ?? 0.00;
                    try {
                      await controller.openNewShift(balance);
                      await controller.reloadEnvironment();
                    } catch (e) {
                      _showSnackBar(e.toString());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Open Cash Drawer & Start Shift'.tr(context), style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // LAYOUT: SHIFT DETAILS (Expected cash / cash-in-outs)
  // ----------------------------------------------------
  Widget _buildShiftDetailsArea(POSController controller) {
    final starting = controller.activeShift?.openingBalance ?? 0.00;
    final cashSalesVal = _cashSales; 
    final expectedTotal = _expectedDrawerBalance;

    double creditSettlementsReceived = 0.0;
    double otherCashIn = 0.0;
    double cashOutAdjustments = 0.0;

    for (var log in controller.drawerLogs) {
      final double amt = double.tryParse(log['amount']?.toString() ?? '0') ?? 0.0;
      if (log['type'] == 'cash_in') {
        if (log['reason']?.toString().contains('Credit Settlement:') ?? false) {
          creditSettlementsReceived += amt;
        } else {
          otherCashIn += amt;
        }
      } else if (log['type'] == 'cash_out') {
        cashOutAdjustments += amt;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cash Status Row Cards
        Card(
          elevation: 0,
          color: AppTheme.cardLight,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.borderLight),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shift Cash Status'.tr(context),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 20),
                _buildCashDetailRow('Opening Cash Balance'.tr(context), starting, Icons.vpn_key_outlined, const Color(0xFFE0F2FE), Colors.blue),
                Divider(height: 24, color: AppTheme.dividerColor),
                _buildCashDetailRow('Today\'s Cash Sales'.tr(context), cashSalesVal, Icons.point_of_sale_outlined, const Color(0xFFE6F4EA), const Color(0xFF137333)),
                Divider(height: 24, color: AppTheme.dividerColor),
                if (creditSettlementsReceived > 0) ...[
                  _buildCashDetailRow('Credit Settlements (Cash)'.tr(context), creditSettlementsReceived, Icons.assignment_returned_outlined, const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
                  Divider(height: 24, color: AppTheme.dividerColor),
                ],
                if (otherCashIn > 0) ...[
                  _buildCashDetailRow('Other Cash In'.tr(context), otherCashIn, Icons.add_circle_outline, const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                  Divider(height: 24, color: AppTheme.dividerColor),
                ],
                if (cashOutAdjustments > 0) ...[
                  _buildCashDetailRow('Cash Out Adjustments'.tr(context), cashOutAdjustments, Icons.remove_circle_outline, const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
                  Divider(height: 24, color: AppTheme.dividerColor),
                ],
                _buildCashDetailRow('Expected Cash in Drawer'.tr(context), expectedTotal, Icons.wallet_outlined, Color(0xFFFFF0F5), AppTheme.primary, isTotal: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Cash Drawer Control card
        Card(
          elevation: 0,
          color: AppTheme.cardLight,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: AppTheme.borderLight),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash Drawer Control (In / Out Adjustments)'.tr(context),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<SupplierModel?>(
                  value: _selectedSupplier,
                  dropdownColor: AppTheme.cardLight,
                  decoration: InputDecoration(
                    labelText: 'Supplier Payment (Optional)'.tr(context),
                  ),
                  items: [
                    DropdownMenuItem<SupplierModel?>(
                      value: null,
                      child: Text('None (General Cash Adjustment)'.tr(context)),
                    ),
                    ..._suppliers.map((s) => DropdownMenuItem<SupplierModel?>(
                          value: s,
                          child: Text('${s.name} (Bal: LKR ${s.outstandingBalance.toStringAsFixed(0)})'),
                        )),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedSupplier = val;
                      if (val != null) {
                        _cashInOutReasonController.text = 'Supplier Payment: ${val.name}';
                      } else {
                        _cashInOutReasonController.clear();
                      }
                    });
                  },
                  style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cashInOutAmountController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Amount (LKR) *'.tr(context)),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _cashInOutReasonController,
                        decoration: InputDecoration(labelText: 'Reason / Remarks *'.tr(context)),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleDrawerAdjustment(controller, 'cash_in'),
                        icon: const Icon(Icons.arrow_upward, size: 16, color: Colors.white),
                        label: Text('Add Cash In'.tr(context)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981), // Emerald Green
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _handleDrawerAdjustment(controller, 'cash_out'),
                        icon: const Icon(Icons.arrow_downward, size: 16, color: Colors.white),
                        label: Text('Remove Cash Out'.tr(context)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF43F5E), // Rose Red
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ----------------------------------------------------
  // LAYOUT: CASH TRANSACTION LEDGER
  // ----------------------------------------------------
  Widget _buildCashDrawerLogsCard(POSController controller) {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Drawer Transaction Logs'.tr(context),
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                if (controller.drawerLogs.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () => _printDrawerLogs(controller),
                    icon: const Icon(Icons.print, size: 14),
                    label: Text('Print Logs'.tr(context), style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            if (controller.drawerLogs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Center(
                  child: Text(
                    'No transaction logs for this shift.'.tr(context),
                    style: GoogleFonts.inter(color: const Color(0xFF64748B)),
                  ),
                ),
              )
            else
              // Log Table
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: AppTheme.bgLight,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: _buildTableHeaderText('TYPE'.tr(context))),
                        Expanded(flex: 3, child: _buildTableHeaderText('AMOUNT'.tr(context))),
                        Expanded(flex: 5, child: _buildTableHeaderText('REASON'.tr(context))),
                        Expanded(flex: 3, child: _buildTableHeaderText('TIME'.tr(context))),
                      ],
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: controller.drawerLogs.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: AppTheme.dividerColor),
                    itemBuilder: (context, index) {
                      final log = controller.drawerLogs[index];
                      final isCashIn = log['type'] == 'cash_in';
                      final timeFormatted = DateFormat('hh:mm a').format((DateTime.tryParse(log['timestamp']) ?? DateTime.now()).toLocal());
                      
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        child: Row(
                          children: [
                            // TYPE BADGE
                            Expanded(
                              flex: 2,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isCashIn ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isCashIn ? 'IN'.tr(context) : 'OUT'.tr(context),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isCashIn ? const Color(0xFF137333) : const Color(0xFFC5221F),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // AMOUNT
                            Expanded(
                              flex: 3,
                              child: Text(
                                'LKR ${double.parse(log['amount'].toString()).toStringAsFixed(2)}',
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isCashIn ? const Color(0xFF137333) : const Color(0xFFC5221F),
                                ),
                              ),
                            ),
                            // REASON
                             Expanded(
                              flex: 5,
                              child: Text(
                                log['reason'] ?? '',
                                style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // TIME
                            Expanded(
                              flex: 3,
                              child: Text(
                                timeFormatted,
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
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

  // ----------------------------------------------------
  // LAYOUT: SHIFT CLOSE & RECONCILIATION
  // ----------------------------------------------------
  Widget _buildShiftCloseArea(POSController controller) {
    final starting = controller.activeShift?.openingBalance ?? 0.00;
    final expectedTotal = _expectedDrawerBalance;

    double creditSettlements = 0.0;
    double otherCashIn = 0.0;
    double supplierPayments = 0.0;
    double otherCashOut = 0.0;

    for (var log in controller.drawerLogs) {
      final double amt = double.tryParse(log['amount']?.toString() ?? '0') ?? 0.0;
      if (log['type'] == 'cash_in') {
        if (log['reason']?.toString().contains('Credit Settlement:') ?? false) {
          creditSettlements += amt;
        } else {
          otherCashIn += amt;
        }
      } else if (log['type'] == 'cash_out') {
        if (log['reason']?.toString().contains('Supplier Payment:') ?? false) {
          supplierPayments += amt;
        } else {
          otherCashOut += amt;
        }
      }
    }

    final double totalSales = _cashSales + _cardSales + _qrSales + _creditSales;

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
              'Shift Close Reconciliation Report'.tr(context),
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Count drawer cash and compare with expected balances. Closing shift prints a final Z-Report.'.tr(context),
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
            ),
            Divider(height: 16, color: AppTheme.dividerColor),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Cash Reconciliation Details
                    Text('CASH DRAWER RECONCILIATION'.tr(context), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 8),
                    _buildMiniReconcileRow('Starting Cash Balance'.tr(context), starting),
                    _buildMiniReconcileRow('Cash Sales (+)'.tr(context), _cashSales, color: const Color(0xFF16A34A)),
                    _buildMiniReconcileRow('Credit Settlements (+)'.tr(context), creditSettlements, color: const Color(0xFF16A34A)),
                    _buildMiniReconcileRow('Other Cash In (+)'.tr(context), otherCashIn, color: const Color(0xFF16A34A)),
                    _buildMiniReconcileRow('Supplier Payments (-)'.tr(context), -supplierPayments, color: const Color(0xFFEF4444)),
                    _buildMiniReconcileRow('Other Cash Out (-)'.tr(context), -otherCashOut, color: const Color(0xFFEF4444)),
                    Divider(height: 12, color: AppTheme.dividerColor),
                    _buildMiniReconcileRow('EXPECTED CASH IN DRAWER'.tr(context), expectedTotal, isBold: true),
                    Divider(height: 16, color: AppTheme.dividerColor),

                    // Other Payment Methods
                    Text('NON-CASH SALES SUMMARY'.tr(context), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 8),
                    _buildMiniReconcileRow('Card Payments'.tr(context), _cardSales),
                    _buildMiniReconcileRow('LankaQR Payments'.tr(context), _qrSales),
                    _buildMiniReconcileRow('Credit Sales (Outstanding Added)'.tr(context), _creditSales),
                    Divider(height: 12, color: AppTheme.dividerColor),
                    _buildMiniReconcileRow('TOTAL SHIFT SALES'.tr(context), totalSales, isBold: true, color: AppTheme.primary),
                    Divider(height: 16, color: AppTheme.dividerColor),

                    // Input Actual Cash Counted
                    Text('ACTUAL DRAWER CASH COUNT'.tr(context), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _actualCashController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Actual Cash Counted (LKR) *'.tr(context),
                        hintText: 'Enter total cash counted',
                        prefixText: 'LKR ',
                      ),
                      style: GoogleFonts.inter(fontSize: 13),
                    ),
                    const SizedBox(height: 24),

                    ElevatedButton.icon(
                      onPressed: () async {
                        final actual = double.tryParse(_actualCashController.text) ?? 0.00;
                        try {
                          // Generate and print Shift Z-Report PDF before closing
                          await _printShiftZReport(
                            controller,
                            starting,
                            _cashSales,
                            creditSettlements,
                            otherCashIn,
                            supplierPayments,
                            otherCashOut,
                            expectedTotal,
                            _cardSales,
                            _qrSales,
                            _creditSales,
                            totalSales,
                            actual,
                          );

                          // Close the shift in backend
                          await controller.closeActiveShift(expectedTotal, actual);
                          await controller.reloadEnvironment();
                          _actualCashController.clear();
                          if (mounted) {
                            _showSnackBar('Shift closed successfully. Z-Report printed.');
                          }
                        } catch (e) {
                          _showSnackBar(e.toString());
                        }
                      },
                      icon: const Icon(Icons.lock_clock, size: 16),
                      label: Text('Close Shift & Print Z-Report'.tr(context), style: const TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.danger,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniReconcileRow(String label, double val, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? AppTheme.textLightPrimary : AppTheme.textLightSecondary,
            ),
          ),
          Text(
            'LKR ${val.toStringAsFixed(2)}',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isBold ? AppTheme.textLightPrimary : AppTheme.textLightPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printShiftZReport(
    POSController controller,
    double starting,
    double cashSales,
    double creditSettlements,
    double otherCashIn,
    double supplierPayments,
    double otherCashOut,
    double expectedCash,
    double cardSales,
    double qrSales,
    double creditSales,
    double totalSales,
    double actualCash,
  ) async {
    try {
      final doc = pw.Document();
      final lang = Provider.of<DashboardController>(context, listen: false).selectedLanguage;
      final fontData = await rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf');
      final font = pw.Font.ttf(fontData);
      final fontBold = font;

      final activeShift = controller.activeShift;
      final shiftIdStr = activeShift?.id.toString() ?? 'N/A';
      final openedAtStr = activeShift?.startTime != null 
          ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(activeShift!.startTime).toLocal())
          : 'N/A';
      final closedAtStr = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
      final cashierName = APIService.instance.currentUser?.name ?? 'Admin';
      final variance = actualCash - expectedCash;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Text('MATARA HOTEL', style: pw.TextStyle(font: fontBold, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Center(
                  child: pw.Text(TranslationService.translateRaw('SHIFT Z-REPORT (RECONCILIATION)', lang), style: pw.TextStyle(font: fontBold, fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
                pw.SizedBox(height: 10),
                pw.Text('${TranslationService.translateRaw('Shift ID:', lang)} #$shiftIdStr', style: pw.TextStyle(font: font, fontSize: 8)),
                pw.Text('${TranslationService.translateRaw('Cashier:', lang)} $cashierName', style: pw.TextStyle(font: font, fontSize: 8)),
                pw.Text('${TranslationService.translateRaw('Opened:', lang)} $openedAtStr', style: pw.TextStyle(font: font, fontSize: 8)),
                pw.Text('${TranslationService.translateRaw('Closed:', lang)} $closedAtStr', style: pw.TextStyle(font: font, fontSize: 8)),
                pw.SizedBox(height: 6),
                pw.Text('-' * 45, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                pw.SizedBox(height: 6),

                pw.Text(TranslationService.translateRaw('CASH DRAWER RECONCILIATION', lang), style: pw.TextStyle(font: fontBold, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                _buildPdfMiniRow(TranslationService.translateRaw('Opening Drawer Cash', lang), starting, font),
                _buildPdfMiniRow(TranslationService.translateRaw('Cash Sales (+)', lang), cashSales, font),
                _buildPdfMiniRow(TranslationService.translateRaw('Credit Settlements (+)', lang), creditSettlements, font),
                _buildPdfMiniRow(TranslationService.translateRaw('Other Cash In (+)', lang), otherCashIn, font),
                _buildPdfMiniRow(TranslationService.translateRaw('Supplier Payments (-)', lang), -supplierPayments, font),
                _buildPdfMiniRow(TranslationService.translateRaw('Other Cash Out (-)', lang), -otherCashOut, font),
                pw.SizedBox(height: 2),
                _buildPdfMiniRow(TranslationService.translateRaw('EXPECTED CASH', lang), expectedCash, fontBold),
                _buildPdfMiniRow(TranslationService.translateRaw('ACTUAL CASH COUNTED', lang), actualCash, fontBold),
                _buildPdfMiniRow(TranslationService.translateRaw('VARIANCE (DIFF)', lang), variance, fontBold, color: variance >= 0 ? PdfColors.green700 : PdfColors.red700),
                
                pw.SizedBox(height: 6),
                pw.Text('-' * 45, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                pw.SizedBox(height: 6),

                pw.Text(TranslationService.translateRaw('NON-CASH SALES SUMMARY', lang), style: pw.TextStyle(font: fontBold, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                _buildPdfMiniRow(TranslationService.translateRaw('Card Sales', lang), cardSales, font),
                _buildPdfMiniRow(TranslationService.translateRaw('LankaQR Sales', lang), qrSales, font),
                _buildPdfMiniRow(TranslationService.translateRaw('Credit Outstanding Added', lang), creditSales, font),
                
                pw.SizedBox(height: 6),
                pw.Text('-' * 45, style: pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                pw.SizedBox(height: 6),

                _buildPdfMiniRow(TranslationService.translateRaw('TOTAL SHIFT SALES', lang), totalSales, fontBold),
                _buildPdfMiniRow(TranslationService.translateRaw('TOTAL ORDERS COUNT', lang), _totalOrdersCount.toDouble(), font, isDecimal: false),
                
                pw.SizedBox(height: 12),
                pw.Center(
                  child: pw.Text(TranslationService.translateRaw('End of Shift Report', lang), style: pw.TextStyle(font: font, fontSize: 8)),
                ),
                pw.Center(
                  child: pw.Text(TranslationService.translateRaw('Software by Perpova. 0713555566', lang), style: pw.TextStyle(font: font, fontSize: 7, color: PdfColors.grey700)),
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Shift_ZReport_Shift$shiftIdStr',
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to print Z-Report: $e');
      }
    }
  }

  pw.Widget _buildPdfMiniRow(String label, double val, pw.Font font, {PdfColor? color, bool isDecimal = true}) {
    final valStr = isDecimal ? 'LKR ${val.toStringAsFixed(2)}' : val.toStringAsFixed(0);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.0),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 8)),
          pw.Text(valStr, style: pw.TextStyle(font: font, fontSize: 8, color: color ?? PdfColors.black, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCashDetailRow(String title, double amount, IconData icon, Color iconBg, Color iconColor, {bool isTotal = false}) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.isDarkMode ? iconColor.withOpacity(0.12) : iconBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? AppTheme.textLightPrimary : AppTheme.textLightSecondary,
            ),
          ),
        ),
        Text(
          'LKR ${amount.toStringAsFixed(2)}',
          style: GoogleFonts.inter(
            fontSize: isTotal ? 16 : 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
            color: isTotal ? AppTheme.primary : AppTheme.textLightPrimary,
          ),
        ),
      ],
    );
  }

  void _handleDrawerAdjustment(POSController controller, String type) async {
    final amt = double.tryParse(_cashInOutAmountController.text) ?? 0.00;
    final reason = _cashInOutReasonController.text.trim();
    if (amt <= 0 || reason.isEmpty) {
      _showSnackBar('Please enter valid amount and reason');
      return;
    }

    if (_selectedSupplier != null && type == 'cash_in') {
      _showSnackBar('Supplier payments must be recorded as Cash Out.');
      return;
    }

    try {
      if (controller.isOnline) {
        if (_selectedSupplier != null && type == 'cash_out') {
          await APIService.instance.paySupplier(_selectedSupplier!.id, amt, 'drawer', reason);
        } else {
          await APIService.instance.logDrawerCash(controller.activeShift!.id, type, amt, reason);
        }
        controller.fetchDrawerLogs();
        _fetchSuppliers();
      } else {
        print('Offline Log Drawer Cash: Shift ID ${controller.activeShift!.id}, Type $type, Amount $amt');
      }
      
      _cashInOutAmountController.clear();
      _cashInOutReasonController.clear();
      setState(() {
        _selectedSupplier = null;
      });
      _loadShiftData(controller);
      _showSnackBar('Cash Drawer Log recorded successfully.');
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  Future<void> _printDrawerLogs(POSController controller) async {
    try {
      final doc = pw.Document();
      
      final headers = ['Type', 'Amount', 'Reason / Remarks', 'Time'];
      
      final data = controller.drawerLogs.map((log) {
        final isCashIn = log['type'] == 'cash_in';
        final timeFormatted = DateFormat('hh:mm a').format((DateTime.tryParse(log['timestamp']) ?? DateTime.now()).toLocal());
        return [
          isCashIn ? 'IN' : 'OUT',
          'LKR ${double.parse(log['amount'].toString()).toStringAsFixed(2)}',
          (log['reason'] ?? '').toString(),
          timeFormatted
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
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Cash Drawer Transaction Logs',
                          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Active Shift ID: ${controller.activeShift?.id ?? "N/A"}'),
                        pw.Text('Opened At: ${controller.activeShift?.startTime ?? "N/A"}'),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Expected Balance',
                          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'LKR ${_expectedDrawerBalance.toStringAsFixed(2)}',
                          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 20),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Text('Logs Generated on: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
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
                    0: pw.Alignment.center,
                    1: pw.Alignment.centerRight,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.center,
                  },
                ),
              ],
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: 'Drawer_Logs_Shift_${controller.activeShift?.id ?? "N/A"}',
      );
    } catch (e) {
      _showSnackBar('Failed to generate PDF: $e');
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
