import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme.dart';

class CustomDateRangePickerDialog extends StatefulWidget {
  final DateTimeRange initialDateRange;

  const CustomDateRangePickerDialog({
    Key? key,
    required this.initialDateRange,
  }) : super(key: key);

  @override
  State<CustomDateRangePickerDialog> createState() => _CustomDateRangePickerDialogState();
}

class _CustomDateRangePickerDialogState extends State<CustomDateRangePickerDialog> {
  late DateTime _selectedStart;
  late DateTime _selectedEnd;
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _selectedStart = widget.initialDateRange.start;
    _selectedEnd = widget.initialDateRange.end;
    _viewMonth = DateTime(_selectedStart.year, _selectedStart.month, 1);
  }

  void _selectToday() {
    final now = DateTime.now();
    setState(() {
      _selectedStart = DateTime(now.year, now.month, now.day);
      _selectedEnd = DateTime(now.year, now.month, now.day);
      _viewMonth = DateTime(now.year, now.month, 1);
    });
  }

  void _selectThisMonth() {
    final now = DateTime.now();
    setState(() {
      _selectedStart = DateTime(now.year, now.month, 1);
      _selectedEnd = DateTime(now.year, now.month + 1, 0); // Last day of month
      _viewMonth = DateTime(now.year, now.month, 1);
    });
  }

  void _selectLastMonth() {
    final now = DateTime.now();
    setState(() {
      _selectedStart = DateTime(now.year, now.month - 1, 1);
      _selectedEnd = DateTime(now.year, now.month, 0);
      _viewMonth = DateTime(now.year, now.month - 1, 1);
    });
  }

  void _previousMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1, 1);
    });
  }

  void _onDayClick(DateTime day) {
    setState(() {
      // If start and end are already selected, or if we need to set start
      if (_selectedStart == _selectedEnd) {
        if (day.isBefore(_selectedStart)) {
          _selectedStart = day;
          _selectedEnd = day;
        } else {
          _selectedEnd = day;
        }
      } else {
        _selectedStart = day;
        _selectedEnd = day;
      }
    });
  }

  bool _isDaySelected(DateTime day) {
    return day.isAtSameMomentAs(_selectedStart) || day.isAtSameMomentAs(_selectedEnd);
  }

  bool _isDayInRange(DateTime day) {
    return day.isAfter(_selectedStart) && day.isBefore(_selectedEnd);
  }

  List<DateTime> _generateCalendarDays() {
    final firstDayOfMonth = DateTime(_viewMonth.year, _viewMonth.month, 1);
    // Find the weekday of the first day (Monday = 1, Sunday = 7)
    int weekday = firstDayOfMonth.weekday;
    
    // How many days to backtrack to reach Monday
    int daysBefore = weekday - 1;
    final startDate = firstDayOfMonth.subtract(Duration(days: daysBefore));

    List<DateTime> days = [];
    // Generate exactly 42 days (6 weeks) for grid completeness
    for (int i = 0; i < 42; i++) {
      days.add(startDate.add(Duration(days: i)));
    }
    return days;
  }

  @override
  Widget build(BuildContext context) {
    final days = _generateCalendarDays();
    final monthStr = DateFormat('MMMM yyyy').format(_viewMonth);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: Colors.white,
        width: 480,
        height: 380,
        child: Row(
          children: [
            // Left sidebar: Quick Select Options
            Container(
              width: 130,
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK SELECT',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF94A3B8),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildQuickButton('Today', _selectToday),
                  const SizedBox(height: 12),
                  _buildQuickButton('This month', _selectThisMonth),
                  const SizedBox(height: 12),
                  _buildQuickButton('Last month', _selectLastMonth),
                ],
              ),
            ),

            // Right area: Custom Calendar month picker
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Header with Month Name and arrows
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left, size: 20, color: Color(0xFF64748B)),
                          onPressed: _previousMonth,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Text(
                          monthStr,
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF1E293B),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF64748B)),
                          onPressed: _nextMonth,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Weekdays header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((w) {
                        return SizedBox(
                          width: 32,
                          child: Text(
                            w,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF94A3B8),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),

                    // Calendar Grid (6 rows of 7 days)
                    Expanded(
                      child: GridView.builder(
                        itemCount: 42,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: 1.0,
                        ),
                        itemBuilder: (context, index) {
                          final day = days[index];
                          final isCurrentMonth = day.month == _viewMonth.month;
                          final isSelected = _isDaySelected(day);
                          final isInRange = _isDayInRange(day);

                          final isStart = day.isAtSameMomentAs(_selectedStart);
                          final isEnd = day.isAtSameMomentAs(_selectedEnd);

                          BoxDecoration? decoration;
                          TextStyle textStyle = GoogleFonts.inter(
                            fontSize: 11,
                            color: isCurrentMonth ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          );

                          if (isSelected) {
                            decoration = BoxDecoration(
                              color: AppTheme.primary,
                              borderRadius: BorderRadius.only(
                                topLeft: isStart ? const Radius.circular(6) : Radius.zero,
                                bottomLeft: isStart ? const Radius.circular(6) : Radius.zero,
                                topRight: isEnd ? const Radius.circular(6) : Radius.zero,
                                bottomRight: isEnd ? const Radius.circular(6) : Radius.zero,
                              ),
                            );
                            textStyle = GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            );
                          } else if (isInRange) {
                            decoration = BoxDecoration(
                              color: AppTheme.primary.withOpacity(0.12),
                            );
                            textStyle = GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            );
                          }

                          return InkWell(
                            onTap: () => _onDayClick(day),
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: decoration,
                              child: Text(
                                day.day.toString(),
                                style: textStyle,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Actions: Cancel / Apply
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(
                            'Cancel',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(
                              context,
                              DateTimeRange(start: _selectedStart, end: _selectedEnd),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            elevation: 0,
                          ),
                          child: Text(
                            'Apply',
                            style: GoogleFonts.inter(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, VoidCallback onClick) {
    return InkWell(
      onTap: onClick,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF475569),
          ),
        ),
      ),
    );
  }
}
