/// Indian dates, always read day first.
///
/// One reader for everything a school office types or a spreadsheet hands
/// over. All of these are 1 December 2025:
///
///   01/12/2025 · 1/12/25 · 01-12-2025 · 1-12-25 · 01.12.2025 · 01 12 2025
///   1-Dec-25 · 1-Dec-2025 · 01-DEC-2025 · 1 Dec 2025 · 1st December, 2025
///   Dec 1, 2025 · December 1 2025 · Mon, 1 Dec 2025 · તા. 01/12/2025
///   ૦૧/૧૨/૨૦૨૫ · ૧ ડિસેમ્બર ૨૦૨૫ · ૧લી ડિસે. ૨૦૨૫ · १ दिसंबर २०२५
///   2025-12-01 · 2025/12/01 · 2025-12-01T10:30:00Z · 01/12/2025 10:30 AM
///   011225 · 01122025 · 20251201 · Excel date number 46000-style serials
///
/// A month above 12 with a day of 12 or less is swapped (12/25/2025 → 25 Dec
/// 2025) because that can only be a month-first entry. Anything that is not
/// a real calendar date (31/02/2025, 29/02/2025, 00/12/2025) is rejected.
class IndianDate {
  IndianDate._();

  /// Short list shown to users wherever a date is typed.
  static const String formatsHint =
      '01/12/2025, 1/12/25, 01-12-2025, 1-12-25, 01.12.2025, 1-Dec-25, 1-Dec-2025, 1 December 2025';

  /// Every style accepted, one example each (used by the Excel template).
  static const List<(String, String)> examples = <(String, String)>[
    ('DD/MM/YYYY', '01/12/2025'),
    ('D/M/YY', '1/12/25'),
    ('DD-MM-YYYY', '01-12-2025'),
    ('D-M-YY', '1-12-25'),
    ('DD.MM.YYYY', '01.12.2025'),
    ('D-Mon-YY', '1-Dec-25'),
    ('D-Mon-YYYY', '1-Dec-2025'),
    ('D Month YYYY', '1 December 2025'),
    ('Month D, YYYY', 'December 1, 2025'),
    ('ગુજરાતી અંક', '૦૧/૧૨/૨૦૨૫'),
    ('ગુજરાતી મહિનો', '૧ ડિસેમ્બર ૨૦૨૫'),
    ('YYYY-MM-DD', '2025-12-01'),
    ('DDMMYYYY', '01122025'),
  ];

  static const int _minYear = 1900;
  static const int _maxYear = 2199;

  // ---------------------------------------------------------------------------
  // PUBLIC API
  // ---------------------------------------------------------------------------

