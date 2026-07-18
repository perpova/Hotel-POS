import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../services/translation_service.dart';
import '../../theme.dart';
import 'custom_date_range_picker.dart';

class OrderStatistics extends StatelessWidget {
  final List<dynamic>? statuses;
  final int totalOrders;
  final DateTimeRange dateRange;
  final Function(DateTimeRange) onDateRangeChanged;

  const OrderStatistics({
    Key? key,
    this.statuses,
    required this.totalOrders,
    required this.dateRange,
    required this.onDateRangeChanged,
  }) : super(key: key);

  int _getStatusCount(String status) {
    if (statuses == null) return 0;
    final match = statuses!.firstWhere(
      (element) => element['status'] == status,
      orElse: () => {'count': 0},
    );
    return match['count'] ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 950;

    // Prepare status cards data
    final items = [
      _StatusData('Total Orders', totalOrders, const Color(0xFFE91E63), Icons.shopping_bag_outlined),
      _StatusData('Pending', _getStatusCount('pending'), const Color(0xFFFFB300), Icons.hourglass_empty_outlined),
      _StatusData('Accept', _getStatusCount('accept'), const Color(0xFF4CAF50), Icons.check_circle_outline),
      _StatusData('Preparing', _getStatusCount('preparing'), const Color(0xFF2196F3), Icons.restaurant_outlined),
      _StatusData('Prepared', _getStatusCount('prepared'), const Color(0xFF9C27B0), Icons.thumb_up_alt_outlined),
      _StatusData('Out For Delivery', _getStatusCount('out_for_delivery'), const Color(0xFF00BCD4), Icons.local_shipping_outlined),
      _StatusData('Delivered', _getStatusCount('delivered'), const Color(0xFF009688), Icons.task_alt_outlined),
      _StatusData('Canceled', _getStatusCount('cancelled'), const Color(0xFFF44336), Icons.cancel_outlined),
      _StatusData('Returned', _getStatusCount('returned'), const Color(0xFF3F51B5), Icons.assignment_return_outlined),
      _StatusData('Rejected', _getStatusCount('rejected'), const Color(0xFFB71C1C), Icons.block_outlined),
    ];

    final dateStr = '${DateFormat('MM/dd/yyyy').format(dateRange.start)} - ${DateFormat('MM/dd/yyyy').format(dateRange.end)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Date Selector Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Order Statistics'.tr(context),
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textLightPrimary,
              ),
            ),
            // Date Picker Button
            InkWell(
              onTap: () async {
                final picked = await showDialog<DateTimeRange>(
                  context: context,
                  builder: (context) => CustomDateRangePickerDialog(
                    initialDateRange: dateRange,
                  ),
                );
                if (picked != null) {
                  onDateRangeChanged(picked);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cardLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Row(
                  children: [
                    Text(
                      dateStr,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.textLightSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: AppTheme.textLightSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Grid of status counts
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isDesktop ? 5 : (size.width > 600 ? 3 : 2),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.2,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.borderLight),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.01),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title.tr(context),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textLightSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.count.toString(),
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textLightPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class _StatusData {
  final String title;
  final int count;
  final Color color;
  final IconData icon;
  _StatusData(this.title, this.count, this.color, this.icon);
}
