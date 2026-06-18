import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../pos_controller.dart';
import '../theme.dart';
import '../models.dart';

class OrderQueueScreen extends StatelessWidget {
  const OrderQueueScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<POSController>(context);

    // Filter orders
    final preparingOrders = controller.activeOrders
        .where((o) => o.status == 'pending' || o.status == 'preparing')
        .toList();
        
    final readyOrders = controller.activeOrders
        .where((o) => o.status == 'prepared')
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark themed for wall displays
      body: Column(
        children: [
          // Screen Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
            color: const Color(0xFF1E293B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CUSTOMER ORDER STATUS',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Please collect when your number is Ready',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),

          // Main Column Split
          Expanded(
            child: Row(
              children: [
                // Preparing Column (Left)
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F172A),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.warning, width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'PREPARING / සකසමින් පවතී',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.warning,
                                ),
                              ),
                              Text(
                                '${preparingOrders.length}',
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.warning),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: preparingOrders.isEmpty
                              ? Center(
                                  child: Text(
                                    'No orders preparing.',
                                    style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.8,
                                  ),
                                  itemCount: preparingOrders.length,
                                  itemBuilder: (context, index) {
                                    final o = preparingOrders[index];
                                    final shortNum = o.orderNumber.substring(o.orderNumber.length - 4);
                                    return _buildQueueToken(shortNum, false);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const VerticalDivider(width: 1, color: Color(0xFF334155)),
                
                // Ready Column (Right)
                Expanded(
                  child: Container(
                    color: const Color(0xFF0F172A),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.accent, width: 1),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'READY / සූදානම්',
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent,
                                ),
                              ),
                              Text(
                                '${readyOrders.length}',
                                style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Expanded(
                          child: readyOrders.isEmpty
                              ? Center(
                                  child: Text(
                                    'No orders ready for collection.',
                                    style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 14),
                                  ),
                                )
                              : GridView.builder(
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.8,
                                  ),
                                  itemCount: readyOrders.length,
                                  itemBuilder: (context, index) {
                                    final o = readyOrders[index];
                                    final shortNum = o.orderNumber.substring(o.orderNumber.length - 4);
                                    return _buildQueueToken(shortNum, true);
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueToken(String token, bool isReady) {
    return Container(
      decoration: BoxDecoration(
        color: isReady ? AppTheme.accent.withOpacity(0.1) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isReady ? AppTheme.accent : const Color(0xFF334155),
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          token,
          style: GoogleFonts.outfit(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isReady ? AppTheme.accent : Colors.white,
          ),
        ),
      ),
    );
  }
}
