import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme.dart';

class TopCustomersList extends StatelessWidget {
  final List<dynamic>? customers;

  const TopCustomersList({Key? key, this.customers}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<_CustomerInfo> customerList = (customers ?? []).map<_CustomerInfo>((c) {
      return _CustomerInfo(
        c['name']?.toString() ?? 'Walking Customer',
        c['orders_count']?.toInt() ?? 0,
      );
    }).toList();

    // Fallback default list if no customers found
    final displayCustomers = customerList.isNotEmpty ? customerList : [
      _CustomerInfo('Walking Customer', 0),
    ];

    return Card(
      elevation: 0,
      color: AppTheme.cardLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top Customers',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.textLightPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: displayCustomers.map((c) {
                return Expanded(
                  child: Container(
                    margin: const EdgeInsets.only(right: 8, left: 8),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.borderLight),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Avatar
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.isDarkMode ? const Color(0xFF0369A1).withOpacity(0.2) : const Color(0xFFE0F2FE), // Light blue avatar bg
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Color(0xFF0284C7), // Blue icon
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Name
                        Text(
                          c.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textLightPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Badge
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7), // Blue badge bg
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${c.ordersCount} Orders',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerInfo {
  final String name;
  final int ordersCount;
  _CustomerInfo(this.name, this.ordersCount);
}
