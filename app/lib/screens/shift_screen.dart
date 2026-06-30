import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../services/api_service.dart';

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

  List<dynamic> _drawerLogs = [];
  bool _loadingLogs = false;
  int? _lastShiftId;

  @override
  void dispose() {
    _openingBalanceController.dispose();
    _actualCashController.dispose();
    _cashInOutAmountController.dispose();
    _cashInOutReasonController.dispose();
    super.dispose();
  }

  Future<void> _fetchDrawerLogs(int shiftId) async {
    setState(() => _loadingLogs = true);
    try {
      final logs = await APIService.instance.getDrawerLogs(shiftId);
      setState(() {
        _drawerLogs = logs;
        _loadingLogs = false;
      });
    } catch (e) {
      setState(() => _loadingLogs = false);
      print('Error fetching drawer logs: $e');
    }
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
        _fetchDrawerLogs(controller.activeShift!.id);
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
                      'Shifts & Cash Drawer',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        const Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Shifts & Cash', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
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
                                    _buildCashDrawerLogsCard(),
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
                              _buildCashDrawerLogsCard(),
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
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                    color: const Color(0xFFFFF0F5),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Icon(Icons.lock_open, size: 30, color: AppTheme.primary),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    'Open Daily Shift',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Setup starting cash balance in drawer.',
                    style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _openingBalanceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Starting Cash Balance (LKR) *',
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
                  child: Text('Open Cash Drawer & Start Shift', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
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
    final cashSalesVal = 12450.00; 
    final expectedTotal = starting + cashSalesVal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cash Status Row Cards
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shift Cash Status',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 20),
                _buildCashDetailRow('Opening Cash Balance', starting, Icons.vpn_key_outlined, const Color(0xFFE0F2FE), Colors.blue),
                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                _buildCashDetailRow('Today\'s Cash Sales', cashSalesVal, Icons.point_of_sale_outlined, const Color(0xFFE6F4EA), const Color(0xFF137333)),
                const Divider(height: 24, color: Color(0xFFF1F5F9)),
                _buildCashDetailRow('Expected Cash in Drawer', expectedTotal, Icons.wallet_outlined, Color(0xFFFFF0F5), AppTheme.primary, isTotal: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        
        // Cash Drawer Control card
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash Drawer Control (In / Out Adjustments)',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _cashInOutAmountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Amount (LKR) *'),
                        style: GoogleFonts.inter(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _cashInOutReasonController,
                        decoration: const InputDecoration(labelText: 'Reason / Remarks *'),
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
                        label: const Text('Add Cash In'),
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
                        label: const Text('Remove Cash Out'),
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
  Widget _buildCashDrawerLogsCard() {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Drawer Transaction Logs',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            const SizedBox(height: 16),

            if (_loadingLogs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
              )
            else if (_drawerLogs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Center(
                  child: Text(
                    'No transaction logs for this shift.',
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
                    color: const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: _buildTableHeaderText('TYPE')),
                        Expanded(flex: 3, child: _buildTableHeaderText('AMOUNT')),
                        Expanded(flex: 5, child: _buildTableHeaderText('REASON')),
                        Expanded(flex: 3, child: _buildTableHeaderText('TIME')),
                      ],
                    ),
                  ),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _drawerLogs.length,
                    separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    itemBuilder: (context, index) {
                      final log = _drawerLogs[index];
                      final isCashIn = log['type'] == 'cash_in';
                      final timeFormatted = DateFormat('hh:mm a').format(DateTime.tryParse(log['timestamp']) ?? DateTime.now());
                      
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
                                    isCashIn ? 'IN' : 'OUT',
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
                                style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // TIME
                            Expanded(
                              flex: 3,
                              child: Text(
                                timeFormatted,
                                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
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

  // ----------------------------------------------------
  // LAYOUT: SHIFT CLOSE & RECONCILIATION
  // ----------------------------------------------------
  Widget _buildShiftCloseArea(POSController controller) {
    final starting = controller.activeShift?.openingBalance ?? 0.00;
    final cashSalesVal = 12450.00;
    final expectedTotal = starting + cashSalesVal;

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
              'End Shift / Reconciliation',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              'Count the total physical cash in your drawer at the end of the shift and enter below to close shift:',
              style: GoogleFonts.inter(fontSize: 13, color: AppTheme.textLightSecondary),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _actualCashController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual Cash Counted (LKR) *',
              ),
              style: GoogleFonts.inter(fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final actual = double.tryParse(_actualCashController.text) ?? 0.00;
                try {
                  await controller.closeActiveShift(expectedTotal, actual);
                  await controller.reloadEnvironment();
                  _actualCashController.clear();
                  if (mounted) {
                    _showSnackBar('Shift Closed successfully. Reconciliation log written to Audit Trail.');
                  }
                } catch (e) {
                  _showSnackBar(e.toString());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.danger,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Close Shift & Print Summary', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashDetailRow(String title, double amount, IconData icon, Color iconBg, Color iconColor, {bool isTotal = false}) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
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

    try {
      if (controller.isOnline) {
        await APIService.instance.logDrawerCash(controller.activeShift!.id, type, amt, reason);
        _fetchDrawerLogs(controller.activeShift!.id);
      } else {
        print('Offline Log Drawer Cash: Shift ID ${controller.activeShift!.id}, Type $type, Amount $amt');
      }
      
      _cashInOutAmountController.clear();
      _cashInOutReasonController.clear();
      _showSnackBar('Cash Drawer Log recorded successfully.');
    } catch (e) {
      _showSnackBar(e.toString());
    }
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