  /// The date in [raw] (String, DateTime or an Excel serial number), or null
  /// when it is not a real date.
  static DateTime? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return DateTime(raw.year, raw.month, raw.day);
    if (raw is num) return _fromSerial(raw.toDouble());
    final s = '$raw'.trim();
    if (s.isEmpty) return null;
    final iso = _fastIso(s);
    if (iso != null) return iso;
    return _parseText(s);
  }

  /// `YYYY-MM-DD` for [raw], or null when it is not a real date.
  static String? toIso(Object? raw) {
    if (raw is String) {
      final t = raw.trim();
      // Stored dates are already ISO: return them without any work.
      if (t.length == 10 && _fastIso(t) != null) return t;
    }
    final d = parse(raw);
    return d == null ? null : iso(d);
  }

  /// `DD/MM/YYYY` for [raw], or null when it is not a real date.
  static String? toDmy(Object? raw, {String separator = '/'}) {
    final d = parse(raw);
    return d == null ? null : dmy(d, separator: separator);
  }

  /// True when [raw] is a real date within [minYear]..[maxYear].
  static bool isValid(Object? raw, {int minYear = _minYear, int maxYear = _maxYear}) {
    final d = parse(raw);
    return d != null && d.year >= minYear && d.year <= maxYear;
  }

  static String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  static String dmy(DateTime d, {String separator = '/'}) =>
      '${_two(d.day)}$separator${_two(d.month)}$separator${d.year.toString().padLeft(4, '0')}';

  /// `1-Dec-2025` style (English month short name).
  static String dMonY(DateTime d) => '${d.day}-${_monthShort[d.month - 1]}-${d.year}';

  // ---------------------------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------------------------

  static String _two(int v) => v.toString().padLeft(2, '0');

  static const List<String> _monthShort = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static bool _isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

  static int _daysIn(int y, int m) => switch (m) {
        2 => _isLeap(y) ? 29 : 28,
        4 || 6 || 9 || 11 => 30,
        _ => 31,
      };

  static DateTime? _make(int y, int m, int d) {
    if (y < _minYear || y > _maxYear || m < 1 || m > 12 || d < 1) return null;
    if (d > _daysIn(y, m)) return null;
    return DateTime(y, m, d);
  }

  /// Exactly `YYYY-MM-DD` (digits only) → date, without regular expressions.
  static DateTime? _fastIso(String s) {
    if (s.length != 10 || s.codeUnitAt(4) != 0x2D || s.codeUnitAt(7) != 0x2D) return null;
    int num(int from, int to) {
      var v = 0;
      for (var i = from; i < to; i++) {
        final c = s.codeUnitAt(i) - 0x30;
        if (c < 0 || c > 9) return -1;
        v = v * 10 + c;
      }
      return v;
    }

    final y = num(0, 4), m = num(5, 7), d = num(8, 10);
    if (y < 0 || m < 0 || d < 0) return null;
    return _make(y, m, d);
  }

  /// Excel / Google Sheets day number (1900 date system, 1899-12-30 based).
  static DateTime? _fromSerial(double v) {
    if (v.isNaN || v < 20000 || v >= 80000) return null; // 1954 … 2119
    final d = DateTime.utc(1899, 12, 30).add(Duration(days: v.floor()));
    return DateTime(d.year, d.month, d.day);
  }

  static int _year(String t) {
    final y = int.parse(t);
    if (t.length == 4) return y;
    if (t.length == 2) return y <= 69 ? 2000 + y : 1900 + y;
    return -1;
  }

  static const String _gujDigits = '૦૧૨૩૪૫૬૭૮૯';
  static const String _devDigits = '०१२३४५६७८९';

  static String _asciiDigits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      final g = _gujDigits.indexOf(ch);
      final d = g >= 0 ? g : _devDigits.indexOf(ch);
      b.write(d >= 0 ? '$d' : ch);
    }
    return b.toString();
  }

  static final RegExp _prefix = RegExp(
    r'^(?:તારીખ|તા\s*\.|તા(?=[\s:\-–]|\d)|dated|date|dt\s*\.|dt(?=[\s:\-–]|\d))\s*[:\-–.]?\s*',
    caseSensitive: false,
  );

  static final RegExp _time = RegExp(
    r'(?:[T\s,]+|^)\d{1,2}:\d{2}(?::\d{2}(?:\.\d+)?)?\s*(?:[ap]\.?\s*m\.?)?\s*(?:z|utc|ist|[+-]\d{2}:?\d{2})?\s*$',
    caseSensitive: false,
  );

  static final RegExp _weekday = RegExp(
    r'\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tues|tue|wed|thurs|thur|thu|fri|sat|sun)\b\.?|સોમવાર|મંગળવાર|બુધવાર|ગુરુવાર|ગુરૂવાર|શુક્રવાર|શનિવાર|રવિવાર|सोमवार|मंगलवार|बुधवार|गुरुवार|शुक्रवार|शनिवार|रविवार',
    caseSensitive: false,
  );

  static final RegExp _separators = RegExp(r"[\s/\\\-–—.,_'’()]+");
  static final RegExp _digitThenOther = RegExp(r'(\d)(?=[^\d\s])');
  static final RegExp _otherThenDigit = RegExp(r'([^\d\s])(?=\d)');
  static final RegExp _allDigits = RegExp(r'^\d+$');
  static final RegExp _serialText = RegExp(r'^\d{5}(?:\.\d+)?$');

  /// Words that may sit next to a date and carry no meaning.
  static const Set<String> _ignore = <String>{
    'st', 'nd', 'rd', 'th', 'of', 'the', 'ad', 'ce', 'on',
    'લી', 'જી', 'થી', 'મી', 'ઠ્ઠી', 'ઠી', 'ના', 'રોજ', 'સન', 'ઈ', 'ઇ', 'સ',
    'वीं', 'वी', 'को', 'सन',
  };

  static final Map<String, int> _months = () {
    final m = <String, int>{};
    void add(int month, List<String> names) {
      for (final n in names) {
        m[n] = month;
      }
    }

    add(1, ['jan', 'january', 'જાન્યુઆરી', 'જાન્યુ', 'જાન', 'जनवरी', 'जन']);
    add(2, ['feb', 'february', 'febuary', 'ફેબ્રુઆરી', 'ફેબ્રુઅરી', 'ફેબ્રુ', 'ફેબ', 'फ़रवरी', 'फरवरी', 'फ़र', 'फर']);
    add(3, ['mar', 'march', 'માર્ચ', 'मार्च']);
    add(4, ['apr', 'april', 'એપ્રિલ', 'એપ્રિ', 'એપ્ર', 'अप्रैल', 'अप्रेल', 'अप्र']);
    add(5, ['may', 'મે', 'મેં', 'मई']);
    add(6, ['jun', 'june', 'જૂન', 'જુન', 'जून']);
    add(7, ['jul', 'july', 'જુલાઈ', 'જુલાઇ', 'જુલા', 'જુલ', 'जुलाई', 'जुल']);
    add(8, ['aug', 'august', 'ઓગસ્ટ', 'ઑગસ્ટ', 'ઓગષ્ટ', 'ઑગષ્ટ', 'ઓગ', 'ઑગ', 'અગસ્ત', 'अगस्त', 'अग']);
    add(9, ['sep', 'sept', 'september', 'સપ્ટેમ્બર', 'સપ્ટેંબર', 'સેપ્ટેમ્બર', 'સપ્ટે', 'સપ્ટ', 'सितंबर', 'सितम्बर', 'सित']);
    add(10, ['oct', 'october', 'ઓક્ટોબર', 'ઑક્ટોબર', 'ઓકટોબર', 'અક્ટોબર', 'ઓક્ટો', 'ઑક્ટો', 'अक्टूबर', 'अक्तूबर', 'अक्टू']);
    add(11, ['nov', 'november', 'નવેમ્બર', 'નવેંબર', 'નવે', 'नवंबर', 'नवम्बर', 'नव']);
    add(12, ['dec', 'december', 'ડિસેમ્બર', 'ડિસેંબર', 'ડીસેમ્બર', 'ડિસે', 'ડીસે', 'दिसंबर', 'दिसम्बर', 'दिस']);
    return m;
  }();

  static DateTime? _parseText(String input) {
    var s = _asciiDigits(input.trim()).toLowerCase();
    s = s.replaceFirst(_prefix, '');
    s = s.replaceAll(_weekday, ' ');
    s = s.replaceFirst(_time, '').trim();
    if (s.isEmpty) return null;

    if (_serialText.hasMatch(s)) return _fromSerial(double.parse(s));
    if (_allDigits.hasMatch(s)) return _packedDigits(s);

    s = s
        .replaceAllMapped(_digitThenOther, (m) => '${m[1]} ')
        .replaceAllMapped(_otherThenDigit, (m) => '${m[1]} ');
    final tokens = s.split(_separators).where((t) => t.isNotEmpty).toList();

    final nums = <String>[];
    int? month;
    var monthPos = -1;
    for (final t in tokens) {
      if (_allDigits.hasMatch(t)) {
        nums.add(t);
        continue;
      }
      if (_ignore.contains(t)) continue;
      final mo = _months[t];
      if (mo == null || month != null) return null; // unknown word / two months
      month = mo;
      monthPos = nums.length;
    }

    if (month != null) {
      if (nums.length != 2) return null;
      final a = nums[0], b = nums[1];
      // 2025 Dec 01 / Dec 2025 01 → year first; otherwise the day comes first
      // (1 Dec 2025, Dec 1 2025, Dec 1, 25).
      if (a.length == 4 && b.length <= 2) return _make(int.parse(a), month, int.parse(b));
      if (a.length > 2) return null;
      final y = _year(b);
      if (y < 0) return null;
      if (monthPos == 2) return null; // "1 2025 Dec"
      return _make(y, month, int.parse(a));
    }

    if (nums.length != 3) return null;
    final p0 = nums[0], p1 = nums[1], p2 = nums[2];
    if (p0.length == 4) {
      // YYYY-MM-DD (or the rare YYYY-DD-MM when the month part is above 12).
      if (p1.length > 2 || p2.length > 2) return null;
      final y = int.parse(p0);
      var m = int.parse(p1), d = int.parse(p2);
      if (m > 12 && d <= 12) (m, d) = (d, m);
      return _make(y, m, d);
    }
    if (p0.length > 2 || p1.length > 2) return null;
    final y = _year(p2);
    if (y < 0) return null;
    var d = int.parse(p0), m = int.parse(p1);
    if (m > 12 && d <= 12) (m, d) = (d, m); // month-first entry
    return _make(y, m, d);
  }

  /// 6 digits = DDMMYY, 8 digits = DDMMYYYY (else YYYYMMDD).
  static DateTime? _packedDigits(String s) {
    int at(int a, int b) => int.parse(s.substring(a, b));
    if (s.length == 6) return _make(_year(s.substring(4)), at(2, 4), at(0, 2));
    if (s.length == 8) {
      return _make(at(4, 8), at(2, 4), at(0, 2)) ?? _make(at(0, 4), at(4, 6), at(6, 8));
    }
    return null;
  }
}
