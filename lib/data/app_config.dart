import 'dart:convert';

import '../models/models.dart';

String _repairSchoolGroupMojibake(String value) {
  if (!value.contains('àª') && !value.contains('à«') && !value.contains('Ã'))
    return value;
  const cp1252Overrides = <int, int>{
    0x20AC: 0x80,
    0x201A: 0x82,
    0x0192: 0x83,
    0x201E: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x02C6: 0x88,
    0x2030: 0x89,
    0x0160: 0x8A,
    0x2039: 0x8B,
    0x0152: 0x8C,
    0x017D: 0x8E,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201C: 0x93,
    0x201D: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x02DC: 0x98,
    0x2122: 0x99,
    0x0161: 0x9A,
    0x203A: 0x9B,
    0x0153: 0x9C,
    0x017E: 0x9E,
    0x0178: 0x9F,
  };
  final bytes = <int>[];
  for (final unit in value.codeUnits) {
    if (unit <= 0xFF) {
      bytes.add(unit);
    } else if (cp1252Overrides.containsKey(unit)) {
      bytes.add(cp1252Overrides[unit]!);
    } else {
      return value;
    }
  }
  try {
    final decoded = utf8.decode(bytes, allowMalformed: false);
    if (RegExp(r'[\u0A80-\u0AFF]').hasMatch(decoded)) return decoded;
  } catch (_) {
    // Preserve the value if it is not a reversible UTF-8 mojibake sequence.
  }
  return value;
}

class SchoolClass {
  final String key;
  final String label;
  final String sheetName;
  final String standard;
  final String section;
  final String reportGroup;

  SchoolClass(
    this.key, {
    String? label,
    String? sheetName,
    String? standard,
    String? section,
    String? reportGroup,
  })  : label = label ?? key.replaceFirst(RegExp(r'^Class\s+'), ''),
        sheetName = sheetName ?? key.replaceFirst(RegExp(r'^Class\s+'), ''),
        standard = standard ?? '',
        section = section ?? '',
        reportGroup = _repairSchoolGroupMojibake(reportGroup ?? '');

  /// A human-readable Gujarati class name. The original [key] is deliberately
  /// retained for database lookups; this value is only for UI/PDF display.
  String get displayLabel => formatDisplayLabel(
        key: key,
        label: label,
        sheetName: sheetName,
        standard: standard,
        section: section,
      );

  static bool isSyntheticClassId(String value) =>
      RegExp(r'^class_\d+$', caseSensitive: false).hasMatch(value.trim());

  static String formatDisplayLabel({
    String key = '',
    String label = '',
    String sheetName = '',
    String standard = '',
    String section = '',
  }) {
    final cleanKey = key.trim();
    final candidates = <String>[
      standard.trim(),
      section.trim(),
      label.trim(),
      sheetName.trim(),
      cleanKey,
    ].where((value) => value.isNotEmpty).toList();

    bool isBalvatika(String value) {
      final normalized = value.trim().toUpperCase().replaceAll(' ', '');
      return normalized == 'BALVATIKA' ||
          normalized == 'BALVATIKA-1' ||
          normalized == 'BALVATIKA1' ||
          value.contains('બાલવાટિકા');
    }

    if (candidates.any(isBalvatika)) return 'બાલવાટિકા';

    final numericStandard =
        RegExp(r'^(?:CLASS\s*)?(\d{1,2})$', caseSensitive: false);
    final classPattern = RegExp(
      r'^(?:CLASS[\s_-]*)?(\d{1,2})(?:[\s_-]*([A-Z]))?$',
      caseSensitive: false,
    );

    String? std;
    String? sec = section.trim().isNotEmpty ? section.trim() : null;
    final rawStandard = standard.trim();
    if (rawStandard.isNotEmpty) {
      final match = numericStandard.firstMatch(rawStandard);
      if (match != null) std = match.group(1);
    }

    // Preserve a section suffix from keys such as 5_a even when the standard
    // field is populated separately by Firestore.
    for (final candidate in <String>[label, sheetName, key]) {
      final match = classPattern.firstMatch(candidate.trim());
      if (match == null) continue;
      std ??= match.group(1);
      sec ??= match.group(2);
      if (std != null && sec != null) break;
    }

    if (std != null) {
      final sectionCode = (sec ?? '').trim();
      final sectionGujarati = _gujaratiSection(sectionCode);
      return sectionGujarati.isEmpty
          ? 'ધોરણ - $std'
          : 'ધોરણ - $std - $sectionGujarati';
    }

    // Do not expose generated Firestore document identifiers as class names.
    for (final candidate in <String>[label, sheetName, key]) {
      final value = candidate.trim();
      if (value.isEmpty || isSyntheticClassId(value)) continue;
      if (RegExp(r'^Class\s+', caseSensitive: false).hasMatch(value)) {
        return 'ધોરણ - ${value.replaceFirst(RegExp(r'^Class\s+', caseSensitive: false), '').trim()}';
      }
      return value;
    }
    return '';
  }

