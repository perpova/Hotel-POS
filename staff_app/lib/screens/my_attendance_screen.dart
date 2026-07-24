import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/theme.dart';
import '../models/models.dart';
import '../providers/auth_provider.dart';

class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({Key? key}) : super(key: key);

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _attendanceData;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.getMyAttendanceReport(user.id);
      if (mounted) setState(() => _attendanceData = res);
    } catch (e) {
      debugPrint('Error loading my attendance: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final data = _attendanceData;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('My Attendance & Work Hours', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
            onPressed: data != null ? _exportPDF : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : data == null
              ? const Center(child: Text('No attendance records found', style: TextStyle(color: AppColors.textMuted)))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Header Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: AppColors.primary.withOpacity(0.2),
                              radius: 22,
                              child: Text(
                                user?.name.substring(0, 1).toUpperCase() ?? 'U',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.primary),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user?.name ?? '', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(user?.role.toUpperCase() ?? '', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Metrics Grid
                      const Text('Work Hours Summary', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1.8,
                        children: [
                          _buildCard('Daily Hours (Today)', '${(data['daily_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', AppColors.primary),
                          _buildCard('Weekly Hours', '${(data['weekly_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', AppColors.info),
                          _buildCard('Monthly Hours', '${(data['monthly_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFF8B5CF6)),
                          _buildCard('Yearly Hours', '${(data['yearly_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', const Color(0xFF6366F1)),
                          _buildCard('Daily Average', '${(data['average_daily_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', AppColors.success),
                          _buildCard('OT Hours Total', '${(data['ot_hours'] as num?)?.toStringAsFixed(1) ?? "0.0"} h', AppColors.warning),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // In / Out Shifts History
                      const Text('Recent Clock In / Out History', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),

                      if ((data['shifts'] as List? ?? []).isEmpty)
                        const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('No shift logs', style: TextStyle(color: AppColors.textMuted))))
                      else
                        ...List.from(data['shifts'] ?? []).map((sh) {
                          final cinRaw = sh['clock_in']?.toString();
                          final coutRaw = sh['clock_out']?.toString();
                          String cinStr = cinRaw ?? '';
                          String coutStr = coutRaw ?? 'In Progress';
                          try {
                            if (cinRaw != null) cinStr = DateFormat('dd MMM, hh:mm a').format(parseServerDate(cinRaw));
                            if (coutRaw != null) coutStr = DateFormat('hh:mm a').format(parseServerDate(coutRaw));
                          } catch (_) {}

                          final int mins = (sh['duration_minutes'] as num?)?.toInt() ?? 0;
                          final hrs = (mins / 60).toStringAsFixed(1);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.bgCard,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('In: $cinStr', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                                    Text('Out: $coutStr', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                                  child: Text('$hrs hrs', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildCard(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _exportPDF() async {
    final data = _attendanceData;
    final user = context.read<AuthProvider>().user;
    if (data == null || user == null) return;

    final pdf = pw.Document();
    final shifts = (data['shifts'] as List? ?? []);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => [
          pw.Text('Hotel POS - Staff Attendance Worksheet', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Text('Staff: ${user.name} (${user.role.toUpperCase()})', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('Generated: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Clock In', 'Clock Out', 'Duration (mins)', 'Hours (h)'],
            data: shifts.map((sh) {
              return [
                sh['clock_in']?.toString() ?? '',
                sh['clock_out']?.toString() ?? 'Active',
                '${sh['duration_minutes'] ?? 0}',
                '${((sh['duration_minutes'] as num? ?? 0) / 60).toStringAsFixed(1)}',
              ];
            }).toList(),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10),
            cellStyle: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Attendance_Report_${user.name}.pdf',
    );
  }
}
