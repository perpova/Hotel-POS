import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../core/api_service.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';

class MySalaryScreen extends StatefulWidget {
  const MySalaryScreen({Key? key}) : super(key: key);

  @override
  State<MySalaryScreen> createState() => _MySalaryScreenState();
}

class _MySalaryScreenState extends State<MySalaryScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _salaryData;
  List<Map<String, dynamic>> _advances = [];

  @override
  void initState() {
    super.initState();
    _loadSalary();
  }

  Future<void> _loadSalary() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.instance.getMySalaryBreakdown(user.id);
      final adv = await ApiService.instance.getMyAdvances(user.id);
      if (mounted) {
        setState(() {
          _salaryData = res;
          _advances = adv;
        });
      }
    } catch (e) {
      debugPrint('Error loading salary: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _parseDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final p = _salaryData;

    return Scaffold(
      backgroundColor: AppColors.bgDeep,
      appBar: AppBar(
        title: const Text('My Salary & Payslip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.primary),
            onPressed: p != null ? _exportPayslipPDF : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : p == null
              ? const Center(child: Text('Salary breakdown unavailable', style: TextStyle(color: AppColors.textMuted)))
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _loadSalary,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Net Salary Highlight Hero
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1E1B4B), Color(0xFF311B92)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('ESTIMATED NET SALARY', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            const SizedBox(height: 6),
                            Text(
                              'LKR ${_parseDouble(p['net_salary']).toStringAsFixed(2)}',
                              style: const TextStyle(color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Period: ${p['period_start']} to ${p['period_end']}',
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Breakdown Section
                      const Text('Salary Earnings Breakdown', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            _buildRow('Basic Salary', _parseDouble(p['basic_salary'])),
                            _buildRow('Worked Hours', _parseDouble(p['working_hours']), isHours: true),
                            _buildRow('OT Hours (${_parseDouble(p['ot_rate'])}/h)', _parseDouble(p['ot_hours']), isHours: true),
                            _buildRow('OT Earnings (+)', _parseDouble(p['ot_amount']), color: AppColors.success),
                            _buildRow('Tip Earnings (+)', _parseDouble(p['tip_amount']), color: AppColors.success),
                            _buildRow('Allowances (+)', _parseDouble(p['allowances']), color: AppColors.success),
                            const Divider(height: 20),
                            _buildRow('Gross Earnings', _parseDouble(p['gross_salary']), isBold: true),
                            _buildRow('Advances Deducted (-)', _parseDouble(p['advance_deduction']), color: AppColors.error),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Advances History Section
                      const Text('My Cash Advances & Loans', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 10),

                      if (_advances.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.bgCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: const Center(child: Text('No cash advances logged', style: TextStyle(color: AppColors.textMuted, fontSize: 12))),
                        )
                      else
                        ..._advances.map((adv) {
                          final bool isDeducted = adv['status'] == 'deducted';

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
                                    Text(adv['reason'] ?? 'Cash Advance', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('Date: ${adv['advance_date'] ?? ''}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('LKR ${_parseDouble(adv['amount']).toStringAsFixed(2)}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text(
                                      isDeducted ? 'Deducted' : 'Pending',
                                      style: TextStyle(color: isDeducted ? AppColors.success : AppColors.warning, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _exportPayslipPDF,
                          icon: const Icon(Icons.download_rounded, size: 20),
                          label: const Text('DOWNLOAD PAYSLIP PDF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRow(String label, double val, {bool isHours = false, bool isBold = false, Color? color}) {
    final str = isHours ? '${val.toStringAsFixed(1)} hrs' : 'LKR ${val.toStringAsFixed(2)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(str, style: TextStyle(color: color ?? AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: isBold ? 14 : 12)),
        ],
      ),
    );
  }

  Future<void> _exportPayslipPDF() async {
    final p = _salaryData;
    final user = context.read<AuthProvider>().user;
    if (p == null || user == null) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(color: PdfColors.amber800, borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('HOTEL POS PAYSLIP', style: pw.TextStyle(color: PdfColors.white, fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.Text('Date: ${DateFormat('yyyy-MM-dd').format(DateTime.now())}', style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text('Employee: ${user.name} (${user.role.toUpperCase()})', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text('Period: ${p['period_start']} to ${p['period_end']}', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
              pw.SizedBox(height: 20),

              pw.TableHelper.fromTextArray(
                headers: ['Item', 'Details', 'Amount (LKR)'],
                data: [
                  ['Basic Salary', 'Fixed Rate', '${_parseDouble(p['basic_salary']).toStringAsFixed(2)}'],
                  ['OT Earnings', '${_parseDouble(p['ot_hours']).toStringAsFixed(1)} hrs @ ${_parseDouble(p['ot_rate'])}/h', '${_parseDouble(p['ot_amount']).toStringAsFixed(2)}'],
                  ['Tip Earnings', 'Orders Tips', '${_parseDouble(p['tip_amount']).toStringAsFixed(2)}'],
                  ['Allowances', 'Standard Perks', '${_parseDouble(p['allowances']).toStringAsFixed(2)}'],
                  ['Advances Deducted', 'Loans', '- LKR ${_parseDouble(p['advance_deduction']).toStringAsFixed(2)}'],
                ],
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(height: 20),

              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(color: PdfColors.amber50, border: pw.Border.all(color: PdfColors.amber800)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('NET PAYABLE SALARY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                    pw.Text('LKR ${_parseDouble(p['net_salary']).toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Payslip_${user.name}.pdf',
    );
  }
}
