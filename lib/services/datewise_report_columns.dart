import 'school_type.dart';

/// Stable flat selection list for the 60 DATE WISE report data columns.
/// The class name column is always shown and is not one of these selectable columns.
class DateWiseReportColumn {
  const DateWiseReportColumn({
    required this.key,
    required this.label,
    required this.metric,
    required this.category,
    required this.gender,
  });

  final String key;
  final String label;
  final String metric;
  /// SC, ST, OBC, OTHER, or CATEGORY_TOTAL.
  final String category;
  /// BOYS, GIRLS, or TOTAL.
  final String gender;

  static final List<DateWiseReportColumn> all = _build();
  static final Set<String> allKeys = all.map((column) => column.key).toSet();

  static String normalizeSchoolType(dynamic raw) => SchoolType.canonical(raw);

  static String schoolTypeDisplayLabel(dynamic raw) {
    switch (normalizeSchoolType(raw)) {
      case 'boys':
        return 'માત્ર કુમાર શાળા (Only Boys — Auto from School Registration)';
      case 'girls':
        return 'માત્ર કન્યા શાળા (Only Girls — Auto from School Registration)';
      default:
        return 'મિશ્ર શાળા (Boys, Girls & Total — Auto from School Registration)';
    }
  }

  static List<DateWiseReportColumn> columnsForSchoolType(dynamic schoolType) {
    final norm = normalizeSchoolType(schoolType);
    if (norm == 'boys') {
      return all
          .where((col) => col.gender == 'BOYS')
          .toList(growable: false);
    }
    if (norm == 'girls') {
      return all
          .where((col) => col.gender == 'GIRLS')
          .toList(growable: false);
    }
    return all;
  }

  static Set<String> keysForSchoolType(dynamic schoolType) =>
      columnsForSchoolType(schoolType).map((c) => c.key).toSet();

  static List<String> filterColumnKeysForSchoolType(
    Iterable<String> keys,
    dynamic schoolType,
  ) {
    final allowed = keysForSchoolType(schoolType);
    final selected = keys.where(allowed.contains).toSet();
    final effective = selected.isEmpty ? allowed : selected;
    return all
        .where((col) => effective.contains(col.key))
        .map((col) => col.key)
        .toList();
  }


  static List<DateWiseReportColumn> _build() {
    const metrics = <(String, String)>[
      ('registered', 'રજીસ્ટરર્ડ'),
      ('present', 'હાજર'),
      ('mdm', 'પીએમ પોષણ'),
      ('breakfast', 'સીએમ અલ્પાહાર'),
    ];
    const categories = <(String, String)>[
      ('SC', 'અ. જા.'),
      ('ST', 'અ. જ. જા.'),
      ('OBC', 'બક્ષીપંચ'),
      ('OTHER', 'અન્ય'),
      ('CATEGORY_TOTAL', 'કુલ'),
    ];
    const genders = <(String, String)>[
      ('BOYS', 'કુમાર'),
      ('GIRLS', 'કન્યા'),
      ('TOTAL', 'TOTAL'),
    ];

    final result = <DateWiseReportColumn>[];
    for (final metric in metrics) {
      for (final category in categories) {
        for (final gender in genders) {
          result.add(DateWiseReportColumn(
            key: '${metric.$1}_${category.$1.toLowerCase()}_${gender.$1.toLowerCase()}',
            label: '${metric.$2} ${category.$2} ${gender.$2}',
            metric: metric.$1,
            category: category.$1,
            gender: gender.$1,
          ));
        }
      }
    }
    return List<DateWiseReportColumn>.unmodifiable(result);
  }
}

/// Selectable & reorderable column sections for the monthly TARIJ report (Page 1 & Page 2).
/// Admin can select which sections to include and set their column header number / order.
class TarijReportColumn {
  const TarijReportColumn({
    required this.key,
    required this.label,
    required this.group,
    required this.defaultNumber,
  });

  final String key;
  final String label;
  final String group;
  final int defaultNumber;

  String get cleanTitle =>
      label.replaceFirst(RegExp(r'^[૦-૯0-9]+\.\s*'), '').trim();

  String numberedLabel(int columnNumber) => '$columnNumber. $cleanTitle';

  static TarijReportColumn? byKey(String key) {
    for (final col in all) {
      if (col.key == key) return col;
    }
    return null;
  }

