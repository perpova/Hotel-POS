import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../theme.dart';
import 'custom_date_range_picker.dart';

class CustomerStatsChart extends StatelessWidget {
  final List<dynamic>? stats;
  final DateTimeRange dateRange;
  final Function(DateTimeRange) onDateRangeChanged;

  const CustomerStatsChart({
    Key? key,
    this.stats,
    required this.dateRange,
    required this.onDateRangeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateStr = '${DateFormat('MM/dd/yyyy').format(dateRange.start)} - ${DateFormat('MM/dd/yyyy').format(dateRange.end)}';

    // Map database customer stats
    final List<Map<String, dynamic>> chartData = (stats ?? []).map<Map<String, dynamic>>((s) {
      return {
        'hour': s['hour']?.toString() ?? '',
        'count': s['count']?.toInt() ?? 0,
      };
    }).toList();

    // Fallback/Default placeholder map if database has no records for selected dates
    final displayData = chartData.isNotEmpty ? chartData : [
      {'hour': '06:00', 'count': 0},
      {'hour': '08:00', 'count': 0},
      {'hour': '10:00', 'count': 0},
      {'hour': '12:00', 'count': 0},
      {'hour': '14:00', 'count': 0},
      {'hour': '16:00', 'count': 0},
      {'hour': '18:00', 'count': 0},
      {'hour': '20:00', 'count': 0},
      {'hour': '22:00', 'count': 0},
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
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Customer Stats',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textLightPrimary,
                  ),
                ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                            fontSize: 11,
                            color: AppTheme.textLightSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: AppTheme.textLightSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Bar Chart
            SizedBox(
              height: 200,
              child: CustomPaint(
                size: Size.infinite,
                painter: CustomerBarChartPainter(displayData),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerBarChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  CustomerBarChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paintBar = Paint()
      ..color = const Color(0xFF42A5F5) // Soft Blue
      ..style = PaintingStyle.fill;

    final paintGrid = Paint()
      ..color = AppTheme.borderLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Find max value
    double maxCount = 10.0;
    for (var d in data) {
      final double c = (d['count'] as num).toDouble();
      if (c > maxCount) {
        maxCount = c;
      }
    }
    maxCount = maxCount * 1.15; // padding

    // Draw horizontal grids
    int gridCount = 4;
    for (int i = 0; i <= gridCount; i++) {
      double y = size.height - 20 - (i * ((size.height - 20) / gridCount));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    final chartHeight = size.height - 20; // reserve space for text labels
    final barSpacing = 4.0;
    final totalWidth = size.width;
    final barWidth = (totalWidth / data.length) - barSpacing;

    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      final countVal = (item['count'] as num).toDouble();
      final barHeight = (countVal / maxCount) * chartHeight;

      final x = i * (barWidth + barSpacing) + barSpacing / 2;
      final y = chartHeight - barHeight;

      // Draw rounded rect bar
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTWH(x, y, barWidth, barHeight),
        topLeft: const Radius.circular(4),
        topRight: const Radius.circular(4),
      );
      canvas.drawRRect(rect, paintBar);

      // Only draw select hour labels to avoid crowding
      if (i % 2 == 0) {
        final labelSpan = TextSpan(
          text: item['hour'],
          style: GoogleFonts.inter(
            color: AppTheme.textLightSecondary,
            fontSize: 8,
            fontWeight: FontWeight.w500,
          ),
        );
        final labelPainter = TextPainter(
          text: labelSpan,
          textDirection: TextDirection.ltr,
        );
        labelPainter.layout();
        labelPainter.paint(
          canvas,
          Offset(x + barWidth / 2 - labelPainter.width / 2, chartHeight + 4),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
