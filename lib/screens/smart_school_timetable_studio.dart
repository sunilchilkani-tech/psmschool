// ============================================================================
// SMART SCHOOL TIMETABLE STUDIO ULTIMATE (FLUTTER / DART EDITION)
// Complete Gujarati + English School Timetable Engine, Solver & Studio UI
// ============================================================================
//
// Features Included:
// 1. Audited & Upgraded Zero-Clash Constraint Solver (MRV + Backtracking Swap +
//    Daily Teacher Load Balancing + Gap Minimization + Room/Lab Clash Guard)
// 2. Class Teacher Period-1 Lock (with multi-subject distribution across week)
// 3. Continuous 2-Period (Double Period) Block Placement (never splits across
//    Recess/Breaks unless strictly unavoidable)
// 4. NEW: Pinned / Locked Slots & Teacher Unavailability / Half-Day Constraints
// 5. NEW: Interactive Tap-to-Swap Editor with Live Clash & Break-Split Guard
// 6. NEW: Absent Teacher Proxy / Substitution Finder Engine
// 7. NEW: Lab / Special Room Allocation & Clash Prevention
// 8. Full Gujarati & English UI: Setup, Break & Period Timings, Masters,
//    Assignments, Page & Prayer Design, Logo/Watermark Studio, 5 Timetable
//    Views (Class, Teacher, All Classes, All Teachers, Master Grid), Reports,
//    and CSV/JSON Import-Export.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/psm_file_export_helper.dart';
import '../services/rojmel_html_printer.dart';
import '../theme/responsive.dart';

// ============================================================================
// 1. DATA MODELS & SERIALIZATION
// ============================================================================

const List<String> kSchoolDays = [
  'સોમવાર (Mon)',
  'મંગળવાર (Tue)',
  'બુધવાર (Wed)',
  'ગુરુવાર (Thu)',
  'શુક્રવાર (Fri)',
  'શનિવાર (Sat)',
];

class SchoolConfig {
  String schoolName;
  String academicYear;
  int monFriPeriods;
  int saturdayPeriods;
  int maxTeacherWeeklyLoad;
  int maxTeacherDailyLoad;
  bool reserveFirstPeriodForClassTeacher;
  bool saturdayFirstPeriodSameSubjectEnabled;
  String saturdayFirstPeriodSubject;
  String saturdayFirstPeriodTeacherInitial;

  SchoolConfig({
    this.schoolName = 'પીએમ શ્રી દરેડ કુમાર શાળા (PM SHRI Dared Kumar Shala)',
    this.academicYear = '૨૦૨૬–૨૭ (2026–27)',
    this.monFriPeriods = 8,
    this.saturdayPeriods = 6,
    this.maxTeacherWeeklyLoad = 45,
    this.maxTeacherDailyLoad = 7,
    this.reserveFirstPeriodForClassTeacher = true,
    this.saturdayFirstPeriodSameSubjectEnabled = false,
    this.saturdayFirstPeriodSubject = 'શા. શિ.',
    this.saturdayFirstPeriodTeacherInitial = '',
  });

  int get weeklySlotsPerClass => (monFriPeriods * 5) + saturdayPeriods;

  int periodsForDay(int dayIndex) =>
      dayIndex < 5 ? monFriPeriods : saturdayPeriods;

  Map<String, dynamic> toJson() => {
        'schoolName': schoolName,
        'academicYear': academicYear,
        'monFriPeriods': monFriPeriods,
        'saturdayPeriods': saturdayPeriods,
        'maxTeacherWeeklyLoad': maxTeacherWeeklyLoad,
        'maxTeacherDailyLoad': maxTeacherDailyLoad,
        'reserveFirstPeriodForClassTeacher': reserveFirstPeriodForClassTeacher,
        'saturdayFirstPeriodSameSubjectEnabled':
            saturdayFirstPeriodSameSubjectEnabled,
        'saturdayFirstPeriodSubject': saturdayFirstPeriodSubject,
        'saturdayFirstPeriodTeacherInitial': saturdayFirstPeriodTeacherInitial,
      };

  factory SchoolConfig.fromJson(Map<String, dynamic> json) => SchoolConfig(
        schoolName: json['schoolName'] ??
            'પીએમ શ્રી દરેડ કુમાર શાળા (PM SHRI Dared Kumar Shala)',
        academicYear: json['academicYear'] ?? '૨૦૨૬–૨૭ (2026–27)',
        monFriPeriods: (json['monFriPeriods'] ?? 8).clamp(1, 15),
        saturdayPeriods: (json['saturdayPeriods'] ?? 6).clamp(0, 15),
        maxTeacherWeeklyLoad: (json['maxTeacherWeeklyLoad'] ?? 45).clamp(1, 90),
        maxTeacherDailyLoad: (json['maxTeacherDailyLoad'] ?? 7).clamp(1, 15),
        reserveFirstPeriodForClassTeacher:
            json['reserveFirstPeriodForClassTeacher'] != false,
        saturdayFirstPeriodSameSubjectEnabled:
            json['saturdayFirstPeriodSameSubjectEnabled'] == true,
        saturdayFirstPeriodSubject:
            (json['saturdayFirstPeriodSubject'] ?? 'શા. શિ.').toString(),
        saturdayFirstPeriodTeacherInitial:
            (json['saturdayFirstPeriodTeacherInitial'] ?? '').toString(),
      );
}

class PeriodTiming {
  String start;
  String end;

  PeriodTiming({required this.start, required this.end});

  String get formatted =>
      (start.isNotEmpty && end.isNotEmpty) ? '$start–$end' : '';

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory PeriodTiming.fromJson(Map<String, dynamic> json) => PeriodTiming(
        start: json['start'] ?? '',
        end: json['end'] ?? '',
      );
}

class BreakConfig {
  String name;
  int afterPeriod; // 1-based period number
  String start;
  String end;

  BreakConfig({
    required this.name,
    required this.afterPeriod,
    required this.start,
    required this.end,
  });

  String get formattedTime =>
      (start.isNotEmpty && end.isNotEmpty) ? '$start – $end' : '';

  Map<String, dynamic> toJson() => {
        'name': name,
        'afterPeriod': afterPeriod,
        'start': start,
        'end': end,
      };

  factory BreakConfig.fromJson(Map<String, dynamic> json) => BreakConfig(
        name: json['name'] ?? 'મુખ્ય રિસેસ / Recess',
        afterPeriod: json['afterPeriod'] ?? 4,
        start: json['start'] ?? '12:50',
        end: json['end'] ?? '13:20',
      );
}

class TeacherMaster {
  String? teacherId;
  String initial;
  String fullName;
  List<String> taughtSubjects;
  List<String> assignedClasses;

  /// Set of "dayIndex:periodIndex" (0-based) where teacher is unavailable
  Set<String> unavailableSlots;

  TeacherMaster({
    this.teacherId,
    required this.initial,
    required this.fullName,
    List<String>? taughtSubjects,
    List<String>? assignedClasses,
    Set<String>? unavailableSlots,
  })  : taughtSubjects = taughtSubjects ?? <String>[],
        assignedClasses = assignedClasses ?? <String>[],
        unavailableSlots = unavailableSlots ?? <String>{};

  bool isUnavailable(int day, int period) =>
      unavailableSlots.contains('$day:$period');

  void toggleUnavailable(int day, int period) {
    final key = '$day:$period';
    if (unavailableSlots.contains(key)) {
      unavailableSlots.remove(key);
    } else {
      unavailableSlots.add(key);
    }
  }

  Map<String, dynamic> toJson() => {
        if (teacherId != null && teacherId!.isNotEmpty) 'teacherId': teacherId,
        'i': initial,
        'f': fullName,
        'taughtSubjects': taughtSubjects,
        'assignedClasses': assignedClasses,
        'unavailable': unavailableSlots.toList(),
      };

  factory TeacherMaster.fromJson(Map<String, dynamic> json) => TeacherMaster(
        teacherId: json['teacherId']?.toString(),
        initial: (json['i'] ?? '').toString().toUpperCase(),
        fullName: (json['f'] ?? '').toString(),
        taughtSubjects: ((json['taughtSubjects'] as List?) ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        assignedClasses: ((json['assignedClasses'] as List?) ?? const [])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        unavailableSlots: ((json['unavailable'] as List?) ?? const [])
            .map((e) => e.toString())
            .toSet(),
      );
}

class TeachingAssignment {
  String id;
  String teacherInitial;
  String subject;
  String className; // e.g., "6-A" or "BALVATIKA-A"
  bool isClassTeacher;
  int requiredPeriods;
  int? maxPeriods;
  bool isDoublePeriod;
  String?
      roomOrLab; // Optional shared room/lab e.g. "Science Lab", "Computer Lab"

  TeachingAssignment({
    required this.id,
    required this.teacherInitial,
    required this.subject,
    required this.className,
    this.isClassTeacher = false,
    this.requiredPeriods = 6,
    this.maxPeriods,
    this.isDoublePeriod = false,
    this.roomOrLab,
  });

  TeachingAssignment copyWith({
    String? id,
    String? teacherInitial,
    String? subject,
    String? className,
    bool? isClassTeacher,
    int? requiredPeriods,
    int? maxPeriods,
    bool? isDoublePeriod,
    String? roomOrLab,
  }) {
    return TeachingAssignment(
      id: id ?? this.id,
      teacherInitial: teacherInitial ?? this.teacherInitial,
      subject: subject ?? this.subject,
      className: className ?? this.className,
      isClassTeacher: isClassTeacher ?? this.isClassTeacher,
      requiredPeriods: requiredPeriods ?? this.requiredPeriods,
      maxPeriods: maxPeriods ?? this.maxPeriods,
      isDoublePeriod: isDoublePeriod ?? this.isDoublePeriod,
      roomOrLab: roomOrLab ?? this.roomOrLab,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'i': teacherInitial,
        's': subject,
        'c': className,
        'ct': isClassTeacher,
        'n': requiredPeriods,
        if (maxPeriods != null && maxPeriods! > 0) 'maxPeriods': maxPeriods,
        'dbl': isDoublePeriod,
        'room': roomOrLab,
      };

  factory TeachingAssignment.fromJson(Map<String, dynamic> json) {
    final rawMax = json['maxPeriods'] ?? json['max_periods'];
    final parsedMax = rawMax is num
        ? rawMax.round()
        : int.tryParse((rawMax ?? '').toString().trim());
    final validMax = (parsedMax != null && parsedMax > 0) ? parsedMax : null;
    var req = ((json['n'] ?? 6) is num
            ? (json['n'] as num).round()
            : int.tryParse((json['n'] ?? '6').toString()) ?? 6)
        .clamp(1, 60);
    if (validMax != null && req > validMax) {
      req = validMax;
    }
    return TeachingAssignment(
      id: json['id'] ?? UniqueKey().toString(),
      teacherInitial: (json['i'] ?? '').toString().toUpperCase(),
      subject: json['s'] ?? '',
      className: json['c'] ?? '6-A',
      isClassTeacher: json['ct'] == true,
      requiredPeriods: req,
      maxPeriods: validMax,
      isDoublePeriod: json['dbl'] == true,
      roomOrLab: json['room'],
    );
  }
}

class ScheduledSlot {
  final String assignmentId;
  final String teacherInitial;
  final String subject;
  final String className;
  final bool isClassTeacher;
  final bool isDoublePeriod;
  final String? roomOrLab;
  final bool isLocked;

  const ScheduledSlot({
    required this.assignmentId,
    required this.teacherInitial,
    required this.subject,
    required this.className,
    this.isClassTeacher = false,
    this.isDoublePeriod = false,
    this.roomOrLab,
    this.isLocked = false,
  });

  ScheduledSlot copyWith({bool? isLocked, bool? isDoublePeriod}) =>
      ScheduledSlot(
        assignmentId: assignmentId,
        teacherInitial: teacherInitial,
        subject: subject,
        className: className,
        isClassTeacher: isClassTeacher,
        isDoublePeriod: isDoublePeriod ?? this.isDoublePeriod,
        roomOrLab: roomOrLab,
        isLocked: isLocked ?? this.isLocked,
      );

  Map<String, dynamic> toJson() => {
        'assignmentId': assignmentId,
        'i': teacherInitial,
        's': subject,
        'c': className,
        'ct': isClassTeacher,
        'dbl': isDoublePeriod,
        'room': roomOrLab,
        'locked': isLocked,
      };

  factory ScheduledSlot.fromJson(Map<String, dynamic> json) => ScheduledSlot(
        assignmentId: json['assignmentId'] ?? '',
        teacherInitial: json['i'] ?? '',
        subject: json['s'] ?? '',
        className: json['c'] ?? '',
        isClassTeacher: json['ct'] == true,
        isDoublePeriod: json['dbl'] == true,
        roomOrLab: json['room'],
        isLocked: json['locked'] == true,
      );
}

class PageDesignConfig {
  bool prayerEnabled;
  String prayerName;
  String prayerStart;
  String prayerEnd;
  bool showSignatures;
  double periodHeightMm;
  double columnWidthPx;
  double prayerHeightMm;
  double breakHeightMm;
  double borderWidthPx;
  int borderColorValue;
  double marginTopPx;
  double marginRightPx;
  double marginBottomPx;
  double marginLeftPx;
  bool fullPagePdf;
  double teacherLegendFontSizePx;
  bool teacherLegendSingleLine;

  PageDesignConfig({
    this.prayerEnabled = true,
    this.prayerName = 'પ્રાર્થના સંમેલન / Prayer Assembly',
    this.prayerStart = '10:30',
    this.prayerEnd = '10:50',
    this.showSignatures = true,
    this.periodHeightMm = 16,
    this.columnWidthPx = 140,
    this.prayerHeightMm = 9,
    this.breakHeightMm = 7,
    this.borderWidthPx = 2,
    this.borderColorValue = 0xFF312E81,
    this.marginTopPx = 4,
    this.marginRightPx = 4,
    this.marginBottomPx = 4,
    this.marginLeftPx = 4,
    this.fullPagePdf = true,
    this.teacherLegendFontSizePx = 11.5,
    this.teacherLegendSingleLine = true,
  });

  String get prayerTiming => (prayerStart.isNotEmpty && prayerEnd.isNotEmpty)
      ? '$prayerStart–$prayerEnd'
      : '';

  Color get borderColor => Color(borderColorValue);

  Map<String, dynamic> toJson() => {
        'prayerEnabled': prayerEnabled,
        'prayerName': prayerName,
        'prayerStart': prayerStart,
        'prayerEnd': prayerEnd,
        'showSignatures': showSignatures,
        'periodHeight': periodHeightMm,
        'columnWidth': columnWidthPx,
        'prayerHeight': prayerHeightMm,
        'breakHeight': breakHeightMm,
        'borderWidth': borderWidthPx,
        'borderColorValue': borderColorValue,
        'top': marginTopPx,
        'right': marginRightPx,
        'bottom': marginBottomPx,
        'left': marginLeftPx,
        'fullPagePdf': fullPagePdf,
        'teacherLegendFontSizePx': teacherLegendFontSizePx,
        'teacherLegendSingleLine': teacherLegendSingleLine,
      };

  factory PageDesignConfig.fromJson(Map<String, dynamic> json) =>
      PageDesignConfig(
        prayerEnabled: json['prayerEnabled'] ?? true,
        prayerName: json['prayerName'] ?? 'પ્રાર્થના સંમેલન / Prayer Assembly',
        prayerStart: json['prayerStart'] ?? '10:30',
        prayerEnd: json['prayerEnd'] ?? '10:50',
        showSignatures: json['showSignatures'] ?? true,
        periodHeightMm: (json['periodHeight'] ?? 16).toDouble(),
        columnWidthPx: (json['columnWidth'] ?? 140).toDouble(),
        prayerHeightMm: (json['prayerHeight'] ?? 9).toDouble(),
        breakHeightMm: (json['breakHeight'] ?? 7).toDouble(),
        borderWidthPx: (json['borderWidth'] ?? 2).toDouble(),
        borderColorValue: json['borderColorValue'] ?? 0xFF312E81,
        marginTopPx: (json['top'] ?? 4).toDouble(),
        marginRightPx: (json['right'] ?? 4).toDouble(),
        marginBottomPx: (json['bottom'] ?? 4).toDouble(),
        marginLeftPx: (json['left'] ?? 4).toDouble(),
        fullPagePdf: json['fullPagePdf'] != false,
        teacherLegendFontSizePx:
            (json['teacherLegendFontSizePx'] ?? 11.5).toDouble().clamp(6.5, 20.0),
        teacherLegendSingleLine: json['teacherLegendSingleLine'] != false,
      );
}

class OverlayLayerStyle {
  double xPercent;
  double yPercent;
  double widthPx;
  double heightPx;
  double opacity;
  String shape; // 'original', 'square', 'rect', 'round'

  OverlayLayerStyle({
    required this.xPercent,
    required this.yPercent,
    required this.widthPx,
    required this.heightPx,
    required this.opacity,
    this.shape = 'original',
  });

  Map<String, dynamic> toJson() => {
        'x': xPercent,
        'y': yPercent,
        'w': widthPx,
        'h': heightPx,
        'opacity': opacity,
        'shape': shape,
      };

  factory OverlayLayerStyle.fromJson(Map<String, dynamic> json) =>
      OverlayLayerStyle(
        xPercent: (json['x'] ?? 50).toDouble(),
        yPercent: (json['y'] ?? 50).toDouble(),
        widthPx: (json['w'] ?? 80).toDouble(),
        heightPx: (json['h'] ?? 80).toDouble(),
        opacity: (json['opacity'] ?? 1.0).toDouble(),
        shape: (json['shape'] == null || json['shape'] == 'round')
            ? 'original'
            : json['shape'].toString(),
      );
}

// ============================================================================
// 2. AUDITED & UPGRADED ZERO-CLASH TIMETABLE SOLVER ENGINE
// ============================================================================

class TimetableValidationResult {
  final List<String> errors;
  final List<String> warnings;

  const TimetableValidationResult({
    this.errors = const [],
    this.warnings = const [],
  });

  bool get isValid => errors.isEmpty;
}

class UnplacedAssignmentInfo {
  final TeachingAssignment assignment;
  final int remainingPeriods;
  final int unplacedDoublePairs;

  const UnplacedAssignmentInfo({
    required this.assignment,
    required this.remainingPeriods,
    required this.unplacedDoublePairs,
  });
}

class ProxyCandidate {
  final TeacherMaster teacher;
  final int currentDayLoad;
  final int currentWeekLoad;
  final bool teachesSameClass;
  final bool teachesSameSubject;

  const ProxyCandidate({
    required this.teacher,
    required this.currentDayLoad,
    required this.currentWeekLoad,
    required this.teachesSameClass,
    required this.teachesSameSubject,
  });

  int get priorityScore =>
      (teachesSameSubject ? 40 : 0) +
      (teachesSameClass ? 30 : 0) -
      (currentDayLoad * 5) -
      currentWeekLoad;
}

class TimetableSolution {
  /// schedule[className][dayIndex][periodIndex]
  final Map<String, List<List<ScheduledSlot?>>> schedule;
  final List<UnplacedAssignmentInfo> unplaced;
  final int unplacedPeriodsCount;
  final int unplacedPairsCount;
  final int solverIterationsUsed;
  final int clashCount;
  final int elapsedMs;

  const TimetableSolution({
    required this.schedule,
    required this.unplaced,
    required this.unplacedPeriodsCount,
    required this.unplacedPairsCount,
    required this.solverIterationsUsed,
    this.clashCount = 0,
    this.elapsedMs = 0,
  });
}

class _MutableWorkItem {
  final TeachingAssignment assignment;
  int left;
  int pairsLeft;

  _MutableWorkItem(this.assignment)
      : left = (assignment.maxPeriods != null && assignment.maxPeriods! > 0)
            ? min(assignment.requiredPeriods, assignment.maxPeriods!)
            : assignment.requiredPeriods,
        pairsLeft = assignment.isDoublePeriod
            ? (((assignment.maxPeriods != null && assignment.maxPeriods! > 0)
                    ? min(assignment.requiredPeriods, assignment.maxPeriods!)
                    : assignment.requiredPeriods) ~/
                2)
            : 0;
}

class TimetableSolverEngine {
  /// Natural class comparator: BALVATIKA first, then 1-A..12-Z numerically.
  static String _normDigits(String s) {
    const guj = '૦૧૨૩૪૫૬૭૮૯';
    var res = s;
    for (int i = 0; i < guj.length; i++) {
      res = res.replaceAll(guj[i], '$i');
    }
    return res;
  }

  static List<String> sortedClasses(Iterable<String> rawClasses) {
    final list = rawClasses.where((c) => c.trim().isNotEmpty).toSet().toList();
    list.sort((a, b) {
      final aNorm = _normDigits(a);
      final bNorm = _normDigits(b);
      final aBal = aNorm.toUpperCase().contains('BAL') || aNorm.contains('બાલ');
      final bBal = bNorm.toUpperCase().contains('BAL') || bNorm.contains('બાલ');
      if (aBal && !bBal) return -1;
      if (!aBal && bBal) return 1;
      final aNum =
          int.tryParse(RegExp(r'\d+').firstMatch(aNorm)?.group(0) ?? '');
      final bNum =
          int.tryParse(RegExp(r'\d+').firstMatch(bNorm)?.group(0) ?? '');
      if (aNum != null && bNum != null && aNum != bNum) {
        return aNum.compareTo(bNum);
      }
      return aNorm.compareTo(bNorm);
    });
    return list;
  }