  static const List<TarijReportColumn> all = <TarijReportColumn>[
    TarijReportColumn(
      key: 'opening',
      defaultNumber: 1,
      label: '૧. શરૂની સંખ્યા (Opening Count • કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'admissions',
      defaultNumber: 2,
      label: '૨. ચાલુ માસમાં નવા દાખલ (Admissions • કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'exits',
      defaultNumber: 3,
      label: '૩. ચાલુ માસમાં કમી થયેલ (Exits / LC • કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'closing',
      defaultNumber: 4,
      label: '૪. આખરની સંખ્યા (Closing Count • જ્ઞાતિવાર કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'working_days',
      defaultNumber: 5,
      label: '૫. માસના ચાલુ દિવસો (Working Days • Auto Count Recorded Attendance Days)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'present_total',
      defaultNumber: 6,
      label: '૬. હાજરી સંખ્યા કુલ (Total Present • કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'avg_present',
      defaultNumber: 7,
      label: '૭. સરેરાશ હાજરી (Average Present • જ્ઞાતિવાર કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'attendance_pct',
      defaultNumber: 8,
      label: '૮. હાજરીની ટકાવારી % (Attendance % • કુમાર/કન્યા/કુલ)',
      group: 'core',
    ),
    TarijReportColumn(
      key: 'mdm_days',
      defaultNumber: 9,
      label: '૯. મ. ભો. ચાલુ દિવસો (PM POSHAN Recorded Days • Auto Count)',
      group: 'mdm',
    ),
    TarijReportColumn(
      key: 'tithi_days',
      defaultNumber: 10,
      label: '૧૦. તિથિ ભોજન દિવસો (Working Days − PM POSHAN Days • Auto)',
      group: 'mdm',
    ),
    TarijReportColumn(
      key: 'mdm_total',
      defaultNumber: 11,
      label: '૧૧. મ.ભો. લાભાર્થી સંખ્યા કુલ (Total MDM • કુમાર/કન્યા/કુલ)',
      group: 'mdm',
    ),
    TarijReportColumn(
      key: 'avg_mdm',
      defaultNumber: 12,
      label: '૧૨. સરેરાશ મ.ભો. લાભાર્થી (Average MDM • જ્ઞાતિવાર કુમાર/કન્યા/કુલ)',
      group: 'mdm',
    ),
    TarijReportColumn(
      key: 'perfect_100',
      defaultNumber: 13,
      label: '૧૩. ૧૦૦% હાજરીવાળા બાળકો (100% Attendance • કુમાર/કન્યા/કુલ)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'age_5_6',
      defaultNumber: 14,
      label: '૧૪. ઉંમર ૫ થી ૬ વર્ષ (Age 5–6 • BOD થી માસની છેલ્લી તારીખ મુજબ Auto)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'age_6_14',
      defaultNumber: 15,
      label: '૧૫. ઉંમર ૬ થી ૧૪ વર્ષ (Age 6–14 • BOD થી માસની છેલ્લી તારીખ મુજબ Auto)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'age_above_14',
      defaultNumber: 16,
      label: '૧૬. ઉંમર ૧૪ થી વધુ (Age >14 • BOD થી માસની છેલ્લી તારીખ મુજબ Auto)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'aadhaar',
      defaultNumber: 17,
      label: '૧૭. આધાર કાર્ડ ધરાવતા બાળકો (Aadhaar = YES • કુમાર/કન્યા/કુલ Auto)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'minority',
      defaultNumber: 18,
      label: '૧૮. લઘુમતી બાળકો (Minority • હિન્દુ સિવાયના • કુમાર/કન્યા/કુલ Auto)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'library_books',
      defaultNumber: 19,
      label: '૧૯. વાંચન અર્થે આપેલ પુસ્તકોની સંખ્યા (Library Register Auto Fetch)',
      group: 'extra',
    ),
    TarijReportColumn(
      key: 'teacher_sign',
      defaultNumber: 20,
      label: '૨૦. વર્ગ શિક્ષકની સહી (Class Teacher Sign Column)',
      group: 'extra',
    ),
  ];

  static final Set<String> allKeys = all.map((c) => c.key).toSet();
}

/// One printed TARIJ column: a section plus (optionally) a category and a
/// gender. Keys look like `opening:BOYS`, `closing:SC:GIRLS`, `working_days`.
///
/// A single-gender school gets 32 columns (each gendered value for that
/// gender only). A mixed school gets Boys, Girls and Total (gender-wise
/// total) for every gendered value. The admin chooses and numbers each
/// column individually.
class TarijColumnSpec {
  const TarijColumnSpec(this.section, {this.category, this.gender});

  final String section;
  final String? category;
  final String? gender;

  static const List<String> categories = <String>['SC', 'ST', 'OBC', 'OTHER', 'TOTAL'];

  static const Set<String> perGenderSections = <String>{
    'opening',
    'admissions',
    'exits',
    'present_total',
    'attendance_pct',
    'mdm_total',
    'perfect_100',
    'age_5_6',
    'age_6_14',
    'age_above_14',
    'aadhaar',
    'minority',
  };

  static const Set<String> perCategorySections = <String>{
    'closing',
    'avg_present',
    'avg_mdm',
  };

