import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../models.dart';
import '../api_service.dart';

class KDSScreen extends StatefulWidget {
  const KDSScreen({Key? key}) : super(key: key);

  @override
  State<KDSScreen> createState() => _KDSScreenState();
}

class _KDSScreenState extends State<KDSScreen> {
  // Map containing orders and their items list
  final Map<int, List<OrderItemModel>> _orderItemsMap = {};
  bool _loadingItems = false;

  @override
  void initState() {
    super.initState();
    _loadItemsForOrders();
  }

  Future<void> _loadItemsForOrders() async {
    if (!mounted) return;
    setState(() => _loadingItems = true);
    final controller = Provider.of<POSController>(context, listen: false);
    
    try {
      for (var order in controller.activeOrders) {
        if (order.id != null) {
          final items = await APIService.instance.getOrderByBarcode(order.barcode);
          if (!mounted) return;
          _orderItemsMap[order.id!] = items.items;
        }
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('Error loading KDS items: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingItems = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);
    
    // Filter orders relevant for kitchen (pending or preparing status)
    final kdsOrders = controller.activeOrders
        .where((o) => o.status == 'pending' || o.status == 'preparing')
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark mode background for high readability in hot kitchens
      body: _loadingItems
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : kdsOrders.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_outline, size: 64, color: AppTheme.accent),
                      const SizedBox(height: 12),
                      Text(
                        'All Orders Prepared! No active queue.',
                        style: GoogleFonts.outfit(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 320,
                      childAspectRatio: 0.8,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: kdsOrders.length,
                    itemBuilder: (context, index) {
                      final order = kdsOrders[index];
                      final items = _orderItemsMap[order.id!] ?? [];
                      
                      return _buildKdsOrderCard(order, items, controller);
                    },
                  ),
                ),
    );
  }

  Widget _buildKdsOrderCard(OrderModel order, List<OrderItemModel> items, POSController controller) {
    final isPreparing = order.status == 'preparing';
    
    // Calculate elapsed time (simulated ticker)
    final createdTime = DateTime.parse(order.createdAt);
    final elapsedMinutes = DateTime.now().difference(createdTime).inMinutes;

    return Card(
      color: const Color(0xFF1E293B), // Slate 800
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPreparing ? AppTheme.warning : const Color(0xFF334155),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Order Number & Elapsed Timer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    order.orderNumber.substring(order.orderNumber.length - 8), // short form
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: elapsedMinutes > 15 ? AppTheme.danger : (isPreparing ? AppTheme.warning.withOpacity(0.2) : Colors.green.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$elapsedMinutes Min ago',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: elapsedMinutes > 15 ? Colors.white : (isPreparing ? AppTheme.warning : AppTheme.accent),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              order.orderType == 'dine_in' ? 'TABLE: ${order.stewardName ?? "Steward"}' : order.orderType.toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(color: Color(0xFF334155), height: 16),

            // Items List
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, idx) {
                  final item = items[idx];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${item.quantity}x ',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary,
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  if (item.productSinhalaName != null)
                                    Text(
                                      item.productSinhalaName!,
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: const Color(0xFF94A3B8),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (item.notes != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 20, top: 2),
                            child: Text(
                              'Note: ${item.notes}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: AppTheme.warning,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            const Divider(color: Color(0xFF334155), height: 16),

            // Bottom Actions (KDS mark processing flow)
            ElevatedButton(
              onPressed: () async {
                try {
                  if (!isPreparing) {
                    // Mark as Preparing
                    await APIService.instance.updateOrderOnline(order.id!, {'status': 'preparing'});
                  } else {
                    // Mark as Prepared / Ready
                    await APIService.instance.updateOrderOnline(order.id!, {'status': 'prepared'});
                  }
                  await controller.reloadEnvironment();
                  if (mounted) {
                    _loadItemsForOrders();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.danger),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isPreparing ? AppTheme.accent : AppTheme.warning,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                isPreparing ? 'Mark Completed (Ready)' : 'Start Cooking (Prepare)',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
