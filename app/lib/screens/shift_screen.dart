import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../api_service.dart';

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

    return Scaffold(
      body: Container(
        color: const Color(0xFFF8FAFC),
        padding: const EdgeInsets.all(24),
        child: controller.activeShift == null
            ? _buildOpenShiftLayout(controller)
            : isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _buildShiftDetailsArea(controller),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: _buildShiftCloseArea(controller),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: _buildShiftDetailsArea(controller)),
                      const SizedBox(height: 16),
                      _buildShiftCloseArea(controller),
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
        width: 400,
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.lock_open, size: 48, color: AppTheme.primary),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Open Daily Shift',
                    style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                Center(
                  child: Text(
                    'Setup starting cash balance in drawer.',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _openingBalanceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Starting Cash Balance (LKR)',
                    hintText: '5000.00',
                  ),
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
                  child: const Text('Open Cash Drawer & Start Shift'),
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
    // Expected Cash Drawer Calculation (Simulated logic: starting + cash sales)
    final starting = controller.activeShift?.openingBalance ?? 0.00;
    
    // For demo/sim, add a fixed value represent today's cash sales
    final cashSalesVal = 12450.00; 
    final expectedTotal = starting + cashSalesVal;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shift Cash Status',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                _buildCashDetailRow('Opening Cash Balance:', starting),
                _buildCashDetailRow('Today\'s Cash Sales:', cashSalesVal),
                _buildCashDetailRow('Expected Cash in Drawer:', expectedTotal, isTotal: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Cash In/Out log trigger card
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cash Drawer Control (In / Out Log)',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cashInOutAmountController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Amount (LKR)'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _cashInOutReasonController,
                          decoration: const InputDecoration(labelText: 'Reason / Remarks'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleDrawerAdjustment(controller, 'cash_in'),
                          icon: const Icon(Icons.arrow_upward, size: 16, color: Colors.white),
                          label: const Text('Add Cash In'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _handleDrawerAdjustment(controller, 'cash_out'),
                          icon: const Icon(Icons.arrow_downward, size: 16, color: Colors.white),
                          label: const Text('Remove Cash Out'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'End Shift / Reconciliation',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text(
              'Count the total physical cash in your drawer at the end of the shift and enter below to close shift:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _actualCashController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Actual Cash Counted (LKR)',
              ),
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
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              child: const Text('Close Shift & Print Summary'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCashDetailRow(String title, double amount, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: isTotal ? 14 : 13,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.w500,
              color: isTotal ? AppTheme.textLightPrimary : AppTheme.textLightSecondary,
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
      ),
    );
  }

  void _handleDrawerAdjustment(POSController controller, String type) async {
    final amt = double.tryParse(_cashInOutAmountController.text) ?? 0.00;
    final reason = _cashInOutReasonController.text.trim();
    if (amt <= 0 || reason.isEmpty) return;

    try {
      if (controller.isOnline) {
        await APIService.instance.logDrawerCash(controller.activeShift!.id, type, amt, reason);
      } else {
        // Offline Mock
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
