import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

class PDFHelper {
  static double _parseVal(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val) ?? 0.0;
    return 0.0;
  }

  /// Generate Attendance Work Sheet PDF Document
  static Future<Uint8List> generateWorkSheetPDF({
    required String companyName,
    required String periodTitle,
    required List<Map<String, dynamic>> attendanceData,
  }) async {
    final pdf = pw.Document();
    final nowStr = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        companyName,
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.pink700,
                        ),
                      ),
                      pw.Text(
                        'STAFF ATTENDANCE & WORKSHEET REPORT',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.grey800,
                        ),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Report Period: $periodTitle', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('Generated: $nowStr', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Divider(color: PdfColors.pink200, thickness: 1.5),
              pw.SizedBox(height: 12),
            ],
          );
        },
        footer: (pw.Context context) {
          return pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Confidential - Internal HR Document', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.TableHelper.fromTextArray(
              headers: [
                'Staff Member',
                'Role',
                'Status',
                'Daily (h)',
                'Weekly (h)',
                'Monthly (h)',
                'Yearly (h)',
                'Avg/Day',
                'OT (h)',
              ],
              data: attendanceData.map((item) {
                return [
                  item['name'] ?? '',
                  item['role']?.toString().toUpperCase() ?? '',
                  item['is_clocked_in'] == true ? 'CLOCKED IN' : 'OFFLINE',
                  _parseVal(item['daily_hours']).toStringAsFixed(1),
                  _parseVal(item['weekly_hours']).toStringAsFixed(1),
                  _parseVal(item['monthly_hours']).toStringAsFixed(1),
                  _parseVal(item['yearly_hours']).toStringAsFixed(1),
                  _parseVal(item['average_daily_hours']).toStringAsFixed(1),
                  _parseVal(item['ot_hours']).toStringAsFixed(1),
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.pink700),
              rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey200))),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }

  /// Generate Pay Sheet / Payslip PDF Document
  static Future<Uint8List> generatePaySheetPDF({
    required String companyName,
    required Map<String, dynamic> payrollData,
  }) async {
    final pdf = pw.Document();
    final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final String staffName = payrollData['name'] ?? 'Staff Member';
    final String role = payrollData['role']?.toString().toUpperCase() ?? 'STAFF';
    final String periodStart = payrollData['period_start'] ?? '';
    final String periodEnd = payrollData['period_end'] ?? '';

    final double basicSalary = _parseVal(payrollData['basic_salary']);
    final double workingHours = _parseVal(payrollData['working_hours']);
    final double otHours = _parseVal(payrollData['ot_hours']);
    final double otRate = _parseVal(payrollData['ot_rate']);
    final double otAmount = _parseVal(payrollData['ot_amount']);
    final double tipAmount = _parseVal(payrollData['tip_amount']);
    final double allowances = _parseVal(payrollData['allowances']);
    final double bonusesOthers = _parseVal(payrollData['bonuses_others']);
    final double advanceDeduction = _parseVal(payrollData['advance_deduction']);
    final double grossSalary = payrollData['gross_salary'] != null
        ? _parseVal(payrollData['gross_salary'])
        : (basicSalary + otAmount + tipAmount + allowances + bonusesOthers);
    final double netSalary = payrollData['net_salary'] != null
        ? _parseVal(payrollData['net_salary'])
        : (grossSalary - advanceDeduction);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.pink700,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          companyName,
                          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                        ),
                        pw.Text(
                          'OFFICIAL SALARY PAYSLIP',
                          style: pw.TextStyle(fontSize: 12, color: PdfColors.pink100, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Date: $nowStr', style: const pw.TextStyle(fontSize: 10, color: PdfColors.white)),
                        pw.Text('Period: $periodStart to $periodEnd', style: const pw.TextStyle(fontSize: 9, color: PdfColors.pink100)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Staff Details
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('EMPLOYEE NAME', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.Text(staffName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('DESIGNATION / ROLE', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.Text(role, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.pink700)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('WORKED HOURS', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                        pw.Text('${workingHours.toStringAsFixed(1)} hrs', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Salary Component Breakdown Table
              pw.Text('EARNINGS & PAYROLL BREAKDOWN', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Details / Rate', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Amount (LKR)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Basic Salary', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Fixed Rate', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(basicSalary.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Overtime (OT) Pay', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('${otHours.toStringAsFixed(1)} hrs @ LKR ${otRate.toStringAsFixed(2)}/hr', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(otAmount.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Tip Earnings', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Order Tip Allocation', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(tipAmount.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Allowances & Perks', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Standard Allowances', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(allowances.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  if (bonusesOthers > 0)
                    pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Bonus / Others', style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Additional Bonus', style: const pw.TextStyle(fontSize: 10))),
                        pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(bonusesOthers.toStringAsFixed(2), style: const pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.right)),
                      ],
                    ),
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('GROSS SALARY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(grossSalary.toStringAsFixed(2), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 16),

              // Deductions Table
              pw.Text('DEDUCTIONS & ADVANCES', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  pw.TableRow(
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Salary Advances / Loans Deducted', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Cash Advances', style: const pw.TextStyle(fontSize: 10))),
                      pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('- LKR ${advanceDeduction.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10, color: PdfColors.red700), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 24),

              // Net Payable Box
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.pink50,
                  border: pw.Border.all(color: PdfColors.pink700, width: 1.5),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('NET PAYABLE SALARY', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.pink900)),
                    pw.Text(
                      'LKR ${netSalary.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.pink900),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)))),
                      pw.SizedBox(height: 4),
                      pw.Text('Employee Signature', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)))),
                      pw.SizedBox(height: 4),
                      pw.Text('Authorized Manager Signature', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Print or Download PDF helper
  static Future<void> printOrDownloadPDF(Uint8List pdfBytes, String filename) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfBytes,
      name: filename,
    );
  }
}