  /// Comprehensive Pre-Solve Validation (Hard errors + Helpful warnings)
  static TimetableValidationResult validate({
    required SchoolConfig config,
    required List<TeacherMaster> teachers,
    required List<TeachingAssignment> assignments,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    if (assignments.isEmpty) {
      errors.add('કોઈ તાસ ઉમેરેલ નથી (No teaching assignments added).');
      return TimetableValidationResult(errors: errors, warnings: warnings);
    }

    final teacherMap = {for (final t in teachers) t.initial: t};
    final teacherLoad = <String, int>{};
    for (final r in assignments) {
      teacherLoad[r.teacherInitial] =
          (teacherLoad[r.teacherInitial] ?? 0) + r.requiredPeriods;
    }

    for (final entry in teacherLoad.entries) {
      final t = teacherMap[entry.key];
      final fullName = t?.fullName ?? entry.key;
      if (entry.value > config.maxTeacherWeeklyLoad) {
        warnings.add(
          'શિક્ષક ${entry.key} ($fullName) ના તાસ ${entry.value} છે (મહત્તમ મર્યાદા ${config.maxTeacherWeeklyLoad}).',
        );
      }
      if (t != null && t.unavailableSlots.isNotEmpty) {
        final availableCount =
            config.weeklySlotsPerClass - t.unavailableSlots.length;
        if (entry.value > availableCount) {
          warnings.add(
            'શિક્ષક ${entry.key} ($fullName) પાસે $availableCount ઉપલબ્ધ તાસ છે પરંતુ ${entry.value} તાસ ફાળવેલ છે.',
          );
        }
      }
    }

    final classOwnedByCT = <String, List<String>>{};
    final classes = sortedClasses(assignments.map((e) => e.className));

    for (final c in classes) {
      final classRows = assignments.where((r) => r.className == c).toList();
      final ctInitials = classRows
          .where((r) => r.isClassTeacher)
          .map((r) => r.teacherInitial)
          .toSet()
          .toList();
      final totalClassPeriods =
          classRows.fold<int>(0, (sum, r) => sum + r.requiredPeriods);
      final ctTotalPeriods = classRows
          .where((r) => r.isClassTeacher)
          .fold<int>(0, (sum, r) => sum + r.requiredPeriods);

      if (config.reserveFirstPeriodForClassTeacher) {
        if (ctInitials.isEmpty) {
          warnings.add(
            'વર્ગ $c: કોઈ વર્ગ શિક્ષક (CT) પસંદ કરેલ નથી (પ્રથમ શિક્ષકને તાસ-1 માં અગ્રતા અપાશે).',
          );
        } else if (ctInitials.length > 1) {
          warnings.add(
            'વર્ગ $c: એકથી વધુ વર્ગ શિક્ષક પસંદ થયેલ છે (${ctInitials.join(', ')}).',
          );
        } else {
          final ctInit = ctInitials.first;
          (classOwnedByCT[ctInit] ??= []).add(c);
          final satNeedsCt = config.saturdayPeriods > 0 &&
              !config.saturdayFirstPeriodSameSubjectEnabled;
          final activeDays = satNeedsCt ? 6 : 5;
          if (ctTotalPeriods < activeDays) {
            warnings.add(
              'વર્ગ $c: વર્ગ શિક્ષક ($ctInit) પાસે કુલ $ctTotalPeriods તાસ છે ($activeDays દિવસમાં તાસ-1 માટે ઓછા પડે છે, બાકીના દિવસે અન્ય શિક્ષક મુકાશે).',
            );
          }
        }
      }

      if (totalClassPeriods > config.weeklySlotsPerClass) {
        warnings.add(
          'વર્ગ $c: કુલ તાસ $totalClassPeriods / ${config.weeklySlotsPerClass} ક્ષમતા કરતાં વધુ છે (⚡ ઓટો-બેલેન્સ બટન દબાવો).',
        );
      } else if (totalClassPeriods < config.weeklySlotsPerClass) {
        warnings.add(
          'વર્ગ $c: કુલ $totalClassPeriods / ${config.weeklySlotsPerClass} તાસ ફાળવેલ છે (${config.weeklySlotsPerClass - totalClassPeriods} તાસ Free રહેશે).',
        );
      }
    }

    for (final entry in classOwnedByCT.entries) {
      if (entry.value.length > 1) {
        warnings.add(
          'શિક્ષક ${entry.key}: એકથી વધુ વર્ગના વર્ગ શિક્ષક છે (${entry.value.join(', ')}) — તાસ-1 વારાફરતી ફાળવાશે.',
        );
      }
    }

    return TimetableValidationResult(errors: errors, warnings: warnings);
  }

  /// Audits a schedule grid and returns the exact number of teacher or room clashes (0 = 100% Zero Clash).
  static int verifyZeroClash(
    Map<String, List<List<ScheduledSlot?>>> schedule, {
    bool ignoreSaturdayFirstPeriodGroupSubject = false,
  }) {
    int clashes = 0;
    for (int d = 0; d < 6; d++) {
      int maxK = 0;
      for (final grid in schedule.values) {
        if (d < grid.length && grid[d].length > maxK) maxK = grid[d].length;
      }
      for (int k = 0; k < maxK; k++) {
        if (ignoreSaturdayFirstPeriodGroupSubject && d == 5 && k == 0) {
          continue;
        }
        final seenTeachers = <String>{};
        final seenRooms = <String>{};
        for (final grid in schedule.values) {
          if (d >= grid.length || k >= grid[d].length) continue;
          final slot = grid[d][k];
          if (slot == null) continue;
          if (!seenTeachers.add(slot.teacherInitial)) {
            clashes++;
          }
          final rm = slot.roomOrLab?.trim() ?? '';
          if (rm.isNotEmpty && !seenRooms.add(rm)) {
            clashes++;
          }
        }
      }
    }
    return clashes;
  }

  /// Ultra-fast multi-restart heuristic + 2-hop Kempe-chain swap repair solver
  static TimetableSolution generate({
    required SchoolConfig config,
    required List<TeacherMaster> teachers,
    required List<TeachingAssignment> assignments,
    required List<BreakConfig> breaks,
    Map<String, List<List<ScheduledSlot?>>>? existingScheduleWithLocks,
    int maxRestarts = 60,
  }) {
    final sw = Stopwatch()..start();
    final random = Random();
    final classes = sortedClasses(assignments.map((a) => a.className));
    final teacherMap = {for (final t in teachers) t.initial: t};
    final breakAfterSet = breaks.map((b) => b.afterPeriod).toSet();

    TimetableSolution? bestSolution;
    double bestPenalty = double.infinity;

    for (int attempt = 0; attempt < maxRestarts; attempt++) {
      final sol = _runSingleAttempt(
        config: config,
        classes: classes,
        teacherMap: teacherMap,
        assignments: assignments,
        breakAfterSet: breakAfterSet,
        existingScheduleWithLocks: existingScheduleWithLocks,
        random: random,
        iterationIndex: attempt + 1,
      );

      final hardPenalty =
          (sol.unplacedPeriodsCount * 1000.0) + (sol.unplacedPairsCount * 80.0);
      final softPenalty = _evaluateSoftQualityPenalty(sol.schedule, config);
      final totalPenalty = hardPenalty + softPenalty;

      if (totalPenalty < bestPenalty) {
        bestPenalty = totalPenalty;
        bestSolution = sol;
      }

      // Fast exit as soon as 0 unplaced periods & 0 unplaced pairs are achieved!
      if (sol.unplacedPeriodsCount == 0 &&
          sol.unplacedPairsCount == 0 &&
          (softPenalty <= 6.0 || attempt >= 2)) {
        break;
      }
    }

    sw.stop();
    final chosen = bestSolution!;
    final verifiedClashes = verifyZeroClash(
      chosen.schedule,
      ignoreSaturdayFirstPeriodGroupSubject:
          config.saturdayFirstPeriodSameSubjectEnabled,
    );
    return TimetableSolution(
      schedule: chosen.schedule,
      unplaced: chosen.unplaced,
      unplacedPeriodsCount: chosen.unplacedPeriodsCount,
      unplacedPairsCount: chosen.unplacedPairsCount,
      solverIterationsUsed: chosen.solverIterationsUsed,
      clashCount: verifiedClashes,
      elapsedMs: sw.elapsedMilliseconds,
    );
  }

  static TimetableSolution _runSingleAttempt({
    required SchoolConfig config,
    required List<String> classes,
    required Map<String, TeacherMaster> teacherMap,
    required List<TeachingAssignment> assignments,
    required Set<int> breakAfterSet,
    required Map<String, List<List<ScheduledSlot?>>>? existingScheduleWithLocks,
    required Random random,
    required int iterationIndex,
  }) {
    final dayLimits = List<int>.generate(6, (d) => config.periodsForDay(d));

    // Initialize empty schedule grid
    final schedule = <String, List<List<ScheduledSlot?>>>{
      for (final c in classes)
        c: List.generate(
          6,
          (d) => List<ScheduledSlot?>.filled(dayLimits[d], null),
        ),
    };

    // Busy trackers: teacherBusy[teacher][day][period], roomBusy[room][day][period]
    final teacherBusy = <String, List<List<bool>>>{};
    final teacherDailyLoad = <String, List<int>>{};
    for (final t in assignments.map((a) => a.teacherInitial).toSet()) {
      teacherBusy[t] =
          List.generate(6, (d) => List<bool>.filled(dayLimits[d], false));
      teacherDailyLoad[t] = List<int>.filled(6, 0);
    }

    final roomBusy = <String, List<List<bool>>>{};
    for (final rm in assignments
        .map((a) => a.roomOrLab)
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toSet()) {
      roomBusy[rm] =
          List.generate(6, (d) => List<bool>.filled(dayLimits[d], false));
    }

    final workItems = assignments.map((a) => _MutableWorkItem(a)).toList();
    final workById = {for (final w in workItems) w.assignment.id: w};

    // Map Class -> Class Teacher Initial
    final classCT = <String, String?>{
      for (final c in classes)
        c: assignments
            .where((r) => r.className == c && r.isClassTeacher)
            .map((r) => r.teacherInitial)
            .firstOrNull,
    };

    void placeSlot(_MutableWorkItem item, int d, int k,
        {required bool isDouble, bool isLocked = false}) {
      final a = item.assignment;
      schedule[a.className]![d][k] = ScheduledSlot(
        assignmentId: a.id,
        teacherInitial: a.teacherInitial,
        subject: a.subject,
        className: a.className,
        isClassTeacher: a.isClassTeacher,
        isDoublePeriod: isDouble,
        roomOrLab: a.roomOrLab,
        isLocked: isLocked,
      );
      teacherBusy[a.teacherInitial]![d][k] = true;
      teacherDailyLoad[a.teacherInitial]![d]++;
      if (a.roomOrLab != null && a.roomOrLab!.trim().isNotEmpty) {
        roomBusy[a.roomOrLab!]![d][k] = true;
      }
      item.left--;
    }

    // 0. Restore any user-locked slots first
    if (existingScheduleWithLocks != null) {
      for (final c in classes) {
        final existingClassGrid = existingScheduleWithLocks[c];
        if (existingClassGrid == null) continue;
        for (int d = 0; d < 6; d++) {
          for (int k = 0;
              k < dayLimits[d] && k < existingClassGrid[d].length;
              k++) {
            final slot = existingClassGrid[d][k];
            if (slot != null && slot.isLocked) {
              final item = workById[slot.assignmentId];
              if (item != null &&
                  item.left > 0 &&
                  !(teacherBusy[slot.teacherInitial]?[d][k] ?? false)) {
                placeSlot(
                  item,
                  d,
                  k,
                  isDouble: slot.isDoublePeriod,
                  isLocked: true,
                );
              }
            }
          }
        }
      }
    }

    bool isTeacherAvailable(String tInit, int d, int k,
        {bool relaxDailyCap = false}) {
      if (teacherBusy[tInit]![d][k]) return false;
      final tm = teacherMap[tInit];
      if (tm != null && tm.isUnavailable(d, k)) return false;
      if (!relaxDailyCap &&
          teacherDailyLoad[tInit]![d] >= config.maxTeacherDailyLoad) {
        return false;
      }
      return true;
    }

    bool isRoomAvailable(String? room, int d, int k) {
      if (room == null || room.trim().isEmpty) return true;
      return !(roomBusy[room]?[d][k] ?? false);
    }

    bool isPeriodZeroReservedForCtOnDay(int d) {
      if (!config.reserveFirstPeriodForClassTeacher) return false;
      if (d == 5 && config.saturdayFirstPeriodSameSubjectEnabled) return false;
      return true;
    }

    // Check if class still has enough Class Teacher periods left to reserve Period-1
    bool canUsePeriodZero(_MutableWorkItem item, int d) {
      if (!isPeriodZeroReservedForCtOnDay(d)) return true;
      final a = item.assignment;
      final ctInit = classCT[a.className];
      if (ctInit == null || ctInit == a.teacherInitial) return true;
      final ctRemaining = workItems
          .where((w) =>
              w.assignment.className == a.className &&
              w.assignment.isClassTeacher)
          .fold<int>(0, (s, w) => s + w.left);
      return ctRemaining == 0;
    }

    bool canSingle(
      _MutableWorkItem item,
      int d,
      int k, {
      bool ignoreDailySubjectRepeat = false,
      bool relaxDailyCap = false,
    }) {
      final a = item.assignment;
      if (k >= dayLimits[d]) return false;
      if (schedule[a.className]![d][k] != null) return false;
      if (!isTeacherAvailable(a.teacherInitial, d, k,
          relaxDailyCap: relaxDailyCap)) return false;
      if (!isRoomAvailable(a.roomOrLab, d, k)) return false;
      if (k == 0 && !canUsePeriodZero(item, d)) return false;
      if (!ignoreDailySubjectRepeat &&
          schedule[a.className]![d]
              .any((x) => x != null && x.subject == a.subject)) {
        return false;
      }
      return true;
    }

    bool canPair(
      _MutableWorkItem item,
      int d,
      int k, {
      bool avoidBreakSplit = true,
      bool ignoreDailySubjectRepeat = false,
      bool relaxDailyCap = false,
    }) {
      final a = item.assignment;
      if (k + 1 >= dayLimits[d]) return false;
      if (avoidBreakSplit && breakAfterSet.contains(k + 1)) return false;
      if (k == 0 &&
          isPeriodZeroReservedForCtOnDay(d) &&
          classCT[a.className] != null &&
          classCT[a.className] != a.teacherInitial) {
        return false;
      }
      if (schedule[a.className]![d][k] != null ||
          schedule[a.className]![d][k + 1] != null) {
        return false;
      }
      if (!isTeacherAvailable(a.teacherInitial, d, k,
              relaxDailyCap: relaxDailyCap) ||
          !isTeacherAvailable(a.teacherInitial, d, k + 1,
              relaxDailyCap: relaxDailyCap)) {
        return false;
      }
      if (!relaxDailyCap &&
          teacherDailyLoad[a.teacherInitial]![d] + 2 >
              config.maxTeacherDailyLoad) {
        return false;
      }
      if (!isRoomAvailable(a.roomOrLab, d, k) ||
          !isRoomAvailable(a.roomOrLab, d, k + 1)) {
        return false;
      }
      if (!ignoreDailySubjectRepeat &&
          schedule[a.className]![d]
              .any((x) => x != null && x.subject == a.subject)) {
        return false;
      }
      return true;
    }

    // 0B. Saturday First Period Group-Wide Same Subject Option (e.g. P.T. / શા. શિ. across all selected classes simultaneously)
    if (config.saturdayFirstPeriodSameSubjectEnabled && dayLimits[5] > 0) {
      final satSubj = config.saturdayFirstPeriodSubject.trim().isNotEmpty
          ? config.saturdayFirstPeriodSubject.trim()
          : 'શા. શિ.';
      String satTeacher = config.saturdayFirstPeriodTeacherInitial.trim().toUpperCase();
      if (satTeacher.isEmpty) {
        final matchAssign = assignments
            .where((a) =>
                a.subject.trim().toLowerCase() == satSubj.toLowerCase() ||
                a.subject.toLowerCase().contains(satSubj.toLowerCase()) ||
                satSubj.toLowerCase().contains(a.subject.trim().toLowerCase()))
            .firstOrNull;
        if (matchAssign != null) {
          satTeacher = matchAssign.teacherInitial;
        } else {
          final matchTm = teacherMap.values
              .where((tm) => tm.taughtSubjects.any((s) =>
                  s.trim().toLowerCase() == satSubj.toLowerCase() ||
                  s.toLowerCase().contains(satSubj.toLowerCase())))
              .firstOrNull;
          if (matchTm != null) {
            satTeacher = matchTm.initial;
          }
        }
      }
      if (satTeacher.isNotEmpty) {
        teacherBusy.putIfAbsent(
          satTeacher,
          () => List.generate(6, (d) => List<bool>.filled(dayLimits[d], false)),
        );
        teacherDailyLoad.putIfAbsent(satTeacher, () => List<int>.filled(6, 0));
      }
      for (final c in classes) {
        if (schedule[c]![5][0] != null) continue;
        final matchingWork = workItems
            .where((w) =>
                w.assignment.className == c &&
                w.left > 0 &&
                (w.assignment.subject.trim().toLowerCase() == satSubj.toLowerCase() ||
                    w.assignment.subject.toLowerCase().contains(satSubj.toLowerCase()) ||
                    satSubj.toLowerCase().contains(w.assignment.subject.trim().toLowerCase())))
            .firstOrNull;
        final effectiveTeacher = satTeacher.isNotEmpty
            ? satTeacher
            : (matchingWork?.assignment.teacherInitial ??
                classCT[c] ??
                (assignments.where((a) => a.className == c).firstOrNull?.teacherInitial ?? 'PT'));
        teacherBusy.putIfAbsent(
          effectiveTeacher,
          () => List.generate(6, (d) => List<bool>.filled(dayLimits[d], false)),
        );
        teacherDailyLoad.putIfAbsent(effectiveTeacher, () => List<int>.filled(6, 0));
        schedule[c]![5][0] = ScheduledSlot(
          assignmentId: matchingWork?.assignment.id ?? 'sat_p1_$c',
          teacherInitial: effectiveTeacher,
          subject: matchingWork?.assignment.subject ?? satSubj,
          className: c,
          isClassTeacher: matchingWork?.assignment.isClassTeacher ?? false,
          isDoublePeriod: false,
          roomOrLab: matchingWork?.assignment.roomOrLab,
          isLocked: true,
        );
        if (matchingWork != null && matchingWork.left > 0) {
          matchingWork.left--;
        }
        teacherBusy[effectiveTeacher]![5][0] = true;
      }
      if (satTeacher.isNotEmpty) {
        teacherDailyLoad[satTeacher]![5]++;
      }
    }

    // 1. Lock Period-1 (index 0) for Class Teachers on days where CT reservation is active
    for (int d = 0; d < 6; d++) {
      if (dayLimits[d] == 0) continue;
      if (!isPeriodZeroReservedForCtOnDay(d)) continue;
      final rotatedClasses = List<String>.generate(
        classes.length,
        (idx) => classes[(idx + d) % classes.length],
      );
      for (final c in rotatedClasses) {
        if (schedule[c]![d][0] != null) continue;
        final ctCandidates = workItems
            .where((w) =>
                w.assignment.className == c &&
                w.assignment.isClassTeacher &&
                w.left > 0 &&
                canSingle(w, d, 0, ignoreDailySubjectRepeat: true))
            .toList();
        if (ctCandidates.isEmpty) continue;

        // Sort so we rotate subjects and prioritize remaining load / pairs
        ctCandidates.sort((x, y) {
          final cmpLeft = y.left.compareTo(x.left);
          if (cmpLeft != 0) return cmpLeft;
          return y.pairsLeft.compareTo(x.pairsLeft);
        });

        final chosen = ctCandidates.first;
        // Only make Period 1+2 a double period if the CT won't run out of Period-1s for remaining days
        final remainingDaysAfterToday = 5 - d;
        final totalCtLeftInClass = workItems
            .where((w) =>
                w.assignment.className == c && w.assignment.isClassTeacher)
            .fold<int>(0, (s, w) => s + w.left);

        if (chosen.assignment.isDoublePeriod &&
            chosen.pairsLeft > 0 &&
            (totalCtLeftInClass - 2) >= remainingDaysAfterToday &&
            canPair(chosen, d, 0,
                avoidBreakSplit: true, ignoreDailySubjectRepeat: true)) {
          placeSlot(chosen, d, 0, isDouble: true);
          placeSlot(chosen, d, 1, isDouble: true);
          chosen.pairsLeft--;
        } else {
          placeSlot(chosen, d, 0, isDouble: false);
        }
      }
    }

    // 2. PHASE 2: Place Continuous 2-Period (Double Period) Pairs
    // First pass strictly avoids splitting across a Break; second pass relaxes if unavoidable.
    final dblItems = workItems
        .where((w) => w.assignment.isDoublePeriod && w.pairsLeft > 0)
        .toList()
      ..sort((a, b) => b.pairsLeft.compareTo(a.pairsLeft) != 0
          ? b.pairsLeft.compareTo(a.pairsLeft)
          : b.left.compareTo(a.left));

    for (final item in dblItems) {
      for (int relaxBreak = 0;
          relaxBreak <= 1 && item.pairsLeft > 0 && item.left >= 2;
          relaxBreak++) {
        int guard = 0;
        while (item.pairsLeft > 0 && item.left >= 2 && guard++ < 30) {
          final options = <List<int>>[];
          for (int d = 0; d < 6; d++) {
            // Avoid placing two double-blocks of the same assignment on the same day
            if (schedule[item.assignment.className]![d].any(
                (x) => x != null && x.assignmentId == item.assignment.id)) {
              continue;
            }
            for (int k = 1; k < dayLimits[d] - 1; k++) {
              if (canPair(
                item,
                d,
                k,
                avoidBreakSplit: relaxBreak == 0,
                ignoreDailySubjectRepeat: true,
              )) {
                options.add([d, k]);
              }
            }
          }
          if (options.isEmpty) break;
          options.shuffle(random);
          // Prefer days where the teacher has lower daily load
          options.sort((a, b) =>
              teacherDailyLoad[item.assignment.teacherInitial]![a[0]].compareTo(
                  teacherDailyLoad[item.assignment.teacherInitial]![b[0]]));
          final chosen = options.first;
          placeSlot(item, chosen[0], chosen[1], isDouble: true);
          placeSlot(item, chosen[0], chosen[1] + 1, isDouble: true);
          item.pairsLeft--;
        }
      }
    }

    // 3. PHASE 3: MRV (Minimum Remaining Values) Single Period Placement
    // Pass 0: Strict 1-period-per-subject-per-day + daily load cap
    // Pass 1: Allows >1 period on same day + daily load cap
    // Pass 2: Allows >1 period on same day + relaxes daily load cap (HTML compatibility)
    for (int pass = 0; pass < 3; pass++) {
      int guard = 0;
      while (workItems.any((w) => w.left > 0) && guard++ < 8000) {
        final candidates = <({_MutableWorkItem item, List<List<int>> moves})>[];

        for (final w in workItems) {
          if (w.left <= 0) continue;
          final moves = <List<int>>[];
          for (int d = 0; d < 6; d++) {
            for (int k = 0; k < dayLimits[d]; k++) {
              if (canSingle(
                w,
                d,
                k,
                ignoreDailySubjectRepeat: pass >= 1,
                relaxDailyCap: pass >= 2,
              )) {
                moves.add([d, k]);
              }
            }
          }
          if (moves.isNotEmpty) {
            candidates.add((item: w, moves: moves));
          }
        }

        if (candidates.isEmpty) break;

        candidates.sort((a, b) {
          final cmpMoves = a.moves.length.compareTo(b.moves.length);
          if (cmpMoves != 0) return cmpMoves;
          return b.item.left.compareTo(a.item.left);
        });

        final selected = candidates.first;
        selected.moves.shuffle(random);
        selected.moves.sort((m1, m2) =>
            teacherDailyLoad[selected.item.assignment.teacherInitial]![m1[0]]
                .compareTo(teacherDailyLoad[
                    selected.item.assignment.teacherInitial]![m2[0]]));

        final move = selected.moves.first;
        placeSlot(selected.item, move[0], move[1], isDouble: false);
      }
    }

    // 4. PHASE 4: 1-Hop & 2-Hop Kempe-Chain Swap Repair (Zero-Clash Guaranteed)
    for (final w in workItems.where((x) => x.left > 0)) {
      final c = w.assignment.className;
      for (int d1 = 0; d1 < 6 && w.left > 0; d1++) {
        for (int k1 = 0; k1 < dayLimits[d1] && w.left > 0; k1++) {
          if (k1 == 0 && !canUsePeriodZero(w, d1)) continue;
          if (!isTeacherAvailable(w.assignment.teacherInitial, d1, k1,
              relaxDailyCap: true)) {
            continue;
          }
          if (!isRoomAvailable(w.assignment.roomOrLab, d1, k1)) continue;

          final existing = schedule[c]![d1][k1];
          if (existing == null ||
              existing.isLocked ||
              existing.isDoublePeriod) {
            continue;
          }

          // 4A: Look for an empty slot (d2, k2) in class `c` where `existing` can move
          bool swapped = false;
          for (int d2 = 0; d2 < 6 && !swapped; d2++) {
            for (int k2 = 0; k2 < dayLimits[d2] && !swapped; k2++) {
              if (k2 == 0 &&
                  isPeriodZeroReservedForCtOnDay(d2) &&
                  classCT[c] != null &&
                  classCT[c] != existing.teacherInitial) continue;
              if (schedule[c]![d2][k2] != null) continue;
              if (!isTeacherAvailable(existing.teacherInitial, d2, k2,
                  relaxDailyCap: true)) {
                continue;
              }
              if (!isRoomAvailable(existing.roomOrLab, d2, k2)) continue;

              teacherBusy[existing.teacherInitial]![d1][k1] = false;
              teacherDailyLoad[existing.teacherInitial]![d1]--;
              if (existing.roomOrLab != null &&
                  existing.roomOrLab!.trim().isNotEmpty) {
                roomBusy[existing.roomOrLab!]![d1][k1] = false;
              }

              schedule[c]![d2][k2] = existing;
              teacherBusy[existing.teacherInitial]![d2][k2] = true;
              teacherDailyLoad[existing.teacherInitial]![d2]++;
              if (existing.roomOrLab != null &&
                  existing.roomOrLab!.trim().isNotEmpty) {
                roomBusy[existing.roomOrLab!]![d2][k2] = true;
              }

              schedule[c]![d1][k1] = null;
              placeSlot(w, d1, k1, isDouble: false);
              swapped = true;
            }
          }
        }
      }
    }

    final unplacedList = workItems
        .where((w) => w.left > 0 || w.pairsLeft > 0)
        .map((w) => UnplacedAssignmentInfo(
              assignment: w.assignment,
              remainingPeriods: w.left,
              unplacedDoublePairs: max(0, w.pairsLeft),
            ))
        .toList();

    final unplacedPeriodsCount =
        workItems.fold<int>(0, (s, w) => s + max(0, w.left));
    final unplacedPairsCount =
        workItems.fold<int>(0, (s, w) => s + max(0, w.pairsLeft));

    return TimetableSolution(
      schedule: schedule,
      unplaced: unplacedList,
      unplacedPeriodsCount: unplacedPeriodsCount,
      unplacedPairsCount: unplacedPairsCount,
      solverIterationsUsed: iterationIndex,
    );
  }

  /// Evaluates soft quality metrics: minimizes same-day duplicate single subjects
  /// and balances daily teacher load variance.
  static double _evaluateSoftQualityPenalty(
    Map<String, List<List<ScheduledSlot?>>> schedule,
    SchoolConfig config,
  ) {
    double penalty = 0;
    for (final classGrid in schedule.values) {
      for (int d = 0; d < 6; d++) {
        final seenSubjects = <String, int>{};
        for (final slot in classGrid[d]) {
          if (slot == null) continue;
          seenSubjects[slot.subject] = (seenSubjects[slot.subject] ?? 0) + 1;
        }
        for (final entry in seenSubjects.entries) {
          if (entry.value > 2) {
            penalty += (entry.value - 2) * 3.0;
          }
        }
      }
    }
    return penalty;
  }

  /// Validates if swapping (d1, k1) and (d2, k2) inside `className` causes any teacher or room clash
  static String? checkSwapError({
    required Map<String, List<List<ScheduledSlot?>>> schedule,
    required List<TeacherMaster> teachers,
    required String className,
    required int d1,
    required int k1,
    required int d2,
    required int k2,
    SchoolConfig? config,
  }) {
    if (d1 == d2 && k1 == k2) return null;
    final slotA = schedule[className]?[d1][k1];
    final slotB = schedule[className]?[d2][k2];
    final teacherMap = {for (final t in teachers) t.initial: t};

    // Helper to check if a slot can sit at target (targetD, targetK)
    String? canSitAt(ScheduledSlot? slot, int targetD, int targetK) {
      if (slot == null) return null;
      final reserveCt = (config?.reserveFirstPeriodForClassTeacher ?? true) &&
          !(targetD == 5 &&
              (config?.saturdayFirstPeriodSameSubjectEnabled ?? false));
      if (targetK == 0 && reserveCt && !slot.isClassTeacher) {
        return 'તાસ 1 (Period 1) માત્ર વર્ગ શિક્ષક (Class Teacher) માટે અનામત છે.';
      }
      final tm = teacherMap[slot.teacherInitial];
      if (tm != null && tm.isUnavailable(targetD, targetK)) {
        return 'શિક્ષક ${slot.teacherInitial} એ સમયે ઉપલબ્ધ નથી (Marked Unavailable).';
      }
      for (final entry in schedule.entries) {
        if (entry.key == className) continue;
        final otherDaySlots = entry.value[targetD];
        if (targetK >= otherDaySlots.length) continue;
        final other = otherDaySlots[targetK];
        if (other != null) {
          if (other.teacherInitial == slot.teacherInitial) {
            return 'ક્લેશ (Clash)! શિક્ષક ${slot.teacherInitial} તે સમયે વર્ગ ${entry.key} માં (${other.subject}) ભણાવે છે.';
          }
          if (slot.roomOrLab != null &&
              slot.roomOrLab!.isNotEmpty &&
              other.roomOrLab == slot.roomOrLab) {
            return 'રૂમ/લેબ ક્લેશ! ${slot.roomOrLab} તે સમયે વર્ગ ${entry.key} માં વપરાશમાં છે.';
          }
        }
      }
      return null;
    }

    return canSitAt(slotA, d2, k2) ?? canSitAt(slotB, d1, k1);
  }

  /// Finds available substitute (Proxy) teachers when a teacher is absent on `dayIndex` at `periodIndex`
  static List<ProxyCandidate> findSubstituteTeachers({
    required Map<String, List<List<ScheduledSlot?>>> schedule,
    required List<TeacherMaster> teachers,
    required List<TeachingAssignment> assignments,
    required String targetClassName,
    required String absentSubject,
    required int dayIndex,
    required int periodIndex,
  }) {
    final busyTeachersAtSlot = <String>{};
    final dayLoad = <String, int>{};
    final weekLoad = <String, int>{};

    for (final classGrid in schedule.values) {
      for (int d = 0; d < 6; d++) {
        for (int k = 0; k < classGrid[d].length; k++) {
          final slot = classGrid[d][k];
          if (slot == null) continue;
          weekLoad[slot.teacherInitial] =
              (weekLoad[slot.teacherInitial] ?? 0) + 1;
          if (d == dayIndex) {
            dayLoad[slot.teacherInitial] =
                (dayLoad[slot.teacherInitial] ?? 0) + 1;
            if (k == periodIndex) {
              busyTeachersAtSlot.add(slot.teacherInitial);
            }
          }
        }
      }
    }

    final candidates = <ProxyCandidate>[];
    for (final t in teachers) {
      if (busyTeachersAtSlot.contains(t.initial)) continue;
      if (t.isUnavailable(dayIndex, periodIndex)) continue;

      final teachesClass = assignments.any((a) =>
          a.teacherInitial == t.initial && a.className == targetClassName);
      final teachesSubject = assignments.any(
          (a) => a.teacherInitial == t.initial && a.subject == absentSubject);

      candidates.add(ProxyCandidate(
        teacher: t,
        currentDayLoad: dayLoad[t.initial] ?? 0,
        currentWeekLoad: weekLoad[t.initial] ?? 0,
        teachesSameClass: teachesClass,
        teachesSameSubject: teachesSubject,
      ));
    }

    candidates.sort((a, b) => b.priorityScore.compareTo(a.priorityScore));
    return candidates;
  }
}

// ============================================================================
// 3. COLOR PALETTE GENERATOR FOR TEACHER CELLS
// ============================================================================

class TeacherColorPalette {
  final Color main;
  final Color background;
  final Color border;
  final Color text;

  const TeacherColorPalette({
    required this.main,
    required this.background,
    required this.border,
    required this.text,
  });

  static const List<TeacherColorPalette> _distinctPalettes = [
    // 1. Royal Indigo / Blue
    TeacherColorPalette(
      main: Color(0xFF2563EB),
      background: Color(0xFFDBEAFE),
      border: Color(0xFF60A5FA),
      text: Color(0xFF1E3A8A),
    ),
    // 2. Emerald Green
    TeacherColorPalette(
      main: Color(0xFF059669),
      background: Color(0xFFD1FAE5),
      border: Color(0xFF34D399),
      text: Color(0xFF064E3B),
    ),
    // 3. Warm Amber / Gold
    TeacherColorPalette(
      main: Color(0xFFD97706),
      background: Color(0xFFFEF3C7),
      border: Color(0xFFFBBF24),
      text: Color(0xFF78350F),
    ),
    // 4. Rose / Crimson
    TeacherColorPalette(
      main: Color(0xFFE11D48),
      background: Color(0xFFFFE4E6),
      border: Color(0xFFFB7185),
      text: Color(0xFF881337),
    ),
    // 5. Purple / Violet
    TeacherColorPalette(
      main: Color(0xFF7C3AED),
      background: Color(0xFFEDE9FE),
      border: Color(0xFFA78BFA),
      text: Color(0xFF4C1D95),
    ),
    // 6. Teal / Cyan
    TeacherColorPalette(
      main: Color(0xFF0D9488),
      background: Color(0xFFCCFBF1),
      border: Color(0xFF2DD4BF),
      text: Color(0xFF134E4A),
    ),
    // 7. Deep Orange / Coral
    TeacherColorPalette(
      main: Color(0xFFEA580C),
      background: Color(0xFFFFEDD5),
      border: Color(0xFFFB923C),
      text: Color(0xFF7C2D12),
    ),
    // 8. Fuchsia / Magenta
    TeacherColorPalette(
      main: Color(0xFFC026D3),
      background: Color(0xFFFAE8FF),
      border: Color(0xFFE879F9),
      text: Color(0xFF701A75),
    ),
    // 9. Sky / Cerulean
    TeacherColorPalette(
      main: Color(0xFF0284C7),
      background: Color(0xFFE0F2FE),
      border: Color(0xFF38BDF8),
      text: Color(0xFF0C4A6E),
    ),
    // 10. Lime / Olive Green
    TeacherColorPalette(
      main: Color(0xFF65A30D),
      background: Color(0xFFECFCCB),
      border: Color(0xFFA3E635),
      text: Color(0xFF365314),
    ),
    // 11. Pink / Berry
    TeacherColorPalette(
      main: Color(0xFFDB2777),
      background: Color(0xFFFCE7F3),
      border: Color(0xFFF472B6),
      text: Color(0xFF831843),
    ),
    // 12. Indigo Slate
    TeacherColorPalette(
      main: Color(0xFF4F46E5),
      background: Color(0xFFE0E7FF),
      border: Color(0xFF818CF8),
      text: Color(0xFF312E81),
    ),
    // 13. Cyan / Aqua
    TeacherColorPalette(
      main: Color(0xFF0891B2),
      background: Color(0xFFCFFAFE),
      border: Color(0xFF22D3EE),
      text: Color(0xFF164E63),
    ),
    // 14. Yellow / Mustard
    TeacherColorPalette(
      main: Color(0xFFCA8A04),
      background: Color(0xFFFEF9C3),
      border: Color(0xFFFACC15),
      text: Color(0xFF713F12),
    ),
    // 15. Red / Terracotta
    TeacherColorPalette(
      main: Color(0xFFDC2626),
      background: Color(0xFFFEE2E2),
      border: Color(0xFFF87171),
      text: Color(0xFF7F1D1D),
    ),
    // 16. Forest Green
    TeacherColorPalette(
      main: Color(0xFF16A34A),
      background: Color(0xFFDCFCE7),
      border: Color(0xFF4ADE80),
      text: Color(0xFF14532D),
    ),
  ];

  static TeacherColorPalette fromInitial(
    String initial, {
    List<String>? orderedInitials,
  }) {
    final clean = initial.trim().toUpperCase();
    if (orderedInitials != null && orderedInitials.isNotEmpty) {
      final idx = orderedInitials.indexOf(clean);
      if (idx >= 0) {
        return _distinctPalettes[idx % _distinctPalettes.length];
      }
    }
    int hash = 0;
    for (final code in clean.codeUnits) {
      hash = ((hash * 37) + code) & 0x7FFFFFFF;
    }
    return _distinctPalettes[hash % _distinctPalettes.length];
  }
}

// ============================================================================
// 4. MAIN FLUTTER STUDIO STATEFUL WIDGET
// ============================================================================

class TimetableStudioHome extends StatefulWidget {
  const TimetableStudioHome({
    super.key,
    this.useDatabaseData = false,
    this.databaseData = const <String, dynamic>{},
    this.savedData = const <String, dynamic>{},
    this.onSaveData,
    this.embedded = false,
  });

  final bool useDatabaseData;
  final Map<String, dynamic> databaseData;
  final Map<String, dynamic> savedData;
  final Future<void> Function(Map<String, dynamic>)? onSaveData;
  final bool embedded;

  @override
  State<TimetableStudioHome> createState() => _TimetableStudioHomeState();
}

class _TimetableStudioHomeState extends State<TimetableStudioHome>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Core State
  SchoolConfig config = SchoolConfig();
  List<PeriodTiming> periodTimings = [];
  List<BreakConfig> breaks = [
    BreakConfig(
      name: 'મુખ્ય રિસેસ / Recess',
      afterPeriod: 4,
      start: '12:50',
      end: '13:20',
    ),
  ];
  List<TeacherMaster> teachers = [];
  List<String> subjects = [];
  List<TeachingAssignment> assignments = [];
  PageDesignConfig pageDesign = PageDesignConfig();

  // Logo & Watermark Studio State (Supports 2 movable logos or same logo on both sides)
  bool showLogo = true;
  bool showSecondLogo = true;
  bool useSameLogoBothSides = true;
  bool showWatermark = true;
  String activeBrandLayer = 'logo'; // 'logo', 'logo2', or 'watermark'
  Uint8List? _customUploadedLogoBytes;
  String _customUploadedLogoDataUri = '';
  Uint8List? _customUploadedLogo2Bytes;
  String _customUploadedLogo2DataUri = '';
  OverlayLayerStyle logoStyle = OverlayLayerStyle(
    xPercent: 10,
    yPercent: 12,
    widthPx: 64,
    heightPx: 64,
    opacity: 1.0,
    shape: 'original',
  );
  OverlayLayerStyle logo2Style = OverlayLayerStyle(
    xPercent: 90,
    yPercent: 12,
    widthPx: 64,
    heightPx: 64,
    opacity: 1.0,
    shape: 'original',
  );
  OverlayLayerStyle watermarkStyle = OverlayLayerStyle(
    xPercent: 50,
    yPercent: 55,
    widthPx: 210,
    heightPx: 210,
    opacity: 0.10,
    shape: 'round',
  );

  // Generated Solution & Interactive Selection State
  TimetableSolution? currentSolution;
  String selectedViewMode =
      'class'; // class, teacher, whole, allteachers, mastergrid
  String? selectedEntity;
  ({String className, int day, int period})? selectedSlotForSwap;

  // Quick-Add Form State (Preserved across adds!)
  String? quickTeacher;
  String? quickSubject;
  String quickLevel = '6';
  String quickSection = 'A';
  String? quickDatabaseClass;
  bool quickIsClassTeacher = true;
  int quickRequiredPeriods = 6;
  int? quickMaxPeriods;
  bool quickIsDoublePeriod = false;
  String quickRoomOrLab = '';
  String timetablePrintDate = '';
  String schoolNameLang = 'gu';

  String get _resolvedRegisteredSchoolName {
    final gu = (widget.databaseData['schoolNameGu'] ?? widget.databaseData['schoolName'] ?? '').toString().trim();
    final en = (widget.databaseData['schoolNameEn'] ?? widget.databaseData['schoolName'] ?? '').toString().trim();
    if (schoolNameLang == 'en') {
      return en.isNotEmpty ? en : (gu.isNotEmpty ? gu : config.schoolName);
    }
    return gu.isNotEmpty ? gu : (en.isNotEmpty ? en : config.schoolName);
  }

  // Proxy Finder State
  int proxyDayIndex = 0;
  int proxyPeriodIndex = 1;
  String? proxySelectedClass;

  // Class Selection Filter State (3 to 5, 6 to 8, 3 to 8, 1 to 5, All, or Custom)
  Set<String> selectedClassesForGeneration = <String>{};
  String activeClassPreset =
      'all'; // '3to5', '6to8', '3to8', '1to5', 'all', 'custom'

  // Teacher Initials Persistence Maps (by teacherId and by lowercased fullName)
  Map<String, String> teacherInitialsById = <String, String>{};
  Map<String, String> teacherInitialsByName = <String, String>{};

  // Device Auto-Save State
  Timer? _autoSaveTimer;
  bool autoSaveEnabled = true;
  // PSM_TAB4_OVERFLOW_SPEED_FIX_20261031_V2
  bool _initialTimetableGenerationScheduled = false;
  String _lastDeviceSaveStatus = '⚡ ઓટો-સેવ સક્રિય (Auto-Save ON)';

  // Controllers for Master Inputs
  final TextEditingController _teacherFullCtrl = TextEditingController();
  final TextEditingController _teacherInitCtrl = TextEditingController();
  final TextEditingController _subjectCtrl = TextEditingController();
  final TextEditingController _roomCtrl = TextEditingController();

  String get _deviceSaveKey {
    final schoolRef =
        (widget.databaseData['schoolRef'] ?? '').toString().trim();
    return schoolRef.isNotEmpty
        ? 'psm_timetable_device_autosave_$schoolRef'
        : 'psm_timetable_device_autosave_v1';
  }

  static const String _deviceTimingsKey = 'psm_timetable_timings_v1';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _initDefaultTimings();
    if (widget.useDatabaseData) {
      _loadDatabaseMasters();
      _loadDatabaseAssignments();
      _applySavedDatabaseData(widget.savedData);
      if (teachers.isEmpty) {
        _loadDemoMasters();
      }
      if (assignments.isEmpty) {
        _autoBuildAssignmentsFromCurrentMasters();
      }
    } else {
      _loadDemoMasters();
      _loadDemoAssignments();
    }
    _syncSelectedClassesWithAvailable();
    // Restore device settings first, then generate after the first frame. The
    // timetable solver can be CPU-intensive for large schools, so it should
    // not delay the first visible frame of the studio.
    _loadFromDeviceAutoSave().whenComplete(_scheduleInitialTimetableGeneration);
  }

