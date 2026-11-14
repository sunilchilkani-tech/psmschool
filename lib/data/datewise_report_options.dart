/// Canonical DATE WISE column definitions shared by the administrator settings
/// and the report PDF generator. Selection is school-wide, not class-specific.
class DateWiseReportColumn {
  final String key;
  final String metricKey;
  final String metricTitle;
  final String categoryKey;
  final String categoryLabel;
  final String genderKey;
  final String genderLabel;
  final String label;

  const DateWiseReportColumn({
    required this.key,
    required this.metricKey,
    required this.metricTitle,
    required this.categoryKey,
    required this.categoryLabel,
    required this.genderKey,
    required this.genderLabel,
    required this.label,
  });
}

class DateWiseReportColumns {
  static const metrics = <Map<String, String>>[
    {'key': 'registered', 'title': 'રજીસ્ટરર્ડ', 'pdfTitle': 'REGISTERED STUDENTS'},
    {'key': 'present', 'title': 'હાજર', 'pdfTitle': 'PRESENT'},
    {'key': 'mdm', 'title': 'પીએમ પોષણ', 'pdfTitle': 'PM POSHAN'},
    {'key': 'breakfast', 'title': 'સીએમ અલ્પાહાર', 'pdfTitle': 'BREAKFAST'},
  ];

  static const categories = <Map<String, String>>[
    {'key': 'SC', 'label': 'અ. જા.'},
    {'key': 'ST', 'label': 'અ. જ. જા.'},
    {'key': 'OBC', 'label': 'બક્ષીપંચ'},
    {'key': 'OTHER', 'label': 'અન્ય'},
    {'key': 'TOTAL', 'label': 'કુલ'},
  ];

  static const genders = <Map<String, String>>[
    {'key': 'boys', 'label': 'કુમાર', 'pdfLabel': 'B'},
    {'key': 'girls', 'label': 'કન્યા', 'pdfLabel': 'G'},
    {'key': 'total', 'label': 'કુલ', 'pdfLabel': 'T'},
  ];

  static final List<DateWiseReportColumn> all = <DateWiseReportColumn>[
    for (final metric in metrics)
      for (final category in categories)
        for (final gender in genders)
          DateWiseReportColumn(
            key: '${metric['key']}_${category['key']!.toLowerCase()}_${gender['key']}',
            metricKey: metric['key']!,
            metricTitle: metric['pdfTitle']!,
            categoryKey: category['key']!,
            categoryLabel: category['label']!,
            genderKey: gender['key']!,
            genderLabel: gender['label']!,
            label: '${metric['title']} ${category['label']} ${category['key'] == 'TOTAL' && gender['key'] == 'total' ? 'TOTAL' : gender['label']}',
          ),
  ];

  static final Set<String> allKeys = all.map((item) => item.key).toSet();
  static List<String> get allKeyList => all.map((item) => item.key).toList();

  static DateWiseReportColumn? byKey(String key) {
    for (final item in all) {
      if (item.key == key) return item;
    }
    return null;
  }
}
