import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:pmshri_attendance/services/class_label.dart';

/// Gujarati leave application PDF for the Supabase-backed teacher leave workflow.
/// A report occupies one half of an A4 portrait page. Set perPage=2 to put
/// two applications on one page. Gujarati is rasterized with TextPainter so
/// glyph shaping matches Flutter's own Gujarati rendering.
class SupabaseLeavePdfService {
  SupabaseLeavePdfService._();

  static bool _fontLoaded = false;
  static const double _dpr = 2.0;
  static const String _fontFamily = 'PSMLeaveGujaratiRaster';

  static Future<void> _ensureFontLoaded() async {
    if (_fontLoaded) return;
    final loader = FontLoader(_fontFamily);
    loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'));
    await loader.load();
    _fontLoaded = true;
  }

  static Map<String, dynamic> _data(Map<String, dynamic> row) {
    final value = row['leave_data'];
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  static String _s(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  static DateTime? _date(dynamic value) {
    try {
      final raw = _s(value);
      if (raw.isEmpty) return null;
      return DateTime.parse(raw.length >= 10 ? raw.substring(0, 10) : raw);
    } catch (_) {
      return null;
    }
  }

  static String _dateLabel(dynamic value) {
    final parsed = _date(value);
    return parsed == null
        ? _s(value, '—')
        : DateFormat('dd/MM/yyyy').format(parsed);
  }

  static double totalDays(Map<String, dynamic> row) {
    final data = _data(row);
    final saved = double.tryParse(_s(data['total_days'] ?? data['days']));
    if (saved != null && saved >= 0) return saved;
    final start = _date(row['start_date']);
    final end = _date(row['end_date']);
    if (start == null || end == null || end.isBefore(start)) return 0;
    return end.difference(start).inDays + 1;
  }

  static String _daysLabel(double days) => days == days.roundToDouble()
      ? days.toInt().toString()
      : days.toStringAsFixed(1);

  static String _teacherName(
          Map<String, dynamic> row, Map<String, dynamic> data) =>
      _s(data['teacher_name'] ?? row['teacher_name'], 'શિક્ષક');

  static Future<pw.Widget?> _rasterText(
    String text, {
    required double left,
    required double top,
    required double maxWidth,
    double fontSize = 8,
    bool bold = false,
    int maxLines = 2,
    pw.TextAlign align = pw.TextAlign.left,
  }) async {
    if (text.trim().isEmpty) return null;
    await _ensureFontLoaded();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: fontSize * _dpr,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: Colors.black,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: switch (align) {
        pw.TextAlign.center => TextAlign.center,
        pw.TextAlign.right => TextAlign.right,
        _ => TextAlign.left,
      },
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(
        minWidth: align == pw.TextAlign.center ? maxWidth * _dpr : 0,
        maxWidth: maxWidth * _dpr,
      );

    // A fixed-width canvas is necessary for true visual centering. Without a
    // minWidth, TextPainter collapses to the text's intrinsic width and a
    // center alignment appears left-aligned in the exported PDF.
    final maxPixels = (maxWidth * _dpr).ceil().clamp(1, 10000).toInt();
    final imageWidth = align == pw.TextAlign.center
        ? maxPixels
        : (painter.width.ceil() + 4).clamp(1, maxPixels).toInt();
    final imageHeight = painter.height.ceil() + 4;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder,
        ui.Rect.fromLTWH(0, 0, imageWidth.toDouble(), imageHeight.toDouble()));
    painter.paint(canvas, const ui.Offset(1, 1));
    final picture = recorder.endRecording();
    final image = await picture.toImage(imageWidth, imageHeight);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    if (byteData == null) return null;

    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Image(
        pw.MemoryImage(byteData.buffer.asUint8List()),
        width: imageWidth / _dpr,
        height: imageHeight / _dpr,
        fit: pw.BoxFit.contain,
      ),
    );
  }

  static int _intRule(Map<String, dynamic> rules, String key, int fallback) =>
      rules[key] is int
          ? rules[key] as int
          : int.tryParse('${rules[key]}') ?? fallback;