  static const Map<String, String> shortTitles = <String, String>{
    'opening': 'શરૂઆતની સંખ્યા',
    'admissions': 'નવા દાખલ',
    'exits': 'શાળા છોડી / કમી',
    'closing': 'અંતે રજી.',
    'working_days': 'માસના ચાલુ દિવસો',
    'present_total': 'કુલ હાજર',
    'avg_present': 'સરેરાશ હાજર',
    'attendance_pct': 'હાજરી %',
    'mdm_days': 'મ.ભો. ચાલુ દિવસો',
    'tithi_days': 'તિથિ ભોજન દિવસો',
    'mdm_total': 'કુલ મ.ભો.',
    'avg_mdm': 'સરેરાશ મ.ભો.',
    'perfect_100': '100% હાજરી',
    'age_5_6': 'ઉંમર 5 થી 6',
    'age_6_14': 'ઉંમર 6 થી 14',
    'age_above_14': 'ઉંમર 14 થી વધુ',
    'aadhaar': 'આધાર કાર્ડ',
    'minority': 'લઘુમતી',
    'library_books': 'વાંચન અર્થે પુસ્તકો',
    'teacher_sign': 'વર્ગ શિક્ષકની સહી',
  };

  static String categoryLabel(String c) => switch (c) {
        'SC' => 'અ.જા.',
        'ST' => 'અ.જ.જા.',
        'OBC' => 'બક્ષીપંચ',
        'OTHER' => 'અન્ય',
        _ => 'કુલ',
      };

  static String genderLabel(String g) => switch (g) {
        'BOYS' => 'કુમાર',
        'GIRLS' => 'કન્યા',
        _ => 'કુલ',
      };

  String get key => <String>[
        section,
        if (category != null) category!,
        if (gender != null) gender!,
      ].join(':');

  /// Header text without the column number.
  String get title {
    final base = shortTitles[section] ?? section;
    final cat = category == null ? '' : ' - ${categoryLabel(category!)}';
    final gen = gender == null ? '' : ' (${genderLabel(gender!)})';
    return '$base$cat$gen';
  }

  static TarijColumnSpec? parse(String raw) {
    final parts = raw.trim().split(':');
    if (parts.isEmpty || !shortTitles.containsKey(parts.first)) return null;
    final section = parts.first;
    if (perCategorySections.contains(section)) {
      if (parts.length != 3) return null;
      return TarijColumnSpec(section, category: parts[1], gender: parts[2]);
    }
    if (perGenderSections.contains(section)) {
      if (parts.length != 2) return null;
      return TarijColumnSpec(section, gender: parts[1]);
    }
    return parts.length == 1 ? TarijColumnSpec(section) : null;
  }

  /// Genders shown for a school type: one gender, or Boys + Girls + Total.
  static List<String> gendersFor(String schoolType) {
    switch (SchoolType.canonical(schoolType)) {
      case 'boys':
        return const <String>['BOYS'];
      case 'girls':
        return const <String>['GIRLS'];
      default:
        return const <String>['BOYS', 'GIRLS', 'TOTAL'];
    }
  }

  /// All printed columns of [section] for this school type.
  static List<TarijColumnSpec> expandSection(String section, String schoolType) {
    final genders = gendersFor(schoolType);
    if (perCategorySections.contains(section)) {
      return <TarijColumnSpec>[
        for (final c in categories)
          for (final g in genders) TarijColumnSpec(section, category: c, gender: g),
      ];
    }
    if (perGenderSections.contains(section)) {
      return <TarijColumnSpec>[
        for (final g in genders) TarijColumnSpec(section, gender: g),
      ];
    }
    return <TarijColumnSpec>[TarijColumnSpec(section)];
  }

  /// Every printable column in default order (32 for a single-gender school).
  static List<TarijColumnSpec> allFor(String schoolType) => <TarijColumnSpec>[
        for (final col in TarijReportColumn.all) ...expandSection(col.key, schoolType),
      ];

  /// Turns saved keys (new column keys or old section keys) into the ordered
  /// columns valid for this school type. Empty → every column.
  static List<TarijColumnSpec> resolve(Iterable<String> keys, String schoolType) {
    final genders = gendersFor(schoolType).toSet();
    final out = <TarijColumnSpec>[];
    final seen = <String>{};
    void add(TarijColumnSpec s) {
      if (seen.add(s.key)) out.add(s);
    }

    for (final raw in keys) {
      final k = raw.trim();
      if (k.isEmpty) continue;
      if (!k.contains(':') && TarijReportColumn.allKeys.contains(k)) {
        expandSection(k, schoolType).forEach(add); // old section-level key
        continue;
      }
      final s = TarijColumnSpec.parse(k);
      if (s == null) continue;
      if (s.gender != null && !genders.contains(s.gender)) continue;
      if (s.category != null && !categories.contains(s.category)) continue;
      add(s);
    }
    return out.isEmpty ? allFor(schoolType) : out;
  }
}
