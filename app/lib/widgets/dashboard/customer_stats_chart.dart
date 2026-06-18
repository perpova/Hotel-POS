import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

class CustomerStatsChart extends StatelessWidget {
  final DateTimeRange dateRange;
  final Function(DateTimeRange) onDateRangeChanged;

  const CustomerStatsChart({
    Key? key,
    required this.dateRange,
    required this.onDateRangeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateStr = '${DateFormat('MM/dd/yyyy').format(dateRange.start)} - ${DateFormat('MM/dd/yyyy').format(dateRange.end)}';

    // Mock hourly customer checkins for display
    final data = [
      {'hour': '06:00', 'count': 2},
      {'hour': '07:00', 'count': 4},
      {'hour': '08:00', 'count': 12},
      {'hour': '09:00', 'count': 8},
      {'hour': '10:00', 'count': 5},
      {'hour': '11:00', 'count': 9},
      {'hour': '12:00', 'count': 22},
      {'hour': '13:00', 'count': 18},
      {'hour': '14:00', 'count': 10},
      {'hour': '15:00', 'count': 6},
      {'hour': '16:00', 'count': 8},
      {'hour': '17:00', 'count': 14},
      {'hour': '18:00', 'count': 25},
      {'hour': '19:00', 'count': 30},
      {'hour': '20:00', 'count': 20},
      {'hour': '21:00', 'count': 12},
      {'hour': '22:00', 'count': 5},
      {'hour': '23:00', 'count': 2},
    ];

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFF1F5F9)),
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
                    color: const Color(0xFF1E293B),
                  ),
                ),
                InkWell(
                  onTap: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2025),
                      lastDate: DateTime(2030),
                      initialDateRange: dateRange,
                    );
                    if (picked != null) {
                      onDateRangeChanged(picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          dateStr,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: const Color(0xFF64748B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Color(0xFF64748B),
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
                painter: CustomerBarChartPainter(data),
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
      ..color = const Color(0xFFF1F5F9)
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
            color: const Color(0xFF94A3B8),
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