  static DateTime _periodStart(DateTime date, int startMonth) => DateTime(
      date.month < startMonth ? date.year - 1 : date.year, startMonth, 1);

  static Future<Map<String, dynamic>> _loadLeaveRules() async {
    final defaults = <String, dynamic>{
      'cl_max_days': 12,
      'cl_year_start_month': 6,
      'cl_year_end_month': 5,
      'marajiyat_max_days': 2,
      'marajiyat_year_start_month': 1,
      'marajiyat_year_end_month': 12,
      'valtar_max_days': 0,
      'valtar_start_month': 1,
      'valtar_end_month': 12,
    };
    try {
      final client = Supabase.instance.client;
      final school = _s(await client.rpc('current_school_ref'));
      if (school.isEmpty) return defaults;
      final row = await client
          .from('school_leave_settings')
          .select(
              'cl_year_start_month,cl_year_end_month,cl_max_days,marajiyat_year_start_month,marajiyat_year_end_month,marajiyat_max_days,valtar_start_month,valtar_end_month,valtar_max_days')
          .eq('school_ref', school)
          .maybeSingle();
      return row == null
          ? defaults
          : <String, dynamic>{...defaults, ...Map<String, dynamic>.from(row)};
    } catch (_) {
      return defaults;
    }
  }

  static Map<String, double> _approvedTotalsForTeacher(
    String teacherId,
    Map<String, dynamic> forRecord,
    List<Map<String, dynamic>> history,
    Map<String, dynamic> rules,
  ) {
    double cl = 0, valtar = 0, marajiyat = 0;
    final recordId = _s(forRecord['id']);
    final recordCreated = DateTime.tryParse(_s(forRecord['created_at']));
    final targetDate = _date(forRecord['start_date']) ?? recordCreated;
    if (targetDate == null)
      return <String, double>{'cl': 0, 'valtar': 0, 'marajiyat': 0};
    final clStart = _intRule(rules, 'cl_year_start_month', 6);
    final marajiyatStart = _intRule(rules, 'marajiyat_year_start_month', 1);
    final valtarStart = _intRule(rules, 'valtar_start_month', 1);
    final targetClPeriod = _periodStart(targetDate, clStart);
    final targetMarajiyatPeriod = _periodStart(targetDate, marajiyatStart);
    final targetValtarPeriod = _periodStart(targetDate, valtarStart);
    for (final row in history) {
      if (_s(row['teacher_id']) != teacherId) continue;
      // A request must never count as utilized in its own report.
      if (recordId.isNotEmpty && _s(row['id']) == recordId) continue;
      final status = _s(row['status']).toLowerCase();
      // Only previously approved leave is actually utilized. Pending, rejected,
      // and cancelled applications do not consume the teacher's leave balance.
      if (status != 'approved') continue;
      final created = DateTime.tryParse(_s(row['created_at']));
      if (recordCreated != null && created != null) {
        if (created.isAfter(recordCreated)) continue;
        if (created.isAtSameMomentAs(recordCreated) &&
            _s(row['id']).compareTo(recordId) >= 0) continue;
      }
      final rowDate = _date(row['start_date']);
      final rowEndDate = _date(row['end_date']);
      // Only leave periods fully ended before this application are utilized.
      if (rowDate == null ||
          rowEndDate == null ||
          !rowEndDate.isBefore(targetDate)) continue;
      final type = _s(row['leave_type']).toLowerCase();
      final days = totalDays(row);
      if (type.contains('પ્રાસંગિક') || type.contains('(cl)') || type == 'cl') {
        if (_periodStart(rowDate, clStart) == targetClPeriod) cl += days;
      } else if (type.contains('મરજિયાત') || type.contains('marajiyat')) {
        if (_periodStart(rowDate, marajiyatStart) == targetMarajiyatPeriod)
          marajiyat += days;
      } else if (type.contains('વળતર') || type.contains('valtar')) {
        if (_periodStart(rowDate, valtarStart) == targetValtarPeriod)
          valtar += days;
      }
    }
    return <String, double>{'cl': cl, 'valtar': valtar, 'marajiyat': marajiyat};
  }

