import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../theme.dart';
import '../services/api_service.dart';
import '../services/pdf_helper.dart';
import '../widgets/image_helper.dart';

class StaffAttendanceSalaryScreen extends StatefulWidget {
  const StaffAttendanceSalaryScreen({Key? key}) : super(key: key);

  @override
  State<StaffAttendanceSalaryScreen> createState() => _StaffAttendanceSalaryScreenState();
}

class _StaffAttendanceSalaryScreenState extends State<StaffAttendanceSalaryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  // Tab 1: Attendance
  List<Map<String, dynamic>> _attendanceSummary = [];
  DateTimeRange? _selectedDateRange;

  // Tab 2: Salary Calculation
  List<Map<String, dynamic>> _staffList = [];
  int? _selectedStaffId;
  DateTime _periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _periodEnd = DateTime.now();
  Map<String, dynamic>? _calculatedPayroll;
  bool _isCalculating = false;
  List<Map<String, dynamic>> _payrollHistory = [];

  // Tab 3: Advances
  List<Map<String, dynamic>> _advancesList = [];

  // Tab 4: Settings
  double _globalOtRate = 250.0;
  String _globalOtStartTime = '17:00';
  int _salaryNotificationDays = 2;
  List<Map<String, dynamic>> _staffSettings = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    _loadTabSpecificData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadAttendance(),
        _loadPayrollSettings(),
        _loadAdvances(),
        _loadPayrollHistory(),
      ]);
    } catch (e) {
      debugPrint('Error loading staff attendance/salary data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTabSpecificData() async {
    switch (_tabController.index) {
      case 0:
        await _loadAttendance();
        break;
      case 1:
        await _loadPayrollHistory();
        if (_selectedStaffId != null) {
          await _calculateSalary();
        }
        break;
      case 2:
        await _loadAdvances();
        break;
      case 3:
        await _loadPayrollSettings();
        break;
    }
  }

  Future<void> _loadAttendance() async {
    try {
      final fromStr = _selectedDateRange != null ? DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start) : null;
      final toStr = _selectedDateRange != null ? DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end) : null;
      final res = await APIService.instance.getStaffAttendanceSummary(from: fromStr, to: toStr);
      if (mounted) {
        setState(() {
          _attendanceSummary = res;
          final Map<int, Map<String, dynamic>> uniqueMap = {};
          for (final item in res) {
            final id = item['user_id'] as int;
            if (!uniqueMap.containsKey(id)) {
              uniqueMap[id] = {
                'id': id,
                'name': item['name'],
                'role': item['role'],
              };
            }
          }
          _staffList = uniqueMap.values.toList();
          if (_selectedStaffId == null && _staffList.isNotEmpty) {
            _selectedStaffId = _staffList.first['id'] as int?;
            _calculateSalary();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading attendance: $e');
    }
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  double? _parseNullableDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  Future<void> _loadPayrollSettings() async {
    try {
      final res = await APIService.instance.getPayrollSettings();
      if (mounted) {
        setState(() {
          _globalOtRate = _parseDouble(res['global_ot_rate']);
          _globalOtStartTime = (res['global_ot_start_time'] as String?) ?? '17:00';
          _salaryNotificationDays = _parseInt(res['salary_notification_days']);
          _staffSettings = List<Map<String, dynamic>>.from(res['staff_settings'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error loading payroll settings: $e');
    }
  }

  Future<void> _loadAdvances() async {
    try {
      final res = await APIService.instance.getStaffAdvances();
      if (mounted) {
        setState(() {
          _advancesList = res;
        });
      }
    } catch (e) {
      debugPrint('Error loading advances: $e');
    }
  }

  Future<void> _loadPayrollHistory() async {
    try {
      final res = await APIService.instance.getPayrollHistory();
      if (mounted) {
        setState(() {
          _payrollHistory = res;
        });
      }
    } catch (e) {
      debugPrint('Error loading payroll history: $e');
    }
  }

  Future<void> _calculateSalary() async {
    if (_selectedStaffId == null) return;
    setState(() => _isCalculating = true);
    try {
      final res = await APIService.instance.calculateStaffSalary(
        _selectedStaffId!,
        periodStart: DateFormat('yyyy-MM-dd').format(_periodStart),
        periodEnd: DateFormat('yyyy-MM-dd').format(_periodEnd),
      );
      if (mounted) {
        setState(() {
          _calculatedPayroll = res;
        });
      }
    } catch (e) {
      debugPrint('Error calculating salary: $e');
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Staff Attendance & Salary Management',
                      style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('Dashboard', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                        Icon(Icons.chevron_right, size: 14, color: AppTheme.textLightSecondary),
                        Text('Staff Attendance & Salary', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _loadAllData,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh Data'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cardLight,
                    foregroundColor: AppTheme.primary,
                    elevation: 0,
                    side: BorderSide(color: AppTheme.primary.withOpacity(0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tab Bar Navigation
            Container(
              decoration: BoxDecoration(
                color: AppTheme.cardLight,
                border: Border(bottom: BorderSide(color: AppTheme.dividerColor)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.textLightSecondary,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500),
                tabs: const [
                  Tab(text: 'Attendance & Work Sheet'),
                  Tab(text: 'Salary Calculation & Payslips'),
                  Tab(text: 'Staff Advances'),
                  Tab(text: 'Payroll Settings & OT Rates'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tab Bar View
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildAttendanceTab(),
                        _buildSalaryCalculationTab(),
                        _buildAdvancesTab(),
                        _buildSettingsTab(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------
  // TAB 1: ATTENDANCE & WORK SHEET REPORT
  // ----------------------------------------------------
  Widget _buildAttendanceTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Controls Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: context,
                      initialDateRange: _selectedDateRange ?? DateTimeRange(start: DateTime.now().subtract(const Duration(days: 30)), end: DateTime.now()),
                      firstDate: DateTime(2025),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _selectedDateRange = picked);
                      _loadAttendance();
                    }
                  },
                  icon: const Icon(Icons.date_range, size: 16),
                  label: Text(_selectedDateRange != null
                      ? '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}'
                      : 'All Time Range'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cardLight,
                    foregroundColor: AppTheme.textLightPrimary,
                    elevation: 0,
                    side: BorderSide(color: AppTheme.borderLight),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                if (_selectedDateRange != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.clear, color: AppTheme.danger),
                    onPressed: () {
                      setState(() => _selectedDateRange = null);
                      _loadAttendance();
                    },
                  ),
                ],
              ],
            ),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _showManualClockDialog,
                  icon: const Icon(Icons.add_alarm, size: 16),
                  label: const Text('Manual Clock Entry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cardLight,
                    foregroundColor: AppTheme.primary,
                    elevation: 0,
                    side: BorderSide(color: AppTheme.primary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _exportWorkSheetPDF,
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: const Text('Download / Print Worksheet PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Attendance Table / Cards
        Expanded(
          child: ListView.builder(
            itemCount: _attendanceSummary.length,
            itemBuilder: (context, index) {
              final staff = _attendanceSummary[index];
              final bool isClockedIn = staff['is_clocked_in'] == true;

              return Card(
                elevation: 0,
                margin: const EdgeInsets.only(bottom: 12),
                color: AppTheme.cardLight,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: isClockedIn ? const Color(0xFF10B981) : AppTheme.borderLight, width: isClockedIn ? 1.5 : 1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showStaffShiftDetailsDialog(staff),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                      // Avatar & Name
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.primary.withOpacity(0.1),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Base64ImageWidget(
                          base64Str: staff['image_base64'],
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  staff['name'] ?? '',
                                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isClockedIn ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isClockedIn ? 'CLOCKED IN' : 'OFFLINE',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: isClockedIn ? const Color(0xFF166534) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Role: ${staff['role']?.toString().toUpperCase() ?? ''} | @${staff['username'] ?? ''}',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                            ),
                          ],
                        ),
                      ),

                      // Worked Hours Breakdown Cards
                      _buildMetricBox('Daily', '${(staff['daily_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', AppTheme.primary),
                      const SizedBox(width: 8),
                      _buildMetricBox('Weekly', '${(staff['weekly_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFF3B82F6)),
                      const SizedBox(width: 8),
                      _buildMetricBox('Monthly', '${(staff['monthly_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFF8B5CF6)),
                      const SizedBox(width: 8),
                      _buildMetricBox('Yearly', '${(staff['yearly_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFF6366F1)),
                      const SizedBox(width: 8),
                      _buildMetricBox('Avg/Day', '${(staff['average_daily_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      _buildMetricBox('OT Hours', '${(staff['ot_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFFF59E0B)),
                    ],
                  ),
                ),
              ),
            );
          },
          ),
        ),
      ],
    );
  }

  Widget _buildMetricBox(String label, String value, Color color) {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  void _showStaffShiftDetailsDialog(Map<String, dynamic> staff) {
    final List<dynamic> shifts = staff['shifts'] ?? [];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: AppTheme.cardLight,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Attendance Shift Log Details',
                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.textLightPrimary),
                  ),
                  Text(
                    '${staff['name']} (${staff['role']?.toString().toUpperCase()})',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(ctx),
              ),
            ],
          ),
          content: SizedBox(
            width: 650,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bgLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildDetailHeaderMetric('Daily Worked', '${_parseDouble(staff['daily_hours']).toStringAsFixed(1)} hrs'),
                      _buildDetailHeaderMetric('Weekly Worked', '${_parseDouble(staff['weekly_hours']).toStringAsFixed(1)} hrs'),
                      _buildDetailHeaderMetric('Monthly Worked', '${_parseDouble(staff['monthly_hours']).toStringAsFixed(1)} hrs'),
                      _buildDetailHeaderMetric('OT Hours', '${_parseDouble(staff['ot_hours']).toStringAsFixed(1)} hrs'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text('Clock In / Out Shift Records', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textLightPrimary)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: shifts.isEmpty
                      ? Center(child: Text('No shift logs recorded for this period.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)))
                      : ListView.separated(
                          itemCount: shifts.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final sh = shifts[index];
                            final DateTime? cin = DateTime.tryParse(sh['clock_in'] ?? '');
                            final DateTime? cout = sh['clock_out'] != null ? DateTime.tryParse(sh['clock_out']) : null;
                            final bool isActive = sh['status'] == 'active' || cout == null;
                            final int durMins = sh['duration_minutes'] ?? 0;

                            final cinStr = cin != null ? DateFormat('yyyy-MM-dd hh:mm a').format(cin) : 'N/A';
                            final coutStr = cout != null ? DateFormat('yyyy-MM-dd hh:mm a').format(cout) : 'IN PROGRESS (ACTIVE)';

                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isActive ? Icons.play_circle_fill : Icons.check_circle,
                                color: isActive ? AppTheme.accent : AppTheme.primary,
                                size: 20,
                              ),
                              title: Text('Clock In: $cinStr', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 12)),
                              subtitle: Text('Clock Out: $coutStr', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    isActive ? 'ACTIVE' : '${(durMins / 60).toStringAsFixed(1)} hrs',
                                    style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: isActive ? AppTheme.accent : AppTheme.textLightPrimary),
                                  ),
                                  Text('$durMins mins', style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailHeaderMetric(String label, String value) {
    return Column(
      children: [
        Text(label, style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textLightSecondary)),
        Text(value, style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.primary)),
      ],
    );
  }

  void _exportWorkSheetPDF() async {
    try {
      final pdfBytes = await PDFHelper.generateWorkSheetPDF(
        companyName: 'Hotel POS Restaurant',
        periodTitle: _selectedDateRange != null
            ? '${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} to ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
            : 'All Time Records',
        attendanceData: _attendanceSummary,
      );
      await PDFHelper.printOrDownloadPDF(pdfBytes, 'Staff_Attendance_Worksheet.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate Worksheet PDF: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _showManualClockDialog() {
    if (_staffList.isEmpty) return;
    int selectedUser = _staffList.first['id'];
    DateTime clockInDate = DateTime.now();
    TimeOfDay clockInTime = TimeOfDay.now();
    DateTime? clockOutDate;
    TimeOfDay? clockOutTime;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              title: Text('Manual Attendance Entry', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedUser,
                      dropdownColor: AppTheme.cardLight,
                      decoration: const InputDecoration(labelText: 'Staff Member *'),
                      items: _staffList.map((s) {
                        return DropdownMenuItem<int>(
                          value: s['id'],
                          child: Text('${s['name']} (${s['role']})'),
                        );
                      }).toList(),
                      onChanged: (val) => setDlgState(() => selectedUser = val!),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      title: Text('Clock In Time: ${DateFormat('yyyy-MM-dd').format(clockInDate)} ${clockInTime.format(context)}'),
                      trailing: const Icon(Icons.calendar_today, size: 18),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: clockInDate, firstDate: DateTime(2025), lastDate: DateTime.now());
                        if (d != null) {
                          final t = await showTimePicker(context: context, initialTime: clockInTime);
                          if (t != null) {
                            setDlgState(() {
                              clockInDate = d;
                              clockInTime = t;
                            });
                          }
                        }
                      },
                    ),
                    ListTile(
                      title: Text(clockOutDate != null && clockOutTime != null
                          ? 'Clock Out Time: ${DateFormat('yyyy-MM-dd').format(clockOutDate!)} ${clockOutTime!.format(context)}'
                          : 'Clock Out Time: (Optional / In Progress)'),
                      trailing: const Icon(Icons.calendar_today, size: 18),
                      onTap: () async {
                        final d = await showDatePicker(context: context, initialDate: clockOutDate ?? DateTime.now(), firstDate: DateTime(2025), lastDate: DateTime.now());
                        if (d != null) {
                          final t = await showTimePicker(context: context, initialTime: clockOutTime ?? TimeOfDay.now());
                          if (t != null) {
                            setDlgState(() {
                              clockOutDate = d;
                              clockOutTime = t;
                            });
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final cinDateTime = DateTime(clockInDate.year, clockInDate.month, clockInDate.day, clockInTime.hour, clockInTime.minute);
                    String cinStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(cinDateTime);
                    String? coutStr;
                    if (clockOutDate != null && clockOutTime != null) {
                      final coutDateTime = DateTime(clockOutDate!.year, clockOutDate!.month, clockOutDate!.day, clockOutTime!.hour, clockOutTime!.minute);
                      coutStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(coutDateTime);
                    }

                    try {
                      await APIService.instance.addManualAttendance(selectedUser, cinStr, clockOut: coutStr);
                      if (mounted) {
                        Navigator.pop(ctx);
                        _loadAttendance();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Manual attendance added successfully'), backgroundColor: AppTheme.accent),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  child: const Text('Save Record'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------
  // TAB 2: SALARY CALCULATION & PAYSLIPS
  // ----------------------------------------------------
  Widget _buildSalaryCalculationTab() {
    final p = _calculatedPayroll;

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Column: Staff Picker & Period Selector (35%)
          Expanded(
            flex: 3,
            child: Card(
              elevation: 0,
              color: AppTheme.cardLight,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Select Staff & Period', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<int>(
                      value: _selectedStaffId,
                      dropdownColor: AppTheme.cardLight,
                      decoration: const InputDecoration(labelText: 'Staff Member *'),
                      items: _staffList.map((s) {
                        return DropdownMenuItem<int>(
                          value: s['id'],
                          child: Text('${s['name']} (${s['role']})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() => _selectedStaffId = val);
                        _calculateSalary();
                      },
                    ),
                    const SizedBox(height: 16),

                    Text('PAYROLL PERIOD', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final d = await showDatePicker(context: context, initialDate: _periodStart, firstDate: DateTime(2025), lastDate: DateTime.now());
                              if (d != null) {
                                setState(() => _periodStart = d);
                                _calculateSalary();
                              }
                            },
                            child: Text(DateFormat('yyyy-MM-dd').format(_periodStart), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('to')),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final d = await showDatePicker(context: context, initialDate: _periodEnd, firstDate: DateTime(2025), lastDate: DateTime.now());
                              if (d != null) {
                                setState(() => _periodEnd = d);
                                _calculateSalary();
                              }
                            },
                            child: Text(DateFormat('yyyy-MM-dd').format(_periodEnd), style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text('PAST PAID PAYSLIPS', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 260,
                      child: _payrollHistory.isEmpty
                          ? Center(child: Text('No paid payslips recorded yet.', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)))
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _payrollHistory.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _payrollHistory[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(item['user_name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                                  subtitle: Text('Paid: ${DateFormat('yyyy-MM-dd').format(DateTime.tryParse(item['paid_at'] ?? '') ?? DateTime.now())}'),
                                  trailing: Text('LKR ${_parseDouble(item['net_salary']).toStringAsFixed(2)}', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                  onTap: () => _reprintPayslipPDF(item),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),

          // Right Column: Live Salary Breakdown & Payslip Actions (65%)
          Expanded(
            flex: 5,
            child: Card(
              elevation: 0,
              color: AppTheme.cardLight,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: AppTheme.borderLight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _isCalculating
                    ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
                    : p == null
                        ? Center(child: Text('Select staff member to calculate salary', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(p['name'] ?? '', style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                      Text('Role: ${p['role']?.toString().toUpperCase()} | Cycle: ${p['salary_type']?.toString().toUpperCase()}', style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textLightSecondary)),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _printPaySheetPDF(p),
                                    icon: const Icon(Icons.picture_as_pdf, size: 16),
                                    label: const Text('Download / Print Payslip PDF'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                              Divider(height: 32, color: AppTheme.dividerColor),

                              // Calculation Breakdown Rows
                              _buildSalaryRow('Basic Salary', _parseDouble(p['basic_salary'])),
                              _buildSalaryRow('Worked Hours', _parseDouble(p['working_hours']), isHours: true),
                              _buildSalaryRow('Overtime (OT) Hours', _parseDouble(p['ot_hours']), isHours: true),
                              _buildSalaryRow('OT Hourly Rate', _parseDouble(p['ot_rate'])),
                              _buildSalaryRow('OT Pay Total (+)', _parseDouble(p['ot_amount']), color: const Color(0xFF10B981)),
                              // Editable Tip Earnings Input Row
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Tip Earnings (+)', style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF10B981))),
                                    SizedBox(
                                      width: 140,
                                      height: 36,
                                      child: TextField(
                                        keyboardType: TextInputType.number,
                                        textAlign: TextAlign.end,
                                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: const Color(0xFF10B981), fontSize: 13),
                                        decoration: InputDecoration(
                                          hintText: '0.00',
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: AppTheme.borderLight)),
                                        ),
                                        onChanged: (val) {
                                          final tip = double.tryParse(val) ?? 0.0;
                                          setState(() {
                                            p['tip_amount'] = tip;
                                            final basic = _parseDouble(p['basic_salary']);
                                            final ot = _parseDouble(p['ot_amount']);
                                            final allowances = _parseDouble(p['allowances']);
                                            final bonuses = _parseDouble(p['bonuses_others']);
                                            final advDeduction = _parseDouble(p['advance_deduction']);
                                            final gross = basic + ot + tip + allowances + bonuses;
                                            p['gross_salary'] = gross;
                                            p['net_salary'] = (gross - advDeduction) < 0 ? 0.0 : (gross - advDeduction);
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _buildSalaryRow('Allowances & Perks (+)', _parseDouble(p['allowances']), color: const Color(0xFF10B981)),
                              Divider(height: 24, color: AppTheme.dividerColor),

                              _buildSalaryRow('GROSS SALARY', _parseDouble(p['gross_salary']), isBold: true),
                              _buildSalaryRow('Advances / Loans Deducted (-)', _parseDouble(p['advance_deduction']), color: const Color(0xFFEF4444)),
                              if (_parseDouble(p['remaining_advance_balance']) > 0)
                                _buildSalaryRow('Remaining Advance Balance (Carried Over)', _parseDouble(p['remaining_advance_balance']), color: const Color(0xFFF59E0B)),
                              Divider(height: 24, color: AppTheme.dividerColor),

                              // NET PAYABLE HIGHLIGHT BOX
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppTheme.primary.withOpacity(0.3), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('NET PAYABLE SALARY', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                    Text('LKR ${_parseDouble(p['net_salary']).toStringAsFixed(2)}', style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Process Payment Action Button
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton.icon(
                                  onPressed: () => _confirmProcessPayment(p),
                                  icon: const Icon(Icons.check_circle, size: 20),
                                  label: Text('Process Payment & Log Expense', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryRow(String label, double val, {bool isHours = false, bool isBold = false, Color? color}) {
    final valStr = isHours ? '${val.toStringAsFixed(1)} hrs' : 'LKR ${val.toStringAsFixed(2)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(fontSize: isBold ? 14 : 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: AppTheme.textLightSecondary)),
          Text(valStr, style: GoogleFonts.inter(fontSize: isBold ? 15 : 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? AppTheme.textLightPrimary)),
        ],
      ),
    );
  }

  void _printPaySheetPDF(Map<String, dynamic> payroll) async {
    try {
      final pdfBytes = await PDFHelper.generatePaySheetPDF(
        companyName: 'Hotel POS Restaurant',
        payrollData: payroll,
      );
      await PDFHelper.printOrDownloadPDF(pdfBytes, 'Payslip_${payroll['name']}.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate Payslip PDF: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _reprintPayslipPDF(Map<String, dynamic> historyItem) async {
    try {
      final pdfBytes = await PDFHelper.generatePaySheetPDF(
        companyName: 'Hotel POS Restaurant',
        payrollData: {
          'name': historyItem['user_name'],
          'role': historyItem['user_role'],
          'period_start': historyItem['period_start'],
          'period_end': historyItem['period_end'],
          'basic_salary': historyItem['basic_salary'],
          'working_hours': historyItem['working_hours'],
          'ot_hours': historyItem['ot_hours'],
          'ot_rate': historyItem['ot_rate'],
          'ot_amount': historyItem['ot_amount'],
          'tip_amount': historyItem['tip_amount'],
          'allowances': historyItem['allowances'],
          'bonuses_others': historyItem['bonuses_others'],
          'advance_deduction': historyItem['advance_deduction'],
          'gross_salary': _parseDouble(historyItem['basic_salary']) + _parseDouble(historyItem['ot_amount']) + _parseDouble(historyItem['tip_amount']) + _parseDouble(historyItem['allowances']),
          'net_salary': historyItem['net_salary'],
        },
      );
      await PDFHelper.printOrDownloadPDF(pdfBytes, 'Payslip_${historyItem['user_name']}.pdf');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to print payslip: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  void _confirmProcessPayment(Map<String, dynamic> payroll) {
    String paymentMethod = 'cash';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDlg) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              title: Text('Confirm Salary Payment', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Staff: ${payroll['name']}', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Net Payable Amount: LKR ${_parseDouble(payroll['net_salary']).toStringAsFixed(2)}', style: GoogleFonts.inter(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    dropdownColor: AppTheme.cardLight,
                    decoration: const InputDecoration(labelText: 'Payment Method / Source *'),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Direct Cash')),
                      DropdownMenuItem(value: 'drawer', child: Text('Drawer Cash (Deducts from Till)')),
                      DropdownMenuItem(value: 'bank', child: Text('Bank Transfer')),
                    ],
                    onChanged: (val) => setStateDlg(() => paymentMethod = val!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final payPayload = Map<String, dynamic>.from(payroll);
                      payPayload['payment_method'] = paymentMethod;

                      await APIService.instance.processSalaryPayment(payPayload);
                      if (mounted) {
                        Navigator.pop(ctx);
                        _calculateSalary();
                        _loadPayrollHistory();
                        _loadAdvances();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Salary payout processed and expense logged successfully!'), backgroundColor: AppTheme.accent),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to process payment: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                  child: const Text('Confirm & Pay'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------
  // TAB 3: STAFF ADVANCES
  // ----------------------------------------------------
  Widget _buildAdvancesTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Staff Cash Advances & Loan Tracking', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
            ElevatedButton.icon(
              onPressed: _showGrantAdvanceDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Grant Staff Advance'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Expanded(
          child: _advancesList.isEmpty
              ? Center(child: Text('No staff advances granted.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
              : ListView.builder(
                  itemCount: _advancesList.length,
                  itemBuilder: (context, index) {
                    final adv = _advancesList[index];
                    final String st = adv['status'] ?? 'pending';
                    final bool isSettled = st == 'settled' || st == 'deducted';
                    final bool isPartial = st == 'partially_deducted';
                    final double origAmt = _parseDouble(adv['amount']);
                    final double dedAmt = _parseDouble(adv['amount_deducted']);
                    final double remBal = adv['remaining_balance'] != null ? _parseDouble(adv['remaining_balance']) : ((origAmt - dedAmt) < 0 ? 0.0 : (origAmt - dedAmt));

                    final String statusText = isSettled ? 'FULLY SETTLED' : (isPartial ? 'PARTIALLY DEDUCTED' : 'PENDING DEDUCTION');
                    final Color badgeBg = isSettled ? const Color(0xFFDCFCE7) : (isPartial ? const Color(0xFFDBEAFE) : const Color(0xFFFEF3C7));
                    final Color badgeText = isSettled ? const Color(0xFF166534) : (isPartial ? const Color(0xFF1E40AF) : const Color(0xFF92400E));

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 8),
                      color: AppTheme.cardLight,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: AppTheme.borderLight),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        title: Row(
                          children: [
                            Text(adv['user_name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: badgeText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reason: ${adv['reason'] ?? 'Staff Advance'} | Date: ${adv['advance_date'] ?? 'N/A'} (Issued by: ${adv['recorded_by_name'] ?? 'Admin'})',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary),
                            ),
                            if (isPartial || isSettled)
                              Text(
                                'Deducted: LKR ${dedAmt.toStringAsFixed(2)} | Remaining Balance: LKR ${remBal.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: remBal > 0 ? AppTheme.warning : AppTheme.accent),
                              ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'LKR ${origAmt.toStringAsFixed(2)}',
                              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.danger),
                            ),
                            if (remBal > 0 && isPartial)
                              Text(
                                'Bal: LKR ${remBal.toStringAsFixed(2)}',
                                style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.warning),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showGrantAdvanceDialog() {
    if (_staffList.isEmpty) return;
    int selectedUser = _staffList.first['id'];
    final amountController = TextEditingController();
    final reasonController = TextEditingController(text: 'Daily salary advance');
    DateTime advanceDate = DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardLight,
              title: Text('Grant Staff Advance', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedUser,
                      dropdownColor: AppTheme.cardLight,
                      decoration: const InputDecoration(labelText: 'Staff Member *'),
                      items: _staffList.map((s) {
                        return DropdownMenuItem<int>(
                          value: s['id'],
                          child: Text('${s['name']} (${s['role']})'),
                        );
                      }).toList(),
                      onChanged: (val) => setDlgState(() => selectedUser = val!),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Advance Amount (LKR) *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(labelText: 'Reason / Remarks *'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: TextStyle(color: AppTheme.textLightSecondary)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final amt = double.tryParse(amountController.text) ?? 0.0;
                    if (amt <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter valid advance amount'), backgroundColor: AppTheme.danger),
                      );
                      return;
                    }

                    try {
                      await APIService.instance.grantStaffAdvance(
                        selectedUser,
                        amt,
                        reasonController.text.trim(),
                        DateFormat('yyyy-MM-dd').format(advanceDate),
                      );
                      if (mounted) {
                        Navigator.pop(ctx);
                        _loadAdvances();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Staff advance granted successfully'), backgroundColor: AppTheme.accent),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: AppTheme.danger),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                  child: const Text('Grant Advance'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ----------------------------------------------------
  // TAB 4: PAYROLL SETTINGS & OT RATES
  // ----------------------------------------------------
  Widget _buildSettingsTab() {
    final otController = TextEditingController(text: _globalOtRate.toStringAsFixed(2));
    final otStartTimeController = TextEditingController(text: _globalOtStartTime);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Global Settings Card
          Card(
            elevation: 0,
            color: AppTheme.cardLight,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppTheme.borderLight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Global Overtime (OT) & Notification Setup', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('GLOBAL OVERTIME (OT) HOURLY RATE (LKR)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: otController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '250.00'),
                              onChanged: (val) {
                                final d = double.tryParse(val);
                                if (d != null) _globalOtRate = d;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('DAILY WORK HOURS LIMIT (OVERTIME AFTER X HOURS)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: otStartTimeController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(hintText: '8.0 Hours'),
                              onChanged: (val) {
                                if (val.trim().isNotEmpty) _globalOtStartTime = val.trim();
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('SALARY DUE REMINDER NOTIFICATION (DAYS BEFORE)', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textLightSecondary)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<int>(
                              value: _salaryNotificationDays,
                              dropdownColor: AppTheme.cardLight,
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('1 Day Before Due Date')),
                                DropdownMenuItem(value: 2, child: Text('2 Days Before Due Date')),
                                DropdownMenuItem(value: 3, child: Text('3 Days Before Due Date')),
                              ],
                              onChanged: (val) => setState(() => _salaryNotificationDays = val!),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Per-Staff Salary Profile Table Card
          Card(
            elevation: 0,
            color: AppTheme.cardLight,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: AppTheme.borderLight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Individual Staff Salary Profiles & Rates', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                  const SizedBox(height: 16),

                  _staffSettings.isEmpty
                      ? Center(child: Text('No staff profiles loaded.', style: GoogleFonts.inter(color: AppTheme.textLightSecondary)))
                      : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _staffSettings.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final s = _staffSettings[index];
                            final isDaily = s['salary_type'] == 'daily';
                            final rateVal = isDaily ? _parseDouble(s['daily_rate']) : _parseDouble(s['basic_salary']);
                            final rateCtrl = TextEditingController(text: rateVal.toStringAsFixed(2));
                            final allowancesCtrl = TextEditingController(text: _parseDouble(s['allowances']).toStringAsFixed(2));
                            final customOtCtrl = TextEditingController(text: s['ot_rate_per_hour'] != null ? _parseDouble(s['ot_rate_per_hour']).toStringAsFixed(2) : '');

                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppTheme.cardLight,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.borderLight),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(s['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.textLightPrimary)),
                                            Text('${s['role']?.toString().toUpperCase()} | @${s['username']}', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textLightSecondary)),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: DropdownButtonFormField<String>(
                                          value: s['salary_type'] ?? 'monthly',
                                          dropdownColor: AppTheme.cardLight,
                                          decoration: const InputDecoration(labelText: 'Salary Cycle Type'),
                                          items: const [
                                            DropdownMenuItem(value: 'monthly', child: Text('Monthly Basic Salary')),
                                            DropdownMenuItem(value: 'daily', child: Text('Daily Wage Rate')),
                                          ],
                                          onChanged: (val) => setState(() => s['salary_type'] = val!),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: TextField(
                                          controller: rateCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: InputDecoration(
                                            labelText: isDaily ? 'Daily Wage Rate (LKR/day)' : 'Basic Monthly Salary (LKR)',
                                          ),
                                          onChanged: (val) {
                                            final numVal = double.tryParse(val) ?? 0.0;
                                            if (isDaily) {
                                              s['daily_rate'] = numVal;
                                            } else {
                                              s['basic_salary'] = numVal;
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Checkbox(
                                            value: s['allow_ot'] ?? true,
                                            activeColor: AppTheme.primary,
                                            onChanged: (val) {
                                              setState(() => s['allow_ot'] = val ?? true);
                                            },
                                          ),
                                          Text('Allow OT', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textLightPrimary)),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: customOtCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(labelText: 'Custom OT Rate/h (Opt)'),
                                          onChanged: (val) {
                                            if (val.trim().isEmpty) {
                                              s['ot_rate_per_hour'] = null;
                                            } else {
                                              s['ot_rate_per_hour'] = double.tryParse(val);
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: allowancesCtrl,
                                          keyboardType: TextInputType.number,
                                          decoration: const InputDecoration(labelText: 'Allowances & Perks (LKR)'),
                                          onChanged: (val) => s['allowances'] = double.tryParse(val) ?? 0.0,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: DropdownButtonFormField<int>(
                                          value: s['salary_due_day'] ?? 28,
                                          dropdownColor: AppTheme.cardLight,
                                          decoration: const InputDecoration(labelText: 'Salary Due Day'),
                                          items: List.generate(28, (i) => i + 1).map((day) {
                                            return DropdownMenuItem<int>(value: day, child: Text('Day $day of month'));
                                          }).toList(),
                                          onChanged: (val) => s['salary_due_day'] = val,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _savePayrollSettings,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text('Save All Payroll Settings', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _savePayrollSettings() async {
    try {
      await APIService.instance.updatePayrollSettings(
        globalOtRate: _globalOtRate,
        globalOtStartTime: _globalOtStartTime,
        salaryNotificationDays: _salaryNotificationDays,
        userSettings: _staffSettings,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payroll settings updated successfully!'), backgroundColor: AppTheme.accent),
      );
      _loadPayrollSettings();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }
}
