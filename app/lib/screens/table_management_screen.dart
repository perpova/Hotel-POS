import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../models.dart';
import '../api_service.dart';

class TableManagementScreen extends StatelessWidget {
  const TableManagementScreen({Key? key}) : super(key: key);

  Color _getTableColor(String status) {
    switch (status) {
      case 'empty':
        return AppTheme.accent; // Green
      case 'seated':
        return AppTheme.danger; // Red
      case 'billing':
        return AppTheme.warning; // Yellow
      default:
        return AppTheme.accent;
    }
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Legend Row
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildLegendItem('Empty Table', AppTheme.accent),
                    _buildLegendItem('Customers Seated', AppTheme.danger),
                    _buildLegendItem('Processing Bill (ACK Printed)', AppTheme.warning),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Grid of Tables
            Expanded(
              child: GridView.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  childAspectRatio: isDesktop ? 1.2 : 1.1,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: controller.diningTables.length,
                itemBuilder: (context, index) {
                  final table = controller.diningTables[index];
                  final tableColor = _getTableColor(table.status);
                  
                  return InkWell(
                    onTap: () => _showTableActionBottomSheet(context, table, controller),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tableColor, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: tableColor.withOpacity(0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                table.tableNumber,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textLightPrimary,
                                ),
                              ),
                              Icon(
                                Icons.chair_alt,
                                color: tableColor,
                                size: 24,
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (table.status != 'empty') ...[
                                Text(
                                  'Steward: ${table.stewardName ?? "N/A"}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textLightPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                table.status.toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: tableColor,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Capacity: ${table.capacity}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: AppTheme.textLightSecondary,
                                ),
                              ),
                              if (table.currentOrderId != null)
                                const Icon(
                                  Icons.receipt_long,
                                  size: 16,
                                  color: AppTheme.textLightSecondary,
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
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  void _showTableActionBottomSheet(BuildContext context, DiningTableModel table, POSController controller) {
    final stewardController = TextEditingController();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actions for ${table.tableNumber}',
              style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Status: ${table.status.toUpperCase()}',
              style: TextStyle(fontWeight: FontWeight.bold, color: _getTableColor(table.status)),
            ),
            const Divider(height: 24),
            
            if (table.status == 'empty') ...[
              Text(
                'Assign Steward to Table',
                style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: stewardController,
                decoration: const InputDecoration(
                  labelText: 'Steward Name',
                  hintText: 'Enter steward name...',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  if (stewardController.text.trim().isEmpty) return;
                  Navigator.pop(context);
                  try {
                    await APIService.instance.updateTableStatus(
                      table.id,
                      'seated',
                      stewardName: stewardController.text.trim(),
                    );
                    await controller.reloadEnvironment();
                  } catch (e) {
                    _showSnackBar(context, e.toString());
                  }
                },
                child: const Text('Seat Customers / Seated'),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  controller.setOrderType('dine_in');
                  controller.selectTable(table);
                  controller.setStewardName(table.stewardName);
                  // Load POS View
                  // Note: The UI switching is managed by selectedIndex inside MainLayout
                  // But setting the selected table in controller triggers a smooth experience.
                  _showSnackBar(context, 'Table ${table.tableNumber} selected. Open POS System to add items.');
                },
                icon: const Icon(Icons.shopping_cart),
                label: const Text('Add Items (Go to POS)'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  try {
                    await APIService.instance.updateTableStatus(table.id, 'empty');
                    await controller.reloadEnvironment();
                  } catch (e) {
                    _showSnackBar(context, e.toString());
                  }
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear Table (Release Seated)'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showSnackBar(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
}
