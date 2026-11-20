import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../models/models.dart';
import 'school_name_language_service.dart';
import 'package:pmshri_attendance/services/class_label.dart';

class CertificateService {
  static bool _fontLoaded = false;

  static Future<void> _ensureFontLoaded() async {
    if (_fontLoaded) return;
    try {
      final loader = FontLoader('NotoSansGujaratiLocal');
      loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'));
      await loader.load();
    } catch (_) {
      // Older installs may only bundle Lohit Gujarati. Keep a real Gujarati
      // font fallback rather than rendering missing-glyph squares.
      final fallback = FontLoader('NotoSansGujaratiLocal');
      fallback.addFont(rootBundle.load('assets/fonts/Lohit-Gujarati.ttf'));
      await fallback.load();
    }
    _fontLoaded = true;
  }

  static Future<pw.Widget> _guText(String? text, double top, double left,
      {double size = 16}) async {
    if (text == null) return pw.SizedBox();
    String cleanText = text.replaceAll('null', '').trim();
    if (cleanText.isEmpty) return pw.SizedBox();

    await _ensureFontLoaded();

    const double dpr = 2.0;
    final tp = TextPainter(
      text: TextSpan(
        text: cleanText,
        style: TextStyle(
          fontFamily: 'NotoSansGujaratiLocal',
          fontSize: size * dpr,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final imgW = (tp.width.ceil() + 2);
    final imgH = (tp.height.ceil() + 2);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()));
    tp.paint(canvas, const ui.Offset(1, 1));

    final picture = recorder.endRecording();
    final img = await picture.toImage(imgW, imgH);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    picture.dispose();

    if (byteData == null) return pw.SizedBox();
    final memoryImage = pw.MemoryImage(byteData.buffer.asUint8List());

    return pw.Positioned(
      top: top,
      left: left,
      child: pw.Image(memoryImage, width: imgW / dpr, height: imgH / dpr),
    );
  }

  static String _metaValue(Map<String, dynamic> meta, List<String> keys) {
    String norm(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0A80-\u0AFF]'), '');
    for (final key in keys) {
      final direct = (meta[key] ?? '').toString().trim();
      if (direct.isNotEmpty && direct.toLowerCase() != 'null') return direct;
      final target = norm(key);
      for (final entry in meta.entries) {
        if (norm(entry.key) != target) continue;
        final value = (entry.value ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
    }
    return '';
  }

  static String _studentField(StudentRecord student, List<String> keys) {
    String norm(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0A80-\u0AFF]'), '');
    for (final key in keys) {
      final direct = (student.customFields[key] ?? '').trim();
      if (direct.isNotEmpty && direct.toLowerCase() != 'null') return direct;
      final target = norm(key);
      for (final entry in student.customFields.entries) {
        if (norm(entry.key) != target) continue;
        final value = entry.value.trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
    }
    return '';
  }

  static pw.Widget _mask(
    double top,
    double left,
    double width,
    double height,
    PdfColor color,
  ) {
    return pw.Positioned(
      top: top,
      left: left,
      child: pw.Container(width: width, height: height, color: color),
    );
  }

  /// Renders a one-line Gujarati/English value centered inside a fixed PDF box.
  /// It reduces font size when a long school name would otherwise run into
  /// neighboring fields in the supplied certificate template.
  static Future<pw.Widget> _guTextBoxAligned(
    String? text,
    double top,
    double left,
    double width, {
    double size = 16,
    double minSize = 6.0,
    TextAlign align = TextAlign.center,
  }) async {
    if (text == null || text.trim().isEmpty) return pw.SizedBox();
    await _ensureFontLoaded();
    const double dpr = 2.0;
    final cleanText = text.replaceAll('null', '').trim();
    if (cleanText.isEmpty) return pw.SizedBox();
    final maxW = width * dpr;
    double fontSize = size * dpr;
    TextPainter painter = TextPainter(
      text: TextSpan(
        text: cleanText,
        style: TextStyle(
          fontFamily: 'NotoSansGujaratiLocal',
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.black,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final minFontSize = minSize * dpr;
    while (painter.width > maxW && fontSize > minFontSize) {
      fontSize -= 0.75;
      painter = TextPainter(
        text: TextSpan(
          text: cleanText,
          style: TextStyle(
            fontFamily: 'NotoSansGujaratiLocal',
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
        maxLines: 1,
      )..layout();
    }
    final imgW = maxW.ceil();
    final imgH = (painter.height.ceil() + 4);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, imgW.toDouble(), imgH.toDouble()),
    );
    double dx = 0;
    if (align == TextAlign.center) {
      dx = ((maxW - painter.width) / 2.0).clamp(0.0, maxW);
    } else if (align == TextAlign.right) {
      dx = (maxW - painter.width).clamp(0.0, maxW);
    }
    painter.paint(canvas, ui.Offset(dx, 2));
    final picture = recorder.endRecording();
    final img = await picture.toImage(imgW, imgH);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    picture.dispose();
    if (byteData == null) return pw.SizedBox();
    return pw.Positioned(
      top: top,
      left: left,
      child: pw.Image(
        pw.MemoryImage(byteData.buffer.asUint8List()),
        width: width,
        height: imgH / dpr,
      ),
    );
  }

  static Future<pw.Widget> _guTextBoxCentered(
    String? text,
    double top,
    double left,
    double width, {
    double size = 16,
    double minSize = 6.0,
  }) =>
      _guTextBoxAligned(
        text,
        top,
        left,
        width,
        size: size,
        minSize: minSize,
        align: TextAlign.center,
      );

  static String _toAsciiDigits(String input) {
    const guDigits = '૦૧૨૩૪૫૬૭૮૯';
    final buf = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final idx = guDigits.indexOf(ch);
      if (idx >= 0) {
        buf.write(idx);
      } else {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  static String _certificateSchoolGujarati(Map<String, dynamic> meta) =>
      _metaValue(meta, const [
        'school_name_gu',
        'schoolNameGu',
        'school_name_gj',
        'gujarati_school_name',
        'schoolNameGujarati',
        'school_name',
        'schoolName',
      ]);

  static String _certificateSchoolEnglish(Map<String, dynamic> meta) =>
      _metaValue(meta, const [
        'school_name_en',
        'schoolNameEn',
        'school_name',
        'schoolName',
        'name',
      ]);

  static String _certificateAddressGujarati(Map<String, dynamic> meta) {
    final address = _metaValue(meta, const [
      'school_address_gu',
      'schoolAddressGu',
      'address_gu',
      'addressGujarati',
      'school_address',
      'schoolAddress',
    ]);
    if (address.isNotEmpty) return address;
    return [
      _metaValue(meta, const ['village', 'village_name', 'villageName']),
      _metaValue(meta, const ['taluka', 'taluka_name', 'talukaName']),
      _metaValue(meta, const ['district', 'district_name', 'districtName']),
    ].where((value) => value.isNotEmpty).join('، ');
  }

  static String _certificateAddressEnglish(Map<String, dynamic> meta) {
    final address = _metaValue(meta, const [
      'school_address_en',
      'schoolAddressEn',
      'address_en',
      'addressEnglish',
    ]);
    if (address.isNotEmpty) return address;
    return [
      _metaValue(meta, const ['village', 'village_name', 'villageName']),
      _metaValue(meta, const ['taluka', 'taluka_name', 'talukaName']),
      _metaValue(meta, const ['district', 'district_name', 'districtName']),
    ].where((value) => value.isNotEmpty).join(', ');
  }

  static String _formatClassName(String rawClass) {
    String c = _toAsciiDigits(rawClass)
        .trim()
        .replaceFirst(RegExp(r'^ધોરણ\s*-?\s*'), '')
        .replaceFirst(RegExp(r'^STD\.?\s*-?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^Class\s*', caseSensitive: false), '')
        .trim();
    final match = RegExp(
      r'^(BALVATIKA|બાલવાટિકા|\d+)\s*[-_ ]?\s*([A-Da-dઅબકડ])$',
      caseSensitive: false,
    ).firstMatch(c);
    if (match == null) {
      return c.toUpperCase() == 'BALVATIKA' ? 'બાલવાટિકા' : c;
    }
    final grade = match.group(1)!;
    final section = switch (match.group(2)!.toUpperCase()) {
      'A' || 'અ' => 'અ',
      'B' || 'બ' => 'બ',
      'C' || 'ક' => 'ક',
      'D' || 'ડ' => 'ડ',
      _ => match.group(2)!,
    };
    final displayGrade =
        grade.toUpperCase() == 'BALVATIKA' || grade == 'બાલવાટિકા'
            ? 'બાલવાટિકા'
            : _toAsciiDigits(grade);
    return '$displayGrade - $section';
  }

  static String _formatDate(String dd, String mm, String yyyy) {
    final d = _toAsciiDigits(dd.trim());
    final m = _toAsciiDigits(mm.trim());
    final y = _toAsciiDigits(yyyy.trim());
    if (d.isEmpty && m.isEmpty && y.isEmpty) return '';
    return '${d.padLeft(2, '0')}/${m.padLeft(2, '0')}/$y';
  }

  static String _twoDigitsOrBlank(String value) =>
      value.trim().isEmpty ? '' : value.trim().padLeft(2, '0');

  static String _displayCertificateDate(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return '';
    final parsed = DateTime.tryParse(clean);
    if (parsed != null) return DateFormat('dd/MM/yyyy').format(parsed);
    return clean;
  }

  static Future<String> _resolveBonafideSchoolNameGu(
    Map<String, dynamic> schoolMeta,
  ) async {
    var name = _certificateSchoolGujarati(schoolMeta);
    if (name.isNotEmpty) return name;
    try {
      final ctx = await SchoolNameLanguageService.loadCurrentSchoolContext(
        Supabase.instance.client,
      );
      name = _certificateSchoolGujarati(ctx);
      if (name.isNotEmpty) return name;
      name = _certificateSchoolEnglish(ctx);
    } catch (_) {}
    return name;
  }

  // =========================================================================
  // 1. બલ્ક બોનાફાઈડ
  // =========================================================================
  static Future<void> generateBulkBonafide({
    required List<StudentRecord> students,
    required String className,
    bool printCategory = false,
    Map<String, dynamic> schoolMeta = const <String, dynamic>{},
  }) async {
    if (students.isEmpty) {
      throw ArgumentError('બોનાફાઈડ માટે ઓછામાં ઓછો એક વિદ્યાર્થી પસંદ કરો.');
    }
    final doc = pw.Document();
    final bgData = await rootBundle.load('assets/images/bonafide.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    final today = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final displayClass = _formatClassName(className);
    final schoolNameGu = await _resolveBonafideSchoolNameGu(schoolMeta);

    Future<pw.Widget> buildSingleBonafideCard(StudentRecord student) async {
      String casteText = student.caste.trim();
      final religion = _studentField(student, const ['religion', 'ધર્મ']);
      if (printCategory && student.category.shortLabel.isNotEmpty) {
        if (casteText.isNotEmpty) casteText += ' --- ';
        casteText += student.category.shortLabel;
      }
      if (religion.isNotEmpty && !casteText.contains(religion)) {
        casteText = casteText.isEmpty ? religion : '$religion — $casteText';
      }

      final pageWidgets = <pw.Widget>[
        pw.Image(bgImage, fit: pw.BoxFit.fill),
        if (schoolNameGu.isNotEmpty) ...<pw.Widget>[
          // Top header school name centered above "બોનાફાઈડ સર્ટીફીકેટ"
          await _guTextBoxAligned(
            schoolNameGu,
            50,
            170,
            490,
            size: 19.5,
            align: TextAlign.center,
          ),
          // 1. First sentence: "આથી [શાળાનું નામ]" right-aligned before "માંથી બોનાફાઈડ..."
          await _guTextBoxAligned(
            'આથી $schoolNameGu',
            218.5,
            40,
            398,
            size: 17.5,
            align: TextAlign.right,
          ),
          // 2. Second sentence: "એ [શાળાનું નામ] માં" on the right side of the student name line
          await _guTextBoxAligned(
            'એ $schoolNameGu માં',
            252,
            508,
            312,
            size: 17.5,
            align: TextAlign.center,
          ),
          // 3. Place: સ્થળ:- [શાળાનું નામ]
          await _guTextBoxAligned(
            schoolNameGu,
            509,
            115,
            340,
            size: 16.5,
            align: TextAlign.left,
          ),
          // 4. Principal block: [શાળાનું નામ] centered directly below "મુખ્ય શિક્ષક"
          await _guTextBoxAligned(
            schoolNameGu,
            534,
            596,
            270,
            size: 13.5,
            align: TextAlign.center,
          ),
        ],
        // Student fields positioned on the dotted lines matching image_891341.png
        await _guTextBoxAligned(
          student.name,
          248,
          60,
          435,
          size: 22,
          align: TextAlign.center,
        ),
        await _guTextBoxAligned(
          displayClass,
          288,
          106,
          92,
          size: 18.5,
          align: TextAlign.center,
        ),
        await _guTextBoxAligned(
          _toAsciiDigits(student.gr),
          325,
          106,
          92,
          size: 18.5,
          align: TextAlign.center,
        ),
        await _guTextBoxAligned(
          _formatDate(student.dd, student.mm, student.yyyy),
          325,
          630,
          190,
          size: 18.5,
          align: TextAlign.center,
        ),
        await _guTextBoxAligned(
          student.dobWords,
          362,
          108,
          452,
          size: 18,
          align: TextAlign.center,
        ),
        await _guTextBoxAligned(
          casteText,
          399,
          108,
          270,
          size: 18,
          align: TextAlign.center,
        ),
        await _guTextBoxAligned(
          today,
          538,
          115,
          200,
          size: 18,
          align: TextAlign.left,
        ),
      ];

      return pw.FittedBox(
        fit: pw.BoxFit.contain,
        child: pw.SizedBox(
          width: PdfPageFormat.a4.landscape.width,
          height: PdfPageFormat.a4.landscape.height,
          child: pw.Stack(
            fit: pw.StackFit.expand,
            children: pageWidgets,
          ),
        ),
      );
    }

    final halfHeight = PdfPageFormat.a4.height / 2.0;
    final pageWidth = PdfPageFormat.a4.width;

    for (var i = 0; i < students.length; i += 2) {
      final topCard = await buildSingleBonafideCard(students[i]);
      final bottomCard = (i + 1 < students.length)
          ? await buildSingleBonafideCard(students[i + 1])
          : null;

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) => pw.Column(
            mainAxisSize: pw.MainAxisSize.max,
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: <pw.Widget>[
              pw.Container(
                width: pageWidth,
                height: halfHeight,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                alignment: pw.Alignment.center,
                child: topCard,
              ),
              pw.Container(
                width: pageWidth,
                height: halfHeight,
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                alignment: pw.Alignment.center,
                child: bottomCard ?? pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    final bytes = await doc.save();
    await Printing.layoutPdf(
      name: '${className}_Bonafide.pdf',
      format: PdfPageFormat.a4,
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

// =========================================================================
  // 2. બલ્ક LC
  // =========================================================================
  static bool _isBalvatikaClass(String value) {
    final v = value.trim().toLowerCase();
    return v.contains('બાલવાટિકા') ||
        v.contains('બાલવાટીકા') ||
        v.contains('balvatika') ||
        v.contains('balwatika');
  }

  static String _cleanClassToken(String raw) {
    return raw
        .trim()
        .replaceFirst(
          RegExp(
            r'^(?:ધોરણ|ધો\.?|std\.?|standard|class)\s*[:-]?\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static String _getGujClassWords(String cName) {
    final normalized = _toAsciiDigits(cName);
    if (normalized.contains('1')) return 'પહેલું';
    if (normalized.contains('2')) return 'બીજું';
    if (normalized.contains('3')) return 'ત્રીજું';
    if (normalized.contains('4')) return 'ચોથું';
    if (normalized.contains('5')) return 'પાંચમું';
    if (normalized.contains('6')) return 'છઠ્ઠું';
    if (normalized.contains('7')) return 'સાતમું';
    if (normalized.contains('8')) return 'આઠમું';
    if (_isBalvatikaClass(cName)) return 'બાલવાટિકા';
    return '';
  }

  static String _getEngClassWords(String cName) {
    final normalized = _toAsciiDigits(cName);
    if (normalized.contains('1')) return 'FIRST';
    if (normalized.contains('2')) return 'SECOND';
    if (normalized.contains('3')) return 'THIRD';
    if (normalized.contains('4')) return 'FOURTH';
    if (normalized.contains('5')) return 'FIFTH';
    if (normalized.contains('6')) return 'SIXTH';
    if (normalized.contains('7')) return 'SEVENTH';
    if (normalized.contains('8')) return 'EIGHTH';
    if (_isBalvatikaClass(cName)) return 'BALVATIKA';
    return '';
  }

  static String _inferReligionEnglish(
    String religionGu,
    String casteGu,
    String explicitReligionEn,
  ) {
    if (explicitReligionEn.trim().isNotEmpty) {
      return explicitReligionEn.trim();
    }
    final combined = '${religionGu.trim()} ${casteGu.trim()}'.toLowerCase();
    if (combined.contains('હિન્દુ') ||
        combined.contains('હિંદુ') ||
        combined.contains('hindu')) {
      return 'HINDU';
    }
    if (combined.contains('મુસ્લિમ') ||
        combined.contains('ઇસ્લામ') ||
        combined.contains('muslim') ||
        combined.contains('islam')) {
      return 'MUSLIM';
    }
    if (combined.contains('જૈન') || combined.contains('jain')) {
      return 'JAIN';
    }
    if (combined.contains('ખ્રિસ્તી') ||
        combined.contains('ક્રિશ્ચિયન') ||
        combined.contains('christian')) {
      return 'CHRISTIAN';
    }
    if (combined.contains('શીખ') ||
        combined.contains('સિખ') ||
        combined.contains('sikh')) {
      return 'SIKH';
    }
    if (combined.contains('બૌદ્ધ') || combined.contains('buddh')) {
      return 'BUDDHIST';
    }
    if (combined.contains('પારસી') || combined.contains('parsi')) {
      return 'PARSI';
    }
    return '';
  }

  static const Map<String, String> predefinedLcReasons = <String, String>{
    'અન્યત્ર અભ્યાસાર્થે જતાં': 'GOING ELSEWHERE FOR STUDY',
    'સહપરિવાર સ્થળાંતર થતાં': 'MIGRATING WITH FAMILY',
    'અન્યત્ર રહેવા જવાથી': 'SHIFTING TO ANOTHER PLACE',
    'વતનમાં જતાં': 'GOING TO NATIVE PLACE',
    'બહાર ગામ જતાં': 'RELOCATING TO ANOTHER VILLAGE/TOWN',
    'વાલીની ઇચ્છાથી': 'BY PARENTS WISH',
    'આ શાળામાં ધોરણ 9 ન હોવાથી': 'STD. 9 IS NOT AVAILABLE IN THIS SCHOOL',
  };

  // Match the special exit reason from the previous CertificateService
  // implementation. Support both ASCII and Gujarati digit 9 and extra spaces.
  static bool _isSchoolHasNoStandardNineReason(String reason) {
    final normalized = reason.trim().replaceAll(RegExp(r'\s+'), ' ');
    return normalized == 'આ શાળામાં ધોરણ 9 ન હોવાથી' ||
        normalized == 'આ શાળામાં ધોરણ ૯ ન હોવાથી';
  }

  static Future<void> generateBulkLC({
    required List<StudentRecord> students,
    required String className,
    bool printCategory = true,
    String leaveReasonGu = '',
    String leaveReasonEn = '',
    String lcDate = '',
    bool preferStudentLeavingDate = true,
    Map<String, dynamic> schoolMeta = const <String, dynamic>{},
    int? certificateStartNumber,
    String certificateNo = '',
    String progressGu = '',
    String progressEn = '',
    String conductGu = '',
    String conductEn = '',
    String remarksGu = '',
    String remarksEn = '',
    Map<String, int?>? presentDaysByStudentId,
    bool leavePresentDaysBlank = false,
  }) async {
    if (students.isEmpty) {
      throw ArgumentError('LC માટે ઓછામાં ઓછો એક વિદ્યાર્થી પસંદ કરો.');
    }
    final doc = pw.Document();
    final bgData = await rootBundle.load('assets/images/lc.png');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());
    final finalLcDate = lcDate.isNotEmpty
        ? lcDate
        : DateFormat('dd/MM/yyyy').format(DateTime.now());

    final schoolNameGu = _certificateSchoolGujarati(schoolMeta);
    final schoolNameEn = _certificateSchoolEnglish(schoolMeta);
    final schoolAddressGu = _certificateAddressGujarati(schoolMeta);
    final schoolAddressEn = _certificateAddressEnglish(schoolMeta);
    final diseCode = _metaValue(schoolMeta, const [
      'school_id',
      'schoolId',
      'diseCode',
      'schoolDiseCode',
      'dise_number',
      'diseNumber',
      'udise',
      'udise_code',
      'school_code',
    ]);


    for (var studentIndex = 0; studentIndex < students.length; studentIndex++) {
      final student = students[studentIndex];
      String casteText = student.caste.trim();
      final religion = _studentField(student, const ['religion', 'ધર્મ']);
      if (printCategory && student.category.shortLabel.isNotEmpty) {
        if (casteText.isNotEmpty) casteText += ' --- ';
        casteText += student.category.shortLabel;
      }
      if (religion.isNotEmpty && !casteText.contains(religion)) {
        casteText = casteText.isEmpty ? religion : '$religion — $casteText';
      }
      final rawReligionEn = _studentField(student, const [
        'religion_en',
        'religionEn',
        'religion_english',
        'ધર્મ ઇંગ્લિશ',
      ]);
      final religionEn = _inferReligionEnglish(
        religion,
        student.caste,
        rawReligionEn,
      );
      String casteTextEn = student.casteEn.trim();
      final catEnLabel = student.catEn.trim().isNotEmpty
          ? student.catEn.trim()
          : (student.category != Category.other ? student.category.apiKey : '');
      if (printCategory && catEnLabel.isNotEmpty) {
        if (casteTextEn.isNotEmpty) casteTextEn += ' --- ';
        casteTextEn += catEnLabel;
      }
      if (religionEn.isNotEmpty &&
          !casteTextEn.toLowerCase().contains(religionEn.toLowerCase())) {
        casteTextEn =
            casteTextEn.isEmpty ? religionEn : '$religionEn — $casteTextEn';
      }

      var apaarId = _studentField(student, const [
        'apaar_id',
        'apaarId',
        'apa ar id',
      ]);
      if (apaarId.isEmpty &&
          RegExp(r'^\d{8,}$')
              .hasMatch(_toAsciiDigits(student.enrollSchClassWordsEn.trim()))) {
        apaarId = _toAsciiDigits(student.enrollSchClassWordsEn.trim());
      }
      final nativePlace = _studentField(student, const [
        'native_place',
        'nativePlace',
        'વતન',
        'c1',
      ]);
      final nativePlaceEn = _studentField(student, const [
        'native_place_en',
        'nativePlaceEn',
        'native_place_english',
        'c2',
      ]);
      String presentDays = '';
      if (!leavePresentDaysBlank) {
        if (presentDaysByStudentId != null) {
          final overrideVal = presentDaysByStudentId[student.id];
          presentDays =
              (overrideVal != null && overrideVal > 0) ? '$overrideVal' : '';
        } else {
          final rawPres = _toAsciiDigits(_studentField(student, const [
            'present_days',
            'presentDays',
            'હાજર દિવસો',
          ])).trim();
          final parsedPres = int.tryParse(rawPres);
          presentDays = (rawPres.isNotEmpty &&
                  rawPres != '0' &&
                  (parsedPres == null || parsedPres > 0))
              ? rawPres
              : '';
        }
      }
      final studentDateFromDb = _studentField(student, const [
        'date_of_leaving',
        'dateOfLeaving',
        'leaving_date',
        'leavingDate',
        'leave_date',
        'lc_date',
        'lcDate',
        'શાળા છોડ્યાની તારીખ',
      ]);
      final rawLeaveReasonGu = leaveReasonGu.trim().isNotEmpty
          ? leaveReasonGu.trim()
          : _studentField(student, const [
              'leave_reason_gu',
              'leaving_reason_gu',
              'reason_for_leaving',
              'reason_of_leaving',
              'શાળા છોડવાનું કારણ',
            ]);
      final studentLcDate =
          _isSchoolHasNoStandardNineReason(rawLeaveReasonGu)
              ? finalLcDate
              : (preferStudentLeavingDate && studentDateFromDb.isNotEmpty
                  ? _displayCertificateDate(studentDateFromDb)
                  : finalLcDate);
      final resolvedLeaveReasonGu = rawLeaveReasonGu;
      var resolvedLeaveReasonEn = leaveReasonEn.trim().isNotEmpty
          ? leaveReasonEn.trim()
          : _studentField(student, const [
              'leave_reason_en',
              'leaving_reason_en',
              'reason_for_leaving_en',
              'reason_of_leaving_en',
            ]);
      if (resolvedLeaveReasonEn.isEmpty && resolvedLeaveReasonGu.isNotEmpty) {
        resolvedLeaveReasonEn =
            predefinedLcReasons[resolvedLeaveReasonGu] ??
            (_isSchoolHasNoStandardNineReason(resolvedLeaveReasonGu)
                ? 'STD. 9 IS NOT AVAILABLE IN THIS SCHOOL'
                : '');
      }

      // Row 8: Date of Admission (with Class)
      String admGuj = '';
      String admEng = '';
      if (student.enrollSchool.trim().isNotEmpty) {
        final admDateGu = student.enrollSchool.trim();
        final admDateEn = _toAsciiDigits(admDateGu);
        final isEnrollBalvatika = _isBalvatikaClass(student.enrollSchClass) ||
            _isBalvatikaClass(student.enrollSchClassEn) ||
            _isBalvatikaClass(student.enrollSchClassWords);
        if (isEnrollBalvatika) {
          // Do NOT repeat Balvatika in brackets in Row 8
          admGuj = 'તારીખ - $admDateGu ને ધોરણ - બાલવાટિકા';
          admEng = 'ON $admDateEn IN CLASS BALVATIKA';
        } else {
          final enrollClassGu = _cleanClassToken(student.enrollSchClass);
          final rawWordsGu = student.enrollSchClassWords.trim();
          final enrollWordsGu = (rawWordsGu.isNotEmpty &&
                  !RegExp(r'^\d+$').hasMatch(_toAsciiDigits(rawWordsGu)) &&
                  !_isBalvatikaClass(rawWordsGu))
              ? rawWordsGu
              : _getGujClassWords(enrollClassGu);
          final rawClassEn = _cleanClassToken(student.enrollSchClassEn);
          final enrollClassEn = (rawClassEn.isNotEmpty &&
                  !_isBalvatikaClass(rawClassEn) &&
                  !RegExp(r'[\u0A80-\u0AFF]').hasMatch(rawClassEn))
              ? _toAsciiDigits(rawClassEn).toUpperCase()
              : _toAsciiDigits(enrollClassGu)
                  .replaceAll(RegExp(r'[^0-9A-Za-z]'), '')
                  .toUpperCase();
          final rawWordsEn = student.enrollSchClassWordsEn.trim();
          final isValidWordsEn = rawWordsEn.isNotEmpty &&
              !RegExp(r'^\d+$').hasMatch(_toAsciiDigits(rawWordsEn)) &&
              !RegExp(r'[\u0A80-\u0AFF]').hasMatch(rawWordsEn) &&
              !_isBalvatikaClass(rawWordsEn);
          final enrollWordsEn = (isValidWordsEn
                  ? rawWordsEn
                  : _getEngClassWords(
                      enrollClassGu.isNotEmpty ? enrollClassGu : enrollClassEn))
              .toUpperCase();
          admGuj = enrollClassGu.isEmpty
              ? 'તારીખ - $admDateGu'
              : 'તારીખ - $admDateGu ને ધોરણ - $enrollClassGu${enrollWordsGu.isNotEmpty ? " ($enrollWordsGu)" : ""}';
          admEng = enrollClassEn.isEmpty
              ? 'ON $admDateEn'
              : 'ON $admDateEn IN CLASS $enrollClassEn${enrollWordsEn.isNotEmpty ? " ($enrollWordsEn)" : ""}';
        }
      }

      // Row 10: In which Standard is He/She Studying & Since when...?
      String studyGuj = '';
      String studyEng = '';
      if (_isSchoolHasNoStandardNineReason(resolvedLeaveReasonGu)) {
        studyGuj = 'ધોરણ ૮ (આઠમું) પાસ, તારીખ - $studentLcDate ના રોજ';
        studyEng = 'PASSED CLASS 8 (EIGHTH) ON ${_toAsciiDigits(studentLcDate)}';
      } else {
        final sinceDateGu = student.enrollClass.trim().isNotEmpty
            ? student.enrollClass.trim()
            : student.enrollSchool.trim();
        final sinceDateEn = _toAsciiDigits(sinceDateGu);
        if (_isBalvatikaClass(className)) {
          // Only one time Balvatika (no bracket repetition)
          studyGuj = sinceDateGu.isNotEmpty
              ? 'તારીખ - $sinceDateGu થી ધોરણ બાલવાટિકા'
              : 'ધોરણ બાલવાટિકા';
          studyEng = sinceDateEn.isNotEmpty
              ? 'FROM DATE $sinceDateEn IN CLASS BALVATIKA'
              : 'IN CLASS BALVATIKA';
        } else {
          final currentNum =
              _toAsciiDigits(className).replaceAll(RegExp(r'[^0-9]'), '');
          final gujWords = _getGujClassWords(currentNum);
          final engWords = _getEngClassWords(currentNum).toUpperCase();
          if (currentNum.isNotEmpty && sinceDateGu.isNotEmpty) {
            studyGuj =
                'તારીખ - $sinceDateGu થી ધોરણ $currentNum${gujWords.isNotEmpty ? " ($gujWords)" : ""}';
            studyEng =
                'FROM DATE $sinceDateEn IN CLASS $currentNum${engWords.isNotEmpty ? " ($engWords)" : ""}';
          } else if (currentNum.isNotEmpty) {
            studyGuj =
                'ધોરણ $currentNum${gujWords.isNotEmpty ? " ($gujWords)" : ""}';
            studyEng =
                'IN CLASS $currentNum${engWords.isNotEmpty ? " ($engWords)" : ""}';
          }
        }
      }

      final dbProgressGu =
          _studentField(student, const ['progress_gu', 'progress', 'પ્રગતિ']);
      final dbProgressEn = _studentField(student, const ['progress_en']);
      final dbConductGu = _studentField(
          student, const ['conduct_gu', 'conduct', 'વર્તણૂક', 'વર્તણુક']);
      final dbConductEn = _studentField(student, const ['conduct_en']);
      final dbRemarksGu = _studentField(student,
          const ['remarks_gu', 'remarks', 'remarksGujarati', 'વિશેષ નોંધ']);
      final dbRemarksEn =
          _studentField(student, const ['remarks_en', 'remarksEnglish']);
      final resolvedProgressGu = progressGu.trim().isNotEmpty
          ? progressGu.trim()
          : (dbProgressGu.isNotEmpty ? dbProgressGu : 'સારી');
      final resolvedProgressEn = progressEn.trim().isNotEmpty
          ? progressEn.trim()
          : (dbProgressEn.isNotEmpty ? dbProgressEn : 'GOOD');
      final resolvedConductGu = conductGu.trim().isNotEmpty
          ? conductGu.trim()
          : (dbConductGu.isNotEmpty ? dbConductGu : 'સારી');
      final resolvedConductEn = conductEn.trim().isNotEmpty
          ? conductEn.trim()
          : (dbConductEn.isNotEmpty ? dbConductEn : 'GOOD');
      // Match the prior CertificateService's free-of-charge remark unless a
      // saved student remark or a value explicitly entered for this print run
      // is available.
      final resolvedRemarksGu = remarksGu.trim().isNotEmpty
          ? remarksGu.trim()
          : (dbRemarksGu.isNotEmpty
              ? dbRemarksGu
              : 'પ્રથમ વખત આ સર્ટી. વિનામૂલ્યે આપેલ છે.');
      final resolvedRemarksEn = remarksEn.trim().isNotEmpty
          ? remarksEn.trim()
          : (dbRemarksEn.isNotEmpty
              ? dbRemarksEn
              : 'THIS CERTIFICATE IS ISSUED FREE OF CHARGE FOR THE FIRST TIME.');
      final rawCertificateNo = certificateNo.trim();
      final currentCertificateNo = certificateStartNumber == null
          ? ''
          : (certificateStartNumber + studentIndex).toString();
      final preserveLeadingZeros = rawCertificateNo.length > 1 &&
          rawCertificateNo.startsWith('0') &&
          int.tryParse(rawCertificateNo) != null;
      final number = certificateStartNumber != null
          ? (preserveLeadingZeros
              ? currentCertificateNo.padLeft(rawCertificateNo.length, '0')
              : currentCertificateNo)
          : rawCertificateNo;

      final pageWidgets = <pw.Widget>[
        pw.Image(bgImage, fit: pw.BoxFit.fill),

        // Print only the live school name and address values into the blank
        // top band. The extra English indicator captions are deliberately not
        // drawn. Medium is already printed in lc.png, so do not mask or redraw it.
        // School Name & Address centered across the full top band (left: 26, width: 560 => center 306.0)
        await _guTextBoxCentered(
          schoolNameGu,
          45,
          26,
          560,
          size: 18.0,
          minSize: 9.0,
        ),
        await _guTextBoxCentered(
          schoolNameEn,
          69,
          26,
          560,
          size: 14.0,
          minSize: 8.0,
        ),
        await _guTextBoxCentered(
          schoolAddressGu,
          89,
          26,
          560,
          size: 11.5,
          minSize: 6.0,
        ),
        await _guTextBoxCentered(
          schoolAddressEn,
          106,
          26,
          560,
          size: 10.0,
          minSize: 5.5,
        ),
        // Mask and print DISE code centered directly under સ્કૂલ ડાયસ કોડ/DISE CODE
        _mask(145, 38, 147, 18, const PdfColor(224 / 255, 1, 191 / 255)),
        await _guTextBoxCentered(
          _toAsciiDigits(diseCode),
          143.5,
          38,
          147,
          size: 13.5,
          minSize: 8.5,
        ),
        await _guTextBoxCentered(_toAsciiDigits(number), 130, 503, 86, size: 12),

        // Student fields follow the demo LC column order and existing template
        // coordinates. GR number and numeric IDs are rendered in English digits.
        await _guText(_toAsciiDigits(student.gr), 168, 190, size: 14),
        await _guText(_toAsciiDigits(apaarId), 192, 305, size: 13),
        await _guText(_toAsciiDigits(student.pen), 215, 305, size: 13),
        await _guText(_toAsciiDigits(student.uid), 235, 305, size: 13),
        await _guText(student.name, 255, 305, size: 14.5),
        await _guText(student.nameEn, 278, 305, size: 11.5),
        await _guText(casteText, 297, 305, size: 13.5),
        await _guText(casteTextEn, 318, 305, size: 11.5),
        await _guText(student.motherName, 336, 305, size: 13.5),
        await _guText(student.motherEn, 353, 305, size: 11.5),
        await _guText(student.birthPlace, 371, 305, size: 13),
        await _guText(student.birthPlaceEn, 391, 305, size: 10.5),
        await _guText(nativePlace, 410, 305, size: 13),
        await _guText(nativePlaceEn, 429, 305, size: 11),
        await _guText(_twoDigitsOrBlank(_toAsciiDigits(student.dd)), 451, 355, size: 13),
        await _guText(_twoDigitsOrBlank(_toAsciiDigits(student.mm)), 451, 445, size: 13),
        await _guText(_toAsciiDigits(student.yyyy), 451, 535, size: 13),
        await _guText(student.dobWords, 472, 305, size: 12),
        await _guText(student.dobEn, 495, 305, size: 10.5),
        await _guText(student.lastSchool, 515, 305, size: 12.5),
        await _guText(student.lastSchoolEn, 535, 305, size: 10.5),
        await _guText(admGuj, 555, 305, size: 14),
        await _guText(admEng, 575, 305, size: 12),
        await _guText(_toAsciiDigits(studentLcDate), 597, 305, size: 13),
        await _guText(studyGuj, 645, 305, size: 12.5),
        await _guText(studyEng, 665, 305, size: 10.5),
        await _guText(resolvedLeaveReasonGu, 689, 305, size: 13),
        await _guText(resolvedLeaveReasonEn, 711, 305, size: 10.5),
        await _guText(_toAsciiDigits(student.accountNumber), 734, 305, size: 13),
        await _guText(
            '${student.bankName}    IFSC: ${student.ifscCode}', 755, 305,
            size: 11),
        await _guText(resolvedProgressGu, 774, 190, size: 13),
        await _guText(resolvedProgressEn, 799, 190, size: 13),
        await _guText(resolvedConductGu, 774, 450, size: 13),
        await _guText(resolvedConductEn, 799, 450, size: 13),
        await _guText(resolvedRemarksGu, 818, 305, size: 13),
        await _guText(resolvedRemarksEn, 838, 305, size: 8),
        await _guText(_toAsciiDigits(presentDays), 854, 190, size: 14),
        await _guText(_toAsciiDigits(studentLcDate), 928, 125, size: 13),
      ];

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.legal,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.Stack(fit: pw.StackFit.expand, children: pageWidgets);
          },
        ),
      );
    }
    final bytes = await doc.save();
    await Printing.layoutPdf(
      name: '${className}_LC.pdf',
      onLayout: (PdfPageFormat format) async => bytes,
    );
  }

// =========================================================================
  // 4. રજા રિપોર્ટ (Leave Application PDF - Blank Page)
  // =========================================================================

  static String _daysToGujaratiWords(String daysStr) {
    if (daysStr == '0.5' || daysStr == '૦.૫') return '૦.૫ (અડધો)';
    if (daysStr == '1' || daysStr == '૧') return '૧ (એક)';
    if (daysStr == '2' || daysStr == '૨') return '૨ (બે)';
    if (daysStr == '3' || daysStr == '૩') return '૩ (ત્રણ)';
    if (daysStr == '4' || daysStr == '૪') return '૪ (ચાર)';
    if (daysStr == '5' || daysStr == '૫') return '૫ (પાંચ)';
    if (daysStr == '6' || daysStr == '૬') return '૬ (છ)';
    if (daysStr == '7' || daysStr == '૭') return '૭ (સાત)';
    if (daysStr == '8' || daysStr == '૮') return '૮ (આઠ)';
    if (daysStr == '9' || daysStr == '૯') return '૯ (નવ)';
    if (daysStr == '10' || daysStr == '૧૦') return '૧૦ (દસ)';
    return daysStr;
  }

  static Future<void> generateLeavePDF({
    required Map<String, dynamic> teacher,
    required Map<String, dynamic> chargeTeacher,
    required String leaveType,
    required String reason,
    required String fromDate,
    required String toDate,
    required String totalDays,
    required Map<String, dynamic> utilizedLeaves,
    String schoolName = '',
  }) async {
    final doc = pw.Document();
    final today = DateFormat('dd/MM/yyyy').format(DateTime.now());

    String rawClass = teacher['assignedClass'] ?? '';
    String cleanClass = ClassLabel.bare(rawClass);
    String tName = teacher['name'] ?? '';
    String cName = chargeTeacher['name'] ?? '';
    String cClass = chargeTeacher['assignedClass']
            ?.toString()
            .replaceAll('ધોરણ -', '')
            .replaceAll('ધોરણ', '')
            .replaceAll('Class', '')
            .trim() ??
        '';

    double clUsed =
        double.tryParse(utilizedLeaves['cl']?.toString() ?? '0') ?? 0;
    double halfClUsed =
        double.tryParse(utilizedLeaves['halfCl']?.toString() ?? '0') ?? 0;
    double valetarUsed =
        double.tryParse(utilizedLeaves['valetar']?.toString() ?? '0') ?? 0;
    double marjiyatUsed =
        double.tryParse(utilizedLeaves['marjiyat']?.toString() ?? '0') ?? 0;

    String fmtLeave(double v) =>
        (v % 1 == 0) ? v.toInt().toString() : v.toStringAsFixed(1);

    // જો clUsed પોતે જ 3.5 હોય અને halfClUsed 0 હોય, તો પણ સરવાળો 3.5 જ રહેશે (ક્યારેય 4 નહીં થાય)
    double totalCl = (utilizedLeaves['totalCl'] != null)
        ? (double.tryParse(utilizedLeaves['totalCl'].toString()) ??
            (clUsed + halfClUsed))
        : (clUsed + halfClUsed);

    String totalClStr = fmtLeave(totalCl);
    String totalValetarStr = fmtLeave(valetarUsed);
    String totalMarjiyatStr = fmtLeave(marjiyatUsed);

    String daysWord = _daysToGujaratiWords(totalDays);
    String displayLeaveType =
        leaveType == 'અડધી રજા (Half CL)' ? 'પ્રાસંગિક રજા (CL)' : leaveType;

    bool isSingleDate = fromDate == toDate;

    // બેકગ્રાઉન્ડ ઈમેજ લોડ કરવી
    final bgData = await rootBundle.load(
        isSingleDate ? 'assets/images/leave1.jpg' : 'assets/images/leave2.jpg');
    final bgImage = pw.MemoryImage(bgData.buffer.asUint8List());

    // જમણી બાજુની વિગતો (તમારા ફોટામાં ખાલી છે એટલે આખું પ્રિન્ટ કરવું પડશે)
    // _guText(લખાણ, Y(ઉપરથી નીચે), X(ડાબેથી જમણે))
    final rightTopDetails = [
      await _guText('નામ :- $tName', 75, 580, size: 15),
      await _guText('હોદ્દો :- મદદનીશ શિક્ષક', 100, 580, size: 15),
      await _guText('શાળા :- ${schoolName.trim().isNotEmpty ? schoolName.trim() : 'દરેડ કુમાર શાળા'}', 125, 580, size: 15),
      await _guText('ધોરણ :- $cleanClass', 150, 580, size: 15),
      await _guText('તારીખ :- $today', 175, 580, size: 15),
    ];

    // વિષય
    final subjectLine = await _guText(
        '$daysWord દિવસની $displayLeaveType મંજૂર કરવા બાબત.', 243, 205,
        size: 15);

    // ભોગવેલી રજાઓ
    final utilizedLeavesDetails = [
      await _guText(totalClStr, 334, 203, size: 15), // CL
      await _guText(totalValetarStr, 334, 313, size: 15), // વળતર
      await _guText(totalMarjiyatStr, 334, 455, size: 15), // મરજિયાત
    ];

    // ચાર્જ શિક્ષક અને સહી
    final chargeDetails = [
      await _guText(cName, 380, 230, size: 15), // ચાર્જ શિક્ષક નામ
      await _guText(cClass, 380, 655, size: 15), // ચાર્જ શિક્ષક ધોરણ
      await _guText(tName, 480, 640, size: 15), // અરજદારની સહીની નીચે નામ
    ];

    // ડાયનેમિક પેજ વિજેટ્સ
    final pageWidgets = <pw.Widget>[
      pw.Image(bgImage, fit: pw.BoxFit.fill),
      ...rightTopDetails,
      subjectLine,
      ...utilizedLeavesDetails,
      ...chargeDetails,
    ];

    // 'કારણસર' શબ્દ ડબલ વાર ન છપાય તે માટે તેને અહીથી રિમૂવ કરીશું
    String cleanReason = reason.replaceAll('કારણસર', '').trim();

    if (isSingleDate) {
      // સિંગલ ડેટ (leave1.jpg)
      pageWidgets.addAll([
        await _guText(cleanReason, 265, 550,
            size: 15), // અહીં cleanReason વાપર્યું
        await _guText(fromDate, 292, 157, size: 15), // ના રોજ
        await _guText(daysWord, 310, 100, size: 15), // દિવસની
        await _guText(displayLeaveType, 310, 256, size: 15), // રજા
      ]);
    } else {
      // ડબલ ડેટ (leave2.jpg)
      pageWidgets.addAll([
        await _guText(cleanReason, 265, 550,
            size: 15), // અહીં cleanReason વાપર્યું
        await _guText(fromDate, 292, 157, size: 15), // થી તારીખ
        await _guText(toDate, 292, 380, size: 15), // સુધી
        await _guText(daysWord, 310, 100, size: 15), // દિવસની
        await _guText(displayLeaveType, 310, 256, size: 15), // રજા
      ]);
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: pw.EdgeInsets.zero,
        build: (pw.Context context) {
          return pw.Container(
            color: const PdfColor(
                1, 1, 1), // આ લાઈનથી બેકગ્રાઉન્ડ પર્ફેક્ટ સફેદ થઈ જશે
            child: pw.Stack(
              fit: pw.StackFit.expand,
              children: pageWidgets,
            ),
          );
        },
      ),
    );

    final bytes = await doc.save();
    await Printing.layoutPdf(
        name: '${tName}_Leave.pdf',
        onLayout: (PdfPageFormat format) async => bytes);
  }
}