  static String _daysToGujaratiWords(double days) {
    final key = _daysLabel(days);
    const values = <String, String>{
      '0.5': '૦.૫ (અડધો)',
      '1': '૧ (એક)',
      '1.5': '૧.૫ (એક અને અડધો)',
      '2': '૨ (બે)',
      '2.5': '૨.૫ (બે અને અડધો)',
      '3': '૩ (ત્રણ)',
      '3.5': '૩.૫ (ત્રણ અને અડધો)',
      '4': '૪ (ચાર)',
      '4.5': '૪.૫ (ચાર અને અડધો)',
      '5': '૫ (પાંચ)',
      '5.5': '૫.૫ (પાંચ અને અડધો)',
      '6': '૬ (છ)',
      '7': '૭ (સાત)',
      '8': '૮ (આઠ)',
      '9': '૯ (નવ)',
      '10': '૧૦ (દસ)',
    };
    return values[key] ??
        key
            .replaceAll('0', '૦')
            .replaceAll('1', '૧')
            .replaceAll('2', '૨')
            .replaceAll('3', '૩')
            .replaceAll('4', '૪')
            .replaceAll('5', '૫')
            .replaceAll('6', '૬')
            .replaceAll('7', '૭')
            .replaceAll('8', '૮')
            .replaceAll('9', '૯');
  }

