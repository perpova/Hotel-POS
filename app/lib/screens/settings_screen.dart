import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../api_service.dart';
import '../models.dart';
import '../local_db.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _apiUrlController = TextEditingController();

  // Stock Adjustment Controllers
  ProductModel? _selectedStockProduct;
  final _stockChangeController = TextEditingController();
  final _stockReasonController = TextEditingController();
  String _stockType = 'purchase'; // 'purchase', 'adjustment', 'wastage'

  // Happy Hour Controllers
  ProductModel? _selectedPromoProduct;
  final _promoPriceController = TextEditingController();
  final _startTimeController = TextEditingController(text: '17:00:00');
  final _endTimeController = TextEditingController(text: '19:00:00');
  String _selectedDays = '1,2,3,4,5'; // Monday to Friday

  @override
  void initState() {
    super.initState();
    _apiUrlController.text = APIService.instance.baseUrl;
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _stockChangeController.dispose();
    _stockReasonController.dispose();
    _promoPriceController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;
    
    final userRole = APIService.instance.currentUser?.role ?? 'cashier';
    final hasSeniorAccess = userRole == 'admin' || userRole == 'owner';

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Base URL config
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('API / VPS Connection Settings', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    const Text('Change base URL to switch from localhost testing to remote database VPS hosting.', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _apiUrlController,
                            decoration: const InputDecoration(
                              labelText: 'Backend API Base URL',
                              hintText: 'http://localhost:3000',
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        ElevatedButton(
                          onPressed: () async {
                            final newUrl = _apiUrlController.text.trim();
                            if (newUrl.isEmpty) return;
                            await APIService.instance.setBaseUrl(newUrl);
                            await controller.reloadEnvironment();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('API Base URL updated to: $newUrl. Reconnected.')),
                              );
                            }
                          },
                          child: const Text('Save & Reconnect'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Senior Level Settings section
            if (!hasSeniorAccess) ...[
              Card(
                color: AppTheme.danger.withOpacity(0.08),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppTheme.danger)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, color: AppTheme.danger),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Stock Adjustments and Happy Hour configurations are locked. Please login as Admin or Owner to access.',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              isDesktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Stock Adjustments (60%)
                        Expanded(
                          flex: 3,
                          child: _buildStockAdjustmentCard(controller),
                        ),
                        const SizedBox(width: 24),
                        // Right: Happy Hour Configs (40%)
                        Expanded(
                          flex: 2,
                          child: _buildHappyHourCard(controller),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _buildStockAdjustmentCard(controller),
                        const SizedBox(height: 20),
                        _buildHappyHourCard(controller),
                      ],
                    ),
            ],
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // CARD 1: STOCK ENTERING / ADJUSTMENTS
  // ----------------------------------------------------
  Widget _buildStockAdjustmentCard(POSController controller) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Stock Entering & Corrections', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            
            // Product Selector
            DropdownButtonFormField<ProductModel>(
              value: _selectedStockProduct,
              decoration: const InputDecoration(labelText: 'Select Product for Stock adjustment'),
              items: [
                ...controller.products.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                        '${p.name} ${p.sinhalaName != null ? "(${p.sinhalaName})" : ""} | Current: ${p.stockQty}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )),
              ],
              onChanged: (p) => setState(() => _selectedStockProduct = p),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stockChangeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Stock Change Qty (negative for wastage)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _stockType,
                    decoration: const InputDecoration(labelText: 'Log Type'),
                    items: const [
                      DropdownMenuItem(value: 'purchase', child: Text('New Purchase / Input')),
                      DropdownMenuItem(value: 'adjustment', child: Text('Correction / Count')),
                      DropdownMenuItem(value: 'wastage', child: Text('Wastage / Spoiled')),
                    ],
                    onChanged: (val) => setState(() => _stockType = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _stockReasonController,
              decoration: const InputDecoration(labelText: 'Reason for Adjustment', hintText: 'e.g. weekly batch input, rotten vegetables'),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () => _handleAdjustStock(controller),
              child: const Text('Update Inventory Level'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleAdjustStock(POSController controller) async {
    if (_selectedStockProduct == null) return;
    final qty = int.tryParse(_stockChangeController.text) ?? 0;
    final reason = _stockReasonController.text.trim();
    if (qty == 0 || reason.isEmpty) return;

    try {
      if (controller.isOnline) {
        await APIService.instance.adjustStock(_selectedStockProduct!.id, qty, _stockType, reason);
      } else {
        // Offline Save Mock
        await LocalDB.instance.saveStockLogOffline(_selectedStockProduct!.id, qty, _stockType, reason, APIService.instance.currentUser?.id ?? 1);
      }
      
      _stockChangeController.clear();
      _stockReasonController.clear();
      _selectedStockProduct = null;
      await controller.reloadEnvironment();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stock level adjusted and activity logged.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
  }

  // ----------------------------------------------------
  // CARD 2: HAPPY HOUR CONFIG
  // ----------------------------------------------------
  Widget _buildHappyHourCard(POSController controller) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.celebration_outlined, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Happy Hour Configuration', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            
            // Product Selector
            DropdownButtonFormField<ProductModel>(
              value: _selectedPromoProduct,
              decoration: const InputDecoration(labelText: 'Select Promo Product'),
              items: [
                ...controller.products.map((p) => DropdownMenuItem(
                      value: p,
                      child: Text('${p.name} (LKR ${p.price.toStringAsFixed(0)})', style: const TextStyle(fontSize: 12)),
                    )),
              ],
              onChanged: (p) => setState(() => _selectedPromoProduct = p),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _promoPriceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Promo Price (LKR)'),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _startTimeController,
                    decoration: const InputDecoration(labelText: 'Start Time', hintText: '17:00:00'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _endTimeController,
                    decoration: const InputDecoration(labelText: 'End Time', hintText: '19:00:00'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _selectedDays,
              decoration: const InputDecoration(labelText: 'Promotion Days'),
              items: const [
                DropdownMenuItem(value: '1,2,3,4,5', child: Text('Weekdays (Mon-Fri)')),
                DropdownMenuItem(value: '6,7', child: Text('Weekends (Sat-Sun)')),
                DropdownMenuItem(value: '1,2,3,4,5,6,7', child: Text('Every Day')),
              ],
              onChanged: (val) => setState(() => _selectedDays = val!),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: () => _handleConfigureHappyHour(controller),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.secondary),
              child: const Text('Save Happy Hour Pricing'),
            ),
          ],
        ),
      ),
    );
  }

  void _handleConfigureHappyHour(POSController controller) async {
    if (_selectedPromoProduct == null) return;
    final price = double.tryParse(_promoPriceController.text) ?? 0.00;
    final start = _startTimeController.text.trim();
    final end = _endTimeController.text.trim();
    if (price <= 0 || start.isEmpty || end.isEmpty) return;

    try {
      await APIService.instance.configureHappyHour(_selectedPromoProduct!.id, price, start, end, _selectedDays);
      
      _promoPriceController.clear();
      _selectedPromoProduct = null;
      await controller.reloadEnvironment();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Happy hour pricing saved. Price updates broadcasted to all terminals.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
      );
    }
  }
}