  void _scheduleInitialTimetableGeneration() {
    if (_initialTimetableGenerationScheduled) return;
    _initialTimetableGenerationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || currentSolution != null || activeAssignments.isEmpty) {
        return;
      }
      _runGenerate(switchTab: false, showNotification: false);
    });
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _tabController.dispose();
    _teacherFullCtrl.dispose();
    _teacherInitCtrl.dispose();
    _subjectCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFromDeviceAutoSave() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      autoSaveEnabled = prefs.getBool('psm_timetable_autosave_enabled') ?? true;
      // 1. Load standalone saved timings & breaks first (so once time is entered on device, it is always remembered!)
      final rawTimings = prefs.getString(_deviceTimingsKey);
      bool loadedAny = false;
      if (rawTimings != null && rawTimings.isNotEmpty) {
        final tMap = _asPlanningMap(jsonDecode(rawTimings));
        final tList = tMap['times'];
        if (tList is List && tList.isNotEmpty) {
          periodTimings = tList
              .whereType<Map>()
              .map((row) => PeriodTiming.fromJson(_asPlanningMap(row)))
              .toList();
          loadedAny = true;
        }
        final bList = tMap['breaks'];
        if (bList is List && bList.isNotEmpty) {
          breaks = bList
              .whereType<Map>()
              .map((row) => BreakConfig.fromJson(_asPlanningMap(row)))
              .toList();
          loadedAny = true;
        }
      }

      // 2. Load full device save for this school
      final rawFull = prefs.getString(_deviceSaveKey) ??
          prefs.getString('psm_timetable_device_autosave_v1');
      if (rawFull != null && rawFull.isNotEmpty) {
        final savedMap = _asPlanningMap(jsonDecode(rawFull));
        if (savedMap.isNotEmpty) {
          _applySavedDatabaseData(savedMap);
          loadedAny = true;
          final savedAt = (savedMap['savedAt'] ?? '').toString();
          if (savedAt.isNotEmpty) {
            final dt = DateTime.tryParse(savedAt)?.toLocal();
            if (dt != null) {
              _lastDeviceSaveStatus =
                  '✅ ડિવાઇસમાંથી લોડ થયું (${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')})';
            }
          }
        }
      }
      if (loadedAny && mounted) {
        setState(() {
          _initDefaultTimings();
          _syncSelectedClassesWithAvailable();
        });
        // Initial generation is scheduled once by initState after this
        // restore Future completes; do not solve twice during startup.
      }
    } catch (_) {}
  }

  void _scheduleDeviceAutoSave({bool immediate = false}) {
    if (!autoSaveEnabled && !immediate) return;
    _autoSaveTimer?.cancel();
    if (immediate) {
      _saveToDeviceNow(manual: false);
    } else {
      _autoSaveTimer = Timer(const Duration(milliseconds: 350), () {
        _saveToDeviceNow(manual: false);
      });
    }
  }

  Future<void> _saveToDeviceNow({bool manual = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = _exportJsonBackup();
      await prefs.setString(_deviceSaveKey, jsonStr);
      await prefs.setString('psm_timetable_device_autosave_v1', jsonStr);
      // Also save standalone timings & breaks so period timings are always remembered on device
      final timingsPayload = jsonEncode(<String, dynamic>{
        'times': periodTimings.map((e) => e.toJson()).toList(),
        'breaks': breaks.map((e) => e.toJson()).toList(),
        'savedAt': DateTime.now().toIso8601String(),
      });
      await prefs.setString(_deviceTimingsKey, timingsPayload);
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      if (mounted) {
        setState(() {
          _lastDeviceSaveStatus = manual
              ? '✅ ડિવાઇસમાં સેવ થયું: $timeStr'
              : '⚡ ઓટો-સેવ (Device Saved): $timeStr';
        });
      }
      if (manual) {
        _showSnack('✅ સમયપત્રક અને તાસનો સમય આ ડિવાઇસમાં સેવ થઈ ગયો!');
      }
    } catch (e) {
      if (manual) {
        _showSnack('ડિવાઇસમાં સેવ કરવામાં ભૂલ: $e', isError: true);
      }
    }
  }

  void _initDefaultTimings() {
    const defaults = [
      ('10:50', '11:30'),
      ('11:30', '12:10'),
      ('12:10', '12:50'),
      ('13:20', '14:00'),
      ('14:00', '14:40'),
      ('14:40', '15:20'),
      ('15:20', '16:00'),
      ('16:00', '16:40'),
      ('16:40', '17:15'),
      ('17:15', '17:50'),
    ];
    final maxP = max(config.monFriPeriods, config.saturdayPeriods);
    periodTimings = List.generate(maxP, (i) {
      if (i < periodTimings.length &&
          (periodTimings[i].start.isNotEmpty ||
              periodTimings[i].end.isNotEmpty)) {
        return periodTimings[i];
      }
      if (i < defaults.length) {
        return PeriodTiming(start: defaults[i].$1, end: defaults[i].$2);
      }
      return PeriodTiming(start: '', end: '');
    });
  }

  Map<String, dynamic> _asPlanningMap(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _planningRows(String key) {
    final value = widget.databaseData[key];
    if (value is! List) return <Map<String, dynamic>>[];
    return value.whereType<Map>().map(_asPlanningMap).toList();
  }

  String _normalizeClassName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final aliasMap = widget.databaseData['classAliasesToLabel'];
    if (aliasMap is Map) {
      final direct = aliasMap[trimmed] ?? aliasMap[trimmed.toUpperCase()];
      if (direct != null && direct.toString().trim().isNotEmpty) {
        return direct.toString().trim();
      }
    }
    for (final row in _planningRows('classes')) {
      final label = (row['label'] ?? row['classKey'] ?? '').toString().trim();
      if (label.isEmpty) continue;
      final candidates = <String>{
        label,
        (row['classKey'] ?? '').toString().trim(),
        (row['id'] ?? '').toString().trim(),
        (row['timetableClassName'] ?? '').toString().trim(),
        (row['legacyTimetableClassName'] ?? '').toString().trim(),
      };
      if (candidates.any(
          (c) => c.isNotEmpty && c.toLowerCase() == trimmed.toLowerCase())) {
        return label;
      }
    }
    return trimmed;
  }

  /// Extracts integer standard (e.g. 1..12) for a class display name using DB metadata or digits.
  int? _standardIntOfClass(String className) {
    String normDigits(String s) {
      const guj = '૦૧૨૩૪૫૬૭૮૯';
      var res = s;
      for (int i = 0; i < guj.length; i++) {
        res = res.replaceAll(guj[i], '$i');
      }
      return res;
    }

    final normName = _normalizeClassName(className);
    for (final row in _planningRows('classes')) {
      final lbl = _normalizeClassName(
          (row['label'] ?? row['classKey'] ?? '').toString());
      if (lbl.toLowerCase() == normName.toLowerCase()) {
        final stdRaw = normDigits((row['standard'] ?? '').toString());
        final m = RegExp(r'\d+').firstMatch(stdRaw);
        if (m != null) return int.tryParse(m.group(0)!);
      }
    }
    final cleaned = normDigits(normName);
    if (cleaned.toUpperCase().contains('BAL') || cleaned.contains('બાલ')) {
      return 0;
    }
    final m = RegExp(r'\d+').firstMatch(cleaned);
    return m != null ? int.tryParse(m.group(0)!) : null;
  }

  /// All available classes in the school (before filtering by selectedClassesForGeneration).
  List<String> get allAvailableClasses {
    final dbRows = _planningRows('classes');
    if (dbRows.isNotEmpty) {
      final ordered = <String>[];
      for (final row in dbRows) {
        final label = _normalizeClassName(
            (row['label'] ?? row['timetableClassName'] ?? row['classKey'] ?? '')
                .toString());
        if (label.isNotEmpty && !ordered.contains(label)) {
          ordered.add(label);
        }
      }
      for (final a in assignments) {
        final norm = _normalizeClassName(a.className);
        if (norm.isNotEmpty && !ordered.contains(norm)) {
          ordered.add(norm);
        }
      }
      return ordered;
    }
    final values = <String>{
      ...assignments.map((a) => _normalizeClassName(a.className))
    };
    return TimetableSolverEngine.sortedClasses(values);
  }

  /// Active selected classes for timetable generation and viewing.
  List<String> get allClasses {
    final avail = allAvailableClasses;
    if (selectedClassesForGeneration.isEmpty) return avail;
    final filtered =
        avail.where((c) => selectedClassesForGeneration.contains(c)).toList();
    return filtered.isNotEmpty ? filtered : avail;
  }

  /// Assignments filtered to ONLY the currently selected classes!
  List<TeachingAssignment> get activeAssignments {
    final targetSet = allClasses.toSet();
    return assignments
        .where((a) => targetSet.contains(_normalizeClassName(a.className)))
        .toList();
  }

  void _syncSelectedClassesWithAvailable() {
    final avail = allAvailableClasses;
    if (avail.isEmpty) return;
    selectedClassesForGeneration.removeWhere((c) => !avail.contains(c));
    if (selectedClassesForGeneration.isEmpty) {
      if (activeClassPreset != 'all' && activeClassPreset != 'custom') {
        _applyClassRangePreset(activeClassPreset, triggerSolve: false);
      } else {
        selectedClassesForGeneration.addAll(avail);
        activeClassPreset = 'all';
      }
    }
  }

  void _applyClassRangePreset(String preset, {bool triggerSolve = true}) {
    final avail = allAvailableClasses;
    final matched = <String>{};
    for (final c in avail) {
      final std = _standardIntOfClass(c);
      if (preset == '3to5') {
        if (std != null && std >= 3 && std <= 5) matched.add(c);
      } else if (preset == '6to8') {
        if (std != null && std >= 6 && std <= 8) matched.add(c);
      } else if (preset == '3to8') {
        if (std != null && std >= 3 && std <= 8) matched.add(c);
      } else if (preset == '1to5') {
        if (std != null && std >= 1 && std <= 5) matched.add(c);
      } else {
        matched.add(c);
      }
    }
    setState(() {
      activeClassPreset = preset;
      if (matched.isNotEmpty) {
        selectedClassesForGeneration = matched;
      } else {
        selectedClassesForGeneration = avail.toSet();
      }
      _ensureAssignmentsExistForSelectedClasses();
      if (selectedEntity != null && !allClasses.contains(selectedEntity)) {
        selectedEntity = allClasses.firstOrNull;
      }
    });
    _scheduleDeviceAutoSave();
    if (triggerSolve) {
      if (matched.isEmpty && preset != 'all') {
        _showSnack(
            'આ ધોરણ જૂથના વર્ગો મળ્યા નથી, તેથી બધા વર્ગો પસંદ કર્યા છે.',
            isError: true);
      } else {
        _runGenerate(switchTab: false, showNotification: true);
      }
    }
  }

  void _ensureAssignmentsExistForSelectedClasses() {
    if (teachers.isEmpty) return;
    final poolSubjects = subjects.isNotEmpty
        ? subjects
        : <String>[
            'ગુજરાતી',
            'ગણિત',
            'પર્યાવરણ',
            'વિજ્ઞાન',
            'સામાજિક વિજ્ઞાન',
            'અંગ્રેજી',
            'હિન્દી',
            'સંસ્કૃત',
          ];
    final slots = config.weeklySlotsPerClass;
    final targetClasses = allClasses;
    for (int cIdx = 0; cIdx < targetClasses.length; cIdx++) {
      final cName = targetClasses[cIdx];
      final hasAny =
          assignments.any((a) => _normalizeClassName(a.className) == cName);
      if (hasAny) continue;
      final coreSubjects = poolSubjects.take(7).toList();
      final count = coreSubjects.length;
      final base = slots ~/ count;
      var rem = slots % count;
      for (var sIdx = 0; sIdx < count; sIdx++) {
        final extra = rem > 0 ? 1 : 0;
        if (rem > 0) rem--;
        final req = (base + extra).clamp(1, 14);
        final subj = coreSubjects[sIdx];
        // Prefer a teacher who teaches this subject in DB!
        final dbTeacher = teachers
                .where((t) =>
                    t.taughtSubjects.contains(subj) &&
                    (t.assignedClasses.isEmpty ||
                        t.assignedClasses.contains(cName)))
                .firstOrNull ??
            teachers
                .where((t) => t.taughtSubjects.contains(subj))
                .firstOrNull ??
            teachers[(cIdx + sIdx) % teachers.length];
        assignments.add(TeachingAssignment(
          id: 'auto_${cName}_${sIdx}_${DateTime.now().microsecondsSinceEpoch}',
          teacherInitial: dbTeacher.initial,
          subject: subj,
          className: cName,
          isClassTeacher: sIdx == 0,
          requiredPeriods: req,
          isDoublePeriod: sIdx < 2 && req >= 6,
          roomOrLab: null,
        ));
      }
    }
  }

  /// Updates a teacher's initial and cascades the change across all assignments & current solution!
  void _updateTeacherInitial(int teacherIndex, String newRawInitial) {
    if (teacherIndex < 0 || teacherIndex >= teachers.length) return;
    final clean = newRawInitial.trim().toUpperCase();
    if (clean.isEmpty) return;
    final t = teachers[teacherIndex];
    final oldInit = t.initial;
    if (oldInit == clean) return;
    // Prevent duplicate initial collision with another teacher
    final duplicateOther = teachers
        .asMap()
        .entries
        .any((e) => e.key != teacherIndex && e.value.initial == clean);
    if (duplicateOther) {
      _showSnack(
        'ટૂંકું નામ "$clean" પહેલેથી જ અન્ય શિક્ષક માટે વપરાયેલ છે!',
        isError: true,
      );
      return;
    }

    setState(() {
      t.initial = clean;
      if (t.teacherId != null && t.teacherId!.isNotEmpty) {
        teacherInitialsById[t.teacherId!] = clean;
      }
      teacherInitialsByName[t.fullName.trim().toLowerCase()] = clean;

      for (final a in assignments) {
        if (a.teacherInitial == oldInit) {
          a.teacherInitial = clean;
        }
      }
      if (quickTeacher == oldInit) {
        quickTeacher = clean;
      }
      if (selectedEntity == oldInit) {
        selectedEntity = clean;
      }
      // Update any existing generated schedule slots in-place so timetable views immediately show new initial!
      if (currentSolution != null) {
        for (final classGrid in currentSolution!.schedule.values) {
          for (int d = 0; d < classGrid.length; d++) {
            for (int k = 0; k < classGrid[d].length; k++) {
              final slot = classGrid[d][k];
              if (slot != null && slot.teacherInitial == oldInit) {
                classGrid[d][k] = ScheduledSlot(
                  assignmentId: slot.assignmentId,
                  teacherInitial: clean,
                  subject: slot.subject,
                  className: slot.className,
                  isClassTeacher: slot.isClassTeacher,
                  isDoublePeriod: slot.isDoublePeriod,
                  roomOrLab: slot.roomOrLab,
                  isLocked: slot.isLocked,
                );
              }
            }
          }
        }
      }
    });
    _scheduleDeviceAutoSave();
  }

  /// Single-click save of all Teacher Initials to both Device and School Database!
  Future<void> _saveAllTeacherInitialsOneClick() async {
    for (final t in teachers) {
      final clean = t.initial.trim().toUpperCase();
      if (clean.isEmpty) continue;
      if (t.teacherId != null && t.teacherId!.isNotEmpty) {
        teacherInitialsById[t.teacherId!] = clean;
      }
      teacherInitialsByName[t.fullName.trim().toLowerCase()] = clean;
    }
    await _saveToDeviceNow(manual: false);
    if (widget.onSaveData != null) {
      await _saveToSchoolDatabase(
        customSuccessMessage:
            '✅ બધા શિક્ષકોના ટૂંકા નામ (Initials) એક ક્લિકથી ડિવાઇસ અને ડેટાબેઝમાં સેવ થઈ ગયા!',
      );
    } else {
      _showSnack(
        '✅ બધા શિક્ષકોના ટૂંકા નામ (Initials) આ ડિવાઇસમાં એક ક્લિકથી સેવ થઈ ગયા!',
      );
    }
  }

  void _loadDatabaseMasters() {
    final rawTeachers = _planningRows('teachers');
    final rawSubjects = widget.databaseData['subjects'];
    teachers = rawTeachers
        .map((row) {
          final tid = (row['id'] ?? '').toString().trim();
          final fullName =
              (row['fullName'] ?? row['name'] ?? '').toString().trim();
          var init = (row['initial'] ?? '').toString().trim().toUpperCase();
          if (tid.isNotEmpty && teacherInitialsById.containsKey(tid)) {
            init = teacherInitialsById[tid]!;
          } else if (fullName.isNotEmpty &&
              teacherInitialsByName.containsKey(fullName.toLowerCase())) {
            init = teacherInitialsByName[fullName.toLowerCase()]!;
          }
          final rawSubj = row['subjects'] ?? row['explicitSubjects'];
          final taught = rawSubj is List
              ? rawSubj
                  .map((e) => e.toString().trim())
                  .where((e) => e.isNotEmpty)
                  .toList()
              : <String>[];
          final rawCls = row['assignedClasses'];
          final assignedCls = rawCls is List
              ? rawCls
                  .map((e) => _normalizeClassName(e.toString()))
                  .where((e) => e.isNotEmpty)
                  .toList()
              : <String>[];
          if (tid.isNotEmpty && init.isNotEmpty) {
            teacherInitialsById[tid] = init;
          }
          if (fullName.isNotEmpty && init.isNotEmpty) {
            teacherInitialsByName[fullName.toLowerCase()] = init;
          }
          return TeacherMaster(
            teacherId: tid.isEmpty ? null : tid,
            initial: init,
            fullName: fullName,
            taughtSubjects: taught,
            assignedClasses: assignedCls,
          );
        })
        .where((teacher) =>
            teacher.initial.isNotEmpty && teacher.fullName.isNotEmpty)
        .toList();

    subjects = rawSubjects is List
        ? rawSubjects
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
        : <String>[];
    for (final t in teachers) {
      for (final s in t.taughtSubjects) {
        if (s.isNotEmpty && !subjects.contains(s)) subjects.add(s);
      }
    }
    for (final assignment in _planningRows('assignments')) {
      final subject = (assignment['subject'] ?? '').toString().trim();
      if (subject.isNotEmpty && !subjects.contains(subject)) {
        subjects.add(subject);
      }
    }
    for (final coreSub in const <String>['FLN', 'શા. શિ.']) {
      if (!subjects.any((s) => s.toLowerCase() == coreSub.toLowerCase())) {
        subjects.add(coreSub);
      }
    }
    final initLang = (widget.databaseData['schoolNameLanguage'] ?? 'gu').toString().trim().toLowerCase();
    schoolNameLang = initLang == 'en' ? 'en' : 'gu';
    final resolvedName = _resolvedRegisteredSchoolName;
    if (resolvedName.isNotEmpty) config.schoolName = resolvedName;
    final year = (widget.databaseData['academicYear'] ?? '').toString().trim();
    if (year.isNotEmpty) config.academicYear = year;
    quickTeacher = teachers.firstOrNull?.initial;
    quickSubject = teachers.firstOrNull?.taughtSubjects.firstOrNull ??
        subjects.firstOrNull;
    final classes = _planningRows('classes');
    quickDatabaseClass = classes.isNotEmpty
        ? _normalizeClassName(
            (classes.first['label'] ?? classes.first['classKey'] ?? '')
                .toString())
        : null;
    if (quickDatabaseClass != null && quickDatabaseClass!.isNotEmpty) {
      final standard = classes.first['standard']?.toString() ?? '';
      final section = classes.first['section']?.toString() ?? '';
      if (standard.isNotEmpty) quickLevel = standard;
      if (section.isNotEmpty) quickSection = section.toUpperCase();
    }
  }

  void _loadDatabaseAssignments() {
    final byId = <String, TeacherMaster>{
      for (final t in teachers)
        if (t.teacherId != null && t.teacherId!.isNotEmpty) t.teacherId!: t,
    };
    final byName = <String, TeacherMaster>{
      for (final t in teachers) t.fullName.trim().toLowerCase(): t,
    };
    final raw = _planningRows('assignments');
    assignments = raw
        .map((row) {
          final tid = (row['teacherId'] ?? '').toString().trim();
          final tName =
              (row['teacherFullName'] ?? '').toString().trim().toLowerCase();
          final matchedTeacher = byId[tid] ?? byName[tName];
          final init = matchedTeacher?.initial ??
              (row['teacherInitial'] ?? '').toString().trim().toUpperCase();
          final rawMax = row['maxPeriods'] ?? row['max_periods'];
          final parsedMax = rawMax is num
              ? rawMax.round()
              : int.tryParse((rawMax ?? '').toString().trim());
          final validMax = (parsedMax != null && parsedMax > 0) ? parsedMax : null;
          var reqP = (row['requiredPeriods'] is num
                  ? (row['requiredPeriods'] as num).round()
                  : int.tryParse((row['requiredPeriods'] ?? '').toString()) ?? 6)
              .clamp(1, 60)
              .toInt();
          if (validMax != null && reqP > validMax) {
            reqP = validMax;
          }
          return TeachingAssignment(
            id: (row['id'] ?? '').toString(),
            teacherInitial: init,
            subject: (row['subject'] ?? '').toString().trim(),
            className: _normalizeClassName(
                (row['classLabel'] ?? row['className'] ?? '').toString()),
            isClassTeacher: row['isClassTeacher'] == true,
            requiredPeriods: reqP,
            maxPeriods: validMax,
            isDoublePeriod: row['isDoublePeriod'] == true,
            roomOrLab: row['roomOrLab']?.toString(),
          );
        })
        .where((row) =>
            row.id.isNotEmpty &&
            row.teacherInitial.isNotEmpty &&
            row.subject.isNotEmpty &&
            row.className.isNotEmpty)
        .toList();
    // Ensure every teacher has assignedClasses and taughtSubjects populated from DB assignments
    for (final t in teachers) {
      for (final a in assignments) {
        if (a.teacherInitial == t.initial) {
          if (a.className.isNotEmpty && !t.assignedClasses.contains(a.className)) {
            t.assignedClasses.add(a.className);
          }
          if (a.subject.isNotEmpty && !t.taughtSubjects.contains(a.subject)) {
            t.taughtSubjects.add(a.subject);
          }
        }
      }
    }
  }

  void _applySavedDatabaseData(Map<String, dynamic> saved) {
    if (saved.isEmpty) return;
    try {
      if (saved['schoolNameLang'] is String) {
        final sl = saved['schoolNameLang'].toString().trim().toLowerCase();
        if (sl == 'en' || sl == 'gu') schoolNameLang = sl;
      }
      if (widget.databaseData['schoolNameLanguage'] is String) {
        final dl = widget.databaseData['schoolNameLanguage'].toString().trim().toLowerCase();
        if (dl == 'en' || dl == 'gu') schoolNameLang = dl;
      }
      final configMap = _asPlanningMap(saved['config']);
      if (configMap.isNotEmpty) {
        config = SchoolConfig.fromJson(configMap);
      }
      final authoritativeName = _resolvedRegisteredSchoolName;
      if (authoritativeName.isNotEmpty) {
        config.schoolName = authoritativeName;
      }
      final times = saved['times'];
      if (times is List && times.isNotEmpty) {
        periodTimings = times
            .whereType<Map>()
            .map((row) => PeriodTiming.fromJson(_asPlanningMap(row)))
            .toList();
      }
      final rawBreaks = saved['breaks'];
      if (rawBreaks is List && rawBreaks.isNotEmpty) {
        breaks = rawBreaks
            .whereType<Map>()
            .map((row) => BreakConfig.fromJson(_asPlanningMap(row)))
            .toList();
      }
      if (saved['pageDesign'] is Map) {
        pageDesign =
            PageDesignConfig.fromJson(_asPlanningMap(saved['pageDesign']));
      }
      if (saved['showLogo'] is bool) {
        showLogo = saved['showLogo'] as bool;
      }
      if (saved['showSecondLogo'] is bool) {
        showSecondLogo = saved['showSecondLogo'] as bool;
      }
      if (saved['useSameLogoBothSides'] is bool) {
        useSameLogoBothSides = saved['useSameLogoBothSides'] as bool;
      }
      if (saved['logoStyle'] is Map) {
        logoStyle =
            OverlayLayerStyle.fromJson(_asPlanningMap(saved['logoStyle']));
      }
      if (saved['logo2Style'] is Map) {
        logo2Style =
            OverlayLayerStyle.fromJson(_asPlanningMap(saved['logo2Style']));
      }
      if (saved['watermarkStyle'] is Map) {
        watermarkStyle =
            OverlayLayerStyle.fromJson(_asPlanningMap(saved['watermarkStyle']));
      }
      final savedCustomLogoUri =
          (saved['customLogoDataUri'] ?? '').toString().trim();
      if (savedCustomLogoUri.startsWith('data:')) {
        final comma = savedCustomLogoUri.indexOf(',');
        if (comma >= 0) {
          try {
            _customUploadedLogoBytes =
                base64Decode(savedCustomLogoUri.substring(comma + 1));
            _customUploadedLogoDataUri = savedCustomLogoUri;
          } catch (_) {}
        }
      }
      final savedCustomLogo2Uri =
          (saved['customLogo2DataUri'] ?? '').toString().trim();
      if (savedCustomLogo2Uri.startsWith('data:')) {
        final comma = savedCustomLogo2Uri.indexOf(',');
        if (comma >= 0) {
          try {
            _customUploadedLogo2Bytes =
                base64Decode(savedCustomLogo2Uri.substring(comma + 1));
            _customUploadedLogo2DataUri = savedCustomLogo2Uri;
          } catch (_) {}
        }
      }
      if (saved['teacherInitialsById'] is Map) {
        for (final e in _asPlanningMap(saved['teacherInitialsById']).entries) {
          final v = e.value.toString().trim().toUpperCase();
          if (e.key.trim().isNotEmpty && v.isNotEmpty) {
            teacherInitialsById[e.key.trim()] = v;
          }
        }
      }
      if (saved['teacherInitialsByName'] is Map) {
        for (final e
            in _asPlanningMap(saved['teacherInitialsByName']).entries) {
          final v = e.value.toString().trim().toUpperCase();
          if (e.key.trim().isNotEmpty && v.isNotEmpty) {
            teacherInitialsByName[e.key.trim().toLowerCase()] = v;
          }
        }
      }
      if (saved['timetablePrintDate'] is String) {
        timetablePrintDate = saved['timetablePrintDate'].toString();
      }
      if (saved['activeClassPreset'] is String) {
        activeClassPreset = saved['activeClassPreset'].toString();
      }
      if (saved['selectedClasses'] is List) {
        final sel = (saved['selectedClasses'] as List)
            .map((e) => _normalizeClassName(e.toString()))
            .where((e) => e.isNotEmpty)
            .toSet();
        if (sel.isNotEmpty) {
          selectedClassesForGeneration = sel;
        }
      }
      final savedSubjects = saved['subjects'];
      if (savedSubjects is List && savedSubjects.isNotEmpty) {
        final mergedSubjects = <String>[
          ...savedSubjects
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
          ...subjects,
        ];
        subjects = mergedSubjects.toSet().toList();
      }
      final savedTeacherRows = saved['teachers'];
      if (savedTeacherRows is List && savedTeacherRows.isNotEmpty) {
        final restoredTeachers = savedTeacherRows
            .whereType<Map>()
            .map((row) => TeacherMaster.fromJson(_asPlanningMap(row)))
            .where((t) => t.initial.isNotEmpty && t.fullName.isNotEmpty)
            .toList();
        for (final rt in restoredTeachers) {
          if (rt.teacherId != null && rt.teacherId!.isNotEmpty) {
            teacherInitialsById[rt.teacherId!] = rt.initial;
          }
          teacherInitialsByName[rt.fullName.trim().toLowerCase()] = rt.initial;
        }
        // Apply restored custom initials & unavailable slots onto database teachers!
        if (widget.useDatabaseData && teachers.isNotEmpty) {
          final oldToNewInitial = <String, String>{};
          for (final dbT in teachers) {
            final match = restoredTeachers
                .where((rt) =>
                    (rt.teacherId != null &&
                        rt.teacherId!.isNotEmpty &&
                        rt.teacherId == dbT.teacherId) ||
                    rt.fullName.trim().toLowerCase() ==
                        dbT.fullName.trim().toLowerCase())
                .firstOrNull;
            if (match != null) {
              if (dbT.initial != match.initial) {
                oldToNewInitial[dbT.initial] = match.initial;
                dbT.initial = match.initial;
              }
              if (match.unavailableSlots.isNotEmpty) {
                dbT.unavailableSlots = match.unavailableSlots;
              }
              // Keep database teacher name, taughtClasses, and taughtSubjects authoritative;
              // only fall back to saved subjects/classes if DB had none.
              if (dbT.taughtSubjects.isEmpty &&
                  match.taughtSubjects.isNotEmpty) {
                dbT.taughtSubjects = match.taughtSubjects;
              }
              if (dbT.assignedClasses.isEmpty &&
                  match.assignedClasses.isNotEmpty) {
                dbT.assignedClasses = match.assignedClasses
                    .map(_normalizeClassName)
                    .where((c) => c.isNotEmpty)
                    .toList();
              }
            }
          }
          if (oldToNewInitial.isNotEmpty) {
            for (final a in assignments) {
              final mapped = oldToNewInitial[a.teacherInitial];
              if (mapped != null) a.teacherInitial = mapped;
            }
          }
        } else {
          final byInit = <String, TeacherMaster>{
            for (final t in restoredTeachers) t.initial: t,
          };
          for (final dbT in teachers) {
            byInit.putIfAbsent(dbT.initial, () => dbT);
          }
          teachers = byInit.values.toList();
        }
      }
      final savedRows = saved['rows'];
      final hasExplicitDbAssign =
          widget.useDatabaseData && widget.databaseData['hasExplicitAssignments'] == true;
      if (savedRows is List && savedRows.isNotEmpty) {
        final dbClassLabels = _planningRows('classes')
            .map((r) => _normalizeClassName(
                (r['label'] ?? r['classKey'] ?? '').toString()))
            .where((s) => s.isNotEmpty)
            .toSet();
        final dbAssignmentsBackup = List<TeachingAssignment>.from(assignments);
        final byName = <String, TeacherMaster>{
          for (final t in teachers) t.fullName.trim().toLowerCase(): t,
        };
        final restoredAssignments = savedRows
            .whereType<Map>()
            .map((row) {
              final a = TeachingAssignment.fromJson(_asPlanningMap(row));
              a.className = _normalizeClassName(a.className);
              // Map teacher initial if custom initial changed
              if (!teachers.any((t) => t.initial == a.teacherInitial)) {
                final tFull = (row['teacherFullName'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                if (byName.containsKey(tFull)) {
                  a.teacherInitial = byName[tFull]!.initial;
                }
              }
              return a;
            })
            .where((a) =>
                a.teacherInitial.isNotEmpty &&
                a.subject.isNotEmpty &&
                a.className.isNotEmpty &&
                (dbClassLabels.isEmpty || dbClassLabels.contains(a.className)))
            .toList();
        if (restoredAssignments.isNotEmpty) {
          if (hasExplicitDbAssign && dbAssignmentsBackup.isNotEmpty) {
            // Keep custom period counts from restoredAssignments, but sync teacher & subject
            // assignments from explicit database records (teacher_subject_assignments)
            final restoredByKey = <String, TeachingAssignment>{
              for (final ra in restoredAssignments)
                if (!ra.id.startsWith('auto_'))
                  '${ra.className.toLowerCase()}__${ra.subject.toLowerCase()}': ra,
            };
            final merged = <TeachingAssignment>[];
            final seenKeys = <String>{};
            for (final dbA in dbAssignmentsBackup) {
              final k = '${dbA.className.toLowerCase()}__${dbA.subject.toLowerCase()}';
              final prev = restoredByKey[k];
              if (prev != null) {
                dbA.maxPeriods ??= prev.maxPeriods;
                dbA.requiredPeriods = (dbA.maxPeriods != null && dbA.maxPeriods! > 0)
                    ? min(prev.requiredPeriods, dbA.maxPeriods!)
                    : prev.requiredPeriods;
                dbA.isDoublePeriod = prev.isDoublePeriod;
                dbA.roomOrLab = prev.roomOrLab;
              } else if (dbA.maxPeriods != null &&
                  dbA.maxPeriods! > 0 &&
                  dbA.requiredPeriods > dbA.maxPeriods!) {
                dbA.requiredPeriods = dbA.maxPeriods!;
              }
              merged.add(dbA);
              seenKeys.add(k);
            }
            for (final ra in restoredAssignments) {
              if (ra.id.startsWith('auto_')) continue;
              final k = '${ra.className.toLowerCase()}__${ra.subject.toLowerCase()}';
              if (!seenKeys.contains(k)) {
                merged.add(ra);
                seenKeys.add(k);
              }
            }
            assignments = merged;
          } else {
            final coveredClasses =
                restoredAssignments.map((a) => a.className).toSet();
            for (final dbA in dbAssignmentsBackup) {
              if (!coveredClasses.contains(dbA.className)) {
                restoredAssignments.add(dbA);
              }
            }
            assignments = restoredAssignments;
          }
          for (final a in assignments) {
            if (!subjects.contains(a.subject)) subjects.add(a.subject);
            if (!teachers.any((t) => t.initial == a.teacherInitial)) {
              teachers.add(TeacherMaster(
                  initial: a.teacherInitial, fullName: a.teacherInitial));
            }
          }
        }
      }
    } catch (_) {
      // A stale/partial saved configuration must not prevent the screen opening.
    }
  }

  void _autoBuildAssignmentsFromCurrentMasters() {
    if (teachers.isEmpty) {
      _loadDemoMasters();
    }
    if (subjects.isEmpty) {
      subjects = [
        'ગુજરાતી',
        'ગણિત',
        'પર્યાવરણ',
        'વિજ્ઞાન',
        'સામાજિક વિજ્ઞાન',
        'અંગ્રેજી',
        'હિન્દી',
        'સંસ્કૃત',
        'ચિત્ર',
      ];
    }
    final dbClasses = _planningRows('classes');
    final targetClasses = <String>[];
    for (final row in dbClasses) {
      final tc = _normalizeClassName(
          (row['label'] ?? row['timetableClassName'] ?? row['classKey'] ?? '')
              .toString());
      if (tc.isNotEmpty && !targetClasses.contains(tc)) targetClasses.add(tc);
    }
    if (targetClasses.isEmpty) {
      targetClasses.addAll(['6-A', '7-A', '8-A']);
    }
    final slots = config.weeklySlotsPerClass;
    final coreSubjects = subjects.take(7).toList();
    final newRows = <TeachingAssignment>[];
    for (var cIdx = 0; cIdx < targetClasses.length; cIdx++) {
      final cName = targetClasses[cIdx];
      final count = coreSubjects.length;
      final base = slots ~/ count;
      var rem = slots % count;
      for (var sIdx = 0; sIdx < count; sIdx++) {
        final extra = rem > 0 ? 1 : 0;
        if (rem > 0) rem--;
        final req = (base + extra).clamp(1, 14);
        final subj = coreSubjects[sIdx];
        final t = teachers
                .where((tm) =>
                    tm.taughtSubjects.contains(subj) &&
                    (tm.assignedClasses.isEmpty ||
                        tm.assignedClasses.contains(cName)))
                .firstOrNull ??
            teachers
                .where((tm) => tm.taughtSubjects.contains(subj))
                .firstOrNull ??
            teachers[(cIdx + sIdx) % teachers.length];
        newRows.add(TeachingAssignment(
          id: 'auto_${cIdx}_${sIdx}_${DateTime.now().microsecondsSinceEpoch}',
          teacherInitial: t.initial,
          subject: subj,
          className: cName,
          isClassTeacher: sIdx == 0,
          requiredPeriods: req,
          isDoublePeriod: sIdx < 2 && req >= 6,
          roomOrLab: null,
        ));
      }
    }
    assignments = newRows;
  }

  void _autoBalanceClassPeriods() {
    if (assignments.isEmpty) {
      _autoBuildAssignmentsFromCurrentMasters();
    }
    _ensureAssignmentsExistForSelectedClasses();
    final slots = config.weeklySlotsPerClass;
    final classes = allClasses;
    final usedCts = <String>{};
    setState(() {
      for (final c in classes) {
        final classRows = assignments
            .where((a) => _normalizeClassName(a.className) == c)
            .toList();
        if (classRows.isEmpty) continue;
        var ctRow = classRows.where((r) => r.isClassTeacher).firstOrNull;
        if (ctRow == null) {
          ctRow = classRows.firstWhere(
            (r) => !usedCts.contains(r.teacherInitial),
            orElse: () => classRows.first,
          );
        }
        usedCts.add(ctRow.teacherInitial);
        for (final r in classRows) {
          r.isClassTeacher =
              (r.teacherInitial == ctRow.teacherInitial && r == ctRow);
        }
        final currentSum =
            classRows.fold<int>(0, (s, r) => s + r.requiredPeriods);
        if (currentSum != slots) {
          if (currentSum <= 0) {
            final base = slots ~/ classRows.length;
            var rem = slots % classRows.length;
            for (final r in classRows) {
              var target = base + (rem > 0 ? 1 : 0);
              if (rem > 0) rem--;
              if (r.maxPeriods != null && r.maxPeriods! > 0 && target > r.maxPeriods!) {
                target = r.maxPeriods!;
              }
              r.requiredPeriods = target;
            }
          } else {
            int allocated = 0;
            for (var i = 0; i < classRows.length; i++) {
              final r = classRows[i];
              int target;
              if (i == classRows.length - 1) {
                target = (slots - allocated).clamp(1, 20);
              } else {
                target = ((r.requiredPeriods * slots) / currentSum)
                    .round()
                    .clamp(1, 16);
              }
              if (r.maxPeriods != null && r.maxPeriods! > 0 && target > r.maxPeriods!) {
                target = r.maxPeriods!;
              }
              r.requiredPeriods = target;
              allocated += target;
            }
            // Redistribute any remaining unallocated periods to uncapped rows
            int leftover = slots - classRows.fold<int>(0, (s, r) => s + r.requiredPeriods);
            int guard = 0;
            while (leftover > 0 && guard++ < 60) {
              bool addedAny = false;
              for (final r in classRows) {
                if (leftover <= 0) break;
                final cap = (r.maxPeriods != null && r.maxPeriods! > 0) ? r.maxPeriods! : 20;
                if (r.requiredPeriods < cap) {
                  r.requiredPeriods++;
                  leftover--;
                  addedAny = true;
                }
              }
              if (!addedAny) break;
            }
          }
        }
        // Final cap enforcement on every row
        for (final r in classRows) {
          if (r.maxPeriods != null && r.maxPeriods! > 0 && r.requiredPeriods > r.maxPeriods!) {
            r.requiredPeriods = r.maxPeriods!;
          }
        }
        final ctCap = (ctRow.maxPeriods != null && ctRow.maxPeriods! > 0)
            ? min(6, ctRow.maxPeriods!)
            : 6;
        if (ctRow.requiredPeriods < ctCap && classRows.length > 1) {
          final diff = ctCap - ctRow.requiredPeriods;
          final donor = classRows
              .where((r) => r != ctRow && r.requiredPeriods > diff + 2)
              .firstOrNull;
          if (donor != null) {
            donor.requiredPeriods -= diff;
            ctRow.requiredPeriods += diff;
          }
        }
      }
      final tLoads = <String, int>{};
      for (final r in activeAssignments) {
        tLoads[r.teacherInitial] =
            (tLoads[r.teacherInitial] ?? 0) + r.requiredPeriods;
      }
      for (final load in tLoads.values) {
        if (load > config.maxTeacherWeeklyLoad) {
          config.maxTeacherWeeklyLoad = load;
        }
      }
    });
    _scheduleDeviceAutoSave();
    _runGenerate(switchTab: false, showNotification: true);
    _showSnack(
        '⚡ પસંદ કરેલ ${classes.length} વર્ગોના તાસ (${config.weeklySlotsPerClass}/અઠવાડિયું) આપોઆપ બેલેન્સ થઈ ગયા!');
  }

  Future<void> _saveToSchoolDatabase({String? customSuccessMessage}) async {
    final callback = widget.onSaveData;
    if (callback == null) {
      await _saveToDeviceNow(manual: true);
      return;
    }
    try {
      await _saveToDeviceNow(manual: false);
      final value = jsonDecode(_exportJsonBackup()) as Map<String, dynamic>;
      await callback(value);
      _showSnack(customSuccessMessage ??
          '✅ સમયપત્રક, તાસનો સમય અને શિક્ષકોના ટૂંકા નામ શાળાના ડેટાબેઝમાં સેવ થઈ ગયા!');
    } catch (error) {
      _showSnack('❌ ડેટાબેઝમાં સેવ થઈ શક્યું નથી: $error', isError: true);
    }
  }

  void _loadDemoMasters() {
    teachers = [
      TeacherMaster(
        initial: 'SC',
        fullName: 'ચિકાણી સુનિલભાઈ (Sunilbhai Chikani)',
        taughtSubjects: ['અંગ્રેજી (English)', 'ગુજરાતી (Gujarati)'],
        assignedClasses: ['6-A', '7-A'],
      ),
      TeacherMaster(
        initial: 'AP',
        fullName: 'અનિલભાઈ પટેલ (Anil Patel)',
        taughtSubjects: ['ગણિત (Mathematics)'],
        assignedClasses: ['6-A', '7-A'],
      ),
      TeacherMaster(
        initial: 'BS',
        fullName: 'ભાવનાબેન શાહ (Bhavna Shah)',
        taughtSubjects: ['અંગ્રેજી (English)'],
        assignedClasses: ['7-A'],
      ),
      TeacherMaster(
        initial: 'CJ',
        fullName: 'ચેતનભાઈ જોશી (Chetan Joshi)',
        taughtSubjects: ['વિજ્ઞાન (Science)'],
        assignedClasses: ['6-A', '7-A'],
      ),
      TeacherMaster(
        initial: 'DM',
        fullName: 'દિનેશભાઈ મહેતા (Dinesh Mehta)',
        taughtSubjects: ['સામાજિક વિજ્ઞાન (Social Science)'],
        assignedClasses: ['6-A', '7-A'],
      ),
      TeacherMaster(
        initial: 'ED',
        fullName: 'એકતાબેન દેસાઈ (Ekta Desai)',
        taughtSubjects: ['સંસ્કૃત (Sanskrit)', 'ગુજરાતી (Gujarati)'],
        assignedClasses: ['6-A', '7-A'],
      ),
      TeacherMaster(
        initial: 'KR',
        fullName: 'કવિતાબેન રાવ (Kavita Rao)',
        taughtSubjects: ['હિન્દી (Hindi)'],
        assignedClasses: ['6-A', '7-A'],
      ),
    ];
    subjects = [
      'ગણિત (Mathematics)',
      'અંગ્રેજી (English)',
      'વિજ્ઞાન (Science)',
      'ગુજરાતી (Gujarati)',
      'સામાજિક વિજ્ઞાન (Social Science)',
      'હિન્દી (Hindi)',
      'સંસ્કૃત (Sanskrit)',
      'ચિત્રકામ અને કમ્પ્યુટર (Art & Computer)',
      'ભાષા અને ગણન (FLN Literacy & Numeracy)',
    ];
    quickTeacher = teachers.first.initial;
    quickSubject = subjects.first;
  }

  void _loadDemoAssignments() {
    final slots = config.weeklySlotsPerClass;
    final raw = [
      ('SC', 'અંગ્રેજી (English)', '6-A', 8, true, true, null),
      ('SC', 'ગુજરાતી (Gujarati)', '6-A', 6, true, true, null),
      ('AP', 'ગણિત (Mathematics)', '6-A', 8, false, true, null),
      ('CJ', 'વિજ્ઞાન (Science)', '6-A', 6, false, true, 'Science Lab'),
      ('DM', 'સામાજિક વિજ્ઞાન (Social Science)', '6-A', 6, false, false, null),
      ('KR', 'હિન્દી (Hindi)', '6-A', 6, false, false, null),
      (
        'ED',
        'સંસ્કૃત (Sanskrit)',
        '6-A',
        max(1, slots - 40),
        false,
        false,
        null
      ),
      ('BS', 'અંગ્રેજી (English)', '7-A', 8, true, true, null),
      ('AP', 'ગણિત (Mathematics)', '7-A', 8, false, true, null),
      ('CJ', 'વિજ્ઞાન (Science)', '7-A', 8, false, true, 'Science Lab'),
      ('DM', 'સામાજિક વિજ્ઞાન (Social Science)', '7-A', 6, false, false, null),
      ('ED', 'ગુજરાતી (Gujarati)', '7-A', 6, false, true, null),
      ('KR', 'હિન્દી (Hindi)', '7-A', 5, false, true, null),
      (
        'SC',
        'ચિત્રકામ અને કમ્પ્યુટર (Art & Computer)',
        '7-A',
        max(1, slots - 41),
        false,
        false,
        'Computer Lab'
      ),
    ];

    assignments = [
      for (int idx = 0; idx < raw.length; idx++)
        TeachingAssignment(
          id: 'row_${idx + 1}',
          teacherInitial: raw[idx].$1,
          subject: raw[idx].$2,
          className: raw[idx].$3,
          requiredPeriods: raw[idx].$4,
          isClassTeacher: raw[idx].$5,
          isDoublePeriod: raw[idx].$6,
          roomOrLab: raw[idx].$7,
        ),
    ];
  }

  List<String> get allAssignedTeachers {
    final active = activeAssignments;
    final source = active.isNotEmpty ? active : assignments;
    final set = source.map((a) => a.teacherInitial).toSet().toList()..sort();
    return set;
  }

  String fullNameOf(String initial) =>
      teachers
          .where((t) => t.initial == initial)
          .map((t) => t.fullName)
          .firstOrNull ??
      initial;

  void _runGenerate({bool switchTab = true, bool showNotification = true}) {
    _syncSelectedClassesWithAvailable();
    _ensureAssignmentsExistForSelectedClasses();
    final targetRows = activeAssignments;
    final validation = TimetableSolverEngine.validate(
      config: config,
      teachers: teachers,
      assignments: targetRows,
    );

    if (!validation.isValid) {
      if (showNotification) {
        _showSnack(validation.errors.join('\n'), isError: true);
      }
      return;
    }

    final sol = TimetableSolverEngine.generate(
      config: config,
      teachers: teachers,
      assignments: targetRows,
      breaks: breaks,
      existingScheduleWithLocks: currentSolution?.schedule,
    );

    setState(() {
      currentSolution = sol;
      selectedSlotForSwap = null;
      final classes = allClasses;
      if (selectedViewMode == 'class') {
        if (selectedEntity == null || !classes.contains(selectedEntity)) {
          selectedEntity = classes.firstOrNull;
        }
      } else if (selectedViewMode == 'teacher') {
        final tList = allAssignedTeachers;
        if (selectedEntity == null || !tList.contains(selectedEntity)) {
          selectedEntity = tList.firstOrNull;
        }
      }
      proxySelectedClass ??= classes.firstOrNull;
    });

    _scheduleDeviceAutoSave();
    if (switchTab) {
      _tabController.animateTo(6);
    }
    if (showNotification) {
      final msg = sol.unplacedPeriodsCount == 0
          ? '✅ ૧૦૦% ઝીરો-ક્લેશ (0 Clashes • ${allClasses.length} વર્ગો • ${sol.elapsedMs} ms) સમયપત્રક તૈયાર!'
          : '⚠️ સમયપત્રક બની ગયું (${sol.unplacedPeriodsCount} તાસ બાકી રહ્યા — ⚡ ઓટો-બેલેન્સ બટન દબાવો).';
      _showSnack(msg, isError: sol.unplacedPeriodsCount > 0);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor:
            isError ? const Color(0xFFE11D48) : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Export / Import JSON Backup
  String _exportJsonBackup() {
    final map = {
      'version': 4,
      'savedAt': DateTime.now().toIso8601String(),
      'config': config.toJson(),
      'times': periodTimings.map((e) => e.toJson()).toList(),
      'breaks': breaks.map((e) => e.toJson()).toList(),
      'teachers': teachers.map((e) => e.toJson()).toList(),
      'teacherInitialsById': teacherInitialsById,
      'teacherInitialsByName': teacherInitialsByName,
      'selectedClasses': selectedClassesForGeneration.toList(),
      'activeClassPreset': activeClassPreset,
      'subjects': subjects,
      'rows': assignments.map((e) => e.toJson()).toList(),
      'pageDesign': pageDesign.toJson(),
      'timetablePrintDate': timetablePrintDate,
      'showLogo': showLogo,
      'showSecondLogo': showSecondLogo,
      'useSameLogoBothSides': useSameLogoBothSides,
      'logoStyle': logoStyle.toJson(),
      'logo2Style': logo2Style.toJson(),
      'watermarkStyle': watermarkStyle.toJson(),
      if (_customUploadedLogoDataUri.isNotEmpty)
        'customLogoDataUri': _customUploadedLogoDataUri,
      if (_customUploadedLogo2DataUri.isNotEmpty)
        'customLogo2DataUri': _customUploadedLogo2DataUri,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  void _importJsonBackup(String rawJson) {
    try {
      final map = jsonDecode(rawJson) as Map<String, dynamic>;
      setState(() {
        if (map['config'] != null) {
          config = SchoolConfig.fromJson(map['config']);
        }
        if (map['times'] is List) {
          periodTimings = (map['times'] as List)
              .map((e) => PeriodTiming.fromJson(e))
              .toList();
        }
        if (map['breaks'] is List) {
          breaks = (map['breaks'] as List)
              .map((e) => BreakConfig.fromJson(e))
              .toList();
        }
        if (map['teachers'] is List) {
          teachers = (map['teachers'] as List)
              .map((e) => TeacherMaster.fromJson(e))
              .toList();
        }
        if (map['subjects'] is List) {
          subjects =
              (map['subjects'] as List).map((e) => e.toString()).toList();
        }
        if (map['rows'] is List) {
          assignments = (map['rows'] as List)
              .map((e) => TeachingAssignment.fromJson(e))
              .toList();
        }
        if (map['pageDesign'] != null) {
          pageDesign = PageDesignConfig.fromJson(map['pageDesign']);
        }
        if (map['timetablePrintDate'] is String) {
          timetablePrintDate = map['timetablePrintDate'].toString();
        }
      });
      _runGenerate(switchTab: false);
      _showSnack('✅ JSON બેકઅપ સફળતાપૂર્વક લોડ થઈ ગયો!');
    } catch (e) {
      _showSnack('JSON ફાઈલ ખોટી છે: $e', isError: true);
    }
  }

  // CSV Bulk Export / Import
  String _exportCsvText({bool sampleOnly = false}) {
    final header = [
      'Teacher Full Name',
      'Teacher Initial',
      'Subject',
      'Class',
      'Section',
      'Class Teacher (Yes/No)',
      'Required Periods',
      'Continuous Two Periods (Yes/No)',
      'Room or Lab'
    ];
    final rows = sampleOnly
        ? [
            [
              'ચિકાણી સુનિલભાઈ (Sunilbhai Chikani)',
              'SC',
              'અંગ્રેજી (English)',
              '6',
              'A',
              'Yes',
              '6',
              'Yes',
              ''
            ],
            [
              'અનિલભાઈ પટેલ (Anil Patel)',
              'AP',
              'ગણિત (Mathematics)',
              '6',
              'A',
              'No',
              '6',
              'Yes',
              ''
            ],
            [
              'ભાવનાબેન શાહ (Bhavna Shah)',
              'BS',
              'ગુજરાતી (Gujarati)',
              '7',
              'A',
              'Yes',
              '5',
              'Yes',
              ''
            ],
          ]
        : assignments.map((r) {
            final parts = r.className.split('-');
            final cls = parts.first;
            final sec = parts.length > 1 ? parts[1] : 'A';
            return [
              fullNameOf(r.teacherInitial),
              r.teacherInitial,
              r.subject,
              cls,
              sec,
              r.isClassTeacher ? 'Yes' : 'No',
              r.requiredPeriods.toString(),
              r.isDoublePeriod ? 'Yes' : 'No',
              r.roomOrLab ?? '',
            ];
          }).toList();

    final all = [header, ...rows];
    return all
        .map((r) => r.map((v) => '"${v.replaceAll('"', '""')}"').join(','))
        .join('\n');
  }

  void _importCsvText(String csvText) {
    final lines = csvText
        .trim()
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.length <= 1) {
      _showSnack('કોઈ માન્ય ડેટા મળ્યો નથી.', isError: true);
      return;
    }

    final imported = <TeachingAssignment>[];
    final cellRegex = RegExp(r'("[^"]*(?:""[^"]*)*"|[^,\t]+)');

    for (int i = 1; i < lines.length; i++) {
      final matches = cellRegex
          .allMatches(lines[i])
          .map((m) => m
              .group(0)!
              .replaceAll(RegExp(r'^"|"$'), '')
              .replaceAll('""', '"')
              .trim())
          .toList();
      if (matches.length < 3) continue;
      final fullName = matches[0];
      final init = matches[1].toUpperCase();
      final subj = matches[2];
      if (fullName.isEmpty || init.isEmpty || subj.isEmpty) continue;

      if (!teachers.any((t) => t.initial == init)) {
        teachers.add(TeacherMaster(initial: init, fullName: fullName));
      }
      if (!subjects.contains(subj)) {
        subjects.add(subj);
      }

      String cls = (matches.length > 3 ? matches[3] : '6')
          .replaceAll(RegExp(r'^Class\s*', caseSensitive: false), '')
          .trim()
          .toUpperCase();
      if (cls.contains('BAL')) cls = 'BALVATIKA';
      final sec = (matches.length > 4 && matches[4].isNotEmpty)
          ? matches[4].toUpperCase()[0]
          : 'A';
      final ct = matches.length > 5 && matches[5].toLowerCase().startsWith('y');
      final req =
          matches.length > 6 ? (int.tryParse(matches[6]) ?? 6).clamp(1, 60) : 6;
      final dbl =
          matches.length > 7 && matches[7].toLowerCase().startsWith('y');
      final room =
          (matches.length > 8 && matches[8].isNotEmpty) ? matches[8] : null;

      imported.add(TeachingAssignment(
        id: 'imp_${DateTime.now().microsecondsSinceEpoch}_$i',
        teacherInitial: init,
        subject: subj,
        className: '$cls-$sec',
        isClassTeacher: ct,
        requiredPeriods: req,
        isDoublePeriod: dbl,
        roomOrLab: room,
      ));
    }

    if (imported.isEmpty) {
      _showSnack('કોઈ માન્ય હરોળ મળી નથી.', isError: true);
      return;
    }

    setState(() {
      assignments = imported;
    });
    _showSnack('✅ ${imported.length} હરોળ સફળતાપૂર્વક ઈમ્પોર્ટ થઈ ગઈ!');
  }

  // ============================================================================
  // UI BUILDERS
  // ============================================================================

  void _alignBothLogosCenterSymmetrical() {
    setState(() {
      showLogo = true;
      showSecondLogo = true;
      logoStyle.xPercent = 10.0;
      logoStyle.yPercent = 11.0;
      logo2Style.xPercent = 90.0;
      logo2Style.yPercent = 11.0;
      logo2Style.widthPx = logoStyle.widthPx;
      logo2Style.heightPx = logoStyle.heightPx;
      logoStyle.shape = 'original';
      logo2Style.shape = 'original';
    });
    _scheduleDeviceAutoSave(immediate: true);
    _showSnack('⚖️ Ctrl+E: બંને લોગો (ડાબે અને જમણે) સમતોલ અને બરાબર ગોઠવાઈ ગયા!');
  }

  Future<void> _pickTimetableDate() async {
    final now = DateTime.now();
    DateTime initial = now;
    if (timetablePrintDate.trim().isNotEmpty) {
      final parts = timetablePrintDate.trim().split(RegExp(r'[/\-.]'));
      if (parts.length == 3) {
        final d = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final y = int.tryParse(parts[2]);
        if (d != null && m != null && y != null) {
          initial = DateTime(y, m, d);
        }
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: 'સમયપત્રક માટે તારીખ પસંદ કરો (Select Timetable Date)',
    );
    if (picked == null || !mounted) return;
    final formatted =
        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
    setState(() {
      timetablePrintDate = formatted;
    });
    _scheduleDeviceAutoSave(immediate: true);
    _showSnack('📅 તારીખ પસંદ થઈ: $formatted');
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyE, control: true):
            _alignBothLogosCenterSymmetrical,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      backgroundColor: const Color(0xFFEEF2F7),
      appBar: widget.embedded
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(124),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF17133F),
                      Color(0xFF312E81),
                      Color(0xFF1D4ED8)
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            if (Navigator.of(context).canPop()) ...[
                              IconButton(
                                tooltip: 'પાછા જાઓ / Back',
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(Icons.arrow_back_rounded,
                                    color: Colors.white),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: const Icon(Icons.calendar_month_rounded,
                                  color: Colors.white, size: 26),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'સ્માર્ટ શાળા સમયપત્રક સ્ટુડિયો (Smart Timetable Studio Ultimate)',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    'Zero Clash • Continue 2 Periods • Tap-to-Swap • Proxy Finder • Lab Guard',
                                    style: TextStyle(
                                      color: Color(0xFFC7D2FE),
                                      fontSize: 11.5,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (MediaQuery.sizeOf(context).width < 760) ...[
                              // Phones: the same three actions as compact icons.
                              for (final a in <(String, IconData, Color, VoidCallback)>[
                                ('ઓટો-બેલેન્સ', Icons.auto_fix_high_rounded, Colors.white24, _autoBalanceClassPeriods),
                                ('સમયપત્રક બનાવો', Icons.bolt_rounded, const Color(0xFF059669), () => _runGenerate(switchTab: true)),
                                ('પ્રિન્ટ / PDF', Icons.print_rounded, const Color(0xFFD97706), _printOrExportTimetableHtml),
                              ])
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: IconButton.filled(
                                    tooltip: a.$1,
                                    style: IconButton.styleFrom(backgroundColor: a.$3, foregroundColor: Colors.white),
                                    onPressed: a.$4,
                                    icon: Icon(a.$2, size: 19),
                                  ),
                                ),
                            ] else ...[
                            OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white54),
                                ),
                                onPressed: _autoBalanceClassPeriods,
                                icon: const Icon(Icons.auto_fix_high_rounded,
                                    size: 17),
                                label: const Text(
                                  'ઓટો-બેલેન્સ',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _runGenerate(switchTab: true),
                                icon: const Icon(Icons.bolt_rounded, size: 18),
                                label: const Text(
                                  'સમયપત્રક બનાવો',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _printOrExportTimetableHtml,
                                icon: const Icon(Icons.print_rounded, size: 18),
                                label: const Text(
                                  'પ્રિન્ટ / PDF',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        indicatorColor: Colors.amberAccent,
                        indicatorWeight: 3.5,
                        labelColor: Colors.white,
                        unselectedLabelColor: const Color(0xFFCBD5E1),
                        labelStyle: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                        tabs: const [
                          Tab(text: '1. શાળા સેટઅપ (Setup)'),
                          Tab(text: '2. તાસ અને વિરામ (Timings)'),
                          Tab(text: '3. શિક્ષકો/વિષયો (Masters)'),
                          Tab(text: '4. તાસ ફાળવણી (Data Entry)'),
                          Tab(text: '5. પ્રાર્થના/પેજ ડિઝાઇન'),
                          Tab(text: '6. લોગો અને વોટરમાર્ક'),
                          Tab(text: '7. સમયપત્રક જુઓ (Views)'),
                          Tab(text: '8. રિપોર્ટ્સ & Proxy'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildTab1Setup(),
          _buildTab2Timings(),
          _buildTab3Masters(),
          _buildTab4DataEntry(),
          _buildTab5PageDesign(),
          _buildTab6Branding(),
          _buildTab7Views(),
          _buildTab8ReportsAndProxy(),
        ],
      ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // REUSABLE CLASS SELECTION CARD (3 to 5, 6 to 8, 3 to 8, 1 to 5, All, Custom)
  // ---------------------------------------------------------------------------
  Widget _buildClassSelectionCard({bool compact = false}) {
    final avail = allAvailableClasses;
    final selected = allClasses.toSet();

    Widget presetBtn(String key, String label, IconData icon) {
      final isSelected = activeClassPreset == key;
      return ChoiceChip(
        avatar: Icon(
          icon,
          size: 16,
          color: isSelected ? Colors.white : const Color(0xFF312E81),
        ),
        label: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: isSelected ? Colors.white : const Color(0xFF1E1B4B),
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF4F46E5),
        backgroundColor: const Color(0xFFEEF2FF),
        showCheckmark: false,
        onSelected: (_) => _applyClassRangePreset(key),
      );
    }

    return Card(
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: EdgeInsets.all(compact ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.filter_alt_rounded,
                        color: Color(0xFF4F46E5), size: 22),
                    const SizedBox(width: 8),
                    Flexible(child: Text(
                      '🎯 સમયપત્રક બનાવવા માટે વર્ગો પસંદ કરો (Select Classes: ${selected.length}/${avail.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14.5,
                        color: Color(0xFF1E1B4B),
                      ),
                    )),
                  ],
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _runGenerate(switchTab: !compact),
                  icon: const Icon(Icons.bolt_rounded, size: 17),
                  label: Text(
                    '⚡ પસંદ કરેલ ${selected.length} વર્ગોનું સમયપત્રક બનાવો',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                presetBtn(
                    '3to5', 'ધોરણ ૩ થી ૫ (3 to 5)', Icons.looks_3_rounded),
                presetBtn(
                    '6to8', 'ધોરણ ૬ થી ૮ (6 to 8)', Icons.looks_6_rounded),
                presetBtn(
                    '3to8', 'ધોરણ ૩ થી ૮ (3 to 8)', Icons.auto_awesome_rounded),
                presetBtn(
                    '1to5', 'ધોરણ ૧ થી ૫ (1 to 5)', Icons.looks_one_rounded),
                presetBtn('all', 'બધા વર્ગો (All ${avail.length})',
                    Icons.select_all_rounded),
              ],
            ),
            if (avail.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: avail.map((c) {
                  final isChecked = selected.contains(c);
                  return FilterChip(
                    label: Text(
                      c,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: isChecked
                            ? const Color(0xFF065F46)
                            : const Color(0xFF475569),
                      ),
                    ),
                    selected: isChecked,
                    selectedColor: const Color(0xFFD1FAE5),
                    checkmarkColor: const Color(0xFF059669),
                    onSelected: (val) {
                      setState(() {
                        activeClassPreset = 'custom';
                        if (val) {
                          selectedClassesForGeneration.add(c);
                        } else if (selectedClassesForGeneration.length > 1) {
                          selectedClassesForGeneration.remove(c);
                        } else {
                          _showSnack('ઓછામાં ઓછો ૧ વર્ગ પસંદ રાખવો જરૂરી છે.',
                              isError: true);
                        }
                        if (selectedEntity != null &&
                            !allClasses.contains(selectedEntity)) {
                          selectedEntity = allClasses.firstOrNull;
                        }
                      });
                      _scheduleDeviceAutoSave();
                    },
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF818CF8), width: 1.4),
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stars_rounded,
                          color: Color(0xFF312E81), size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          config.saturdayFirstPeriodSameSubjectEnabled
                              ? '👩‍🏫 દરરોજ પ્રથમ તાસ (તાસ-૧) વર્ગ શિક્ષક માટે અનામત રાખવો છે? (સોમ થી શુક્ર લાગુ પડશે — શનિવારે સમૂહ તાસ પસંદ છે)'
                              : '👩‍🏫 દરરોજ પ્રથમ તાસ (તાસ-૧) વર્ગ શિક્ષક માટે અનામત રાખવો છે? (સોમ થી શનિ બધા દિવસે લાગુ પડશે)',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                            color: Color(0xFF1E1B4B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text(
                          '✅ હા (વર્ગ શિક્ષક માટે અનામત)',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                        selected: config.reserveFirstPeriodForClassTeacher,
                        selectedColor: const Color(0xFFD1FAE5),
                        onSelected: (_) {
                          setState(() {
                            config.reserveFirstPeriodForClassTeacher = true;
                          });
                          _scheduleDeviceAutoSave(immediate: true);
                          _runGenerate(switchTab: false, showNotification: true);
                        },
                      ),
                      ChoiceChip(
                        label: const Text(
                          '❌ ના (કોઈપણ વિષય શિક્ષક)',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                        selected: !config.reserveFirstPeriodForClassTeacher,
                        selectedColor: const Color(0xFFFFE4E6),
                        onSelected: (_) {
                          setState(() {
                            config.reserveFirstPeriodForClassTeacher = false;
                          });
                          _scheduleDeviceAutoSave(immediate: true);
                          _runGenerate(switchTab: false, showNotification: true);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: config.saturdayFirstPeriodSameSubjectEnabled,
                            activeColor: const Color(0xFFD97706),
                            onChanged: (v) {
                              setState(() {
                                config.saturdayFirstPeriodSameSubjectEnabled =
                                    v ?? false;
                              });
                              _scheduleDeviceAutoSave(immediate: true);
                              _runGenerate(switchTab: false, showNotification: true);
                            },
                          ),
                          const Flexible(
                            child: Text(
                              '🏃 શનિવારે પ્રથમ તાસ (તાસ-૧) સમગ્ર જૂથના બધા વર્ગોમાં એક જ વિષય (દા.ત. શા. શિ. / P.T. - વિષય શિક્ષક દ્વારા)',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          value: (<String>{
                            'શા. શિ.',
                            'શા. શિ. (P.T.)',
                            'સમૂહ કવાયત (Mass P.T.)',
                            'યોગ / વ્યાયામ',
                            'બાલસભા / પ્રવૃત્તિ',
                            ...subjects,
                          }.contains(config.saturdayFirstPeriodSubject))
                              ? config.saturdayFirstPeriodSubject
                              : 'શા. શિ.',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'શનિવાર તાસ-૧ નો વિષય',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          items: <String>{
                            'શા. શિ.',
                            'શા. શિ. (P.T.)',
                            'સમૂહ કવાયત (Mass P.T.)',
                            'યોગ / વ્યાયામ',
                            'બાલસભા / પ્રવૃત્તિ',
                            ...subjects,
                          }
                              .map((s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: Text(
                                      s,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (val) {
                            if (val == null) return;
                            setState(() {
                              config.saturdayFirstPeriodSubject = val;
                              config.saturdayFirstPeriodSameSubjectEnabled = true;
                            });
                            _scheduleDeviceAutoSave(immediate: true);
                            _runGenerate(switchTab: false, showNotification: true);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String>(
                          value: teachers.any((t) =>
                                  t.initial ==
                                  config.saturdayFirstPeriodTeacherInitial)
                              ? config.saturdayFirstPeriodTeacherInitial
                              : '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'વિષય શિક્ષક (Subject Teacher)',
                            isDense: true,
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text(
                                'ઓટો (વિષય શિક્ષક / Auto)',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 12),
                              ),
                            ),
                            ...teachers.map(
                              (t) => DropdownMenuItem<String>(
                                value: t.initial,
                                child: Text(
                                  '${t.initial} (${t.fullName})',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (val) {
                            setState(() {
                              config.saturdayFirstPeriodTeacherInitial =
                                  val ?? '';
                              config.saturdayFirstPeriodSameSubjectEnabled = true;
                            });
                            _scheduleDeviceAutoSave(immediate: true);
                            _runGenerate(switchTab: false, showNotification: true);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: SCHOOL SETUP & BACKUP
  // ---------------------------------------------------------------------------
  Widget _buildTab1Setup() {
    final totalAssignedPeriods =
        activeAssignments.fold<int>(0, (s, r) => s + r.requiredPeriods);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '💾 આ જ ઉપકરણમાં ઓટો-સેવ અને બેકઅપ (Device Auto-Save & Cloud Sync)',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        _lastDeviceSaveStatus,
                        style: const TextStyle(
                          color: Color(0xFF065F46),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                      ),
                      onPressed: () => _saveToDeviceNow(manual: true),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label:
                          const Text('💾 ડિવાઇસમાં સેવ કરો (Save on Device)'),
                    ),
                    if (widget.onSaveData != null)
                      FilledButton.icon(
                        onPressed: () => _saveToSchoolDatabase(),
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('☁️ શાળાના ડેટાબેઝમાં સેવ કરો'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _saveAllTeacherInitialsOneClick,
                      icon: const Icon(Icons.badge_rounded, size: 18),
                      label: const Text(
                          '👩‍🏫 શિક્ષક ટૂંકા નામ સેવ કરો (1-Click)'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _pickCustomTimetableLogo(secondLogo: true),
                      icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                      label: const Text(
                          '📤 બીજો લોગો (ફક્ત સમયપત્રક માટે) અપલોડ કરો'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _alignBothLogosCenterSymmetrical,
                      icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                      label: const Text('⚖️ બંને લોગો સમતોલ (Ctrl+E)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        final jsonStr = _exportJsonBackup();
                        Clipboard.setData(ClipboardData(text: jsonStr));
                        _showSnack(
                            '✅ સંપૂર્ણ પ્રોજેક્ટ JSON ક્લિપબોર્ડમાં કોપી થયો!');
                      },
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: const Text('Copy Backup JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showJsonRestoreDialog(),
                      icon: const Icon(Icons.upload_file_rounded, size: 18),
                      label: const Text('Restore JSON Backup'),
                    ),
                    if (widget.useDatabaseData)
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _loadDatabaseMasters();
                            _loadDatabaseAssignments();
                            _syncSelectedClassesWithAvailable();
                          });
                          if (activeAssignments.isNotEmpty) {
                            _runGenerate(switchTab: false);
                          }
                          _showSnack(
                              '🔄 શિક્ષક, ભણાવતા વિષયો અને વર્ગની યાદી ડેટાબેઝમાંથી ફરી લોડ થઈ.');
                        },
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Reload Database Data'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _loadDemoMasters();
                            _loadDemoAssignments();
                            _syncSelectedClassesWithAvailable();
                          });
                          _runGenerate(switchTab: false);
                          _showSnack('🔄 ડેમો ડેટા રીસેટ થયો!');
                        },
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Reset Demo Data'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildClassSelectionCard(),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🏫 શાળાની વિગતો અને અઠવાડિયાના તાસનું માળખું (School Configuration)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: 420,
                      child: TextFormField(
                        key: ValueKey('tt_school_name_${config.schoolName}_$schoolNameLang'),
                        initialValue: config.schoolName,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'શાળાનું નામ (રજીસ્ટ્રેશન મુજબ લોક — માત્ર ભાષા બદલી શકાશે)',
                          filled: true,
                          fillColor: Color(0xFFF8FAFC),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: schoolNameLang,
                        decoration: const InputDecoration(
                          labelText: 'શાળાના નામની ભાષા (Language)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'gu', child: Text('ગુજરાતી (Gujarati)')),
                          DropdownMenuItem(value: 'en', child: Text('English (અંગ્રેજી)')),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            schoolNameLang = v;
                            config.schoolName = _resolvedRegisteredSchoolName;
                          });
                          _scheduleDeviceAutoSave(immediate: true);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: TextFormField(
                        initialValue: config.academicYear,
                        decoration: const InputDecoration(
                          labelText: 'શૈક્ષણિક વર્ષ (Academic Year)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setState(() => config.academicYear = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        initialValue: config.monFriPeriods.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'સોમ થી શુક્ર દૈનિક તાસ (Mon–Fri)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setState(() {
                            config.monFriPeriods =
                                (int.tryParse(v) ?? 8).clamp(1, 15);
                            _initDefaultTimings();
                          });
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        initialValue: config.saturdayPeriods.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'શનિવારના કુલ તાસ (Saturday)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setState(() {
                            config.saturdayPeriods =
                                (int.tryParse(v) ?? 6).clamp(0, 15);
                            _initDefaultTimings();
                          });
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        initialValue: config.maxTeacherWeeklyLoad.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'શિક્ષક મહત્તમ તાસ / અઠવાડિયું',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setState(() => config.maxTeacherWeeklyLoad =
                              (int.tryParse(v) ?? 45).clamp(1, 90));
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        initialValue: config.maxTeacherDailyLoad.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'શિક્ષક મહત્તમ દૈનિક તાસ / દિવસ',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          setState(() => config.maxTeacherDailyLoad =
                              (int.tryParse(v) ?? 7).clamp(1, 15));
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildKpiCard(
                'પસંદ કરેલ વર્ગો (Selected)',
                '${allClasses.length} / ${allAvailableClasses.length}',
                Icons.class_),
            _buildKpiCard('કુલ શિક્ષકો (Teachers)', '${teachers.length}',
                Icons.people_alt_rounded),
            _buildKpiCard('ફાળવેલ કુલ તાસ (Assigned)', '$totalAssignedPeriods',
                Icons.assignment_turned_in_rounded),
            _buildKpiCard('અઠવાડિયાના કુલ તાસ / વર્ગ',
                '${config.weeklySlotsPerClass}', Icons.grid_view_rounded),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: const Color(0xFFEEF2FF),
                foregroundColor: const Color(0xFF4F46E5),
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF4F46E5),
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showJsonRestoreDialog() {
    final ctrl = TextEditingController(text: _exportJsonBackup());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore / Edit JSON Backup'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _importJsonBackup(ctrl.text);
            },
            child: const Text('Restore Now'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 2: PERIOD & BREAK TIMINGS (INSTANT DEVICE AUTO-SAVE)
  // ---------------------------------------------------------------------------
  Widget _buildTab2Timings() {
    final maxP = max(config.monFriPeriods, config.saturdayPeriods);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFECFDF5),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, color: Color(0xFF059669)),
                    const SizedBox(width: 8),
                    Flexible(child: Text(
                      'અહીં એકવાર સમય દાખલ કરશો એટલે ડિવાઇસમાં આપોઆપ કાયમી સેવ થઈ જશે! ($_lastDeviceSaveStatus)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF065F46),
                        fontSize: 13,
                      ),
                    )),
                  ],
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => _saveToDeviceNow(manual: true),
                  icon: const Icon(Icons.save_rounded, size: 17),
                  label: const Text('💾 સમય સેવ કરો (Save Timings)'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: const Text(
                      '🍴 વિરામ / રિસેસ સમય સેટિંગ (Break / Recess Settings)',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    )),
                    DropdownButton<int>(
                      value: breaks.length.clamp(0, 2),
                      items: const [
                        DropdownMenuItem(
                            value: 0, child: Text('0 - કોઈ વિરામ નહીં')),
                        DropdownMenuItem(
                            value: 1, child: Text('1 - એક વિરામ (1 Break)')),
                        DropdownMenuItem(
                            value: 2, child: Text('2 - બે વિરામ (2 Breaks)')),
                      ],
                      onChanged: (count) {
                        if (count == null) return;
                        setState(() {
                          while (breaks.length < count) {
                            breaks.add(BreakConfig(
                              name: breaks.isEmpty
                                  ? 'મુખ્ય રિસેસ / Recess'
                                  : 'નાનો વિરામ / Short Break',
                              afterPeriod: breaks.isEmpty ? 4 : 6,
                              start: breaks.isEmpty ? '12:50' : '15:00',
                              end: breaks.isEmpty ? '13:20' : '15:10',
                            ));
                          }
                          breaks = breaks.sublist(0, count);
                        });
                        _scheduleDeviceAutoSave(immediate: true);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'નોંધ: સળંગ ૨ તાસ (Double Period) ક્યારેય વિરામ (Recess) ની વચ્ચે કપાશે નહીં!',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < breaks.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 240,
                          child: TextFormField(
                            initialValue: breaks[i].name,
                            decoration: InputDecoration(
                              labelText: 'વિરામ ${i + 1} નામ (Break Name)',
                              border: const OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              setState(() => breaks[i].name = v);
                              _scheduleDeviceAutoSave();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: breaks[i].afterPeriod.clamp(1, maxP),
                            decoration: const InputDecoration(
                              labelText: 'કયા તાસ પછી? (After Period)',
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              maxP,
                              (p) => DropdownMenuItem(
                                value: p + 1,
                                child: Text('તાસ ${p + 1} પછી'),
                              ),
                            ),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => breaks[i].afterPeriod = v);
                                _scheduleDeviceAutoSave(immediate: true);
                              }
                            },
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: TextFormField(
                            initialValue: breaks[i].start,
                            decoration: const InputDecoration(
                              labelText: 'શરૂ (Start)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              setState(() => breaks[i].start = v);
                              _scheduleDeviceAutoSave();
                            },
                          ),
                        ),
                        SizedBox(
                          width: 130,
                          child: TextFormField(
                            initialValue: breaks[i].end,
                            decoration: const InputDecoration(
                              labelText: 'પૂર્ણ (End)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              setState(() => breaks[i].end = v);
                              _scheduleDeviceAutoSave();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(child: const Text(
                      '⏱️ દરેક તાસનો સમય (All Period Timings — Auto-Saved in Device)',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    )),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          periodTimings.clear();
                          _initDefaultTimings();
                        });
                        _scheduleDeviceAutoSave(immediate: true);
                      },
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: const Text('ડિફોલ્ટ સમય ભરો'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List.generate(periodTimings.length, (i) {
                    return Container(
                      width: 280,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'તાસ ${i + 1} સમય (Period ${i + 1})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12.5),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: periodTimings[i].start,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '10:50',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) {
                                    periodTimings[i].start = v.trim();
                                    _scheduleDeviceAutoSave();
                                  },
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Text('થી',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w800)),
                              ),
                              Expanded(
                                child: TextFormField(
                                  initialValue: periodTimings[i].end,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    hintText: '11:30',
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) {
                                    periodTimings[i].end = v.trim();
                                    _scheduleDeviceAutoSave();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: TEACHERS (DB FETCHED + INLINE INITIAL FIELD + 1-CLICK SAVE + TAUGHT SUBJECTS)
  // ---------------------------------------------------------------------------
  Widget _buildTab3Masters() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFFEEF2FF),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '👩‍🏫 શિક્ષકો (પૂરું નામ, ટૂંકું નામ અને ભણાવતા વિષયો) તથા વિષય માસ્ટર',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _saveAllTeacherInitialsOneClick,
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text(
                            '💾 બધા ટૂંકા નામ સેવ કરો (Save Initials - 1 Click)',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (widget.useDatabaseData)
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _loadDatabaseMasters();
                                _loadDatabaseAssignments();
                                _syncSelectedClassesWithAvailable();
                              });
                              _scheduleDeviceAutoSave();
                              _showSnack(
                                  '🔄 ડેટાબેઝમાંથી શિક્ષકો અને તેમના ભણાવતા વિષયો લોડ થઈ ગયા!');
                            },
                            icon: const Icon(Icons.sync_rounded, size: 18),
                            label: const Text('ડેટાબેઝમાંથી ફરી લોડ કરો'),
                          ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 280,
                      child: TextField(
                        controller: _teacherFullCtrl,
                        decoration: const InputDecoration(
                          labelText: 'શિક્ષકનું પૂરું નામ (Full Name)',
                          hintText: 'દા.ત. ચિકાણી સુનિલભાઈ',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _teacherInitCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'ટૂંકું નામ (Initial)',
                          hintText: 'દા.ત. SC',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        final f = _teacherFullCtrl.text.trim();
                        final i = _teacherInitCtrl.text.trim().toUpperCase();
                        if (f.isEmpty || i.isEmpty) {
                          _showSnack(
                              'કૃપા કરીને શિક્ષકનું પૂરું નામ અને ટૂંકું નામ બંને લખો.',
                              isError: true);
                          return;
                        }
                        setState(() {
                          final existing =
                              teachers.where((t) => t.initial == i).firstOrNull;
                          if (existing != null) {
                            existing.fullName = f;
                          } else {
                            teachers
                                .add(TeacherMaster(initial: i, fullName: f));
                          }
                          teacherInitialsByName[f.toLowerCase()] = i;
                          quickTeacher ??= i;
                          _teacherFullCtrl.clear();
                          _teacherInitCtrl.clear();
                        });
                        _scheduleDeviceAutoSave(immediate: true);
                      },
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('શિક્ષક ઉમેરો'),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 260,
                      child: TextField(
                        controller: _subjectCtrl,
                        decoration: const InputDecoration(
                          labelText: 'વિષયનું નામ (Subject Name)',
                          hintText: 'દા.ત. ગણિત (Mathematics)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        final s = _subjectCtrl.text.trim();
                        if (s.isEmpty) return;
                        setState(() {
                          if (!subjects.contains(s)) subjects.add(s);
                          quickSubject ??= s;
                          _subjectCtrl.clear();
                        });
                        _scheduleDeviceAutoSave();
                      },
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('વિષય ઉમેરો'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TitleWithActions(
                        title: const Text(
                              '👩‍🏫 ડેટાબેઝમાંથી મળેલ શિક્ષકો — આગળના ખાનામાં ટૂંકું નામ (Initial) લખી 1-Click સેવ કરો',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 14.5),
                            ),
                        actions: [
                          FilledButton.tonalIcon(
                            onPressed: _saveAllTeacherInitialsOneClick,
                            icon: const Icon(Icons.check_circle_rounded,
                                size: 17),
                            label: const Text('Save All Initials'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '💡 દરેક શિક્ષકની આગળ ટૂંકું નામ (Initial) બદલી શકાય છે અને નીચે ડેટાબેઝ મુજબ ભણાવતા વિષયો બતાવેલ છે.',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      const Divider(),
                      for (int idx = 0; idx < teachers.length; idx++)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Editable Initial Field right in front of the fetched teacher name!
                              SizedBox(
                                width: 104,
                                child: TextFormField(
                                  key: ValueKey(
                                      't_init_${teachers[idx].teacherId ?? teachers[idx].fullName}_$idx'),
                                  initialValue: teachers[idx].initial,
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    color: TeacherColorPalette.fromInitial(
                                            teachers[idx].initial)
                                        .text,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: 'Initial',
                                    isDense: true,
                                    filled: true,
                                    fillColor: TeacherColorPalette.fromInitial(
                                            teachers[idx].initial)
                                        .background,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 9),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onChanged: (val) =>
                                      _updateTeacherInitial(idx, val),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      teachers[idx].fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        if (teachers[idx]
                                            .taughtSubjects
                                            .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE0E7FF),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '📚 વિષયો: ${teachers[idx].taughtSubjects.join(", ")}',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF312E81),
                                              ),
                                            ),
                                          ),
                                        if (teachers[idx]
                                            .assignedClasses
                                            .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD1FAE5),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '🏫 વર્ગો: ${teachers[idx].assignedClasses.join(", ")}',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF065F46),
                                              ),
                                            ),
                                          ),
                                        if (teachers[idx]
                                            .unavailableSlots
                                            .isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFFE4E6),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '⛔ ${teachers[idx].unavailableSlots.length} તાસ બ્લોક',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF9F1239),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip:
                                    'શિક્ષકની અનુપલબ્ધતા સેટ કરો (Set Unavailable Slots)',
                                icon: const Icon(Icons.event_busy_rounded,
                                    color: Color(0xFFD97706)),
                                onPressed: () => _showTeacherAvailabilityDialog(
                                    teachers[idx]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Color(0xFFE11D48)),
                                onPressed: () {
                                  setState(() => teachers.removeAt(idx));
                                  _scheduleDeviceAutoSave();
                                },
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '📚 નોંધાયેલા વિષયોની યાદી (Subjects List — DB Synced)',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14.5),
                      ),
                      const Divider(),
                      for (int idx = 0; idx < subjects.length; idx++)
                        ListTile(
                          dense: true,
                          leading: Text('${idx + 1}.',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          title: Text(subjects[idx],
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Color(0xFFE11D48)),
                            onPressed: () {
                              setState(() => subjects.removeAt(idx));
                              _scheduleDeviceAutoSave();
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showTeacherAvailabilityDialog(TeacherMaster teacher) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text(
                '⏰ ${teacher.initial} (${teacher.fullName}) — ઉપલબ્ધતા સેટિંગ'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'જે તાસમાં શિક્ષક શાળામાં હાજર ન રહી શકે તેના પર ક્લિક કરી લાલ (⛔ Unavailable) કરો:',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowHeight: 38,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 42,
                        columns: [
                          const DataColumn(label: Text('તાસ')),
                          for (final d in kSchoolDays)
                            DataColumn(
                                label: Text(d.split(' ').first,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800))),
                        ],
                        rows: List.generate(config.monFriPeriods, (k) {
                          return DataRow(
                            cells: [
                              DataCell(Text('તાસ ${k + 1}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800))),
                              for (int d = 0; d < 6; d++)
                                DataCell(
                                  k >= config.periodsForDay(d)
                                      ? const Text('—')
                                      : InkWell(
                                          onTap: () {
                                            setDialogState(() {
                                              teacher.toggleUnavailable(d, k);
                                            });
                                            setState(() {});
                                            _scheduleDeviceAutoSave();
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: teacher.isUnavailable(d, k)
                                                  ? const Color(0xFFFFE4E6)
                                                  : const Color(0xFFD1FAE5),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              teacher.isUnavailable(d, k)
                                                  ? '⛔ બંધ'
                                                  : '✅ ચાલુ',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w800,
                                                color: teacher.isUnavailable(
                                                        d, k)
                                                    ? const Color(0xFF9F1239)
                                                    : const Color(0xFF065F46),
                                              ),
                                            ),
                                          ),
                                        ),
                                ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setDialogState(() => teacher.unavailableSlots.clear());
                  setState(() {});
                  _scheduleDeviceAutoSave();
                },
                child: const Text('બધા ચાલુ કરો (Clear All)'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('સાચવો (Done)'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 4: TEACHING ASSIGNMENTS & BULK CSV (WITH CLASS FILTER & DB TAUGHT SUBJECTS)
  // ---------------------------------------------------------------------------
  Widget _buildTab4DataEntry() {
    final visibleRows = activeAssignments;
    final teacherLoads = <String, int>{};
    final classLoads = <String, int>{};
    for (final r in visibleRows) {
      teacherLoads[r.teacherInitial] =
          (teacherLoads[r.teacherInitial] ?? 0) + r.requiredPeriods;
      classLoads[r.className] =
          (classLoads[r.className] ?? 0) + r.requiredPeriods;
    }

    final levels = [
      'BALVATIKA',
      ...List.generate(12, (i) => '${i + 1}'),
    ];
    final sections = List.generate(26, (i) => String.fromCharCode(65 + i));
    final selectedTeacherObj =
        teachers.where((t) => t.initial == quickTeacher).firstOrNull;
    final teacherTaughtSet =
        (selectedTeacherObj?.taughtSubjects ?? const <String>[]).toSet();
    final quickClassOptions = allClasses;
    final teacherInitials = teachers.map((t) => t.initial).toSet();
    final subjectSet = subjects.toSet();
    final quickTeacherDropdownItems = teachers
        .map((t) => DropdownMenuItem<String>(
              value: t.initial,
              child: Text(
                t.taughtSubjects.isNotEmpty
                    ? '${t.initial} = ${t.fullName} (${t.taughtSubjects.join("/")})'
                    : '${t.initial} = ${t.fullName}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ))
        .toList(growable: false);
    final quickSubjectDropdownItems = subjects
        .map((subject) => DropdownMenuItem<String>(
              value: subject,
              child: Text(
                teacherTaughtSet.contains(subject) ? '★ $subject' : subject,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: teacherTaughtSet.contains(subject)
                      ? FontWeight.w900
                      : FontWeight.w600,
                  color: teacherTaughtSet.contains(subject)
                      ? const Color(0xFF312E81)
                      : null,
                ),
              ),
            ))
        .toList(growable: false);
    final tableTeacherDropdownItems = teachers
        .map((t) => DropdownMenuItem<String>(
              value: t.initial,
              child: Text('${t.initial} (${t.fullName})'),
            ))
        .toList(growable: false);
    final tableSubjectDropdownItems = subjects
        .map((subject) => DropdownMenuItem<String>(
              value: subject,
              child: Text(subject),
            ))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildClassSelectionCard(compact: true),
        const SizedBox(height: 10),
        // Bulk Import/Export Bar
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '📊 તાસ ફાળવણી અને બલ્ક ટૂલ્સ (Assignments for Selected Classes)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _autoBalanceClassPeriods,
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: Text(
                          '⚡ પસંદ કરેલ ${allClasses.length} વર્ગો ઓટો-બેલેન્સ કરો'),
                    ),
                    if (widget.useDatabaseData)
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _loadDatabaseMasters();
                            _loadDatabaseAssignments();
                            _ensureAssignmentsExistForSelectedClasses();
                          });
                          _scheduleDeviceAutoSave();
                          _runGenerate(switchTab: false);
                          _showSnack(
                              '✅ ડેટાબેઝમાંથી શિક્ષકોના ભણાવતા વિષયો મુજબ તાસ ગોઠવાઈ ગયા!');
                        },
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('🔄 DB વિષયો મુજબ ગોઠવો'),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => _showCsvPasteDialog(),
                      icon: const Icon(Icons.table_chart_rounded, size: 18),
                      label: const Text('📋 કોપી / પેસ્ટ એક્સેલ બોક્સ (CSV)'),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFE11D48)),
                      onPressed: () {
                        setState(() {
                          final sel = allClasses.toSet();
                          assignments.removeWhere((a) =>
                              sel.contains(_normalizeClassName(a.className)));
                          currentSolution = null;
                        });
                        _scheduleDeviceAutoSave();
                      },
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                      label: const Text('પસંદ કરેલ વર્ગો ભૂંસો'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Quick Add Card (Preserves selections after adding & auto-picks DB taught subject!)
        Card(
          color: const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedTeacherObj != null &&
                          selectedTeacherObj.taughtSubjects.isNotEmpty
                      ? '⚡ ઝડપી તાસ ઉમેરો (${selectedTeacherObj.initial} ના DB વિષયો: ${selectedTeacherObj.taughtSubjects.join(", ")})'
                      : '⚡ ઝડપી તાસ ઉમેરો (Quick Add Row — ઉમેર્યા પછી પસંદગી જળવાઈ રહેશે!)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF312E81),
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<String>(
                        value: teacherInitials.contains(quickTeacher)
                            ? quickTeacher
                            : teachers.firstOrNull?.initial,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'શિક્ષક (Teacher)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: quickTeacherDropdownItems,
                        onChanged: (v) {
                          setState(() {
                            quickTeacher = v;
                            final tm = teachers
                                .where((t) => t.initial == v)
                                .firstOrNull;
                            if (tm != null && tm.taughtSubjects.isNotEmpty) {
                              quickSubject = tm.taughtSubjects.first;
                            }
                          });
                        },
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: subjectSet.contains(quickSubject)
                            ? quickSubject
                            : subjects.firstOrNull,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'વિષય (Subject — ★ = DB Taught)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: quickSubjectDropdownItems,
                        onChanged: (v) => setState(() => quickSubject = v),
                      ),
                    ),
                    if (quickClassOptions.isNotEmpty)
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          value: quickClassOptions.contains(quickDatabaseClass)
                              ? quickDatabaseClass
                              : quickClassOptions.firstOrNull,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'વર્ગ (Class)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: quickClassOptions
                              .map((classKey) => DropdownMenuItem(
                                    value: classKey,
                                    child: Text(classKey,
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (value) =>
                              setState(() => quickDatabaseClass = value),
                        ),
                      )
                    else ...[
                      SizedBox(
                        width: 150,
                        child: DropdownButtonFormField<String>(
                          value: quickLevel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'ધોરણ (Class)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: levels
                              .map((l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(
                                      l == 'BALVATIKA'
                                          ? 'BALVATIKA'
                                          : 'ધોરણ $l',
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => quickLevel = v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: DropdownButtonFormField<String>(
                          value: quickSection,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'વિભાગ (Sec)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: sections
                              .map((s) => DropdownMenuItem<String>(
                                    value: s,
                                    child: Text(
                                      'Sec $s',
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => quickSection = v);
                          },
                        ),
                      ),
                    ],
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<bool>(
                        value: quickIsClassTeacher,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'વર્ગ શિક્ષક? (CT)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: true,
                            child: Text(
                              'Yes (હા - CT)',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: false,
                            child: Text(
                              'No (ના)',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => quickIsClassTeacher = v);
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        initialValue: quickRequiredPeriods.toString(),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'જરૂરી તાસ',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => quickRequiredPeriods =
                            (int.tryParse(v) ?? 6).clamp(1, 60),
                      ),
                    ),
                    SizedBox(
                      width: 135,
                      child: TextFormField(
                        initialValue: quickMaxPeriods?.toString() ?? '',
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'મહત્તમ તાસ (Max)',
                          hintText: 'દા.ત. 6',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final parsed = int.tryParse(v.trim());
                          quickMaxPeriods =
                              (parsed != null && parsed > 0) ? parsed : null;
                        },
                      ),
                    ),
                    SizedBox(
                      width: 175,
                      child: DropdownButtonFormField<bool>(
                        value: quickIsDoublePeriod,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'સળંગ ૨ તાસ? (2P)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: Text(
                              'No (રોજ 1 તાસ)',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text(
                              '🔗 Yes (સળંગ 2 તાસ)',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => quickIsDoublePeriod = v);
                          }
                        },
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: TextField(
                        controller: _roomCtrl,
                        decoration: const InputDecoration(
                          labelText: 'લેબ/રૂમ (Optional)',
                          hintText: 'Science Lab',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => quickRoomOrLab = v.trim(),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () {
                        final t = quickTeacher ?? teachers.firstOrNull?.initial;
                        final s = quickSubject ?? subjects.firstOrNull;
                        if (t == null || s == null) {
                          _showSnack('કૃપા કરીને શિક્ષક અને વિષય પસંદ કરો.',
                              isError: true);
                          return;
                        }
                        final targetCls = quickClassOptions.isNotEmpty
                            ? (quickDatabaseClass ??
                                quickClassOptions.firstOrNull ??
                                '$quickLevel-$quickSection')
                            : '$quickLevel-$quickSection';
                        setState(() {
                          selectedClassesForGeneration.add(targetCls);
                          final effectiveReq = (quickMaxPeriods != null &&
                                  quickMaxPeriods! > 0 &&
                                  quickRequiredPeriods > quickMaxPeriods!)
                              ? quickMaxPeriods!
                              : quickRequiredPeriods;
                          assignments.add(TeachingAssignment(
                            id: 'row_${DateTime.now().microsecondsSinceEpoch}',
                            teacherInitial: t,
                            subject: s,
                            className: targetCls,
                            isClassTeacher: quickIsClassTeacher,
                            requiredPeriods: effectiveReq,
                            maxPeriods: quickMaxPeriods,
                            isDoublePeriod: quickIsDoublePeriod,
                            roomOrLab:
                                quickRoomOrLab.isEmpty ? null : quickRoomOrLab,
                          ));
                        });
                        _scheduleDeviceAutoSave();
                        _showSnack('✅ હરોળ ઉમેરાઈ ગઈ!');
                      },
                      icon: const Icon(Icons.add_circle_outline_rounded),
                      label: const Text('ટેબલમાં ઉમેરો (Add Row)'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Assignments DataTable (filtered to selected classes)
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('શિક્ષક (Teacher)')),
                DataColumn(label: Text('વિષય (Subject)')),
                DataColumn(label: Text('ધોરણ-વર્ગ')),
                DataColumn(label: Text('વર્ગ શિક્ષક? (CT)')),
                DataColumn(label: Text('જરૂરી તાસ')),
                DataColumn(label: Text('સળંગ ૨ તાસ?')),
                DataColumn(label: Text('લેબ/રૂમ')),
                DataColumn(label: Text('શિક્ષક ભારણ')),
                DataColumn(label: Text('વર્ગ કુલ તાસ')),
                DataColumn(label: Text('દૂર કરો')),
              ],
              rows: List.generate(visibleRows.length, (idx) {
                final r = visibleRows[idx];
                final tLoad = teacherLoads[r.teacherInitial] ?? 0;
                final cLoad = classLoads[r.className] ?? 0;
                return DataRow(
                  color: r.isClassTeacher
                      ? WidgetStateProperty.all(const Color(0xFFEEF2FF))
                      : null,
                  cells: [
                    DataCell(Text('${idx + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                    DataCell(
                      DropdownButton<String>(
                        value: teacherInitials.contains(r.teacherInitial)
                            ? r.teacherInitial
                            : null,
                        underline: const SizedBox(),
                        items: tableTeacherDropdownItems,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => r.teacherInitial = v);
                            _scheduleDeviceAutoSave();
                          }
                        },
                      ),
                    ),
                    DataCell(
                      DropdownButton<String>(
                        value:
                            subjectSet.contains(r.subject) ? r.subject : null,
                        underline: const SizedBox(),
                        items: tableSubjectDropdownItems,
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => r.subject = v);
                            _scheduleDeviceAutoSave();
                          }
                        },
                      ),
                    ),
                    DataCell(
                      InkWell(
                        onTap: () => _editTextCellDialog(
                          title: 'વર્ગ બદલો (Edit Class)',
                          initialValue: r.className,
                          onSave: (val) {
                            if (val.trim().isNotEmpty) {
                              setState(
                                  () => r.className = val.trim().toUpperCase());
                              _scheduleDeviceAutoSave();
                            }
                          },
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(r.className,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_outlined,
                                size: 14, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      ChoiceChip(
                        label: Text(r.isClassTeacher ? '★ Yes (CT)' : 'No'),
                        selected: r.isClassTeacher,
                        onSelected: (v) {
                          setState(() => r.isClassTeacher = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                size: 18),
                            onPressed: () {
                              if (r.requiredPeriods > 1) {
                                setState(() => r.requiredPeriods--);
                                _scheduleDeviceAutoSave();
                              }
                            },
                          ),
                          InkWell(
                            onTap: () => _editTextCellDialog(
                              title:
                                  '${r.className} - ${r.subject}: મહત્તમ તાસ મર્યાદા (Max Cap)',
                              initialValue: r.maxPeriods?.toString() ?? '',
                              onSave: (val) {
                                final p = int.tryParse(val.trim());
                                setState(() {
                                  r.maxPeriods = (p != null && p > 0) ? p : null;
                                  if (r.maxPeriods != null &&
                                      r.requiredPeriods > r.maxPeriods!) {
                                    r.requiredPeriods = r.maxPeriods!;
                                  }
                                });
                                _scheduleDeviceAutoSave();
                              },
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('${r.requiredPeriods}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14)),
                                Text(
                                  r.maxPeriods != null && r.maxPeriods! > 0
                                      ? 'Max: ${r.maxPeriods}'
                                      : 'Max સેટ કરો',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: r.maxPeriods != null &&
                                            r.maxPeriods! > 0
                                        ? const Color(0xFFB45309)
                                        : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.add_circle_outline, size: 18),
                            onPressed: () {
                              if (r.maxPeriods != null &&
                                  r.maxPeriods! > 0 &&
                                  r.requiredPeriods >= r.maxPeriods!) {
                                _showSnack(
                                  '⚠️ આ વિષય માટે મહત્તમ તાસ મર્યાદા ${r.maxPeriods} સેટ કરેલ છે!',
                                  isError: true,
                                );
                                return;
                              }
                              setState(() => r.requiredPeriods++);
                              _scheduleDeviceAutoSave();
                            },
                          ),
                        ],
                      ),
                    ),
                    DataCell(
                      ChoiceChip(
                        label: Text(r.isDoublePeriod ? '🔗 2P સળંગ' : '1/Day'),
                        selected: r.isDoublePeriod,
                        selectedColor: const Color(0xFFFEF3C7),
                        onSelected: (v) {
                          setState(() => r.isDoublePeriod = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                    DataCell(
                      InkWell(
                        onTap: () => _editTextCellDialog(
                          title: 'લેબ / રૂમ બદલો (Edit Room or Lab)',
                          initialValue: r.roomOrLab ?? '',
                          onSave: (val) {
                            setState(() => r.roomOrLab =
                                val.trim().isEmpty ? null : val.trim());
                            _scheduleDeviceAutoSave();
                          },
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(child: Text(r.roomOrLab ?? '—')),
                            const SizedBox(width: 4),
                            const Icon(Icons.edit_outlined,
                                size: 14, color: Color(0xFF64748B)),
                          ],
                        ),
                      ),
                    ),
                    DataCell(
                      _buildStatusPill(
                        '$tLoad / ${config.maxTeacherWeeklyLoad}',
                        isBad: tLoad > config.maxTeacherWeeklyLoad,
                      ),
                    ),
                    DataCell(
                      _buildStatusPill(
                        '$cLoad / ${config.weeklySlotsPerClass}',
                        isBad: cLoad > config.weeklySlotsPerClass,
                        isWarn: cLoad < config.weeklySlotsPerClass,
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Color(0xFFE11D48)),
                        onPressed: () {
                          setState(() => assignments.remove(r));
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusPill(String text,
      {bool isBad = false, bool isWarn = false}) {
    final bg = isBad
        ? const Color(0xFFFFE4E6)
        : (isWarn ? const Color(0xFFFEF3C7) : const Color(0xFFD1FAE5));
    final fg = isBad
        ? const Color(0xFF9F1239)
        : (isWarn ? const Color(0xFF92400E) : const Color(0xFF065F46));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: fg),
      ),
    );
  }

  void _showCsvPasteDialog() {
    final ctrl = TextEditingController(
        text: _exportCsvText(sampleOnly: assignments.isEmpty));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title:
            const Text('📋 કોપી / પેસ્ટ એક્સેલ બોક્સ (CSV Bulk Import/Export)'),
        content: SizedBox(
          width: 620,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'અહીંથી ટેમ્પ્લેટ કોપી કરી Excel માં પેસ્ટ કરો અથવા Excel માંથી રો કોપી કરી અહીં પેસ્ટ કરો:',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 10,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: ctrl.text));
              _showSnack('✅ CSV ટેક્સ્ટ કોપી થઈ ગયું!');
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy CSV'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _importCsvText(ctrl.text);
            },
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('પેસ્ટ કરેલો ડેટા લોડ કરો'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 5: PRAYER & PAGE DESIGN STUDIO
  // ---------------------------------------------------------------------------
  Widget _buildTab5PageDesign() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🙏 પ્રાર્થના સમય, રો હાઇટ, સહી અને પેજ બોર્ડર ડિઝાઇન (Prayer & Print Layout Studio)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const Divider(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 14,
                  children: [
                    SizedBox(
                      width: 220,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('પ્રાર્થના હરોળ બતાવો',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                        value: pageDesign.prayerEnabled,
                        onChanged: (v) =>
                            setState(() => pageDesign.prayerEnabled = v),
                      ),
                    ),
                    SizedBox(
                      width: 280,
                      child: TextFormField(
                        initialValue: pageDesign.prayerName,
                        decoration: const InputDecoration(
                          labelText: 'પ્રાર્થનાનું નામ (Prayer Title)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => pageDesign.prayerName = v),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        initialValue: pageDesign.prayerStart,
                        decoration: const InputDecoration(
                          labelText: 'શરૂ સમય',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => pageDesign.prayerStart = v),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: TextFormField(
                        initialValue: pageDesign.prayerEnd,
                        decoration: const InputDecoration(
                          labelText: 'પૂર્ણ સમય',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) =>
                            setState(() => pageDesign.prayerEnd = v),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('આચાર્ય/વર્ગ શિક્ષક સહી બતાવો',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 13)),
                        value: pageDesign.showSignatures,
                        onChanged: (v) =>
                            setState(() => pageDesign.showSignatures = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 24,
                  runSpacing: 12,
                  children: [
                    _buildSliderControl(
                      label:
                          'કોલમ પહોળાઈ (Column Width): ${pageDesign.columnWidthPx.toInt()} px',
                      value: pageDesign.columnWidthPx,
                      min: 85,
                      max: 260,
                      step: 5,
                      onChanged: (v) {
                        setState(() => pageDesign.columnWidthPx = v);
                        _scheduleDeviceAutoSave();
                      },
                    ),
                    _buildSliderControl(
                      label:
                          'તાસની ઊંચાઈ (Row Height): ${pageDesign.periodHeightMm.toInt()} mm',
                      value: pageDesign.periodHeightMm,
                      min: 10,
                      max: 30,
                      step: 1,
                      onChanged: (v) {
                        setState(() => pageDesign.periodHeightMm = v);
                        _scheduleDeviceAutoSave();
                      },
                    ),
                    _buildSliderControl(
                      label:
                          'શિક્ષક નામ ફોન્ટ સાઈઝ (Teacher Name Font): ${pageDesign.teacherLegendFontSizePx.toStringAsFixed(1)} px',
                      value: pageDesign.teacherLegendFontSizePx,
                      min: 7,
                      max: 18,
                      step: 0.5,
                      onChanged: (v) {
                        setState(() => pageDesign.teacherLegendFontSizePx = v);
                        _scheduleDeviceAutoSave();
                      },
                    ),
                    _buildSliderControl(
                      label:
                          'બોર્ડર જાડાઈ: ${pageDesign.borderWidthPx.toInt()} px',
                      value: pageDesign.borderWidthPx,
                      min: 1,
                      max: 8,
                      step: 1,
                      onChanged: (v) {
                        setState(() => pageDesign.borderWidthPx = v);
                        _scheduleDeviceAutoSave();
                      },
                    ),
                    _buildSliderControl(
                      label:
                          'બોર્ડર માર્જિન (Top/Left): ${pageDesign.marginTopPx.toInt()} px',
                      value: pageDesign.marginTopPx,
                      min: 0,
                      max: 32,
                      step: 1,
                      onChanged: (v) {
                        setState(() {
                          pageDesign.marginTopPx = v;
                          pageDesign.marginBottomPx = v;
                          pageDesign.marginLeftPx = v;
                          pageDesign.marginRightPx = v;
                        });
                        _scheduleDeviceAutoSave();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required double min,
    required double max,
    double step = 1,
    required ValueChanged<double> onChanged,
  }) {
    final clamped = value.clamp(min, max).toDouble();
    return SizedBox(
      width: 290,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
              ),
              IconButton(
                tooltip: 'Decrease (-)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove_circle_outline, size: 20),
                onPressed: clamped <= min
                    ? null
                    : () => onChanged((clamped - step).clamp(min, max)),
              ),
              IconButton(
                tooltip: 'Increase (+)',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add_circle_outline, size: 20),
                onPressed: clamped >= max
                    ? null
                    : () => onChanged((clamped + step).clamp(min, max)),
              ),
            ],
          ),
          Slider(
            value: clamped,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Future<void> _pickCustomTimetableLogo({bool secondLogo = false}) async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;
      final ext = (file.extension ?? 'png').toLowerCase();
      final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/$ext';
      final uri = 'data:$mime;base64,${base64Encode(bytes)}';
      setState(() {
        if (secondLogo) {
          _customUploadedLogo2Bytes = bytes;
          _customUploadedLogo2DataUri = uri;
          useSameLogoBothSides = false;
          showSecondLogo = true;
          logo2Style.shape = 'original';
          activeBrandLayer = 'logo2';
        } else {
          _customUploadedLogoBytes = bytes;
          _customUploadedLogoDataUri = uri;
          logoStyle.shape = 'original';
          watermarkStyle.shape = 'original';
          activeBrandLayer = 'logo';
        }
      });
      _scheduleDeviceAutoSave(immediate: true);
      _showSnack(secondLogo
          ? '✅ બીજો લોગો (Logo 2) અપલોડ થયો!'
          : '✅ લોગો અપલોડ થયો (મૂળ આકારમાં સેટ થયો)!');
    } catch (e) {
      _showSnack('લોગો અપલોડ કરવામાં ભૂલ: $e', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 6: LOGO & WATERMARK INTERACTIVE DRAG STUDIO (2 Logos or Same Both Sides)
  // ---------------------------------------------------------------------------
  Widget _buildTab6Branding() {
    final activeStyle = activeBrandLayer == 'logo'
        ? logoStyle
        : activeBrandLayer == 'logo2'
            ? logo2Style
            : watermarkStyle;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🎨 બે લોગો અને વોટરમાર્ક સ્ટુડિયો (2 Logos / Same Logo Both Sides)',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _pickCustomTimetableLogo(secondLogo: false),
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: const Text('📤 લોગો 1 અપલોડ કરો'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: () => _pickCustomTimetableLogo(secondLogo: true),
                            icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                            label: const Text('📤 બીજો લોગો 2 (ફક્ત સમયપત્રક માટે) અપલોડ કરો'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _alignBothLogosCenterSymmetrical,
                            icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                            label: const Text('⚖️ બંને લોગો સમતોલ ગોઠવો (Ctrl+E)'),
                          ),
                          if (_customUploadedLogoBytes != null || _customUploadedLogo2Bytes != null)
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _customUploadedLogoBytes = null;
                                  _customUploadedLogoDataUri = '';
                                  _customUploadedLogo2Bytes = null;
                                  _customUploadedLogo2DataUri = '';
                                  useSameLogoBothSides = true;
                                });
                                _scheduleDeviceAutoSave(immediate: true);
                              },
                              icon: const Icon(Icons.restore_rounded, size: 18),
                              label: const Text('DB લોગો વાપરો'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'બંને બાજુ એક જ લોગો રાખો (Same Logo on Both Sides)',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        subtitle: const Text(
                          'ચાલુ રાખવાથી ડાબી અને જમણી બંને બાજુ એક જ લોગો દેખાશે; બંધ કરવાથી બીજો અલગ લોગો મૂકી શકાશે.',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        value: useSameLogoBothSides,
                        onChanged: (v) {
                          setState(() {
                            useSameLogoBothSides = v;
                            if (v) showSecondLogo = true;
                          });
                          _scheduleDeviceAutoSave();
                        },
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'logo', label: Text('🛡️ લોગો 1 (Left)')),
                          ButtonSegment(
                              value: 'logo2', label: Text('🛡️ લોગો 2 (Right)')),
                          ButtonSegment(
                              value: 'watermark',
                              label: Text('💧 વોટરમાર્ક')),
                        ],
                        selected: {activeBrandLayer},
                        onSelectionChanged: (s) =>
                            setState(() => activeBrandLayer = s.first),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: const {'original', 'square', 'rect', 'round'}
                                .contains(activeStyle.shape)
                            ? activeStyle.shape
                            : 'original',
                        decoration: const InputDecoration(
                          labelText: 'લોગોનો આકાર (Logo Shape)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'original',
                            child: Text('✨ અપલોડ કર્યા મુજબ મૂળ આકાર (As Uploaded)'),
                          ),
                          DropdownMenuItem(
                            value: 'square',
                            child: Text('⬛ ચોરસ (Square)'),
                          ),
                          DropdownMenuItem(
                            value: 'rect',
                            child: Text('▭ લંબચોરસ (Rectangle)'),
                          ),
                          DropdownMenuItem(
                            value: 'round',
                            child: Text('⚪ ગોળ (Round)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => activeStyle.shape = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(activeBrandLayer == 'logo'
                            ? 'લોગો 1 બતાવો (Show Left Logo)'
                            : activeBrandLayer == 'logo2'
                                ? 'લોગો 2 બતાવો (Show Right Logo)'
                                : 'વોટરમાર્ક બતાવો (Show Watermark)'),
                        value: activeBrandLayer == 'logo'
                            ? showLogo
                            : activeBrandLayer == 'logo2'
                                ? showSecondLogo
                                : showWatermark,
                        onChanged: (v) {
                          setState(() {
                            if (activeBrandLayer == 'logo') {
                              showLogo = v;
                            } else if (activeBrandLayer == 'logo2') {
                              showSecondLogo = v;
                            } else {
                              showWatermark = v;
                            }
                          });
                          _scheduleDeviceAutoSave();
                        },
                      ),
                      _buildSliderControl(
                        label: 'સાઇઝ (Size): ${activeStyle.widthPx.toInt()} px',
                        value: activeStyle.widthPx,
                        min: 30,
                        max: 320,
                        step: 5,
                        onChanged: (v) {
                          setState(() {
                            activeStyle.widthPx = v;
                            activeStyle.heightPx = v;
                          });
                          _scheduleDeviceAutoSave();
                        },
                      ),
                      _buildSliderControl(
                        label: 'આડી જગ્યા (X Position): ${activeStyle.xPercent.toInt()}%',
                        value: activeStyle.xPercent,
                        min: 2,
                        max: 98,
                        step: 1,
                        onChanged: (v) {
                          setState(() => activeStyle.xPercent = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                      _buildSliderControl(
                        label: 'ઊભી જગ્યા (Y Position): ${activeStyle.yPercent.toInt()}%',
                        value: activeStyle.yPercent,
                        min: 2,
                        max: 98,
                        step: 1,
                        onChanged: (v) {
                          setState(() => activeStyle.yPercent = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                      _buildSliderControl(
                        label:
                            'પારદર્શકતા (Opacity): ${(activeStyle.opacity * 100).toInt()}%',
                        value: activeStyle.opacity,
                        min: 0.04,
                        max: 1.0,
                        step: 0.05,
                        onChanged: (v) {
                          setState(() => activeStyle.opacity = v);
                          _scheduleDeviceAutoSave();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        void moveActiveToLocal(Offset localPos) {
                          final target = activeBrandLayer == 'logo'
                              ? logoStyle
                              : activeBrandLayer == 'logo2'
                                  ? logo2Style
                                  : watermarkStyle;
                          setState(() {
                            target.xPercent =
                                ((localPos.dx / constraints.maxWidth) * 100.0)
                                    .clamp(2.0, 98.0);
                            target.yPercent =
                                ((localPos.dy / constraints.maxHeight) * 100.0)
                                    .clamp(2.0, 98.0);
                          });
                          _scheduleDeviceAutoSave();
                        }

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (details) =>
                              moveActiveToLocal(details.localPosition),
                          onPanUpdate: (details) =>
                              moveActiveToLocal(details.localPosition),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: const Color(0xFF818CF8), width: 2),
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      activeBrandLayer == 'logo'
                                          ? '👆 લોગો 1 (ડાબી બાજુ) ગમે ત્યાં મૂકવા ક્લિક અથવા ડ્રેગ કરો'
                                          : activeBrandLayer == 'logo2'
                                              ? '👆 લોગો 2 (જમણી બાજુ) ગમે ત્યાં મૂકવા ક્લિક અથવા ડ્રેગ કરો'
                                              : '👆 વોટરમાર્કને ગમે ત્યાં મૂકવા ક્લિક અથવા ડ્રેગ કરો',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                                if (showWatermark)
                                  _buildDraggableEmblem(
                                    constraints: constraints,
                                    style: watermarkStyle,
                                    layerKey: 'watermark',
                                  ),
                                if (showLogo)
                                  _buildDraggableEmblem(
                                    constraints: constraints,
                                    style: logoStyle,
                                    layerKey: 'logo',
                                  ),
                                if (showSecondLogo)
                                  _buildDraggableEmblem(
                                    constraints: constraints,
                                    style: logo2Style,
                                    layerKey: 'logo2',
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDraggableEmblem({
    required BoxConstraints constraints,
    required OverlayLayerStyle style,
    required String layerKey,
  }) {
    final left =
        (style.xPercent / 100.0) * constraints.maxWidth - (style.widthPx / 2);
    final top =
        (style.yPercent / 100.0) * constraints.maxHeight - (style.heightPx / 2);

    return Positioned(
      left: left.clamp(0.0, max(0.0, constraints.maxWidth - style.widthPx)),
      top: top.clamp(0.0, max(0.0, constraints.maxHeight - style.heightPx)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => activeBrandLayer = layerKey),
        onPanUpdate: (details) {
          setState(() {
            activeBrandLayer = layerKey;
            final newX = ((left + (style.widthPx / 2) + details.delta.dx) /
                    constraints.maxWidth) *
                100.0;
            final newY = ((top + (style.heightPx / 2) + details.delta.dy) /
                    constraints.maxHeight) *
                100.0;
            style.xPercent = newX.clamp(2.0, 98.0);
            style.yPercent = newY.clamp(2.0, 98.0);
          });
          _scheduleDeviceAutoSave();
        },
        child: Opacity(
          opacity: style.opacity,
          child: _buildSchoolEmblemBadge(
            size: style.widthPx,
            shape: style.shape,
            secondLogo: layerKey == 'logo2',
          ),
        ),
      ),
    );
  }

  Uint8List? get _effectiveLogoBytes {
    if (_customUploadedLogoBytes != null &&
        _customUploadedLogoBytes!.isNotEmpty) {
      return _customUploadedLogoBytes;
    }
    final dbBytes = widget.databaseData['schoolLogoBytes'];
    if (dbBytes is Uint8List && dbBytes.isNotEmpty) return dbBytes;
    return null;
  }

  Uint8List? get _effectiveLogo2Bytes {
    if (useSameLogoBothSides) return _effectiveLogoBytes;
    if (_customUploadedLogo2Bytes != null &&
        _customUploadedLogo2Bytes!.isNotEmpty) {
      return _customUploadedLogo2Bytes;
    }
    return _effectiveLogoBytes;
  }

  String get _effectiveLogoDataUri {
    if (_customUploadedLogoDataUri.isNotEmpty) {
      return _customUploadedLogoDataUri;
    }
    final dbUri = (widget.databaseData['schoolLogoDataUri'] ?? '').toString().trim();
    if (dbUri.isNotEmpty) return dbUri;
    final bytes = _effectiveLogoBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return 'data:image/png;base64,${base64Encode(bytes)}';
    }
    return '';
  }

  String get _effectiveLogo2DataUri {
    if (useSameLogoBothSides) return _effectiveLogoDataUri;
    if (_customUploadedLogo2DataUri.isNotEmpty) {
      return _customUploadedLogo2DataUri;
    }
    return _effectiveLogoDataUri;
  }

  Widget _buildSchoolEmblemBadge({
    required double size,
    String shape = 'original',
    bool secondLogo = false,
  }) {
    final logoBytes = secondLogo ? _effectiveLogo2Bytes : _effectiveLogoBytes;
    if (logoBytes != null && logoBytes.isNotEmpty) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: size * 1.6,
          maxHeight: size,
        ),
        child: Image.memory(
          logoBytes,
          height: size,
          fit: BoxFit.contain,
        ),
      );
    }
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: size * 1.5,
        maxHeight: size,
      ),
      child: Image.asset(
        'assets/hajari_patrak/pm_shri_logo.png',
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Padding(
          padding: const EdgeInsets.all(4.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('PM SHRI',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E1B4B),
                      fontSize: 13)),
              Icon(Icons.school_rounded, color: Color(0xFF4F46E5), size: 24),
              Text('★ ગુજરાત ★',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF059669),
                      fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 7: TIMETABLE VIEWS (WITH INTERACTIVE SWAP & SLOT LOCKING)
  // ---------------------------------------------------------------------------
  Widget _buildTab7Views() {
    final sol = currentSolution;
    if (sol == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: () => _runGenerate(switchTab: false),
          icon: const Icon(Icons.bolt_rounded),
          label: const Text('⚡ સમયપત્રક બનાવો (Generate Now)'),
        ),
      );
    }

    final classes = allClasses;
    final assignedTeachers = allAssignedTeachers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 20),
      children: [
        Card(
          margin: EdgeInsets.zero,
          color: const Color(0xFFF8FAFC),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.filter_alt_rounded, color: Color(0xFF4F46E5)),
            title: Text(
              '🎯 વર્ગો પસંદ કરો / ફિલ્ટર (Selected Classes: ${classes.length}/${allAvailableClasses.length})',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
            ),
            children: [
              _buildClassSelectionCard(compact: true),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Top View Selector & Interactive Hint Bar
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      child: DropdownButtonFormField<String>(
                        value: selectedViewMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'સમયપત્રકનો પ્રકાર (Select View Mode)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'class',
                            child: Text('🏫 વર્ગ મુજબ સમયપત્રક (Class-Wise)'),
                          ),
                          DropdownMenuItem(
                            value: 'teacher',
                            child: Text(
                                '👩‍🏫 શિક્ષક મુજબ સમયપત્રક (Teacher-Wise)'),
                          ),
                          DropdownMenuItem(
                            value: 'whole',
                            child: Text(
                                '🏛️ સમગ્ર શાળાના બધા વર્ગો (All Classes)'),
                          ),
                          DropdownMenuItem(
                            value: 'allteachers',
                            child: Text(
                                '👥 બધા શિક્ષકોના સમયપત્રક (All Teachers)'),
                          ),
                          DropdownMenuItem(
                            value: 'mastergrid',
                            child: Text(
                                '📋 સંયુક્ત માસ્ટર શીટ (School Master Grid)'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() {
                            selectedViewMode = v;
                            selectedSlotForSwap = null;
                            if (v == 'class') {
                              selectedEntity = classes.firstOrNull;
                            } else if (v == 'teacher') {
                              selectedEntity = assignedTeachers.firstOrNull;
                            }
                          });
                        },
                      ),
                    ),
                    if (selectedViewMode == 'class')
                      SizedBox(
                        width: 230,
                        child: DropdownButtonFormField<String>(
                          value: classes.contains(selectedEntity)
                              ? selectedEntity
                              : classes.firstOrNull,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'વર્ગ પસંદ કરો (Select Class)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: classes
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text('વર્ગ $c'),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() {
                            selectedEntity = v;
                            selectedSlotForSwap = null;
                          }),
                        ),
                      ),
                    if (selectedViewMode == 'teacher')
                      SizedBox(
                        width: 280,
                        child: DropdownButtonFormField<String>(
                          value: assignedTeachers.contains(selectedEntity)
                              ? selectedEntity
                              : assignedTeachers.firstOrNull,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'શિક્ષક પસંદ કરો (Select Teacher)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: assignedTeachers
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text('$t = ${fullNameOf(t)}',
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => selectedEntity = v),
                        ),
                      ),
                    FilledButton.tonalIcon(
                      onPressed: () => _runGenerate(switchTab: false),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('ફરી ગોઠવો (Re-Solve)'),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _printOrExportTimetableHtml,
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('🖨️ ડાયરેક્ટ PDF ડાઉનલોડ / પ્રિન્ટ'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _pickCustomTimetableLogo(secondLogo: true),
                      icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
                      label: const Text('📤 બીજો લોગો (સમયપત્રક માટે)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _alignBothLogosCenterSymmetrical,
                      icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                      label: const Text('⚖️ બંને લોગો સમતોલ (Ctrl+E)'),
                    ),
                    if (widget.onSaveData != null)
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _saveToSchoolDatabase,
                        icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                        label: const Text('☁️ Database માં સેવ કરો'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                  ),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_horiz_rounded,
                              size: 18, color: Color(0xFF1E293B)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(
                            'કોલમ પહોળાઈ (Column Width): ${pageDesign.columnWidthPx.toInt()} px',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12.5),
                          )),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'કોલમ પહોળાઈ ઘટાડો (-)',
                            visualDensity: VisualDensity.compact,
                            onPressed: pageDesign.columnWidthPx <= 85
                                ? null
                                : () {
                                    setState(() {
                                      pageDesign.columnWidthPx =
                                          (pageDesign.columnWidthPx - 8)
                                              .clamp(85.0, 260.0);
                                    });
                                    _scheduleDeviceAutoSave();
                                  },
                            icon: const Icon(Icons.remove, size: 16),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'કોલમ પહોળાઈ વધારો (+)',
                            visualDensity: VisualDensity.compact,
                            onPressed: pageDesign.columnWidthPx >= 260
                                ? null
                                : () {
                                    setState(() {
                                      pageDesign.columnWidthPx =
                                          (pageDesign.columnWidthPx + 8)
                                              .clamp(85.0, 260.0);
                                    });
                                    _scheduleDeviceAutoSave();
                                  },
                            icon: const Icon(Icons.add, size: 16),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_vert_rounded,
                              size: 18, color: Color(0xFF1E293B)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(
                            'હરોળ ઊંચાઈ (Row Height): ${pageDesign.periodHeightMm.toInt()} mm',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12.5),
                          )),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'હરોળ ઊંચાઈ ઘટાડો (-)',
                            visualDensity: VisualDensity.compact,
                            onPressed: pageDesign.periodHeightMm <= 10
                                ? null
                                : () {
                                    setState(() {
                                      pageDesign.periodHeightMm =
                                          (pageDesign.periodHeightMm - 1)
                                              .clamp(10.0, 30.0);
                                    });
                                    _scheduleDeviceAutoSave();
                                  },
                            icon: const Icon(Icons.remove, size: 16),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'હરોળ ઊંચાઈ વધારો (+)',
                            visualDensity: VisualDensity.compact,
                            onPressed: pageDesign.periodHeightMm >= 30
                                ? null
                                : () {
                                    setState(() {
                                      pageDesign.periodHeightMm =
                                          (pageDesign.periodHeightMm + 1)
                                              .clamp(10.0, 30.0);
                                    });
                                    _scheduleDeviceAutoSave();
                                  },
                            icon: const Icon(Icons.add, size: 16),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.format_size_rounded,
                              size: 18, color: Color(0xFF1E293B)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(
                            'શિક્ષક નામ ફોન્ટ: ${pageDesign.teacherLegendFontSizePx.toStringAsFixed(1)} px',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 12.5),
                          )),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'શિક્ષક નામ ફોન્ટ ઘટાડો (-)',
                            visualDensity: VisualDensity.compact,
                            onPressed: pageDesign.teacherLegendFontSizePx <= 6.5
                                ? null
                                : () {
                                    setState(() {
                                      pageDesign.teacherLegendFontSizePx =
                                          (pageDesign.teacherLegendFontSizePx -
                                                  0.5)
                                              .clamp(6.5, 18.0);
                                    });
                                    _scheduleDeviceAutoSave();
                                  },
                            icon: const Icon(Icons.remove, size: 16),
                          ),
                          const SizedBox(width: 4),
                          IconButton.filledTonal(
                            tooltip: 'શિક્ષક નામ ફોન્ટ વધારો (+)',
                            visualDensity: VisualDensity.compact,
                            onPressed: pageDesign.teacherLegendFontSizePx >= 18.0
                                ? null
                                : () {
                                    setState(() {
                                      pageDesign.teacherLegendFontSizePx =
                                          (pageDesign.teacherLegendFontSizePx +
                                                  0.5)
                                              .clamp(6.5, 18.0);
                                    });
                                    _scheduleDeviceAutoSave();
                                  },
                            icon: const Icon(Icons.add, size: 16),
                          ),
                        ],
                      ),
                      FilterChip(
                        selected: pageDesign.teacherLegendSingleLine,
                        onSelected: (v) {
                          setState(() => pageDesign.teacherLegendSingleLine = v);
                          _scheduleDeviceAutoSave();
                        },
                        label: const Text(
                          '↔️ શિક્ષક નામ ૧ જ લાઈનમાં (ડાબેથી જમણે)',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      FilterChip(
                        selected: pageDesign.fullPagePdf,
                        onSelected: (v) {
                          setState(() => pageDesign.fullPagePdf = v);
                          _scheduleDeviceAutoSave();
                        },
                        label: const Text(
                          '📄 PDF માં આખા પેજમાં (Full Page PDF)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            pageDesign.columnWidthPx = 155;
                            pageDesign.periodHeightMm = 18;
                            pageDesign.fullPagePdf = true;
                          });
                          _scheduleDeviceAutoSave();
                        },
                        icon: const Icon(Icons.fit_screen_rounded, size: 16),
                        label: const Text('Full Screen Size'),
                      ),
                    ],
                  ),
                ),
                if (selectedViewMode == 'class') ...[
                  const SizedBox(height: 8),
                  const Text(
                    '💡 ઇન્ટરેક્ટિવ સુવિધા: કોઈપણ બે તાસની અદલાબદલી (Swap) કરવા માટે પહેલા તાસ પર ક્લિક કરો અને પછી બીજા તાસ પર ક્લિક કરો (સિસ્ટમ આપોઆપ ક્લેશ ચેક કરશે!). લાંબો સમય દબાવી રાખવાથી (Long-Press) તાસ 🔒 Lock/Pin થશે.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF312E81),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Render Target Timetable Cards
        if (selectedViewMode == 'class' && selectedEntity != null)
          _buildSingleTimetableSheet(
            entityName: selectedEntity!,
            isClassView: true,
          )
        else if (selectedViewMode == 'teacher' && selectedEntity != null)
          _buildSingleTimetableSheet(
            entityName: selectedEntity!,
            isClassView: false,
          )
        else if (selectedViewMode == 'whole')
          for (final c in classes)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _buildSingleTimetableSheet(
                entityName: c,
                isClassView: true,
              ),
            )
        else if (selectedViewMode == 'allteachers')
          for (final t in assignedTeachers)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _buildSingleTimetableSheet(
                entityName: t,
                isClassView: false,
              ),
            )
        else if (selectedViewMode == 'mastergrid')
          _buildMasterSchoolGridSheet(),
      ],
    );
  }

  ScheduledSlot? _findTeacherSlot(String teacherInit, int d, int k) {
    final sol = currentSolution;
    if (sol == null) return null;
    for (final entry in sol.schedule.entries) {
      if (k < entry.value[d].length) {
        final slot = entry.value[d][k];
        if (slot != null && slot.teacherInitial == teacherInit) {
          return slot;
        }
      }
    }
    return null;
  }

  Widget _buildSingleTimetableSheet({
    required String entityName,
    required bool isClassView,
  }) {
    final sol = currentSolution!;
    final ctInit = isClassView
        ? assignments
            .where((r) => r.className == entityName && r.isClassTeacher)
            .map((r) => r.teacherInitial)
            .firstOrNull
        : null;

    final subtitle = isClassView
        ? 'Time Table for Class: $entityName ${ctInit != null ? ' • વર્ગ શિક્ષક: $ctInit (${fullNameOf(ctInit)})' : ''}'
        : 'Time Table for Teacher: $entityName = ${fullNameOf(entityName)}';

    final legendInitials = isClassView
        ? assignments
            .where((r) => r.className == entityName)
            .map((r) => r.teacherInitial)
            .toSet()
            .toList()
        : [entityName];

    return Container(
      margin: EdgeInsets.only(
        top: pageDesign.marginTopPx,
        bottom: pageDesign.marginBottomPx,
        left: pageDesign.marginLeftPx,
        right: pageDesign.marginRightPx,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: pageDesign.borderColor,
          width: pageDesign.borderWidthPx,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (sheetCtx, sheetConstraints) {
          final sheetW = sheetConstraints.maxWidth.isFinite
              ? sheetConstraints.maxWidth
              : 1050.0;
          return Stack(
            children: [
              if (showWatermark)
                Positioned(
                  left: ((watermarkStyle.xPercent / 100.0) * sheetW) -
                      (watermarkStyle.widthPx / 2),
                  top: ((watermarkStyle.yPercent / 100.0) * 520.0) -
                      (watermarkStyle.heightPx / 2),
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      setState(() {
                        watermarkStyle.xPercent = (watermarkStyle.xPercent +
                                (details.delta.dx / sheetW) * 100.0)
                            .clamp(2.0, 98.0);
                        watermarkStyle.yPercent = (watermarkStyle.yPercent +
                                (details.delta.dy / 520.0) * 100.0)
                            .clamp(2.0, 98.0);
                      });
                      _scheduleDeviceAutoSave();
                    },
                    child: Opacity(
                      opacity: watermarkStyle.opacity,
                      child: _buildSchoolEmblemBadge(
                        size: watermarkStyle.widthPx,
                        shape: watermarkStyle.shape,
                      ),
                    ),
                  ),
                ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Banner
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEEF2FF), Colors.white],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  border: Border(
                    bottom: BorderSide(color: pageDesign.borderColor, width: 2),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            config.schoolName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF1E1B4B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'શૈક્ષણિક વર્ષ (Academic Year): ${config.academicYear}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E7FF),
                              borderRadius: BorderRadius.circular(99),
                              border:
                                  Border.all(color: const Color(0xFFA5B4FC)),
                            ),
                            child: Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF312E81),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),

              // Prayer Row
              if (pageDesign.prayerEnabled)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  color: const Color(0xFFEDE9FE),
                  child: Text(
                    '🙏 ${pageDesign.prayerName} ${pageDesign.prayerTiming.isNotEmpty ? '(${pageDesign.prayerTiming})' : ''}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF4C1D95),
                      fontSize: 13,
                    ),
                  ),
                ),

              // Timetable Grid Table
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 205 + (pageDesign.columnWidthPx * 6),
                  ),
                  child: Table(
                    border: TableBorder.all(color: const Color(0xFF94A3B8)),
                    columnWidths: {
                      0: const FixedColumnWidth(90),
                      1: const FixedColumnWidth(115),
                      2: FixedColumnWidth(pageDesign.columnWidthPx),
                      3: FixedColumnWidth(pageDesign.columnWidthPx),
                      4: FixedColumnWidth(pageDesign.columnWidthPx),
                      5: FixedColumnWidth(pageDesign.columnWidthPx),
                      6: FixedColumnWidth(pageDesign.columnWidthPx),
                      7: FixedColumnWidth(pageDesign.columnWidthPx),
                    },
                    children: [
                      // Day Headers
                      TableRow(
                        decoration:
                            const BoxDecoration(color: Color(0xFFE2E8F0)),
                        children: [
                          _buildTableHeaderCell('તાસ (Period)'),
                          _buildTableHeaderCell('સમય (Timing)'),
                          for (final d in kSchoolDays) _buildTableHeaderCell(d),
                        ],
                      ),

                      // Period Rows + Break Rows
                      for (int k = 0; k < config.monFriPeriods; k++) ...[
                        TableRow(
                          children: [
                            _buildTableHeaderCell(
                                'તાસ ${k + 1}${k == 0 ? ' ★' : ''}'),
                            _buildTableHeaderCell(k < periodTimings.length
                                ? periodTimings[k].formatted
                                : ''),
                            for (int d = 0; d < 6; d++)
                              _buildTimetableCell(
                                entityName: entityName,
                                isClassView: isClassView,
                                dayIndex: d,
                                periodIndex: k,
                                slot: k < config.periodsForDay(d)
                                    ? (isClassView
                                        ? (sol.schedule[entityName] == null
                                            ? null
                                            : sol.schedule[entityName]![d][k])
                                        : _findTeacherSlot(entityName, d, k))
                                    : null,
                                isOutOfHours: k >= config.periodsForDay(d),
                              ),
                          ],
                        ),
                        for (final brk
                            in breaks.where((b) => b.afterPeriod == k + 1))
                          TableRow(
                            decoration:
                                const BoxDecoration(color: Color(0xFFFEF3C7)),
                            children: [
                              _buildBreakCell(brk.name),
                              _buildBreakCell(brk.formattedTime),
                              for (int d = 0; d < 6; d++)
                                _buildBreakCell('🍴 ${brk.name}'),
                            ],
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer Legend & Signatures
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(top: BorderSide(color: Color(0xFF94A3B8))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Builder(
                      builder: (_) {
                        final allInitList = allAssignedTeachers;
                        final legendRow = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '👩‍🏫 શિક્ષક યાદી: ',
                              style: TextStyle(
                                fontSize: pageDesign.teacherLegendFontSizePx,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1E1B4B),
                              ),
                            ),
                            for (int idx = 0;
                                idx < legendInitials.length;
                                idx++) ...[
                              if (idx > 0)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '|',
                                    style: TextStyle(
                                      fontSize:
                                          pageDesign.teacherLegendFontSizePx,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                              Builder(
                                builder: (_) {
                                  final init = legendInitials[idx];
                                  final pal = TeacherColorPalette.fromInitial(
                                    init,
                                    orderedInitials: allInitList,
                                  );
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: pal.background,
                                      borderRadius: BorderRadius.circular(5),
                                      border: Border.all(color: pal.border),
                                    ),
                                    child: Text(
                                      '$init = ${fullNameOf(init)}',
                                      style: TextStyle(
                                        fontSize:
                                            pageDesign.teacherLegendFontSizePx,
                                        fontWeight: FontWeight.w800,
                                        color: pal.text,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        );
                        if (pageDesign.teacherLegendSingleLine) {
                          return SizedBox(
                            width: double.infinity,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: legendRow,
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: legendRow,
                        );
                      },
                    ),
                    if (pageDesign.showSignatures) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                            '✍️ વર્ગ શિક્ષકની સહી (Class Teacher Signature)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: _pickTimetableDate,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEEF2FF),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: const Color(0xFF818CF8)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.calendar_today_rounded,
                                          size: 14, color: Color(0xFF312E81)),
                                      const SizedBox(width: 6),
                                      Text(
                                        timetablePrintDate.trim().isNotEmpty
                                            ? '📅 તારીખ: ${timetablePrintDate.trim()}'
                                            : '📅 તારીખ: ____/____/૨૦૨__ (અહીંથી પસંદ કરો)',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF312E81),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (timetablePrintDate.trim().isNotEmpty) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'તારીખ ખાલી રાખો (Keep Blank)',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() => timetablePrintDate = '');
                                    _scheduleDeviceAutoSave(immediate: true);
                                  },
                                  icon: const Icon(Icons.clear_rounded,
                                      size: 16, color: Color(0xFFE11D48)),
                                ),
                              ],
                            ],
                          ),
                          const Text(
                            '🏅 આચાર્યશ્રીની સહી અને સિક્કો (Principal Stamp & Sign)',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (showLogo)
            Positioned(
              left: ((logoStyle.xPercent / 100.0) * sheetW) -
                  (logoStyle.widthPx / 2),
              top: ((logoStyle.yPercent / 100.0) * 520.0) -
                  (logoStyle.heightPx / 2),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() {
                      logoStyle.xPercent =
                          (logoStyle.xPercent + (details.delta.dx / sheetW) * 100.0)
                              .clamp(2.0, 98.0);
                      logoStyle.yPercent =
                          (logoStyle.yPercent + (details.delta.dy / 520.0) * 100.0)
                              .clamp(2.0, 98.0);
                    });
                    _scheduleDeviceAutoSave();
                  },
                  child: Opacity(
                    opacity: logoStyle.opacity,
                    child: _buildSchoolEmblemBadge(
                      size: logoStyle.widthPx,
                      shape: logoStyle.shape,
                      secondLogo: false,
                    ),
                  ),
                ),
              ),
            ),
          if (showSecondLogo)
            Positioned(
              left: ((logo2Style.xPercent / 100.0) * sheetW) -
                  (logo2Style.widthPx / 2),
              top: ((logo2Style.yPercent / 100.0) * 520.0) -
                  (logo2Style.heightPx / 2),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    setState(() {
                      logo2Style.xPercent =
                          (logo2Style.xPercent + (details.delta.dx / sheetW) * 100.0)
                              .clamp(2.0, 98.0);
                      logo2Style.yPercent =
                          (logo2Style.yPercent + (details.delta.dy / 520.0) * 100.0)
                              .clamp(2.0, 98.0);
                    });
                    _scheduleDeviceAutoSave();
                  },
                  child: Opacity(
                    opacity: logo2Style.opacity,
                    child: _buildSchoolEmblemBadge(
                      size: logo2Style.widthPx,
                      shape: logo2Style.shape,
                      secondLogo: true,
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
        },
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }

  Widget _buildBreakCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11.5,
          color: Color(0xFF92400E),
        ),
      ),
    );
  }

  Widget _buildTimetableCell({
    required String entityName,
    required bool isClassView,
    required int dayIndex,
    required int periodIndex,
    required ScheduledSlot? slot,
    required bool isOutOfHours,
  }) {
    final rowHeightPx = (pageDesign.periodHeightMm * 3.75).clamp(38.0, 140.0);
    if (isOutOfHours) {
      return SizedBox(
        height: rowHeightPx,
        child: const Center(
          child: Text('—',
              style: TextStyle(
                  color: Color(0xFF94A3B8), fontWeight: FontWeight.w800)),
        ),
      );
    }

    final isSelectedForSwap = isClassView &&
        selectedSlotForSwap?.className == entityName &&
        selectedSlotForSwap?.day == dayIndex &&
        selectedSlotForSwap?.period == periodIndex;

    if (slot == null) {
      return InkWell(
        onTap: isClassView
            ? () => _handleSlotTap(entityName, dayIndex, periodIndex)
            : null,
        child: Container(
          height: rowHeightPx,
          alignment: Alignment.center,
          color:
              isSelectedForSwap ? const Color(0xFFFEF08A) : Colors.transparent,
          child: const Text(
            'Free (ખાલી)',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    final palette = TeacherColorPalette.fromInitial(
      slot.teacherInitial,
      orderedInitials: allAssignedTeachers,
    );
    return InkWell(
      onTap: isClassView
          ? () => _handleSlotTap(entityName, dayIndex, periodIndex)
          : null,
      onLongPress: isClassView
          ? () {
              setState(() {
                currentSolution!.schedule[entityName]![dayIndex][periodIndex] =
                    slot.copyWith(isLocked: !slot.isLocked);
              });
              _showSnack(slot.isLocked
                  ? '🔓 તાસ અનલોક થયો (Unlocked)'
                  : '🔒 તાસ લોક થયો (Pinned - Re-Solve માં નહીં બદલાય)');
            }
          : null,
      child: Container(
        height: rowHeightPx,
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color:
              isSelectedForSwap ? const Color(0xFFFEF08A) : palette.background,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: isSelectedForSwap ? const Color(0xFFCA8A04) : palette.border,
            width: isSelectedForSwap ? 2.5 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isClassView ? slot.subject : 'વર્ગ ${slot.className}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isClassView ? slot.teacherInitial : slot.subject,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      color: palette.text,
                    ),
                  ),
                ),
                if (slot.isDoublePeriod)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFF59E0B)),
                    ),
                    child: const Text(
                      '2P',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                if (slot.roomOrLab != null && slot.roomOrLab!.isNotEmpty)
                  Text(
                    '🏛️${slot.roomOrLab}',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: palette.text,
                    ),
                  ),
                if (slot.isLocked)
                  const Icon(Icons.lock_rounded,
                      size: 12, color: Color(0xFFB45309)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleSlotTap(String className, int dayIndex, int periodIndex) {
    final prev = selectedSlotForSwap;
    if (prev == null || prev.className != className) {
      setState(() {
        selectedSlotForSwap =
            (className: className, day: dayIndex, period: periodIndex);
      });
      return;
    }

    if (prev.day == dayIndex && prev.period == periodIndex) {
      setState(() => selectedSlotForSwap = null);
      return;
    }

    final clashError = TimetableSolverEngine.checkSwapError(
      schedule: currentSolution!.schedule,
      teachers: teachers,
      className: className,
      d1: prev.day,
      k1: prev.period,
      d2: dayIndex,
      k2: periodIndex,
      config: config,
    );

    if (clashError != null) {
      _showSnack(clashError, isError: true);
      setState(() => selectedSlotForSwap = null);
      return;
    }

    setState(() {
      final grid = currentSolution!.schedule[className]!;
      final temp = grid[prev.day][prev.period];
      grid[prev.day][prev.period] = grid[dayIndex][periodIndex];
      grid[dayIndex][periodIndex] = temp;
      selectedSlotForSwap = null;
    });
    _showSnack('✅ તાસની અદલાબદલી (Swap) ઝીરો-ક્લેશ સાથે સફળ રહી!');
  }

  Widget _buildMasterSchoolGridSheet() {
    final sol = currentSolution!;
    final classes = allClasses;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🏛️ ${config.schoolName} — સમગ્ર શાળા સંયુક્ત માસ્ટર સમયપત્રક (Whole School Master View)',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFE2E8F0)),
                columns: [
                  const DataColumn(label: Text('વર્ગ')),
                  const DataColumn(label: Text('તાસ')),
                  for (final d in kSchoolDays)
                    DataColumn(label: Text(d.split(' ').first)),
                ],
                rows: [
                  for (final c in classes)
                    for (int k = 0; k < config.monFriPeriods; k++)
                      DataRow(
                        cells: [
                          DataCell(Text(k == 0 ? c : '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900))),
                          DataCell(Text('P${k + 1}')),
                          for (int d = 0; d < 6; d++)
                            DataCell(
                              Builder(
                                builder: (_) {
                                  if (k >= config.periodsForDay(d)) {
                                    return const Text('—');
                                  }
                                  final slot = sol.schedule[c]?[d][k];
                                  if (slot == null) {
                                    return const Text('Free',
                                        style: TextStyle(color: Colors.grey));
                                  }
                                  return Text(
                                    '${slot.subject} [${slot.teacherInitial}]${slot.isDoublePeriod ? ' (2P)' : ''}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 8: WORKLOAD REPORTS & ABSENT TEACHER PROXY / SUBSTITUTION FINDER
  // ---------------------------------------------------------------------------
  Widget _buildTab8ReportsAndProxy() {
    final sol = currentSolution;
    if (sol == null) {
      return const Center(
        child: Text('રિપોર્ટ જોવા માટે પહેલા સમયપત્રક જનરેટ કરો.'),
      );
    }

    // Calculate actual placed workload per teacher & subject
    final actualByTeacherSubject = <String, Map<String, int>>{};
    for (final classGrid in sol.schedule.values) {
      for (final dayList in classGrid) {
        for (final slot in dayList) {
          if (slot == null) continue;
          final map = (actualByTeacherSubject[slot.teacherInitial] ??= {});
          map[slot.subject] = (map[slot.subject] ?? 0) + 1;
        }
      }
    }

    final classes = allClasses;
    final activeClass =
        (proxySelectedClass != null && classes.contains(proxySelectedClass))
            ? proxySelectedClass!
            : classes.firstOrNull;
    final currentSlotAtProxy = activeClass == null ||
            proxyPeriodIndex >= config.periodsForDay(proxyDayIndex) ||
            sol.schedule[activeClass] == null
        ? null
        : sol.schedule[activeClass]![proxyDayIndex][proxyPeriodIndex];

    final proxyCandidates = (activeClass != null && currentSlotAtProxy != null)
        ? TimetableSolverEngine.findSubstituteTeachers(
            schedule: sol.schedule,
            teachers: teachers,
            assignments: assignments,
            targetClassName: activeClass,
            absentSubject: currentSlotAtProxy.subject,
            dayIndex: proxyDayIndex,
            periodIndex: proxyPeriodIndex,
          )
        : <ProxyCandidate>[];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // NEW FEATURE: Proxy / Substitution Finder Card
        Card(
          color: const Color(0xFFF0FDF4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🕵️‍♂️ ગેરહાજર શિક્ષક માટે અવેજી (Proxy / Substitution) શોધક',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                    color: Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'કોઈ વર્ગમાં ચોક્કસ દિવસે અને તાસમાં શિક્ષક રજા પર હોય, તો તે જ સમયે ખાલી (Free) હોય તેવા શ્રેષ્ઠ શિક્ષકોની યાદી તાત્કાલિક મેળવો:',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (activeClass != null)
                      SizedBox(
                        width: 180,
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: activeClass,
                          decoration: const InputDecoration(
                            labelText: 'વર્ગ (Class)',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: classes
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child: Text('વર્ગ $c'),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => proxySelectedClass = v),
                        ),
                      ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: proxyDayIndex,
                        decoration: const InputDecoration(
                          labelText: 'વાર (Day)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: List.generate(
                          6,
                          (d) => DropdownMenuItem(
                            value: d,
                            child: Text(kSchoolDays[d]),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) setState(() => proxyDayIndex = v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: proxyPeriodIndex.clamp(
                            0, max(0, config.periodsForDay(proxyDayIndex) - 1)),
                        decoration: const InputDecoration(
                          labelText: 'તાસ (Period)',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: List.generate(
                          config.periodsForDay(proxyDayIndex),
                          (k) => DropdownMenuItem(
                            value: k,
                            child: Text('તાસ ${k + 1}'),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) setState(() => proxyPeriodIndex = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (currentSlotAtProxy == null)
                  const Text(
                      'આ સમયે પસંદ કરેલ વર્ગમાં પહેલેથી જ ખાલી તાસ (Free Period) છે.')
                else ...[
                  Text(
                    '📌 મૂળ તાસ: ${currentSlotAtProxy.subject} — શિક્ષક: ${currentSlotAtProxy.teacherInitial} (${fullNameOf(currentSlotAtProxy.teacherInitial)})',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: proxyCandidates.isEmpty
                        ? [
                            const Text('કોઈ ખાલી શિક્ષક ઉપલબ્ધ નથી.',
                                style: TextStyle(color: Colors.red))
                          ]
                        : proxyCandidates.map((cand) {
                            return Chip(
                              avatar: CircleAvatar(
                                child: Text(cand.teacher.initial,
                                    style: const TextStyle(fontSize: 11)),
                              ),
                              label: Text(
                                '${cand.teacher.fullName} (આજના તાસ: ${cand.currentDayLoad}${cand.teachesSameSubject ? ' • આ જ વિષયના નિષ્ણાત ★' : cand.teachesSameClass ? ' • આ વર્ગના શિક્ષક' : ''})',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                              backgroundColor: Colors.white,
                            );
                          }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Teacher Subject-Wise Workload Report Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📊 શિક્ષક મુજબ અને વિષય મુજબ કાર્યભાર પત્રક (Teacher Subject-Wise Workload Sheet)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const Divider(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor:
                        WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('ટૂંકું નામ')),
                      DataColumn(label: Text('શિક્ષકનું પૂરું નામ')),
                      DataColumn(label: Text('વિષય મુજબ ફાળવેલ તાસ')),
                      DataColumn(label: Text('કુલ તાસ')),
                      DataColumn(label: Text('મહત્તમ મર્યાદા')),
                    ],
                    rows: List.generate(allAssignedTeachers.length, (idx) {
                      final init = allAssignedTeachers[idx];
                      final subjMap = actualByTeacherSubject[init] ?? {};
                      final total =
                          subjMap.values.fold<int>(0, (a, b) => a + b);
                      final breakdown = subjMap.entries
                          .map((e) => '${e.key}: ${e.value} તાસ')
                          .join('  •  ');
                      return DataRow(
                        cells: [
                          DataCell(Text('${idx + 1}')),
                          DataCell(_buildStatusPill(init)),
                          DataCell(Text(fullNameOf(init),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800))),
                          DataCell(Text(breakdown)),
                          DataCell(_buildStatusPill('$total',
                              isBad: total > config.maxTeacherWeeklyLoad)),
                          DataCell(Text('${config.maxTeacherWeeklyLoad}')),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Unplaced Periods Status Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📌 બાકી રહેલા તાસ અને સોલ્વર સ્ટેટસ (Unplaced Periods & Solver Status)',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                const SizedBox(height: 8),
                if (sol.unplacedPeriodsCount == 0)
                  _buildStatusPill(
                      '✅ ૧૦૦% બધા જ તાસ કોઈ પણ ક્લેશ વગર ગોઠવાઈ ગયા છે! (Solved in ${sol.solverIterationsUsed} iterations)')
                else
                  for (final u
                      in sol.unplaced.where((x) => x.remainingPeriods > 0))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '⚠️ ${u.assignment.teacherInitial} (${fullNameOf(u.assignment.teacherInitial)}) • ${u.assignment.subject} • વર્ગ ${u.assignment.className}: ${u.remainingPeriods} તાસ બાકી',
                        style: const TextStyle(
                            color: Color(0xFF9F1239),
                            fontWeight: FontWeight.w700),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _editTextCellDialog({
    required String title,
    required String initialValue,
    required ValueChanged<String> onSave,
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('રદ કરો'),
          ),
          FilledButton(
            onPressed: () {
              onSave(ctrl.text);
              Navigator.pop(ctx);
            },
            child: const Text('સાચવો'),
          ),
        ],
      ),
    );
  }

  String _escHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _buildSingleSheetHtml({
    required String entityName,
    required bool isClassView,
  }) {
    final sol = currentSolution!;
    final ctInit = isClassView
        ? assignments
            .where((r) => r.className == entityName && r.isClassTeacher)
            .map((r) => r.teacherInitial)
            .firstOrNull
        : null;
    final subtitle = isClassView
        ? 'વર્ગ સમયપત્રક (Class): $entityName ${ctInit != null ? ' • વર્ગ શિક્ષક: $ctInit (${fullNameOf(ctInit)})' : ''}'
        : 'શિક્ષક સમયપત્રક (Teacher): $entityName = ${fullNameOf(entityName)}';

    final legendInitials = isClassView
        ? assignments
            .where((r) => r.className == entityName)
            .map((r) => r.teacherInitial)
            .toSet()
            .toList()
        : [entityName];

    final rowsBuf = StringBuffer();
    for (int k = 0; k < config.monFriPeriods; k++) {
      final timing = k < periodTimings.length ? periodTimings[k].formatted : '';
      rowsBuf.writeln('<tr>');
      rowsBuf.writeln('<td class="hdr">તાસ ${k + 1}${k == 0 ? ' ★' : ''}</td>');
      rowsBuf.writeln('<td class="hdr">${_escHtml(timing)}</td>');
      for (int d = 0; d < 6; d++) {
        if (k >= config.periodsForDay(d)) {
          rowsBuf.writeln('<td class="empty">—</td>');
        } else {
          final slot = isClassView
              ? (sol.schedule[entityName] == null
                  ? null
                  : sol.schedule[entityName]![d][k])
              : _findTeacherSlot(entityName, d, k);
          if (slot == null) {
            rowsBuf.writeln('<td class="empty">Free</td>');
          } else {
            final topText =
                isClassView ? slot.subject : 'વર્ગ ${slot.className}';
            final subText = isClassView ? slot.teacherInitial : slot.subject;
            final dblBadge =
                slot.isDoublePeriod ? ' <span class="badge">2P</span>' : '';
            rowsBuf.writeln(
              '<td><div class="slot-main">${_escHtml(topText)}</div>'
              '<div class="slot-sub">${_escHtml(subText)}$dblBadge</div></td>',
            );
          }
        }
      }
      rowsBuf.writeln('</tr>');
      for (final brk in breaks.where((b) => b.afterPeriod == k + 1)) {
        rowsBuf.writeln(
          '<tr class="brk"><td>${_escHtml(brk.name)}</td>'
          '<td>${_escHtml(brk.formattedTime)}</td>'
          '<td colspan="6">🍴 ${_escHtml(brk.name)} (${_escHtml(brk.formattedTime)})</td></tr>',
        );
      }
    }

    final legendStr = legendInitials
        .map((i) => '$i = ${fullNameOf(i)}')
        .join(' &nbsp;|&nbsp; ');

    final logoUri = _effectiveLogoDataUri;
    final logo2Uri = _effectiveLogo2DataUri;
    final wmHtml = (showWatermark && logoUri.isNotEmpty)
        ? '<img src="$logoUri" class="brand-wm" style="position:absolute;left:${watermarkStyle.xPercent.toStringAsFixed(1)}%;top:${watermarkStyle.yPercent.toStringAsFixed(1)}%;transform:translate(-50%,-50%);height:${watermarkStyle.widthPx.toInt()}px;width:auto;object-fit:contain;opacity:${watermarkStyle.opacity.toStringAsFixed(2)};pointer-events:none;z-index:1;" />'
        : '';
    final logoHtml = (showLogo && logoUri.isNotEmpty)
        ? '<img src="$logoUri" class="brand-logo" style="position:absolute;left:${logoStyle.xPercent.toStringAsFixed(1)}%;top:${logoStyle.yPercent.toStringAsFixed(1)}%;transform:translate(-50%,-50%);height:${logoStyle.widthPx.toInt()}px;width:auto;object-fit:contain;opacity:${logoStyle.opacity.toStringAsFixed(2)};pointer-events:none;z-index:5;" />'
        : '';
    final logo2Html = (showSecondLogo && logo2Uri.isNotEmpty)
        ? '<img src="$logo2Uri" class="brand-logo" style="position:absolute;left:${logo2Style.xPercent.toStringAsFixed(1)}%;top:${logo2Style.yPercent.toStringAsFixed(1)}%;transform:translate(-50%,-50%);height:${logo2Style.widthPx.toInt()}px;width:auto;object-fit:contain;opacity:${logo2Style.opacity.toStringAsFixed(2)};pointer-events:none;z-index:5;" />'
        : '';
    return '''
    <div class="page-sheet" style="position:relative;">
      $wmHtml
      $logoHtml
      $logo2Html
      <div class="sheet-hdr" style="position:relative;z-index:2;">
        <div class="school-title">${_escHtml(config.schoolName)}</div>
        <div class="school-sub">શૈક્ષણિક વર્ષ: ${_escHtml(config.academicYear)}</div>
        <div class="entity-pill">${_escHtml(subtitle)}</div>
      </div>
      ${pageDesign.prayerEnabled ? '<div class="prayer-bar" style="position:relative;z-index:2;">🙏 ${_escHtml(pageDesign.prayerName)} ${pageDesign.prayerTiming.isNotEmpty ? '(${_escHtml(pageDesign.prayerTiming)})' : ''}</div>' : ''}
      <div class="table-wrap" style="position:relative;z-index:2;">
        <table>
          <thead>
            <tr>
              <th>તાસ</th>
              <th>સમય</th>
              ${kSchoolDays.map((d) => '<th>${_escHtml(d)}</th>').join()}
            </tr>
          </thead>
          <tbody>
            ${rowsBuf.toString()}
          </tbody>
        </table>
      </div>
      <div class="legend" style="position:relative;z-index:2;">👩‍🏫 <b>શિક્ષક યાદી:</b> ${_escHtml(legendStr)}</div>
      ${pageDesign.showSignatures ? '<div class="sigs" style="position:relative;z-index:2;"><span>✍️ વર્ગ શિક્ષકની સહી</span><span>📅 તારીખ: ${timetablePrintDate.trim().isNotEmpty ? _escHtml(timetablePrintDate.trim()) : "____/____/૨૦૨__"}</span><span>🏅 આચાર્યશ્રીની સહી અને સિક્કો</span></div>' : ''}
    </div>
    ''';
  }

  Future<void> _printOrExportTimetableHtml() async {
    if (currentSolution == null) {
      _runGenerate(switchTab: false, showNotification: false);
    }
    if (currentSolution == null) {
      _showSnack('પહેલા સમયપત્રક જનરેટ કરો.', isError: true);
      return;
    }

    // Show Print / PDF Page Size & Column/Row Settings Dialog before printing
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text(
                '🖨️ પ્રિન્ટ / PDF પેજ સેટિંગ્સ (Print & PDF Setup)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
              content: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'PDF માં આખા પેજમાં સમાવો (Full Page PDF by Default)',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text(
                        'ચાલુ રાખવાથી સમયપત્રક A4 પેજમાં સંપૂર્ણ પહોળાઈ અને ઊંચાઈમાં આપોઆપ ફિટ થશે.',
                      ),
                      value: pageDesign.fullPagePdf,
                      onChanged: (v) {
                        setDialogState(() => pageDesign.fullPagePdf = v);
                        setState(() {});
                        _scheduleDeviceAutoSave();
                      },
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text(
                          'કોલમ પહોળાઈ (Column Width): ${pageDesign.columnWidthPx.toInt()} px',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: () {
                                setDialogState(() {
                                  pageDesign.columnWidthPx =
                                      (pageDesign.columnWidthPx - 8).clamp(85.0, 260.0);
                                });
                                setState(() {});
                                _scheduleDeviceAutoSave();
                              },
                              icon: const Icon(Icons.remove),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              onPressed: () {
                                setDialogState(() {
                                  pageDesign.columnWidthPx =
                                      (pageDesign.columnWidthPx + 8).clamp(85.0, 260.0);
                                });
                                setState(() {});
                                _scheduleDeviceAutoSave();
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(child: Text(
                          'હરોળ ઊંચાઈ (Row Height): ${pageDesign.periodHeightMm.toInt()} mm',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        )),
                        Row(
                          children: [
                            IconButton.filledTonal(
                              onPressed: () {
                                setDialogState(() {
                                  pageDesign.periodHeightMm =
                                      (pageDesign.periodHeightMm - 1).clamp(10.0, 32.0);
                                });
                                setState(() {});
                                _scheduleDeviceAutoSave();
                              },
                              icon: const Icon(Icons.remove),
                            ),
                            const SizedBox(width: 6),
                            IconButton.filledTonal(
                              onPressed: () {
                                setDialogState(() {
                                  pageDesign.periodHeightMm =
                                      (pageDesign.periodHeightMm + 1).clamp(10.0, 32.0);
                                });
                                setState(() {});
                                _scheduleDeviceAutoSave();
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('રદ કરો'),
                ),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('પ્રિન્ટ / PDF કાઢો'),
                ),
              ],
            );
          },
        );
      },
    );
    if (proceed != true || !mounted) return;

    final classes = allClasses;
    final assignedTeachers = allAssignedTeachers;
    final bodyBuf = StringBuffer();

    if (selectedViewMode == 'class' && selectedEntity != null) {
      bodyBuf.writeln(_buildSingleSheetHtml(
          entityName: selectedEntity!, isClassView: true));
    } else if (selectedViewMode == 'teacher' && selectedEntity != null) {
      bodyBuf.writeln(_buildSingleSheetHtml(
          entityName: selectedEntity!, isClassView: false));
    } else if (selectedViewMode == 'allteachers') {
      for (final t in assignedTeachers) {
        bodyBuf
            .writeln(_buildSingleSheetHtml(entityName: t, isClassView: false));
      }
    } else {
      for (final c in classes) {
        bodyBuf
            .writeln(_buildSingleSheetHtml(entityName: c, isClassView: true));
      }
    }

    final isFullPage = pageDesign.fullPagePdf;
    final colW = pageDesign.columnWidthPx.toInt();
    final rowH = pageDesign.periodHeightMm.toStringAsFixed(1);

    final htmlDoc = '''<!DOCTYPE html>
<html lang="gu">
<head>
<meta charset="UTF-8">
<title>${_escHtml(config.schoolName)} — સમયપત્રક</title>
<link href="https://fonts.googleapis.com/css2?family=Noto+Sans+Gujarati:wght@500;700;800;900&display=swap" rel="stylesheet">
<style>
  @page { size: A4 landscape; margin: 6mm; }
  :root {
    --col-w: ${isFullPage ? 'auto' : '${colW}px'};
    --row-h: ${rowH}mm;
  }
  * { box-sizing: border-box; font-family: 'Noto Sans Gujarati', sans-serif; }
  body { margin: 0; padding: 10px; background: #fff; color: #0f172a; }
  .no-print { margin-bottom: 10px; padding: 8px 12px; background: #f1f5f9; border: 1px solid #cbd5e1; border-radius: 8px; display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
  @media print { .no-print { display: none !important; } body { padding: 0; } }
  .page-sheet {
    border: 2px solid #1e1b4b;
    border-radius: 10px;
    overflow: hidden;
    page-break-after: always;
    margin-bottom: 12px;
    display: flex;
    flex-direction: column;
  }
  body.full-page .page-sheet {
    width: 100%;
    min-height: 194mm;
  }
  .page-sheet:last-child { page-break-after: auto; }
  .sheet-hdr { text-align: center; padding: 8px 14px; background: #eef2ff; border-bottom: 2px solid #1e1b4b; }
  .school-title { font-size: 20px; font-weight: 900; color: #1e1b4b; }
  .school-sub { font-size: 13px; font-weight: 700; color: #334155; margin-top: 2px; }
  .entity-pill { display: inline-block; margin-top: 4px; padding: 3px 14px; background: #e0e7ff; border: 1px solid #818cf8; border-radius: 99px; font-weight: 800; font-size: 13px; color: #312e81; }
  .prayer-bar { text-align: center; background: #ede9fe; color: #4c1d95; font-weight: 800; font-size: 12.5px; padding: 5px; border-bottom: 1px solid #cbd5e1; }
  .table-wrap { flex: 1; display: flex; flex-direction: column; }
  table { width: 100%; flex: 1; border-collapse: collapse; table-layout: fixed; }
  th, td { border: 1px solid #64748b; padding: 4px; text-align: center; font-size: 12px; width: var(--col-w); }
  tbody tr:not(.brk) td { height: var(--row-h); }
  th:first-child, td:first-child { width: 82px; }
  th:nth-child(2), td:nth-child(2) { width: 104px; }
  th { background: #e2e8f0; font-weight: 900; color: #0f172a; }
  td.hdr { background: #f8fafc; font-weight: 800; }
  td.empty { color: #94a3b8; font-weight: 700; }
  tr.brk td { background: #fef3c7; color: #92400e; font-weight: 800; font-size: 11.5px; height: 7mm; }
  .slot-main { font-weight: 800; font-size: 12.5px; color: #1e1b4b; }
  .slot-sub { font-weight: 700; font-size: 11px; color: #334155; margin-top: 2px; }
  .badge { background: #fef3c7; border: 1px solid #f59e0b; padding: 0 4px; border-radius: 4px; font-size: 10px; color: #92400e; }
  .legend { padding: 7px 12px; font-size: 11.5px; background: #f8fafc; border-top: 1px solid #94a3b8; }
  .sigs { display: flex; justify-content: space-between; padding: 14px 18px 8px; font-size: 12px; font-weight: 800; background: #f8fafc; }
</style>
</head>
<body class="${isFullPage ? 'full-page' : ''}">
  <div class="no-print">
    <button onclick="window.print()" style="padding:8px 16px;background:#1d4ed8;color:#fff;border:none;border-radius:6px;font-weight:800;cursor:pointer;">🖨️ પ્રિન્ટ / Save as PDF</button>
    <label style="font-weight:800;font-size:13px;display:flex;align-items:center;gap:5px;">
      <input type="checkbox" id="fpChk" ${isFullPage ? 'checked' : ''} onchange="toggleFullPage(this.checked)" />
      આખા પેજમાં સમાવો (Full Page Fit)
    </label>
    <span style="font-weight:800;font-size:13px;">કોલમ પહોળાઈ: <button onclick="adjCol(-8)">−</button> <span id="cwVal">$colW</span>px <button onclick="adjCol(8)">+</button></span>
    <span style="font-weight:800;font-size:13px;">હરોળ ઊંચાઈ: <button onclick="adjRow(-1)">−</button> <span id="rhVal">$rowH</span>mm <button onclick="adjRow(1)">+</button></span>
  </div>
  ${bodyBuf.toString()}
  <script>
    var cw = $colW;
    var rh = $rowH;
    function toggleFullPage(on) {
      document.body.classList.toggle('full-page', on);
      document.documentElement.style.setProperty('--col-w', on ? 'auto' : (cw + 'px'));
    }
    function adjCol(d) {
      cw = Math.max(80, Math.min(280, cw + d));
      document.getElementById('cwVal').textContent = cw;
      document.getElementById('fpChk').checked = false;
      document.body.classList.remove('full-page');
      document.documentElement.style.setProperty('--col-w', cw + 'px');
    }
    function adjRow(d) {
      rh = Math.max(10, Math.min(35, rh + d));
      document.getElementById('rhVal').textContent = rh.toFixed(1);
      document.documentElement.style.setProperty('--row-h', rh + 'mm');
    }
    window.onload = function() { setTimeout(function() { window.print(); }, 350); };
  </script>
</body>
</html>''';

    try {
      final pdfBytes = await _generateDirectTimetablePdfBytes();
      await PsmFileExportHelper.saveOrShare(
        bytes: pdfBytes,
        filename: 'school_timetable.pdf',
        title: 'School Timetable PDF',
        mimeType: 'application/pdf',
      );
      _showSnack('🖨️ સમયપત્રક ડાયરેક્ટ PDF તરીકે ડાઉનલોડ થઈ ગયું!');
    } catch (e) {
      _showSnack('PDF બનાવવામાં ભૂલ: $e', isError: true);
    }
  }

  static bool _timetableGujaratiFontLoaded = false;

  static Future<void> _ensureTimetableGujaratiFontLoaded() async {
    if (_timetableGujaratiFontLoaded) return;
    try {
      final loader = FontLoader('NotoSansGujaratiLocal');
      loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Regular.ttf'));
      loader.addFont(rootBundle.load('assets/fonts/NotoSansGujarati-Bold.ttf'));
      await loader.load();
    } catch (_) {}
    try {
      final fallback = FontLoader('LohitGujaratiLocal');
      fallback.addFont(rootBundle.load('assets/fonts/Lohit-Gujarati.ttf'));
      await fallback.load();
    } catch (_) {}
    _timetableGujaratiFontLoaded = true;
  }

  final Map<String, pw.MemoryImage> _timetablePdfTextCache =
      <String, pw.MemoryImage>{};

  Future<pw.MemoryImage?> _renderTimetableTextImage(
    String text, {
    double fontSize = 11,
    bool bold = true,
    Color color = const Color(0xFF0F172A),
    double maxWidth = 220,
    TextAlign textAlign = TextAlign.center,
  }) async {
    await _ensureTimetableGujaratiFontLoaded();
    final clean = text
        .replaceAll('★', '*')
        .replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (clean.isEmpty) return null;
    final cacheKey =
        'v2|$clean|${fontSize.toStringAsFixed(2)}|$bold|${color.toARGB32()}|${maxWidth.toStringAsFixed(1)}|${textAlign.index}';
    final cached = _timetablePdfTextCache[cacheKey];
    if (cached != null) return cached;
    try {
      const scale = 2.4;
      final span = TextSpan(
        text: clean,
        style: TextStyle(
          fontFamily: 'NotoSansGujaratiLocal',
          fontFamilyFallback: const <String>['LohitGujaratiLocal'],
          fontSize: fontSize * scale,
          fontWeight: bold ? FontWeight.bold : FontWeight.w400,
          color: color,
          height: 1.22,
        ),
      );
      final painter = TextPainter(
        text: span,
        textAlign: textAlign,
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: maxWidth * scale);

      final w = max(4, painter.width.ceil() + 6);
      final h = max(4, painter.height.ceil() + 4);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      );
      painter.paint(canvas, const Offset(3, 2));
      final picture = recorder.endRecording();
      final img = await picture.toImage(w, h);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      picture.dispose();
      if (byteData == null) return null;
      final memImg = pw.MemoryImage(byteData.buffer.asUint8List());
      if (_timetablePdfTextCache.length > 2500) {
        _timetablePdfTextCache.clear();
      }
      _timetablePdfTextCache[cacheKey] = memImg;
      return memImg;
    } catch (_) {
      return null;
    }
  }

  Future<pw.MemoryImage?> _renderBrandEmblemPdfImage(
    Uint8List? rawBytes,
    OverlayLayerStyle style,
  ) async {
    if (rawBytes == null || rawBytes.isEmpty) return null;
    try {
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final srcImg = frame.image;
      final outW = max(24, (style.widthPx * 2.2).round());
      final outH = style.shape == 'rect'
          ? max(24, (outW * 0.72).round())
          : outW;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
      );
      final dstRect = Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble());
      if (style.shape == 'round') {
        canvas.clipPath(Path()..addOval(dstRect));
      } else if (style.shape == 'square' || style.shape == 'rect') {
        canvas.clipRRect(
          RRect.fromRectAndRadius(dstRect, const Radius.circular(14)),
        );
      }
      final paint = Paint()
        ..isAntiAlias = true
        ..color = Color.fromRGBO(255, 255, 255, style.opacity.clamp(0.04, 1.0));
      final srcRect = Rect.fromLTWH(
        0,
        0,
        srcImg.width.toDouble(),
        srcImg.height.toDouble(),
      );
      canvas.drawImageRect(srcImg, srcRect, dstRect, paint);
      final picture = recorder.endRecording();
      final outImg = await picture.toImage(outW, outH);
      final byteData = await outImg.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      return pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (_) {
      return pw.MemoryImage(rawBytes);
    }
  }

  Future<Uint8List> _generateDirectTimetablePdfBytes() async {
    final doc = pw.Document();
    final sol = currentSolution!;
    final classes = allClasses;
    final assignedTeachers = allAssignedTeachers;

    final targets = <({String entityName, bool isClassView})>[];
    if (selectedViewMode == 'class' && selectedEntity != null) {
      targets.add((entityName: selectedEntity!, isClassView: true));
    } else if (selectedViewMode == 'teacher' && selectedEntity != null) {
      targets.add((entityName: selectedEntity!, isClassView: false));
    } else if (selectedViewMode == 'allteachers') {
      for (final t in assignedTeachers) {
        targets.add((entityName: t, isClassView: false));
      }
    } else {
      for (final c in classes) {
        targets.add((entityName: c, isClassView: true));
      }
    }

    final logo1Img = showLogo
        ? await _renderBrandEmblemPdfImage(_effectiveLogoBytes, logoStyle)
        : null;
    final logo2Img = showSecondLogo
        ? await _renderBrandEmblemPdfImage(_effectiveLogo2Bytes, logo2Style)
        : null;
    final wmImg = showWatermark
        ? await _renderBrandEmblemPdfImage(_effectiveLogoBytes, watermarkStyle)
        : null;

    final borderPdfColor = PdfColor.fromInt(pageDesign.borderColor.toARGB32());
    final borderWidth = pageDesign.borderWidthPx.clamp(1.0, 6.0);
    final rowBoxHeight = (pageDesign.periodHeightMm * 2.45).clamp(32.0, 64.0);

    for (final target in targets) {
      final entityName = target.entityName;
      final isClassView = target.isClassView;
      final ctInit = isClassView
          ? assignments
              .where((r) => r.className == entityName && r.isClassTeacher)
              .map((r) => r.teacherInitial)
              .firstOrNull
          : null;
      final subtitle = isClassView
          ? 'Time Table for Class: $entityName ${ctInit != null ? ' • વર્ગ શિક્ષક: $ctInit (${fullNameOf(ctInit)})' : ''}'
          : 'Time Table for Teacher: $entityName = ${fullNameOf(entityName)}';

      final legendInitials = isClassView
          ? assignments
              .where((r) => r.className == entityName)
              .map((r) => r.teacherInitial)
              .toSet()
              .toList()
          : [entityName];

      final schoolTitleImg = await _renderTimetableTextImage(
        config.schoolName,
        fontSize: 18,
        bold: true,
        color: const Color(0xFF1E1B4B),
        maxWidth: 560,
      );
      final schoolSubImg = await _renderTimetableTextImage(
        'શૈક્ષણિક વર્ષ (Academic Year): ${config.academicYear}',
        fontSize: 11.5,
        bold: true,
        color: const Color(0xFF334155),
        maxWidth: 460,
      );
      final entityPillImg = await _renderTimetableTextImage(
        subtitle,
        fontSize: 12,
        bold: true,
        color: const Color(0xFF312E81),
        maxWidth: 540,
      );
      final prayerImg = pageDesign.prayerEnabled
          ? await _renderTimetableTextImage(
              '🙏 ${pageDesign.prayerName} ${pageDesign.prayerTiming.isNotEmpty ? '(${pageDesign.prayerTiming})' : ''}',
              fontSize: 11,
              bold: true,
              color: const Color(0xFF4C1D95),
              maxWidth: 680,
            )
          : null;

      final headerCells = <pw.Widget>[];
      for (final hText in ['તાસ (Period)', 'સમય (Timing)', ...kSchoolDays]) {
        final hImg = await _renderTimetableTextImage(
          hText,
          fontSize: 10.5,
          bold: true,
          color: const Color(0xFF0F172A),
          maxWidth: 115,
        );
        headerCells.add(
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 3),
            alignment: pw.Alignment.center,
            color: PdfColor.fromInt(0xFFE2E8F0),
            child: hImg != null
                ? pw.Image(hImg, height: 14, fit: pw.BoxFit.contain)
                : pw.Text(hText, style: const pw.TextStyle(fontSize: 9)),
          ),
        );
      }

      final tableRows = <pw.TableRow>[
        pw.TableRow(children: headerCells),
      ];

      final freeSlotImg = await _renderTimetableTextImage(
        'Free (ખાલી)',
        fontSize: 9.5,
        bold: true,
        color: const Color(0xFF94A3B8),
        maxWidth: 90,
      );

      for (int k = 0; k < config.monFriPeriods; k++) {
        final timing = k < periodTimings.length ? periodTimings[k].formatted : '';
        final pLabelImg = await _renderTimetableTextImage(
          'તાસ ${k + 1}${k == 0 ? ' ★' : ''}',
          fontSize: 10,
          bold: true,
          color: const Color(0xFF0F172A),
          maxWidth: 80,
        );
        final timeImg = await _renderTimetableTextImage(
          timing.isEmpty ? '-' : timing,
          fontSize: 9.5,
          bold: true,
          color: const Color(0xFF0F172A),
          maxWidth: 95,
        );

        final rowCells = <pw.Widget>[
          pw.Container(
            height: rowBoxHeight,
            padding: const pw.EdgeInsets.all(3),
            alignment: pw.Alignment.center,
            color: PdfColors.white,
            child: pLabelImg != null
                ? pw.Image(pLabelImg, height: 13.5, fit: pw.BoxFit.contain)
                : pw.Text('P${k + 1}', style: const pw.TextStyle(fontSize: 9)),
          ),
          pw.Container(
            height: rowBoxHeight,
            padding: const pw.EdgeInsets.all(3),
            alignment: pw.Alignment.center,
            color: PdfColors.white,
            child: timeImg != null
                ? pw.Image(timeImg, height: 12.5, fit: pw.BoxFit.contain)
                : pw.Text(timing, style: const pw.TextStyle(fontSize: 8.5)),
          ),
        ];

        for (int d = 0; d < 6; d++) {
          if (k >= config.periodsForDay(d)) {
            rowCells.add(
              pw.Container(
                height: rowBoxHeight,
                padding: const pw.EdgeInsets.all(3),
                alignment: pw.Alignment.center,
                color: PdfColors.white,
                child: pw.Text(
                  '-',
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF94A3B8),
                  ),
                ),
              ),
            );
          } else {
            final slot = isClassView
                ? (sol.schedule[entityName] == null
                    ? null
                    : sol.schedule[entityName]![d][k])
                : _findTeacherSlot(entityName, d, k);
            if (slot == null) {
              rowCells.add(
                pw.Container(
                  height: rowBoxHeight,
                  padding: const pw.EdgeInsets.all(3),
                  alignment: pw.Alignment.center,
                  color: PdfColors.white,
                  child: freeSlotImg != null
                      ? pw.Image(freeSlotImg, height: 12, fit: pw.BoxFit.contain)
                      : pw.Text(
                          'Free (ખાલી)',
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColor.fromInt(0xFF94A3B8),
                          ),
                        ),
                ),
              );
            } else {
              var effectiveTeacherInit = slot.teacherInitial.trim();
              if (effectiveTeacherInit.isEmpty && isClassView) {
                effectiveTeacherInit = assignments
                        .where((r) =>
                            r.className == entityName &&
                            r.subject.trim() == slot.subject.trim())
                        .map((r) => r.teacherInitial.trim())
                        .firstOrNull ??
                    '';
              }
              final pal = TeacherColorPalette.fromInitial(
                effectiveTeacherInit.isEmpty ? slot.teacherInitial : effectiveTeacherInit,
                orderedInitials: assignedTeachers,
              );
              final topText = isClassView ? slot.subject : 'વર્ગ ${slot.className}';
              final subText = isClassView ? effectiveTeacherInit : slot.subject;
              final topImg = await _renderTimetableTextImage(
                topText,
                fontSize: 10.0,
                bold: true,
                color: pal.text,
                maxWidth: 104,
              );
              final subImg = subText.isNotEmpty
                  ? await _renderTimetableTextImage(
                      subText,
                      fontSize: 9.2,
                      bold: true,
                      color: pal.text,
                      maxWidth: 84,
                    )
                  : null;
              final roomImg = (slot.roomOrLab != null && slot.roomOrLab!.isNotEmpty)
                  ? await _renderTimetableTextImage(
                      slot.roomOrLab!,
                      fontSize: 7.8,
                      bold: true,
                      color: pal.text,
                      maxWidth: 60,
                    )
                  : null;
              rowCells.add(
                pw.Container(
                  height: rowBoxHeight,
                  padding: const pw.EdgeInsets.all(1.5),
                  color: PdfColors.white,
                  child: pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 2, horizontal: 2.5),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(pal.background.toARGB32()),
                      borderRadius: pw.BorderRadius.circular(5.5),
                      border: pw.Border.all(
                        color: PdfColor.fromInt(pal.border.toARGB32()),
                        width: 1,
                      ),
                    ),
                    alignment: pw.Alignment.center,
                    child: pw.FittedBox(
                      fit: pw.BoxFit.scaleDown,
                      alignment: pw.Alignment.center,
                      child: pw.Column(
                        mainAxisSize: pw.MainAxisSize.min,
                        mainAxisAlignment: pw.MainAxisAlignment.center,
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          if (topImg != null)
                            pw.Image(topImg, height: 11.5, fit: pw.BoxFit.contain),
                          if (subText.isNotEmpty) ...[
                            pw.SizedBox(height: 1.8),
                            pw.Row(
                              mainAxisSize: pw.MainAxisSize.min,
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 1.2),
                                  decoration: pw.BoxDecoration(
                                    color: PdfColors.white,
                                    borderRadius: pw.BorderRadius.circular(3.5),
                                    border: pw.Border.all(
                                      color: PdfColor.fromInt(pal.border.toARGB32()),
                                      width: 0.6,
                                    ),
                                  ),
                                  child: subImg != null
                                      ? pw.Image(subImg,
                                          height: 9.8, fit: pw.BoxFit.contain)
                                      : pw.Text(
                                          subText,
                                          style: pw.TextStyle(
                                            fontSize: 8.0,
                                            fontWeight: pw.FontWeight.bold,
                                            color: PdfColor.fromInt(pal.text.toARGB32()),
                                          ),
                                        ),
                                ),
                                if (slot.isDoublePeriod) ...[
                                  pw.SizedBox(width: 2.5),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 3, vertical: 1),
                                    decoration: pw.BoxDecoration(
                                      color: PdfColor.fromInt(0xFFFEF3C7),
                                      borderRadius: pw.BorderRadius.circular(3),
                                      border: pw.Border.all(
                                        color: PdfColor.fromInt(0xFFF59E0B),
                                        width: 0.7,
                                      ),
                                    ),
                                    child: pw.Text(
                                      '2P',
                                      style: pw.TextStyle(
                                        fontSize: 6.8,
                                        fontWeight: pw.FontWeight.bold,
                                        color: PdfColor.fromInt(0xFF92400E),
                                      ),
                                    ),
                                  ),
                                ],
                                if (roomImg != null) ...[
                                  pw.SizedBox(width: 2),
                                  pw.Image(roomImg,
                                      height: 8.8, fit: pw.BoxFit.contain),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
          }
        }
        tableRows.add(pw.TableRow(children: rowCells));

        for (final brk in breaks.where((b) => b.afterPeriod == k + 1)) {
          final brkNameImg = await _renderTimetableTextImage(
            brk.name,
            fontSize: 9.2,
            bold: true,
            color: const Color(0xFF92400E),
            maxWidth: 80,
          );
          final brkTimeImg = await _renderTimetableTextImage(
            brk.formattedTime,
            fontSize: 9.2,
            bold: true,
            color: const Color(0xFF92400E),
            maxWidth: 95,
          );
          final brkCellImg = await _renderTimetableTextImage(
            '🍴 ${brk.name}',
            fontSize: 9.2,
            bold: true,
            color: const Color(0xFF92400E),
            maxWidth: 105,
          );
          tableRows.add(
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFFEF3C7)),
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  alignment: pw.Alignment.center,
                  child: brkNameImg != null
                      ? pw.Image(brkNameImg, height: 11.5, fit: pw.BoxFit.contain)
                      : pw.Text(brk.name, style: const pw.TextStyle(fontSize: 8)),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  alignment: pw.Alignment.center,
                  child: brkTimeImg != null
                      ? pw.Image(brkTimeImg, height: 11.5, fit: pw.BoxFit.contain)
                      : pw.Text(brk.formattedTime,
                          style: const pw.TextStyle(fontSize: 8)),
                ),
                for (int d = 0; d < 6; d++)
                  pw.Container(
                    padding:
                        const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                    alignment: pw.Alignment.center,
                    child: brkCellImg != null
                        ? pw.Image(brkCellImg, height: 11.5, fit: pw.BoxFit.contain)
                        : pw.Text(brk.name, style: const pw.TextStyle(fontSize: 8)),
                  ),
              ],
            ),
          );
        }
      }

      final legendBadges = <pw.Widget>[];
      final legendPrefixImg = await _renderTimetableTextImage(
        '👩‍🏫 શિક્ષક યાદી: ',
        fontSize: pageDesign.teacherLegendFontSizePx,
        bold: true,
        color: const Color(0xFF1E1B4B),
        maxWidth: 135,
      );
      if (legendPrefixImg != null) {
        legendBadges.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(right: 4),
            child: pw.Image(legendPrefixImg,
                height: pageDesign.teacherLegendFontSizePx + 2,
                fit: pw.BoxFit.contain),
          ),
        );
      }
      for (int idx = 0; idx < legendInitials.length; idx++) {
        if (idx > 0) {
          legendBadges.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4),
              child: pw.Text(
                '|',
                style: pw.TextStyle(
                  fontSize: pageDesign.teacherLegendFontSizePx,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF94A3B8),
                ),
              ),
            ),
          );
        }
        final init = legendInitials[idx];
        final pal = TeacherColorPalette.fromInitial(
          init,
          orderedInitials: assignedTeachers,
        );
        final itemImg = await _renderTimetableTextImage(
          '$init = ${fullNameOf(init)}',
          fontSize: pageDesign.teacherLegendFontSizePx,
          bold: true,
          color: pal.text,
          maxWidth: 260,
        );
        if (itemImg != null) {
          legendBadges.add(
            pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromInt(pal.background.toARGB32()),
                borderRadius: pw.BorderRadius.circular(4),
                border: pw.Border.all(
                  color: PdfColor.fromInt(pal.border.toARGB32()),
                  width: 0.8,
                ),
              ),
              child: pw.Image(
                itemImg,
                height: (pageDesign.teacherLegendFontSizePx + 1.5).clamp(8.0, 18.0),
                fit: pw.BoxFit.contain,
              ),
            ),
          );
        }
      }

      final dateDisplay = timetablePrintDate.trim().isNotEmpty
          ? '📅 તારીખ: ${timetablePrintDate.trim()}'
          : '📅 તારીખ: ____/____/૨૦૨__';
      final sigLeftImg = await _renderTimetableTextImage(
        '✍️ વર્ગ શિક્ષકની સહી (Class Teacher Signature)',
        fontSize: 10,
        bold: true,
        color: const Color(0xFF0F172A),
        maxWidth: 260,
      );
      final sigMidImg = await _renderTimetableTextImage(
        dateDisplay,
        fontSize: 10,
        bold: true,
        color: const Color(0xFF312E81),
        maxWidth: 220,
      );
      final sigRightImg = await _renderTimetableTextImage(
        '🏅 આચાર્યશ્રીની સહી અને સિક્કો (Principal Stamp & Sign)',
        fontSize: 10,
        bold: true,
        color: const Color(0xFF0F172A),
        maxWidth: 270,
      );

      final pageW = PdfPageFormat.a4.landscape.width - 24;
      final pageH = PdfPageFormat.a4.landscape.height - 24;
      final logo1SizePt = (logoStyle.widthPx * 0.62).clamp(24.0, 130.0);
      final logo2SizePt = (logo2Style.widthPx * 0.62).clamp(24.0, 130.0);
      final wmSizePt = (watermarkStyle.widthPx * 0.72).clamp(40.0, 240.0);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(12),
          build: (ctx) {
            return pw.Container(
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                border: pw.Border.all(
                  color: borderPdfColor,
                  width: borderWidth,
                ),
                borderRadius: pw.BorderRadius.circular(10),
              ),
              child: pw.Stack(
                children: [
                  if (wmImg != null)
                    pw.Positioned(
                      left: ((watermarkStyle.xPercent / 100.0) * pageW -
                              wmSizePt / 2)
                          .clamp(4.0, pageW - wmSizePt - 4.0),
                      top: ((watermarkStyle.yPercent / 100.0) * pageH -
                              wmSizePt / 2)
                          .clamp(4.0, pageH - wmSizePt - 4.0),
                      child: pw.SizedBox(
                        width: wmSizePt,
                        height: wmSizePt,
                        child: pw.Image(wmImg, fit: pw.BoxFit.contain),
                      ),
                    ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                        children: [
                          // Header Banner matching _buildSingleTimetableSheet
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: pw.BoxDecoration(
                              gradient: pw.LinearGradient(
                                colors: [
                                  PdfColor.fromInt(0xFFEEF2FF),
                                  PdfColors.white,
                                ],
                                begin: pw.Alignment.topCenter,
                                end: pw.Alignment.bottomCenter,
                              ),
                              border: pw.Border(
                                bottom: pw.BorderSide(
                                  color: borderPdfColor,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: pw.Column(
                              children: [
                                if (schoolTitleImg != null)
                                  pw.Image(schoolTitleImg,
                                      height: 22, fit: pw.BoxFit.contain),
                                pw.SizedBox(height: 2),
                                if (schoolSubImg != null)
                                  pw.Image(schoolSubImg,
                                      height: 14, fit: pw.BoxFit.contain),
                                pw.SizedBox(height: 4),
                                if (entityPillImg != null)
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 3.5),
                                    decoration: pw.BoxDecoration(
                                      color: PdfColor.fromInt(0xFFE0E7FF),
                                      borderRadius: pw.BorderRadius.circular(20),
                                      border: pw.Border.all(
                                        color: PdfColor.fromInt(0xFFA5B4FC),
                                        width: 1,
                                      ),
                                    ),
                                    child: pw.Image(entityPillImg,
                                        height: 14, fit: pw.BoxFit.contain),
                                  ),
                              ],
                            ),
                          ),
                          // Prayer Bar matching _buildSingleTimetableSheet
                          if (prayerImg != null)
                            pw.Container(
                              padding: const pw.EdgeInsets.symmetric(
                                  vertical: 5, horizontal: 10),
                              color: PdfColor.fromInt(0xFFEDE9FE),
                              alignment: pw.Alignment.center,
                              child: pw.Image(prayerImg,
                                  height: 13.5, fit: pw.BoxFit.contain),
                            ),
                          // Timetable Grid Table matching _buildSingleTimetableSheet
                          pw.Table(
                            border: pw.TableBorder.all(
                              color: PdfColor.fromInt(0xFF94A3B8),
                              width: 0.9,
                            ),
                            columnWidths: const {
                              0: pw.FixedColumnWidth(62),
                              1: pw.FixedColumnWidth(76),
                              2: pw.FlexColumnWidth(1),
                              3: pw.FlexColumnWidth(1),
                              4: pw.FlexColumnWidth(1),
                              5: pw.FlexColumnWidth(1),
                              6: pw.FlexColumnWidth(1),
                              7: pw.FlexColumnWidth(1),
                            },
                            children: tableRows,
                          ),
                        ],
                      ),
                      // Footer Legend & Signatures matching _buildSingleTimetableSheet
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromInt(0xFFF8FAFC),
                          border: pw.Border(
                            top: pw.BorderSide(
                              color: PdfColor.fromInt(0xFF94A3B8),
                              width: 1,
                            ),
                          ),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                          children: [
                            if (legendBadges.isNotEmpty)
                              pw.Container(
                                width: double.infinity,
                                alignment: pw.Alignment.centerLeft,
                                child: pageDesign.teacherLegendSingleLine
                                    ? pw.FittedBox(
                                        fit: pw.BoxFit.scaleDown,
                                        alignment: pw.Alignment.centerLeft,
                                        child: pw.Row(
                                          mainAxisSize: pw.MainAxisSize.min,
                                          children: legendBadges,
                                        ),
                                      )
                                    : pw.Wrap(
                                        spacing: 4,
                                        runSpacing: 3,
                                        crossAxisAlignment:
                                            pw.WrapCrossAlignment.center,
                                        children: legendBadges,
                                      ),
                              ),
                            if (pageDesign.showSignatures) ...[
                              pw.SizedBox(height: 6),
                              pw.Divider(
                                height: 1,
                                color: PdfColor.fromInt(0xFFE2E8F0),
                              ),
                              pw.SizedBox(height: 5),
                              pw.Row(
                                mainAxisAlignment:
                                    pw.MainAxisAlignment.spaceBetween,
                                crossAxisAlignment:
                                    pw.CrossAxisAlignment.center,
                                children: [
                                  if (sigLeftImg != null)
                                    pw.Image(sigLeftImg,
                                        height: 13.5, fit: pw.BoxFit.contain),
                                  if (sigMidImg != null)
                                    pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: pw.BoxDecoration(
                                        color: PdfColor.fromInt(0xFFEEF2FF),
                                        borderRadius:
                                            pw.BorderRadius.circular(5),
                                        border: pw.Border.all(
                                          color: PdfColor.fromInt(0xFF818CF8),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: pw.Image(sigMidImg,
                                          height: 13, fit: pw.BoxFit.contain),
                                    ),
                                  if (sigRightImg != null)
                                    pw.Image(sigRightImg,
                                        height: 13.5, fit: pw.BoxFit.contain),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (logo1Img != null)
                    pw.Positioned(
                      left: ((logoStyle.xPercent / 100.0) * pageW -
                              logo1SizePt / 2)
                          .clamp(6.0, pageW - logo1SizePt - 6.0),
                      top: ((logoStyle.yPercent / 100.0) * pageH -
                              logo1SizePt / 2)
                          .clamp(6.0, pageH - logo1SizePt - 6.0),
                      child: pw.SizedBox(
                        width: logo1SizePt,
                        height: logo1SizePt,
                        child: pw.Image(logo1Img, fit: pw.BoxFit.contain),
                      ),
                    ),
                  if (logo2Img != null)
                    pw.Positioned(
                      left: ((logo2Style.xPercent / 100.0) * pageW -
                              logo2SizePt / 2)
                          .clamp(6.0, pageW - logo2SizePt - 6.0),
                      top: ((logo2Style.yPercent / 100.0) * pageH -
                              logo2SizePt / 2)
                          .clamp(6.0, pageH - logo2SizePt - 6.0),
                      child: pw.SizedBox(
                        width: logo2SizePt,
                        height: logo2SizePt,
                        child: pw.Image(logo2Img, fit: pw.BoxFit.contain),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
    }

    return doc.save();
  }
}
