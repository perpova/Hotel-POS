import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_service.dart';
import '../core/theme.dart';

class StaffPayrollScreen extends StatefulWidget {
  const StaffPayrollScreen({Key? key}) : super(key: key);

  @override
  State<StaffPayrollScreen> createState() => _StaffPayrollScreenState();
}

class _StaffPayrollScreenState extends State<StaffPayrollScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;

  List<Map<String, dynamic>> _attendanceSummary = [];
  List<Map<String, dynamic>> _advancesList = [];
  double _globalOtRate = 250.0;
  String _globalOtStartTime = '2';
  int _salaryNotificationDays = 2;
  List<Map<String, dynamic>> _staffSettings = [];

  final _curr = NumberFormat('#,##0.00', 'en_US');

  // Salary Calc
  int? _selectedStaffId;
  DateTime _periodStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _periodEnd = DateTime.now();
  Map<String, dynamic>? _payrollData;
  bool _isCalculating = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  int _parseInt(dynamic val) {
    if (val == null) return 0;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val) ?? 0;
    return 0;
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final summary = await ApiService.instance.getStaffAttendanceSummary();
      final adv = await ApiService.instance.getStaffAdvances();
      final settings = await ApiService.instance.getPayrollSettings();

      if (mounted) {
        setState(() {
          final Map<int, Map<String, dynamic>> uniqueMap = {};
          for (final s in summary) {
            final uid = s['user_id'] as int?;
            if (uid != null && !uniqueMap.containsKey(uid)) {
              uniqueMap[uid] = s;
            }
          }
          _attendanceSummary = uniqueMap.values.toList();
          _advancesList = adv;
          _globalOtRate = _parseDouble(settings['global_ot_rate']);
          _globalOtStartTime = settings['global_ot_start_time']?.toString() ?? '2';
          _salaryNotificationDays = _parseInt(settings['salary_notification_days']);
          _staffSettings = List<Map<String, dynamic>>.from(settings['staff_settings'] ?? []);

          if (_selectedStaffId == null && _attendanceSummary.isNotEmpty) {
            _selectedStaffId = _attendanceSummary.first['user_id'] as int?;
            _calculateSalary();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading admin payroll screen: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateSalary() async {
    if (_selectedStaffId == null) return;
    setState(() => _isCalculating = true);
    try {
      final res = await ApiService.instance.calculateStaffSalary(
        _selectedStaffId!,
        periodStart: DateFormat('yyyy-MM-dd').format(_periodStart),
        periodEnd: DateFormat('yyyy-MM-dd').format(_periodEnd),
      );
      if (mounted) {
        setState(() => _payrollData = res);
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
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('Staff Attendance & Payroll', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontSize: 13),
          tabs: const [
            Tab(text: 'Attendance'),
            Tab(text: 'Salary Calc'),
            Tab(text: 'Advance & OT Setup'),
            Tab(text: 'Staff Cash Advances'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTab(),
                _buildSalaryTab(),
                _buildOTSetupTab(),
                _buildCashAdvancesTab(),
              ],
            ),
    );
  }

  // Attendance Tab
  Widget _buildAttendanceTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _attendanceSummary.length,
      itemBuilder: (context, index) {
        final s = _attendanceSummary[index];
        final bool isClockedIn = s['is_clocked_in'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isClockedIn ? AppColors.success : AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: AppColors.primary.withOpacity(0.2),
                          radius: 16,
                          child: Text(
                            s['name']?.substring(0, 1).toUpperCase() ?? 'U',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s['name'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                              Text(s['role']?.toString().toUpperCase() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 10), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isClockedIn ? AppColors.successGlow : AppColors.bgCardAlt,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isClockedIn ? 'CLOCKED IN' : 'OFFLINE',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isClockedIn ? AppColors.success : AppColors.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatPill('Daily', '${_parseDouble(s['daily_hours']).toStringAsFixed(1)}h'),
                    const SizedBox(width: 16),
                    _buildStatPill('Weekly', '${_parseDouble(s['weekly_hours']).toStringAsFixed(1)}h'),
                    const SizedBox(width: 16),
                    _buildStatPill('Monthly', '${_parseDouble(s['monthly_hours']).toStringAsFixed(1)}h'),
                    const SizedBox(width: 16),
                    _buildStatPill('Yearly', '${_parseDouble(s['yearly_hours']).toStringAsFixed(1)}h'),
                    const SizedBox(width: 16),
                    _buildStatPill('Avg/Day', '${_parseDouble(s['average_daily_hours']).toStringAsFixed(1)}h'),
                    const SizedBox(width: 16),
                    _buildStatPill('OT', '${_parseDouble(s['ot_hours']).toStringAsFixed(1)}h', color: AppColors.warning),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatPill(String label, String val, {Color? color}) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 9, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color ?? AppColors.textPrimary)),
      ],
    );
  }

  // Salary Calc Tab
  Widget _buildSalaryTab() {
    final p = _payrollData;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Staff Picker
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _selectedStaffId,
              dropdownColor: AppColors.bgCard,
              isExpanded: true,
              hint: const Text('Select Staff Member', style: TextStyle(color: AppColors.textSecondary)),
              items: _attendanceSummary.map((s) {
                return DropdownMenuItem<int>(
                  value: s['user_id'],
                  child: Text('${s['name']} (${s['role']})', style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
                );
              }).toList(),
              onChanged: (val) {
                setState(() => _selectedStaffId = val);
                _calculateSalary();
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (_isCalculating)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppColors.primary)))
        else if (p == null)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('Select staff to calculate salary', style: TextStyle(color: AppColors.textMuted))))
        else ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['name'] ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Period: ${p['period_start']} to ${p['period_end']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                const Divider(height: 24),

                _buildRow('Basic Salary', _parseDouble(p['basic_salary'])),
                _buildRow('Worked Hours', _parseDouble(p['working_hours']), isHours: true),
                _buildRow('OT Hours (${_parseDouble(p['ot_rate'])}/h)', _parseDouble(p['ot_hours']), isHours: true),
                _buildRow('OT Total Pay (+)', _parseDouble(p['ot_amount']), color: AppColors.success),
                _buildRow('Tip Earnings (+)', _parseDouble(p['tip_amount']), color: AppColors.success),
                _buildRow('Allowances (+)', _parseDouble(p['allowances']), color: AppColors.success),
                const Divider(height: 20),
                _buildRow('Advances Deducted (-)', _parseDouble(p['advance_deduction']), color: AppColors.error),
                if (_parseDouble(p['remaining_advance_balance']) > 0)
                  _buildRow('Remaining Advance Bal (Carried Over)', _parseDouble(p['remaining_advance_balance']), color: AppColors.warning),
                const Divider(height: 24),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('NET SALARY', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                      Text(
                        'LKR ${_curr.format(_parseDouble(p['net_salary']))}',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      try {
                        final payload = Map<String, dynamic>.from(p);
                        payload['payment_method'] = 'cash';
                        await ApiService.instance.processSalaryPayment(payload);
                        if (mounted) {
                          _calculateSalary();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Salary paid and recorded as expense!'), backgroundColor: AppColors.success),
                          );
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('PROCESS PAYOUT & LOG EXPENSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRow(String label, double val, {bool isHours = false, Color? color}) {
    final str = isHours ? '${val.toStringAsFixed(1)} hrs' : 'LKR ${_curr.format(val)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(str, style: TextStyle(color: color ?? AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  // OT & Salary Setup Tab
  Widget _buildOTSetupTab() {
    final otCtrl = TextEditingController(text: _globalOtRate.toStringAsFixed(2));
    final otStartCtrl = TextEditingController(text: _globalOtStartTime);
    int notificationDays = _salaryNotificationDays;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Global OT & Notification Setup Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Global Overtime (OT) & Notification Setup', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: otCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Global OT Rate (LKR/h)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: otStartCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Daily Work Limit (hrs)',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: notificationDays,
                      dropdownColor: AppColors.bgCardAlt,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Salary Notification',
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 Day Before Due', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                        DropdownMenuItem(value: 2, child: Text('2 Days Before Due', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                        DropdownMenuItem(value: 3, child: Text('3 Days Before Due', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                        DropdownMenuItem(value: 5, child: Text('5 Days Before Due', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                      ],
                      onChanged: (v) {
                        if (v != null) notificationDays = v;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () async {
                        final rate = double.tryParse(otCtrl.text) ?? 250.0;
                        final otStart = otStartCtrl.text.trim().isEmpty ? '2' : otStartCtrl.text.trim();
                        await ApiService.instance.updatePayrollSettings(
                          globalOtRate: rate,
                          globalOtStartTime: otStart,
                          salaryNotificationDays: notificationDays,
                        );
                        setState(() {
                          _globalOtRate = rate;
                          _globalOtStartTime = otStart;
                          _salaryNotificationDays = notificationDays;
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Global Payroll Settings Saved!'), backgroundColor: AppColors.success),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('SAVE GLOBAL', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Individual Staff Salary Profiles Section
        const Text('Individual Staff Salary Profiles & Rates', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 8),

        if (_staffSettings.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No staff salary profiles loaded.', style: TextStyle(color: AppColors.textMuted))))
        else
          ..._staffSettings.map((st) => _buildStaffSalaryProfileCard(st)).toList(),
      ],
    );
  }

  // Staff Cash Advances Tab
  Widget _buildCashAdvancesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Advances List Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Staff Cash Advances & Loan Tracking', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
            IconButton(
              icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary, size: 28),
              onPressed: _showAddAdvanceDialog,
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_advancesList.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('No staff advances logged.', style: TextStyle(color: AppColors.textMuted))))
        else
          ..._advancesList.map((adv) {
            final String st = adv['status'] ?? 'pending';
            final bool isSettled = st == 'settled' || st == 'deducted';
            final bool isPartial = st == 'partially_deducted';
            final double origAmt = _parseDouble(adv['amount']);
            final double dedAmt = _parseDouble(adv['amount_deducted']);
            final double remBal = adv['remaining_balance'] != null ? _parseDouble(adv['remaining_balance']) : ((origAmt - dedAmt) < 0 ? 0.0 : (origAmt - dedAmt));

            final String stText = isSettled ? 'Settled' : (isPartial ? 'Partially Deducted' : 'Pending');
            final Color stColor = isSettled ? AppColors.success : (isPartial ? AppColors.info : AppColors.warning);

            String rawDate = adv['advance_date']?.toString() ?? '';
            String formattedDate = rawDate;
            if (rawDate.isNotEmpty) {
              try {
                final dt = DateTime.parse(rawDate).toLocal();
                formattedDate = DateFormat('yyyy-MM-dd').format(dt);
              } catch (_) {
                formattedDate = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
              }
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          adv['user_name'] ?? '',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${adv['reason'] ?? 'Advance'} · $formattedDate',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (isPartial)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Deducted: LKR ${_curr.format(dedAmt)} | Bal: LKR ${_curr.format(remBal)}',
                              style: const TextStyle(color: AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'LKR ${_curr.format(origAmt)}',
                        style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: stColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          stText.toUpperCase(),
                          style: TextStyle(color: stColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildStaffSalaryProfileCard(Map<String, dynamic> st) {
    final int userId = st['user_id'];
    final name = st['name'] ?? 'Staff';
    final role = st['role']?.toString().toUpperCase() ?? '';
    final username = st['username'] ?? '';

    String salaryType = st['salary_type'] ?? 'monthly';
    final basicCtrl = TextEditingController(text: _parseDouble(st['basic_salary']).toStringAsFixed(2));
    final otRateCtrl = TextEditingController(text: st['custom_ot_rate'] != null ? _parseDouble(st['custom_ot_rate']).toStringAsFixed(2) : '');
    final allowancesCtrl = TextEditingController(text: _parseDouble(st['allowances']).toStringAsFixed(2));
    int dueDay = _parseInt(st['salary_due_day']) == 0 ? 28 : _parseInt(st['salary_due_day']);
    bool allowOt = st['allow_ot'] == 1 || st['allow_ot'] == true || st['allow_ot'] == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis),
                    Text('ROLE: $role | @$username', style: const TextStyle(color: AppColors.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Row(
                children: [
                  Checkbox(
                    value: allowOt,
                    activeColor: AppColors.primary,
                    onChanged: (v) {
                      setState(() => st['allow_ot'] = v ?? true);
                    },
                  ),
                  const Text('Allow OT', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: salaryType,
                  dropdownColor: AppColors.bgCardAlt,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Salary Cycle Type',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'monthly', child: Text('Monthly Basic', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                    DropdownMenuItem(value: 'daily', child: Text('Daily Wage', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                    DropdownMenuItem(value: 'hourly', child: Text('Hourly Rate', style: TextStyle(color: AppColors.textPrimary, fontSize: 12))),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => st['salary_type'] = v);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: basicCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    labelText: salaryType == 'daily' ? 'Daily Rate (LKR)' : 'Basic Salary (LKR)',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: otRateCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Custom OT/h (Opt)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: allowancesCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                  decoration: const InputDecoration(
                    labelText: 'Allowances (LKR)',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: dueDay,
                  dropdownColor: AppColors.bgCardAlt,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Salary Due Day',
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: List.generate(31, (i) => i + 1).map((day) {
                    return DropdownMenuItem(value: day, child: Text('Day $day of month', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)));
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) dueDay = v;
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final uSetting = {
                      'user_id': userId,
                      'salary_type': st['salary_type'] ?? 'monthly',
                      'basic_salary': double.tryParse(basicCtrl.text) ?? 0.0,
                      'custom_ot_rate': otRateCtrl.text.trim().isEmpty ? null : double.tryParse(otRateCtrl.text),
                      'allowances': double.tryParse(allowancesCtrl.text) ?? 0.0,
                      'salary_due_day': dueDay,
                      'allow_ot': allowOt ? 1 : 0,
                    };
                    await ApiService.instance.updatePayrollSettings(userSettings: [uSetting]);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Salary profile updated for $name!'), backgroundColor: AppColors.success),
                      );
                    }
                  },
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('SAVE PROFILE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddAdvanceDialog() {
    if (_attendanceSummary.isEmpty) return;
    int selectedUser = _attendanceSummary.first['user_id'];
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController(text: 'Daily salary advance');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Grant Staff Advance', style: TextStyle(color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<int>(
              value: selectedUser,
              dropdownColor: AppColors.bgCard,
              isExpanded: true,
              items: _attendanceSummary.map((s) {
                return DropdownMenuItem<int>(value: s['user_id'], child: Text('${s['name']}', style: const TextStyle(color: AppColors.textPrimary)));
              }).toList(),
              onChanged: (val) => selectedUser = val!,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Advance Amount (LKR)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Reason'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () async {
              final amt = double.tryParse(amtCtrl.text) ?? 0.0;
              if (amt <= 0) return;
              await ApiService.instance.grantStaffAdvance(selectedUser, amt, reasonCtrl.text.trim(), DateFormat('yyyy-MM-dd').format(DateTime.now()));
              if (mounted) {
                Navigator.pop(ctx);
                _loadAll();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }
}