  static String _gujaratiSection(String value) {
    final section = value.trim();
    if (section.isEmpty) return '';
    if (RegExp(r'^[\u0A80-\u0AFF]+$').hasMatch(section)) return section;
    if (section.length != 1) return section;
    const sectionMap = <String, String>{
      'A': 'અ',
      'B': 'બ',
      'C': 'ક',
      'D': 'ડ',
      'E': 'ઇ',
      'F': 'ફ',
      'G': 'ગ',
      'H': 'હ',
      'I': 'ઈ',
      'J': 'જ',
      'K': 'ક',
      'L': 'લ',
      'M': 'મ',
      'N': 'ન',
      'O': 'ઓ',
      'P': 'પ',
      'Q': 'ક્યુ',
      'R': 'ર',
      'S': 'સ',
      'T': 'ત',
      'U': 'ઉ',
      'V': 'વ',
      'W': 'ડબલ્યુ',
      'X': 'એક્સ',
      'Y': 'ય',
      'Z': 'ઝ',
    };
    return sectionMap[section.toUpperCase()] ?? section;
  }

  factory SchoolClass.fromJson(Map<String, dynamic> json) => SchoolClass(
        (json['key'] ?? json['label'] ?? '').toString(),
        label: (json['label'] ?? json['key'] ?? '').toString(),
        sheetName: (json['sheetName'] ?? json['label'] ?? json['key'] ?? '')
            .toString(),
        standard: (json['standard'] ?? '').toString(),
        section: (json['section'] ?? '').toString(),
        reportGroup: (json['reportGroup'] ?? '').toString(),
      );
}

class AppConfig {
  AppConfig._();

  static const List<Category> categories = [
    Category.sc,
    Category.st,
    Category.obc,
    Category.other,
  ];

  static const List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const String prefsKeyBackendUrl = 'backend_url_v5_shared_platform';
  static const String prefsKeyResultBackendUrl = 'result_backend_url_v2';
  static const String prefsKeySession = 'session_teacher_name';
  static const String prefsKeySchoolCode = 'tenant_school_code_v1';
  static const String prefsKeySessionToken = 'tenant_session_token_v1';
  static const String prefsKeySchoolConfig = 'tenant_school_config_v1';
  static const String prefsKeySessionJson = 'session_teacher_json';
  static const String prefsKeyLastClass = 'last_selected_class';
  static const String prefsKeyEntryMode = 'preferred_entry_mode';
  static const String prefsKeyQuickPick = 'preferred_quick_pick';

  // Remembers which screen was used last: 'menu', 'attendance', or 'result'
  static const String prefsKeyLastModule = 'last_used_module';
  static const String prefsKeyLastSemester = 'last_selected_semester';
  static const String prefsKeyLastSubject = 'last_selected_subject';

  /// Configure one shared platform Web App URL on first start. No school's URL is embedded in the app.
  static const String defaultBackendUrl = '';

  /// Kept for migration only; the professional multi-school version uses one router/API for both modules.
  static const String defaultResultBackendUrl = '';

  /// Legacy screens may still reference this during migration. Do not use as backend authorization.
  static const String masterPassword = '';
}
