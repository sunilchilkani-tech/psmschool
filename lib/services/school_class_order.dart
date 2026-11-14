import 'dart:convert';

/// Shared class grouping and ordering rules used by attendance and report screens.
/// This file is intentionally dependency-free so it can be imported by all report services.
class SchoolClassOrder {
  static const String balvatika = 'BALVATIKA';
  static const String standards1to5 = 'STD 1 TO 5';
  static const String standards6to8 = 'STD 6 TO 8';
  static const String all = 'ALL';
  static const String other = 'OTHER';

  /// Value/label pairs used by report-group dropdowns.
  static const List<(String, String)> reportGroups = <(String, String)>[
    (balvatika, 'બાલવાટિકા'),
    (standards1to5, 'ધો. 1 થી 5'),
    (standards6to8, 'ધો. 6 થી 8'),
    (all, 'આખી શાળા'),
  ];

  /// Returns a sorted copy: Balvatika, Standards 1-5, Standards 6-8, then other.
  static List<Map<String, dynamic>> sorted(
    Iterable<Map<String, dynamic>> rows,
  ) {
    final result = rows.map((r) {
      final copy = Map<String, dynamic>.from(r);
      for (final k in const <String>[
        'label',
        'class_label',
        'class_name',
        'sheet_name',
      ]) {
        if (copy[k] is String) {
          copy[k] = cleanText(copy[k]);
        }
      }
      return copy;
    }).toList();
    result.sort((a, b) {
      var comparison = _groupRank(groupOf(a)).compareTo(_groupRank(groupOf(b)));
      if (comparison != 0) return comparison;

      comparison = _classNumber(a).compareTo(_classNumber(b));
      if (comparison != 0) return comparison;

      comparison = _intValue(a['sort_order'] ?? a['class_sort_order'])
          .compareTo(_intValue(b['sort_order'] ?? b['class_sort_order']));
      if (comparison != 0) return comparison;

      comparison = _text(_firstValue(a, const ['section', 'class_section']))
          .compareTo(_text(_firstValue(b, const ['section', 'class_section'])));
      if (comparison != 0) return comparison;

      return _text(_firstValue(a, const [
        'class_label', 'label', 'class_key', 'sheet_name', 'class_name'
      ])).compareTo(_text(_firstValue(b, const [
        'class_label', 'label', 'class_key', 'sheet_name', 'class_name'
      ])));
    });
    return result;
  }

  /// Classifies a class row from school_classes or a school-wide report RPC row.
  static String groupOf(Map<String, dynamic> row) {
    for (final key in const ['report_group', 'class_report_group', 'reportGroup']) {
      final recognised = _recogniseGroup(_normalise(row[key]));
      if (recognised != null) return recognised;
    }

    for (final key in const [
      'standard', 'class_standard', 'standard_name', 'class_label', 'label',
      'class_key', 'sheet_name', 'class_name', 'className'
    ]) {
      final value = _normalise(row[key]);
      if (value.isEmpty) continue;

      final recognised = _recogniseGroup(value);
      if (recognised != null) return recognised;

      final number = _numberFromText(value);
      if (number != null) {
        if (number >= 1 && number <= 5) return standards1to5;
        if (number >= 6 && number <= 8) return standards6to8;
      }
    }
    return other;
  }

  /// Whether the row belongs to the selected report group; ALL includes every class.
  static bool matches(Map<String, dynamic> row, String group) {
    final wanted = _canonicalGroup(group);
    if (wanted == all) return true;
    return groupOf(row) == wanted;
  }

  static String labelFor(String group) {
    switch (_canonicalGroup(group)) {
      case balvatika:
        return 'બાલવાટિકા';
      case standards1to5:
        return 'ધોરણ 1 થી 5';
      case standards6to8:
        return 'ધોરણ 6 થી 8';
      case all:
        return 'આખી શાળા';
      default:
        return 'અન્ય વર્ગો';
    }
  }

  static String _canonicalGroup(String value) {
    final normalised = _normalise(value);
    if (normalised == all ||
        normalised == 'ALL CLASSES' ||
        normalised == 'WHOLE SCHOOL' ||
        normalised.contains('આખી શાળા')) {
      return all;
    }
    return _recogniseGroup(normalised) ?? other;
  }

  static String? _recogniseGroup(String value) {
    if (value.isEmpty) return null;
    if (value.contains('BALVATIKA') ||
        value.contains('BALVATI') ||
        value.contains('બાલવાટિકા')) {
      return balvatika;
    }
    if (RegExp(r'\b1\s*(?:TO|THROUGH|THI|-|–|—)\s*5\b').hasMatch(value) ||
        value.contains('1 થી 5')) {
      return standards1to5;
    }
    if (RegExp(r'\b6\s*(?:TO|THROUGH|THI|-|–|—)\s*8\b').hasMatch(value) ||
        value.contains('6 થી 8')) {
      return standards6to8;
    }
    return null;
  }

  static int _classNumber(Map<String, dynamic> row) {
    for (final key in const [
      'standard', 'class_standard', 'standard_name', 'class_label', 'label',
      'class_key', 'sheet_name', 'class_name', 'className'
    ]) {
      final value = _normalise(row[key]);
      if (value.isEmpty || _recogniseGroup(value) != null) continue;
      final number = _numberFromText(value);
      if (number != null) return number;
    }
    return 999;
  }

  static int? _numberFromText(String value) {
    final normalised = _convertGujaratiDigits(value);
    final match = RegExp(r'(?:^|\D)([0-8])(?:ST|ND|RD|TH)?(?:\D|$)')
        .firstMatch(normalised);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static int _groupRank(String group) {
    switch (group) {
      case balvatika:
        return 0;
      case standards1to5:
        return 1;
      case standards6to8:
        return 2;
      default:
        return 3;
    }
  }

  static dynamic _firstValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && value.toString().trim().isNotEmpty) return value;
    }
    return '';
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _text(dynamic value) =>
      (value?.toString() ?? '').trim().toLowerCase();

  static String _normalise(dynamic value) => _repairMojibake(value?.toString() ?? '')
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[_–—]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String cleanText(dynamic value) => _repairMojibake(value?.toString() ?? '').trim();

  static String _repairMojibake(String value) {
    var v = value
        .replaceAll('\u00e2\u20ac\u00a2', '•')
        .replaceAll('\u00e2\u20ac\u201d', '—')
        .replaceAll('\u00e2\u20ac\u201c', '–')
        .replaceAll('\u00e2\u20ac\u00a6', '…')
        .replaceAll('\u00e2\u2020\u2019', '→');
    if (!v.contains('àª') && !v.contains('à«') && !v.contains('Ã')) return v;
    value = v;
    const cp1252Overrides = <int, int>{
      0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84,
      0x2026: 0x85, 0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88,
      0x2030: 0x89, 0x0160: 0x8A, 0x2039: 0x8B, 0x0152: 0x8C,
      0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92, 0x201C: 0x93,
      0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
      0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B,
      0x0153: 0x9C, 0x017E: 0x9E, 0x0178: 0x9F,
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
      // Keep the original label if it is not a reversible UTF-8 mojibake sequence.
    }
    return value;
  }

  static String _convertGujaratiDigits(String value) {
    const digits = <String, String>{
      '૦': '0', '૧': '1', '૨': '2', '૩': '3', '૪': '4',
      '૫': '5', '૬': '6', '૭': '7', '૮': '8', '૯': '9',
    };
    var result = value;
    digits.forEach((gujarati, ascii) {
      result = result.replaceAll(gujarati, ascii);
    });
    return result;
  }
}
