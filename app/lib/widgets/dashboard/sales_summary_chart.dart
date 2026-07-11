import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../models.dart';
import 'custom_date_range_picker.dart';

class SalesSummaryChart extends StatelessWidget {
  final List<dynamic>? hourlySales;
  final double totalSales;
  final DateTimeRange dateRange;
  final Function(DateTimeRange) onDateRangeChanged;

  const SalesSummaryChart({
    Key? key,
    this.hourlySales,
    required this.totalSales,
    required this.dateRange,
    required this.onDateRangeChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final dateStr = '${DateFormat('MM/dd/yyyy').format(dateRange.start)} - ${DateFormat('MM/dd/yyyy').format(dateRange.end)}';

    // Calculate metrics
    final days = dateRange.end.difference(dateRange.start).inDays + 1;
    final double avgSales = days > 0 ? totalSales / days : totalSales;

    // Use mock or real hourly sales
    final salesList = hourlySales ?? [
      {'hour': 9, 'sales': 0.0},
      {'hour': 12, 'sales': 0.0},
      {'hour': 15, 'sales': 0.0},
      {'hour': 18, 'sales': 0.0},
      {'hour': 21, 'sales': 0.0},
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
            // Title and Date picker
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sales Summary',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
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
            const SizedBox(height: 20),

            // Sales metrics
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bar_chart, color: Color(0xFF64748B), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'LKR ${totalSales.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total Sales',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 40),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.show_chart, color: Color(0xFF64748B), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'LKR ${avgSales.toStringAsFixed(2)}',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Avg. Sales Per Day',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Custom Chart
            SizedBox(
              height: 200,
              child: CustomPaint(
                size: Size.infinite,
                painter: SalesLineChartPainter(salesList),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SalesLineChartPainter extends CustomPainter {
  final List<dynamic> hourlySales;

  SalesLineChartPainter(this.hourlySales);

  @override
  void paint(Canvas canvas, Size size) {
    if (hourlySales.isEmpty) return;

    final paintLine = Paint()
      ..color = const Color(0xFFE91E63) // Pink FoodKing color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final paintFill = Paint()..style = PaintingStyle.fill;

    final paintGrid = Paint()
      ..color = const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final paintPoint = Paint()
      ..color = const Color(0xFFE91E63)
      ..style = PaintingStyle.fill;

    final paintPointBorder = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Find max value
    double maxSales = 100.0;
    for (var sale in hourlySales) {
      final salesVal = toDouble(sale['sales']);
      if (salesVal > maxSales) {
        maxSales = salesVal;
      }
    }
    maxSales = maxSales * 1.2; // Padding

    // Draw horizontal grid lines
    int gridLinesCount = 4;
    for (int i = 0; i <= gridLinesCount; i++) {
      double y = size.height - (i * (size.height / gridLinesCount));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paintGrid);
    }

    double stepX = size.width / (hourlySales.length > 1 ? (hourlySales.length - 1) : 1);
    Path linePath = Path();
    Path fillPath = Path();

    List<Offset> points = [];

    for (int i = 0; i < hourlySales.length; i++) {
      double salesVal = toDouble(hourlySales[i]['sales']);
      double x = i * stepX;
      double y = size.height - ((salesVal / maxSales) * size.height);

      Offset pt = Offset(x, y);
      points.add(pt);

      if (i == 0) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (i == hourlySales.length - 1) {
        fillPath.lineTo(x, size.height);
        fillPath.close();
      }
    }

    // Draw filling gradient
    paintFill.shader = LinearGradient(
      colors: [const Color(0xFFE91E63).withOpacity(0.2), const Color(0xFFE91E63).withOpacity(0.0)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ).createShader(Rect.fromLTRB(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, paintFill);

    // Draw line
    canvas.drawPath(linePath, paintLine);

    // Draw points & labels
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      canvas.drawCircle(pt, 5, paintPoint);
      canvas.drawCircle(pt, 5, paintPointBorder);

      // Draw Hour/X label under the chart
      final hour = hourlySales[i]['hour'];
      final textSpan = TextSpan(
        text: '${hour}:00',
        style: GoogleFonts.inter(
          color: const Color(0xFF94A3B8),
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(pt.dx - textPainter.width / 2, size.height - 15));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
