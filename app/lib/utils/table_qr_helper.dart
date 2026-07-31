import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/models.dart';

class TableQRHelper {
  /// Generate a single Table QR Card PDF
  static Future<Uint8List> generateSingleTableQRPDF({
    required String companyName,
    required DiningTableModel table,
  }) async {
    final pdf = pw.Document();
    
    // Load Sinhala Font if available
    pw.Font? sinhalaFont;
    try {
      final fontData = await rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf');
      sinhalaFont = pw.Font.ttf(fontData);
    } catch (_) {}

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a6,
        margin: const pw.EdgeInsets.all(16),
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.indigo900, width: 2),
                borderRadius: pw.BorderRadius.circular(12),
                color: PdfColors.white,
              ),
              child: pw.Column(
                mainAxisSize: pw.MainAxisSize.min,
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    companyName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo900,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.indigo900,
                      borderRadius: pw.BorderRadius.circular(20),
                    ),
                    child: pw.Text(
                      'TABLE ${table.tableNumber}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: 'TABLE-${table.tableNumber}',
                    width: 140,
                    height: 140,
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    'Capacity: ${table.capacity} Persons',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Divider(thickness: 0.5, color: PdfColors.grey400),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'INTERNAL POS SCANNER QR CODE',
                    style: pw.TextStyle(
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.indigo700,
                    ),
                  ),
                  pw.Text(
                    'Scan with POS barcode reader to auto-select table',
                    style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Generate a multi-page A4 PDF sheet containing all Table QR Cards
  static Future<Uint8List> generateAllTablesQRPDF({
    required String companyName,
    required List<DiningTableModel> tables,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    companyName,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900),
                  ),
                  pw.Text(
                    'OFFICIAL DINING TABLES QR CODE SHEET',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1, color: PdfColors.indigo200),
              pw.SizedBox(height: 10),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            pw.GridView(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: tables.map((t) {
                return pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.indigo800, width: 1.5),
                    borderRadius: pw.BorderRadius.circular(10),
                    color: PdfColors.white,
                  ),
                  child: pw.Column(
                    mainAxisSize: pw.MainAxisSize.min,
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.indigo900,
                          borderRadius: pw.BorderRadius.circular(14),
                        ),
                        child: pw.Text(
                          'TABLE ${t.tableNumber}',
                          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.BarcodeWidget(
                        barcode: pw.Barcode.qrCode(),
                        data: 'TABLE-${t.tableNumber}',
                        width: 105,
                        height: 105,
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('Capacity: ${t.capacity} Seats', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                      pw.SizedBox(height: 4),
                      pw.Text('TABLE-${t.tableNumber}', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ];
        },
      ),
    );

    return pdf.save();
  }
}