  /// Uses the project's original leave1/leave2 background templates. The
  /// source artwork is an A4-landscape form (842 x 595 points); scaling it to
  /// half an A4 portrait page retains the exact template proportions.
  static Future<pw.Widget> _form({
    required Map<String, dynamic> row,
    required List<Map<String, dynamic>> history,
    required String schoolName,
    required Map<String, dynamic> leaveRules,
    required double width,
    required double height,
  }) async {
    final data = _data(row);
    final teacherId = _s(row['teacher_id']);
    final teacherName = _teacherName(row, data);
    final teacherClass = _s(data['teacher_class'] ?? data['class_name'], '—');
    final chargeName = _s(data['charge_teacher_name'], '—');
    final chargeClass = _s(data['charge_teacher_class'], '—');
    final rawType = _s(row['leave_type'], 'રજા');
    final leaveType =
        rawType == 'અડધી રજા (Half CL)' ? 'પ્રાસંગિક રજા (CL)' : rawType;
    final reason = _s(row['reason'], '—').replaceAll('કારણસર', '').trim();
    final days = totalDays(row);
    final daysText = _daysToGujaratiWords(days);
    final start = _dateLabel(row['start_date']);
    final end = _dateLabel(row['end_date']);
    final requestedAt = _dateLabel(row['created_at']);
    final storedSnapshotValue =
        row['utilized_leave_snapshot'] ?? _data(row)['utilized_leave_snapshot'];
    final storedSnapshot = storedSnapshotValue is Map
        ? storedSnapshotValue.map(
            (key, value) => MapEntry<String, dynamic>(key.toString(), value))
        : <String, dynamic>{};
    // The saved snapshot is authoritative for all later reprints. If an older
    // record has no snapshot yet, use the corrected date-wise fallback calculation.
    final totals = storedSnapshot.isNotEmpty
        ? <String, double>{
            'cl': double.tryParse(_s(storedSnapshot['cl'], '0')) ?? 0,
            'valtar': double.tryParse(_s(storedSnapshot['valtar'], '0')) ?? 0,
            'marajiyat':
                double.tryParse(_s(storedSnapshot['marajiyat'], '0')) ?? 0,
          }
        : _approvedTotalsForTeacher(teacherId, row, history, leaveRules);
    final clText = _daysLabel(totals['cl'] ?? 0)
        .replaceAll('0', '૦')
        .replaceAll('1', '૧')
        .replaceAll('2', '૨')
        .replaceAll('3', '૩')
        .replaceAll('4', '૪')
        .replaceAll('5', '૫')
        .replaceAll('6', '૬')
        .replaceAll('7', '૭')
        .replaceAll('8', '૮')
        .replaceAll('9', '૯');
    final valtarText = _daysLabel(totals['valtar'] ?? 0)
        .replaceAll('0', '૦')
        .replaceAll('1', '૧')
        .replaceAll('2', '૨')
        .replaceAll('3', '૩')
        .replaceAll('4', '૪')
        .replaceAll('5', '૫')
        .replaceAll('6', '૬')
        .replaceAll('7', '૭')
        .replaceAll('8', '૮')
        .replaceAll('9', '૯');
    final marajiyatText = _daysLabel(totals['marajiyat'] ?? 0)
        .replaceAll('0', '૦')
        .replaceAll('1', '૧')
        .replaceAll('2', '૨')
        .replaceAll('3', '૩')
        .replaceAll('4', '૪')
        .replaceAll('5', '૫')
        .replaceAll('6', '૬')
        .replaceAll('7', '૭')
        .replaceAll('8', '૮')
        .replaceAll('9', '૯');

    final startDate = _date(row['start_date']);
    final endDate = _date(row['end_date']);
    final isSingleDate = startDate != null &&
        endDate != null &&
        startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day;
    final bgData = await rootBundle.load(
        isSingleDate ? 'assets/images/leave1.jpg' : 'assets/images/leave2.jpg');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    // The legacy certificate service places values on this same template in
    // A4 landscape coordinates. Scale all positions and font sizes together.
    const baseWidth = 842.0;
    final scale = width / baseWidth;
    final widgets = <pw.Widget>[
      pw.Positioned(
        left: 0,
        top: 0,
        child: pw.Image(bgImage,
            width: width, height: height, fit: pw.BoxFit.fill),
      ),
    ];

    Future<void> add(String text, double top, double left,
        {double size = 15,
        double maxWidth = 240,
        int lines = 1,
        bool bold = true,
        bool autoFit = false,
        pw.TextAlign align = pw.TextAlign.left}) async {
      if (autoFit && text.runes.length > 24) {
        size = (size * 24 / text.runes.length).clamp(7.0, size).toDouble();
      }
      final image = await _rasterText(
        text,
        left: left * scale,
        top: top * scale,
        maxWidth: maxWidth * scale,
        fontSize: size * scale,
        bold: bold,
        maxLines: lines,
        align: align,
      );
      if (image != null) widgets.add(image);
    }

    // The original template image had the old school's Gujarati name printed
    // into its pixels twice. Cover only those two text areas so each registered
    // school receives its own Gujarati name in the addressee and Head Teacher
    // signature block below.
    widgets.addAll(<pw.Widget>[
      pw.Positioned(
        left: 74 * scale,
        top: 217 * scale,
        child: pw.Container(
          width: 160 * scale,
          height: 23 * scale,
          color: PdfColors.white,
        ),
      ),
      pw.Positioned(
        left: 369 * scale,
        top: 545 * scale,
        child: pw.Container(
          width: 117 * scale,
          height: 18 * scale,
          color: PdfColors.white,
        ),
      ),
    ]);

    final rawClass = ClassLabel.bare(teacherClass);
    await add('નામ :- $teacherName', 75, 580, maxWidth: 245);
    await add('હોદ્દો :- મદદનીશ શિક્ષક', 100, 580, maxWidth: 245);
    await add('શાળા :- $schoolName', 125, 580,
        maxWidth: 245, size: 13, autoFit: true);
    await add('ધોરણ :- $rawClass', 150, 580, maxWidth: 245);
    await add('તારીખ :- $requestedAt', 175, 580, maxWidth: 245);
    // Dynamic Gujarati school name on the address block under મુખ્ય શિક્ષક.
    await add(schoolName, 220, 79, maxWidth: 200, size: 14);
    await add('$daysText દિવસની $leaveType મંજૂર કરવા બાબત.', 243, 205,
        maxWidth: 590, lines: 2);
    await add(clText, 334, 203, maxWidth: 62);
    await add(valtarText, 334, 313, maxWidth: 62);
    await add(marajiyatText, 334, 455, maxWidth: 62);
    await add(chargeName, 380, 230, maxWidth: 390);
    await add(chargeClass, 380, 655, maxWidth: 110);
    // Center the applicant's name directly beneath the pre-printed આપનો વિશ્વાસુ.
    await add(
      teacherName,
      480,
      585,
      maxWidth: 230,
      size: 15,
      align: pw.TextAlign.center,
    );
    // Keep the Head Teacher label from the template and print the registered
    // Gujarati school name centered immediately beneath it.
    await add(
      schoolName,
      549,
      306,
      maxWidth: 230,
      size: 14,
      align: pw.TextAlign.center,
    );
    await add(reason, 265, 550, maxWidth: 265, lines: 2);
    if (isSingleDate) {
      await add(start, 292, 157, maxWidth: 125);
      await add(daysText, 310, 100, maxWidth: 150);
      await add(leaveType, 310, 256, maxWidth: 260);
    } else {
      await add(start, 292, 157, maxWidth: 145);
      await add(end, 292, 380, maxWidth: 145);
      await add(daysText, 310, 100, maxWidth: 150);
      await add(leaveType, 310, 256, maxWidth: 260);
    }
    // The half-day period remains stored for the application workflow, but is
    // deliberately not printed: it overlapped the pre-printed used-leave line.
    // Approval/admin notes remain in the application register and Excel export;
    // they are not overlaid on the printed application template.

    return pw.SizedBox(
      width: width,
      height: height,
      child: pw.Stack(fit: pw.StackFit.expand, children: widgets),
    );
  }

