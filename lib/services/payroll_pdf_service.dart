// lib/services/payroll_pdf_service.dart
//
// Generates a full-month payroll PDF report.
// Pulls clock_in / clock_out records from Firestore (web) or local DB (mobile)
// and computes daily & monthly revenue figures.
//
// Dependencies to add to pubspec.yaml:
//   pdf: ^3.10.8
//   printing: ^5.12.0          ← handles share / download on all platforms
//   path_provider: ^2.1.2      ← mobile save path
//   intl: (already present)
//
// Usage:
//   await PayrollPdfService.generate(context, employee: emp, hourlyRate: 75.0);

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show BuildContext;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/employee.dart';
import '../services/database_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data model for one day's attendance + earnings
// ─────────────────────────────────────────────────────────────────────────────
class _DayRecord {
  final String date;         // yyyy-MM-dd
  final String? timeIn;      // HH:mm:ss
  final String? timeOut;     // HH:mm:ss
  final String  method;
  final double  hoursWorked;
  final double  dailyEarned;

  const _DayRecord({
    required this.date,
    this.timeIn,
    this.timeOut,
    required this.method,
    required this.hoursWorked,
    required this.dailyEarned,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Color palette — matches the dark navy app theme (converted to PDF colours)
// ─────────────────────────────────────────────────────────────────────────────
class _K {
  static const navy     = PdfColor.fromInt(0xFF0A0F2E);
  static const card     = PdfColor.fromInt(0xFF0F1535);
  static const accent   = PdfColor.fromInt(0xFF00D4FF);
  static const success  = PdfColor.fromInt(0xFF00C88A);
  static const warning  = PdfColor.fromInt(0xFFFFBB00);
  static const error    = PdfColor.fromInt(0xFFFF4D6D);
  static const white    = PdfColors.white;
  static const white70  = PdfColor.fromInt(0xB3FFFFFF);
  static const textGrey = PdfColor.fromInt(0xFF8892A4);
  static const rowAlt   = PdfColor.fromInt(0xFF131A45);
}

// ─────────────────────────────────────────────────────────────────────────────
// PayrollPdfService
// ─────────────────────────────────────────────────────────────────────────────
class PayrollPdfService {
  PayrollPdfService._();

  /// Entry point — call this from the Export tab's "Generate PDF" button.
  ///
  /// [employee]   — the logged-in Employee model.
  /// [hourlyRate] — peso / hour wage. Falls back to 75.0 if not stored.
  /// [month]      — target month; defaults to current month.
  static Future<void> generate(
      BuildContext context, {
        required Employee employee,
        double hourlyRate = 75.0,
        DateTime? month,
      }) async {
    final target = month ?? DateTime.now();
    final records = await _fetchMonthRecords(employee, target, hourlyRate);
    final bytes   = await _buildPdf(employee, target, records, hourlyRate);

    await Printing.sharePdf(
      bytes: bytes,
      filename: _filename(employee, target),
    );
  }

  // ── fetch ──────────────────────────────────────────────────────────────────
  static Future<List<_DayRecord>> _fetchMonthRecords(
      Employee employee,
      DateTime month,
      double hourlyRate,
      ) async {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay  = DateTime(month.year, month.month + 1, 0);
    final fmt      = DateFormat('yyyy-MM-dd');

    if (kIsWeb) {
      return _fetchFromFirestore(employee, firstDay, lastDay, fmt, hourlyRate);
    } else {
      return _fetchFromLocalDb(employee, firstDay, lastDay, fmt, hourlyRate);
    }
  }

  // ── Firestore (web) ────────────────────────────────────────────────────────
  static Future<List<_DayRecord>> _fetchFromFirestore(
      Employee employee,
      DateTime firstDay,
      DateTime lastDay,
      DateFormat fmt,
      double hourlyRate,
      ) async {
    final firstStr = fmt.format(firstDay);
    final lastStr  = fmt.format(lastDay);

    // attendance_logs collection: each doc has type IN|OUT, date, time
    final snap = await FirebaseFirestore.instance
        .collection('attendance_logs')
        .where('employee_id', isEqualTo: employee.employeeId)
        .where('date', isGreaterThanOrEqualTo: firstStr)
        .where('date', isLessThanOrEqualTo:    lastStr)
        .orderBy('date')
        .orderBy('timestamp')
        .get();

    // Group by date
    final Map<String, Map<String, String?>> byDate = {};
    for (final doc in snap.docs) {
      final d    = doc.data();
      final date = d['date']?.toString() ?? '';
      final type = d['type']?.toString() ?? '';
      final time = d['time']?.toString();
      final meth = d['method']?.toString() ?? 'PIN';

      byDate[date] ??= {'IN': null, 'OUT': null, 'method': meth};
      if (type == 'IN')  byDate[date]!['IN']  = time;
      if (type == 'OUT') byDate[date]!['OUT'] = time;
    }

    return _mapToRecords(byDate, hourlyRate);
  }

  // ── Local SQLite (mobile) ──────────────────────────────────────────────────
  static Future<List<_DayRecord>> _fetchFromLocalDb(
      Employee employee,
      DateTime firstDay,
      DateTime lastDay,
      DateFormat fmt,
      double hourlyRate,
      ) async {
    // getAttendanceByEmployee already orders by date desc; we reverse for asc.
    final history = await DatabaseService.instance
        .getAttendanceByEmployee(employee.id, limit: 100);

    final Map<String, Map<String, String?>> byDate = {};

    for (final att in history) {
      final d = DateTime.tryParse(att.date);
      if (d == null) continue;
      if (d.isBefore(firstDay) || d.isAfter(lastDay)) continue;

      byDate[att.date] ??= {'IN': null, 'OUT': null, 'method': att.method.name};
      byDate[att.date]!['IN']  = att.timeIn;
      byDate[att.date]!['OUT'] = att.timeOut;
    }

    return _mapToRecords(byDate, hourlyRate);
  }

  // ── shared mapper ──────────────────────────────────────────────────────────
  static List<_DayRecord> _mapToRecords(
      Map<String, Map<String, String?>> byDate,
      double hourlyRate,
      ) {
    final records = <_DayRecord>[];

    for (final entry in byDate.entries) {
      final timeIn  = entry.value['IN'];
      final timeOut = entry.value['OUT'];
      final method  = entry.value['method'] ?? 'PIN';
      double hours  = 0.0;

      if (timeIn != null && timeOut != null) {
        try {
          final inDt  = DateFormat('HH:mm:ss').parse(timeIn);
          final outDt = DateFormat('HH:mm:ss').parse(timeOut);
          hours = outDt.difference(inDt).inMinutes / 60.0;
          if (hours < 0) hours = 0;
        } catch (_) {}
      }

      records.add(_DayRecord(
        date        : entry.key,
        timeIn      : timeIn,
        timeOut     : timeOut,
        method      : method.toUpperCase(),
        hoursWorked : hours,
        dailyEarned : hours * hourlyRate,
      ));
    }

    // Sort ascending by date
    records.sort((a, b) => a.date.compareTo(b.date));
    return records;
  }

  // ── PDF builder ────────────────────────────────────────────────────────────
  static Future<Uint8List> _buildPdf(
      Employee employee,
      DateTime month,
      List<_DayRecord> records,
      double hourlyRate,
      ) async {
    final doc = pw.Document(
      title  : 'Payroll Report — ${employee.fullName}',
      author : 'HRIS BioMetrics',
    );

    // Totals
    final totalHours   = records.fold(0.0, (s, r) => s + r.hoursWorked);
    final totalEarned  = records.fold(0.0, (s, r) => s + r.dailyEarned);
    final daysWorked   = records.where((r) => r.hoursWorked > 0).length;
    final currency     = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final monthLabel   = DateFormat('MMMM yyyy').format(month);

    doc.addPage(
      pw.MultiPage(
        pageFormat  : PdfPageFormat.a4,
        margin      : const pw.EdgeInsets.all(36),
        // ── header repeated on every page ──────────────────────────────────
        header      : (ctx) => _pageHeader(employee, monthLabel, ctx),
        // ── footer with page number ────────────────────────────────────────
        footer      : (ctx) => _pageFooter(ctx),
        build       : (ctx) => [
          pw.SizedBox(height: 8),
          // ── summary cards row ───────────────────────────────────────────
          _summaryRow(
            daysWorked   : daysWorked,
            totalHours   : totalHours,
            totalEarned  : totalEarned,
            hourlyRate   : hourlyRate,
            currency     : currency,
          ),
          pw.SizedBox(height: 20),
          // ── attendance table ────────────────────────────────────────────
          _sectionTitle('ATTENDANCE & EARNINGS — $monthLabel'),
          pw.SizedBox(height: 8),
          _attendanceTable(records, currency, hourlyRate),
          pw.SizedBox(height: 20),
          // ── totals row ──────────────────────────────────────────────────
          _totalsBar(totalHours, totalEarned, daysWorked, currency),
          pw.SizedBox(height: 24),
          // ── signature block ─────────────────────────────────────────────
          _signatureBlock(employee),
        ],
      ),
    );

    return doc.save();
  }

  // ── page header ────────────────────────────────────────────────────────────
  static pw.Widget _pageHeader(
      Employee employee, String monthLabel, pw.Context ctx) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          color  : _K.navy,
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child  : pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('HRIS BIOMETRICS',
                    style: pw.TextStyle(
                      color     : _K.accent,
                      fontSize  : 10,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 2,
                    )),
                pw.SizedBox(height: 2),
                pw.Text('Monthly Payroll Report',
                    style: pw.TextStyle(color: _K.white, fontSize: 16,
                        fontWeight: pw.FontWeight.bold)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text(employee.fullName,
                    style: pw.TextStyle(color: _K.white, fontSize: 12,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 2),
                pw.Text('ID: ${employee.employeeId}',
                    style: pw.TextStyle(color: _K.textGrey, fontSize: 9)),
                pw.Text(monthLabel,
                    style: pw.TextStyle(color: _K.accent, fontSize: 9,
                        fontWeight: pw.FontWeight.bold)),
              ]),
            ],
          ),
        ),
        pw.Divider(color: _K.accent, thickness: 2, height: 2),
      ],
    );
  }

  // ── page footer ────────────────────────────────────────────────────────────
  static pw.Widget _pageFooter(pw.Context ctx) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generated ${DateFormat('MMM d, yyyy — hh:mm a').format(DateTime.now())}',
            style: pw.TextStyle(color: _K.textGrey, fontSize: 8),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: pw.TextStyle(color: _K.textGrey, fontSize: 8),
          ),
        ],
      ),
    );
  }

  // ── summary cards ──────────────────────────────────────────────────────────
  static pw.Widget _summaryRow({
    required int    daysWorked,
    required double totalHours,
    required double totalEarned,
    required double hourlyRate,
    required NumberFormat currency,
  }) {
    return pw.Row(
      children: [
        _summaryCard('DAYS WORKED',   '$daysWorked days',
            'This month',              _K.accent),
        pw.SizedBox(width: 10),
        _summaryCard('TOTAL HOURS',   '${totalHours.toStringAsFixed(1)}h',
            'Clocked hours',           _K.success),
        pw.SizedBox(width: 10),
        _summaryCard('HOURLY RATE',   currency.format(hourlyRate),
            'Per hour',                _K.warning),
        pw.SizedBox(width: 10),
        _summaryCard('TOTAL EARNED',  currency.format(totalEarned),
            'Gross pay',               _K.error,   highlight: true),
      ],
    );
  }

  static pw.Widget _summaryCard(
      String label, String value, String sub, PdfColor color,
      {bool highlight = false}) {
    return pw.Expanded(
      child: pw.Container(
        padding   : const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color       : highlight ? color : _K.card,
          borderRadius: pw.BorderRadius.circular(8),
          border      : pw.Border.all(
            color: highlight ? color : PdfColor.fromInt(0xFF1A3356),
            width: highlight ? 0 : 1,
          ),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label,
                style: pw.TextStyle(
                    color    : highlight ? _K.white70 : _K.textGrey,
                    fontSize : 7,
                    fontWeight: pw.FontWeight.bold,
                    letterSpacing: 0.8)),
            pw.SizedBox(height: 4),
            pw.Text(value,
                style: pw.TextStyle(
                    color    : highlight ? _K.white : color,
                    fontSize : 14,
                    fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(sub,
                style: pw.TextStyle(
                    color  : highlight ? _K.white70 : _K.textGrey,
                    fontSize: 7)),
          ],
        ),
      ),
    );
  }

  // ── section title ──────────────────────────────────────────────────────────
  static pw.Widget _sectionTitle(String text) {
    return pw.Row(children: [
      pw.Container(width: 3, height: 14, color: _K.accent),
      pw.SizedBox(width: 6),
      pw.Text(text,
          style: pw.TextStyle(
              color    : _K.textGrey,
              fontSize : 8,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.5)),
    ]);
  }

  // ── attendance table ───────────────────────────────────────────────────────
  static pw.Widget _attendanceTable(
      List<_DayRecord> records, NumberFormat currency, double hourlyRate) {
    final headers = ['DATE', 'DAY', 'CLOCK IN', 'CLOCK OUT', 'HOURS', 'METHOD', 'EARNED'];

    // Column widths (relative flex)
    const widths = [
      pw.FlexColumnWidth(2.2), // date
      pw.FlexColumnWidth(1.4), // day
      pw.FlexColumnWidth(1.8), // clock in
      pw.FlexColumnWidth(1.8), // clock out
      pw.FlexColumnWidth(1.2), // hours
      pw.FlexColumnWidth(1.4), // method
      pw.FlexColumnWidth(2.0), // earned
    ];

    pw.Widget cell(String text, {
      PdfColor? color,
      pw.Alignment align = pw.Alignment.centerLeft,
      bool bold = false,
    }) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          child: pw.Align(
            alignment: align,
            child: pw.Text(text,
                style: pw.TextStyle(
                    color    : color ?? _K.white,
                    fontSize : 8,
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          ),
        );

    // Header row
    final headerRow = pw.TableRow(
      decoration: pw.BoxDecoration(color: _K.navy),
      children  : headers
          .map((h) => cell(h, color: _K.accent, bold: true))
          .toList(),
    );

    // Data rows
    final dataRows = <pw.TableRow>[];
    for (int i = 0; i < records.length; i++) {
      final r      = records[i];
      final isAlt  = i % 2 == 1;
      final date   = DateTime.tryParse(r.date);
      final dayStr = date != null ? DateFormat('EEE').format(date) : '';
      final isWeekend = date != null
          ? (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday)
          : false;

      final hasOut    = r.timeOut != null;
      final earnColor = r.dailyEarned > 0 ? _K.success : _K.textGrey;

      dataRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
          color: isWeekend
              ? PdfColor.fromInt(0xFF1A0A2E)
              : (isAlt ? _K.rowAlt : _K.card),
        ),
        children: [
          cell(date != null ? DateFormat('MMM d, yyyy').format(date) : r.date),
          cell(dayStr,
              color: isWeekend ? _K.warning : _K.white70),
          cell(r.timeIn  != null ? _fmt12(r.timeIn!)  : '—',
              color: _K.success),
          cell(r.timeOut != null ? _fmt12(r.timeOut!) : '—',
              color: hasOut ? _K.error : _K.textGrey),
          cell(r.hoursWorked > 0
              ? '${r.hoursWorked.toStringAsFixed(2)}h' : '—',
              align: pw.Alignment.center),
          cell(r.method, color: _K.accent),
          cell(r.dailyEarned > 0
              ? currency.format(r.dailyEarned) : '—',
              color: earnColor, bold: r.dailyEarned > 0, align: pw.Alignment.centerRight),
        ],
      ));
    }

    if (records.isEmpty) {
      dataRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: _K.card),
        children: List.generate(
          headers.length,
              (i) => i == 0
              ? cell('No attendance records found for this period.',
              color: _K.textGrey)
              : cell(''),
        ),
      ));
    }

    return pw.Table(
      border         : pw.TableBorder.all(color: PdfColor.fromInt(0xFF1A3356), width: 0.5),
      columnWidths   : {for (int i = 0; i < widths.length; i++) i: widths[i]},
      children       : [headerRow, ...dataRows],
    );
  }

  // ── totals bar ─────────────────────────────────────────────────────────────
  static pw.Widget _totalsBar(
      double totalHours, double totalEarned, int daysWorked, NumberFormat currency) {
    return pw.Container(
      padding   : const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        gradient: const pw.LinearGradient(
          colors: [_K.navy, PdfColor.fromInt(0xFF131A45)],
        ),
        borderRadius: pw.BorderRadius.circular(8),
        border      : pw.Border.all(color: PdfColor.fromInt(0xFF00D4FF), width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _totalItem('DAYS WORKED', '$daysWorked', _K.accent),
          _totalDivider(),
          _totalItem('TOTAL HOURS', '${totalHours.toStringAsFixed(2)}h', _K.success),
          _totalDivider(),
          _totalItem('GROSS EARNINGS', currency.format(totalEarned), _K.error,
              large: true),
        ],
      ),
    );
  }

  static pw.Widget _totalItem(String label, String value, PdfColor color,
      {bool large = false}) {
    return pw.Column(children: [
      pw.Text(label,
          style: pw.TextStyle(
              color    : _K.textGrey,
              fontSize : 7,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1)),
      pw.SizedBox(height: 4),
      pw.Text(value,
          style: pw.TextStyle(
              color    : color,
              fontSize : large ? 18 : 14,
              fontWeight: pw.FontWeight.bold)),
    ]);
  }

  static pw.Widget _totalDivider() => pw.Container(
    width : 1,
    height: 36,
    color : PdfColor.fromInt(0xFF1A3356),
  );

  // ── signature block ────────────────────────────────────────────────────────
  static pw.Widget _signatureBlock(Employee employee) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _sigBox('EMPLOYEE SIGNATURE', employee.fullName),
        pw.SizedBox(width: 30),
        _sigBox('HR / SUPERVISOR',    'Authorized Signatory'),
        pw.SizedBox(width: 30),
        _sigBox('DATE PROCESSED',
            DateFormat('MMM d, yyyy').format(DateTime.now())),
      ],
    );
  }

  static pw.Widget _sigBox(String label, String name) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(height: 40,
              decoration: pw.BoxDecoration(
                  border: pw.Border(
                      bottom: pw.BorderSide(
                          color: PdfColor.fromInt(0xFF1A3356), width: 1)))),
          pw.SizedBox(height: 4),
          pw.Text(name,
              style: pw.TextStyle(
                  color: _K.white, fontSize: 8, fontWeight: pw.FontWeight.bold)),
          pw.Text(label,
              style: pw.TextStyle(color: _K.textGrey, fontSize: 7)),
        ],
      ),
    );
  }

  // ── utils ──────────────────────────────────────────────────────────────────
  static String _fmt12(String t) {
    try {
      return DateFormat('hh:mm a').format(DateFormat('HH:mm:ss').parse(t));
    } catch (_) {
      return t;
    }
  }

  static String _filename(Employee employee, DateTime month) {
    final m = DateFormat('yyyy-MM').format(month);
    final n = employee.fullName.replaceAll(RegExp(r'\s+'), '_');
    return 'Payroll_${n}_$m.pdf';
  }
}