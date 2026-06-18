import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;

class OrdersSummaryRadial extends StatelessWidget {
  final List<dynamic>? statuses;
  final DateTimeRange dateRange;
  final Function(DateTimeRange) onDateRangeChanged;

  const OrdersSummaryRadial({
    Key? key,
    this.statuses,
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
    final dateStr = '${DateFormat('MM/dd/yyyy').format(dateRange.start)} - ${DateFormat('MM/dd/yyyy').format(dateRange.end)}';

    // Extract counts
    final delivered = _getStatusCount('delivered');
    final returned = _getStatusCount('returned');
    final canceled = _getStatusCount('cancelled');
    final rejected = _getStatusCount('rejected');
    final total = delivered + returned + canceled + rejected;

    // Calculate percentages
    final double deliveredPct = total > 0 ? delivered / total : 0.0;
    final double returnedPct = total > 0 ? returned / total : 0.0;
    final double canceledPct = total > 0 ? canceled / total : 0.0;
    final double rejectedPct = total > 0 ? rejected / total : 0.0;

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
                  'Orders Summary',
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

            // Content: Rings on left, Legend on right
            Row(
              children: [
                // Concentric progress rings
                SizedBox(
                  width: 140,
                  height: 140,
                  child: CustomPaint(
                    painter: ConcentricRadialPainter(
                      deliveredPct: deliveredPct,
                      returnedPct: returnedPct,
                      canceledPct: canceledPct,
                      rejectedPct: rejectedPct,
                      totalCount: total,
                    ),
                  ),
                ),
                const SizedBox(width: 24),
                // Legend
                Expanded(
                  child: Column(
                    children: [
                      _buildLegendItem('Delivered', deliveredPct, const Color(0xFFE91E63)),
                      const SizedBox(height: 12),
                      _buildLegendItem('Returned', returnedPct, const Color(0xFF2196F3)),
                      const SizedBox(height: 12),
                      _buildLegendItem('Canceled', canceledPct, const Color(0xFF9C27B0)),
                      const SizedBox(height: 12),
                      _buildLegendItem('Rejected', rejectedPct, const Color(0xFFF44336)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, double pct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct > 0 ? pct : 0.05, // minor fill if 0% for aesthetics
            color: color,
            backgroundColor: const Color(0xFFF1F5F9),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class ConcentricRadialPainter extends CustomPainter {
  final double deliveredPct;
  final double returnedPct;
  final double canceledPct;
  final double rejectedPct;
  final int totalCount;

  ConcentricRadialPainter({
    required this.deliveredPct,
    required this.returnedPct,
    required this.canceledPct,
    required this.rejectedPct,
    required this.totalCount,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = min(size.width, size.height) / 2;

    final ringWidth = 8.0;
    final ringSpace = 6.0;

    final ringsData = [
      _Ring(deliveredPct, const Color(0xFFE91E63)),
      _Ring(returnedPct, const Color(0xFF2196F3)),
      _Ring(canceledPct, const Color(0xFF9C27B0)),
      _Ring(rejectedPct, const Color(0xFFF44336)),
    ];

    for (int i = 0; i < ringsData.length; i++) {
      final ring = ringsData[i];
      final radius = baseRadius - (i * (ringWidth + ringSpace)) - ringWidth / 2;

      // Draw background track
      final trackPaint = Paint()
        ..color = const Color(0xFFF1F5F9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = ringWidth;

      canvas.drawCircle(center, radius, trackPaint);

      // Draw progress arc
      if (ring.percentage > 0.0) {
        final progressPaint = Paint()
          ..color = ring.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ringWidth
          ..strokeCap = StrokeCap.round;

        // Draw arc starting from the top (-pi / 2)
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -pi / 2,
          2 * pi * ring.percentage,
          false,
          progressPaint,
        );
      }
    }

    // Draw inner label "Total" and count in the center
    final labelSpan = TextSpan(
      text: 'Total\n',
      style: GoogleFonts.inter(
        color: const Color(0xFF64748B),
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 1.2,
      ),
      children: [
        TextSpan(
          text: totalCount.toString(),
          style: GoogleFonts.outfit(
            color: const Color(0xFF1E293B),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );

    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    labelPainter.layout();
    labelPainter.paint(
      canvas,
      Offset(center.dx - labelPainter.width / 2, center.dy - labelPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _Ring {
  final double percentage;
  final Color color;
  _Ring(this.percentage, this.color);
}