  /// Prints each selected application in A4 portrait. perPage=1 creates one
  /// half-page form per sheet; perPage=2 places two half-page forms per sheet.
  static Future<void> printRequests({
    required List<Map<String, dynamic>> records,
    required List<Map<String, dynamic>> history,
    required String schoolName,
    int perPage = 1,
    String fileName = 'Teacher_Leave_Report.pdf',
  }) async {
    if (records.isEmpty) throw StateError('PDF બનાવવા માટે રજા અરજી પસંદ કરો.');
    if (perPage != 1 && perPage != 2)
      throw ArgumentError.value(perPage, 'perPage', 'Must be 1 or 2.');

    final doc = pw.Document();
    final leaveRules = await _loadLeaveRules();
    final orderedRecords = records.toList()
      ..sort((a, b) {
        final aCreated = DateTime.tryParse(_s(a['created_at'])) ??
            _date(a['start_date']) ??
            DateTime(1900);
        final bCreated = DateTime.tryParse(_s(b['created_at'])) ??
            _date(b['start_date']) ??
            DateTime(1900);
        return aCreated.compareTo(bCreated);
      });
    const margin = 8.0;
    const gap = 8.0;
    final pageWidth = PdfPageFormat.a4.width - margin * 2;
    final formHeight = (PdfPageFormat.a4.height - margin * 2 - gap) / 2;
    final rowsPerPage = perPage;

    for (var offset = 0;
        offset < orderedRecords.length;
        offset += rowsPerPage) {
      final pageRows = orderedRecords.skip(offset).take(rowsPerPage).toList();
      final positioned = <pw.Widget>[];
      for (var i = 0; i < pageRows.length; i++) {
        final form = await _form(
          row: pageRows[i],
          history: history,
          schoolName: schoolName,
          leaveRules: leaveRules,
          width: pageWidth,
          height: formHeight,
        );
        positioned.add(pw.Positioned(
          left: 0,
          top: i * (formHeight + gap),
          child: form,
        ));
      }
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(margin),
        build: (_) => pw.Stack(fit: pw.StackFit.expand, children: positioned),
      ));
    }

    final bytes = await doc.save();
    await Printing.layoutPdf(
      name: fileName,
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }
}
