import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/translation_service.dart';

class OverviewCards extends StatelessWidget {
  final Map<String, dynamic>? summary;

  const OverviewCards({Key? key, this.summary}) : super(key: key);

  @override
  Widget build(BuildContext context) {
      final double sales = summary?['total_sales']?.toDouble() ?? 0.00;
    final int orders = summary?['total_orders']?.toInt() ?? 0;
    final int customers = summary?['total_customers']?.toInt() ?? 0;
    final int menuItems = summary?['total_menu_items']?.toInt() ?? 0;

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;

    return GridView.count(
      crossAxisCount: isDesktop ? 4 : (size.width > 600 ? 2 : 1),
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: isDesktop ? 1.7 : 1.5,
      children: [
        _buildGradientCard(
          context: context,
          label: 'Total Sales',
          value: 'LKR ${sales.toStringAsFixed(2)}',
          icon: Icons.payments,
          colors: [const Color(0xFFE91E63), const Color(0xFFFF6090)], // Pink/Red
        ),
        _buildGradientCard(
          context: context,
          label: 'Total Orders',
          value: orders.toString(),
          icon: Icons.inventory_2_outlined,
          colors: [const Color(0xFF7E57C2), const Color(0xFFB39DDB)], // Purple
        ),
        _buildGradientCard(
          context: context,
          label: 'Total Customers',
          value: customers.toString(),
          icon: Icons.people_outline,
          colors: [const Color(0xFF42A5F5), const Color(0xFF90CAF9)], // Blue
        ),
        _buildGradientCard(
          context: context,
          label: 'Total Menu Items',
          value: menuItems.toString(),
          icon: Icons.menu_book_outlined,
          colors: [const Color(0xFFAB47BC), const Color(0xFFE1BEE7)], // Violet
        ),
      ],
    );
  }

  Widget _buildGradientCard({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required List<Color> colors,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colors.first.withOpacity(0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          // Text Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.tr(context),
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // White Circular Icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: colors.first,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}
