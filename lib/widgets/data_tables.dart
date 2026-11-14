import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';

const double _colLabel = 118;
const double _colCat = 46;
const double _colTotal = 58;
const double _colBf = 72;
double get _groupWidth => _colCat * 4 + _colTotal;

class StatsRow {
  final String label;
  final AttendanceRecord? record;
  final bool highlight;
  const StatsRow(this.label, this.record, {this.highlight = false});
}

/// Grouped table: Label | હાજર(SC,ST,OBC,અન્ય,કુલ) | પીએમ પોષણ(...) | અલ્પાહાર
/// Used by both the History tab (rows = dates) and Daily Summary tab
/// (rows = classes). Horizontally + vertically scrollable, matching
/// the original's `.table-wrap { overflow-x:auto }`.
class AttendanceStatsTable extends StatelessWidget {
  final String firstColumnLabel;
  final List<StatsRow> rows;
  const AttendanceStatsTable({super.key, required this.firstColumnLabel, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupHeaderRow(),
            _subHeaderRow(),
            for (int i = 0; i < rows.length; i++) _bodyRow(rows[i], i),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, double width, {Color? bg, Color? fg, FontWeight? weight, double fontSize = 11}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      alignment: Alignment.center,
      color: bg,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: guFont(fontSize: fontSize, fontWeight: weight ?? FontWeight.w700, color: fg ?? AppColors.navy),
      ),
    );
  }

  Widget _groupHeaderRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell(firstColumnLabel, _colLabel, bg: AppColors.navy, fg: Colors.white, weight: FontWeight.w800, fontSize: 11),
        _cell('✅ હાજર', _groupWidth, bg: AppColors.navy, fg: Colors.white, weight: FontWeight.w800),
        _cell('🍽️ પીએમ પોષણ', _groupWidth, bg: AppColors.navy, fg: Colors.white, weight: FontWeight.w800),
        _cell('🥐 અલ્પાહાર', _colBf, bg: AppColors.navy, fg: Colors.white, weight: FontWeight.w800),
      ],
    );
  }

  Widget _subHeaderRow() {
    const subBg = Color(0xFF1E3460);
    const subFg = Color(0xFFCBD5E1);
    Widget sub(String t, double w) => _cell(t, w, bg: subBg, fg: subFg, weight: FontWeight.w700, fontSize: 10);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell('', _colLabel, bg: subBg),
        sub('SC', _colCat),
        sub('ST', _colCat),
        sub('OBC', _colCat),
        sub('અન્ય', _colCat),
        sub('કુલ', _colTotal),
        sub('SC', _colCat),
        sub('ST', _colCat),
        sub('OBC', _colCat),
        sub('અન્ય', _colCat),
        sub('કુલ', _colTotal),
        _cell('', _colBf, bg: subBg),
      ],
    );
  }

  Widget _bodyRow(StatsRow row, int index) {
    final rec = row.record;
    final zebra = index.isOdd ? const Color(0xFFF8FAFC) : Colors.white;
    final bg = row.highlight ? const Color(0xFFFFF8E7) : zebra;
    Widget num(int? v, {bool totalCol = false}) => _cell(
          v == null ? '—' : '$v',
          totalCol ? _colTotal : _colCat,
          bg: totalCol ? const Color(0xFFF0FDF4) : bg,
          fg: totalCol ? AppColors.teal : AppColors.navy,
          weight: totalCol ? FontWeight.w900 : FontWeight.w700,
          fontSize: 12,
        );
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: const Color(0xFFF1F5F9)))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _colLabel,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            color: bg,
            alignment: Alignment.center,
            child: Text(
              row.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: guFont(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
          ),
          num(rec?.present[Category.sc]),
          num(rec?.present[Category.st]),
          num(rec?.present[Category.obc]),
          num(rec?.present[Category.other]),
          num(rec?.present.total, totalCol: true),
          num(rec?.mdm[Category.sc]),
          num(rec?.mdm[Category.st]),
          num(rec?.mdm[Category.obc]),
          num(rec?.mdm[Category.other]),
          num(rec?.mdm.total, totalCol: true),
          Container(
            width: _colBf,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            color: bg,
            alignment: Alignment.center,
            child: Text(
              rec == null ? '—' : '${rec.breakfastTotal}',
              style: guFont(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a raw 2D string grid returned by the backend as-is (used for
/// the DATE WISE report `values`, and TARIJ `headers` + `row`). No
/// column typing is assumed since these come straight from a live
/// Google Sheet via getDisplayValues().
class RawGridTable extends StatelessWidget {
  final List<List<String>> rows;
  final int headerRows;
  const RawGridTable({super.key, required this.rows, this.headerRows = 1});

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int r = 0; r < rows.length; r++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int c = 0; c < colCount; c++)
                    Container(
                      width: 92,
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                      alignment: Alignment.center,
                      color: r < headerRows ? AppColors.navy : (r.isOdd ? const Color(0xFFF8FAFC) : Colors.white),
                      child: Text(
                        c < rows[r].length ? rows[r][c] : '',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: guFont(
                          fontSize: 11.5,
                          fontWeight: r < headerRows ? FontWeight.w800 : FontWeight.w600,
                          color: r < headerRows ? Colors.white : AppColors.navy,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}


// ============================================================
// DAILY SUMMARY (all classes) — Registered + Present + PM-Poshan +
// Breakfast, with the group subtotal rows (TOTAL 1-5 / BV-5 / 6-8 /
// 1-8 / BV-8) exactly like the original website's loadSummary().
// ============================================================

const double _sCat = 34;
const double _sTot = 46;
const double _sBf = 54;
const double _sLabel = 120;
double get _sGroup => _sCat * 4 + _sTot;

/// One row of the daily summary: a single class OR a highlighted
/// subtotal (`isSubtotal`).
class SummaryRow {
  final String label;
  final CategoryCounts reg;
  final CategoryCounts present;
  final CategoryCounts mdm;
  final int bf;
  final bool isSubtotal;
  const SummaryRow({
    required this.label,
    required this.reg,
    required this.present,
    required this.mdm,
    required this.bf,
    this.isSubtotal = false,
  });
}

class SummaryReportTable extends StatelessWidget {
  final List<SummaryRow> rows;
  const SummaryReportTable({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _groupHeader(),
            _subHeader(),
            for (int i = 0; i < rows.length; i++) _bodyRow(rows[i], i),
          ],
        ),
      ),
    );
  }

  Widget _cell(String text, double width,
      {Color? bg, Color? fg, FontWeight? weight, double fontSize = 10}) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
      alignment: Alignment.center,
      color: bg,
      child: Text(
        text,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: guFont(fontSize: fontSize, fontWeight: weight ?? FontWeight.w700, color: fg ?? AppColors.navy),
      ),
    );
  }

  Widget _groupHeader() {
    const regBg = Color(0xFF1E3A8A);
    const presBg = Color(0xFF166534);
    const mdmBg = Color(0xFF854D0E);
    const bfBg = Color(0xFF0F766E);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell('ધોરણ', _sLabel, bg: AppColors.navy, fg: Colors.white, weight: FontWeight.w800, fontSize: 11),
        _cell('રજિસ્ટર્ડ', _sGroup, bg: regBg, fg: Colors.white, weight: FontWeight.w800, fontSize: 11),
        _cell('હાજર', _sGroup, bg: presBg, fg: Colors.white, weight: FontWeight.w800, fontSize: 11),
        _cell('પીએમ પોષણ', _sGroup, bg: mdmBg, fg: Colors.white, weight: FontWeight.w800, fontSize: 11),
        _cell('અલ્પાહાર', _sBf, bg: bfBg, fg: Colors.white, weight: FontWeight.w800, fontSize: 10),
      ],
    );
  }

  Widget _subHeader() {
    const bg = Color(0xFFF1F5F9);
    Widget h(String t, double w) => _cell(t, w, bg: bg, fg: AppColors.navy, weight: FontWeight.w700, fontSize: 9.5);
    Widget group() => Row(mainAxisSize: MainAxisSize.min, children: [
          h('અ.જા.', _sCat), h('અ.જ.જા.', _sCat), h('બક્ષી', _sCat), h('અન્ય', _sCat), h('કુલ', _sTot),
        ]);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _cell('', _sLabel, bg: bg),
        group(),
        group(),
        group(),
        _cell('', _sBf, bg: bg),
      ],
    );
  }

  Widget _bodyRow(SummaryRow row, int index) {
    final zebra = index.isOdd ? const Color(0xFFF8FAFC) : Colors.white;
    final bg = row.isSubtotal ? const Color(0xFFFFF8E7) : zebra;
    final weight = row.isSubtotal ? FontWeight.w900 : FontWeight.w700;

    Widget num(int v, {bool totalCol = false}) => _cell(
          '$v',
          totalCol ? _sTot : _sCat,
          bg: totalCol ? const Color(0xFFF0FDF4) : bg,
          fg: totalCol ? AppColors.teal : AppColors.navy,
          weight: totalCol ? FontWeight.w900 : weight,
          fontSize: 11,
        );

    Widget block(CategoryCounts c) => Row(mainAxisSize: MainAxisSize.min, children: [
          num(c[Category.sc]),
          num(c[Category.st]),
          num(c[Category.obc]),
          num(c[Category.other]),
          num(c.total, totalCol: true),
        ]);

    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: _sLabel,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
            color: row.isSubtotal ? const Color(0xFFE2E8F0) : bg,
            alignment: Alignment.centerLeft,
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: guFont(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.navy),
            ),
          ),
          block(row.reg),
          block(row.present),
          block(row.mdm),
          Container(
            width: _sBf,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
            color: const Color(0xFFF0FDF4),
            alignment: Alignment.center,
            child: Text('${row.bf}', style: guFont(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.teal)),
          ),
        ],
      ),
    );
  }
}

/// One line in a category-by-gender report. Gender totals are read only from
/// explicit saved splits. Legacy totals are retained, but are not guessed into
/// Boys or Girls.
class GenderMetricRow {
  final String label;
  final CategoryCounts registered;
  final CategoryCounts present;
  final CategoryCounts mdm;
  final int breakfastTotal;
  final Map<String, dynamic> genderBreakdown;
  final bool highlight;
  final bool isSubtotal;

  const GenderMetricRow({
    required this.label,
    required this.registered,
    required this.present,
    required this.mdm,
    required this.breakfastTotal,
    this.genderBreakdown = const <String, dynamic>{},
    this.highlight = false,
    this.isSubtotal = false,
  });
}

/// Grouped table: each category contains Boys / Girls / Total, and the final
/// group repeats the school/class total. Totals include legacy unassigned values
/// when the original record has them; a note makes that exception visible.
class GenderCategoryMetricTable extends StatelessWidget {
  final String title;
  final String metric; // registered | present | mdm | breakfast
  final List<GenderMetricRow> rows;

  /// Co-ed report preference:
  /// true  -> each category shows Boys / Girls / Total.
  /// false -> each category shows Boys / Girls only.
  /// The final overall કુલ group ALWAYS shows Boys / Girls / Total.
  final bool showCategoryTotal;

  const GenderCategoryMetricTable({
    super.key,
    required this.title,
    required this.metric,
    required this.rows,
    this.showCategoryTotal = true,
  });

  static const List<Category> _categories = Category.values;
  static const double _labelWidth = 122;
  static const double _genderWidth = 48;
  static const double _totalWidth = 52;

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic>? _categoryGender(GenderMetricRow row, String gender, Category category) {
    final gm = row.genderBreakdown[gender];
    if (gm is! Map) return null;
    final cm = gm[category.apiKey];
    if (cm is! Map) return null;
    return cm.cast<String, dynamic>();
  }

  int? _value(GenderMetricRow row, String gender, Category category) {
    final map = _categoryGender(row, gender, category);
    if (map == null || !map.containsKey(metric)) return null;
    return _asInt(map[metric]);
  }

  int? _overallValue(GenderMetricRow row, String gender) {
    final group = row.genderBreakdown[gender];
    if (group is! Map) return null;
    final overall = group['_OVERALL'];
    if (overall is! Map || !overall.containsKey(metric)) return null;
    return _asInt(overall[metric]);
  }

  bool _hasAnyBreakdown(GenderMetricRow row) {
    for (final category in _categories) {
      if (_categoryGender(row, 'BOYS', category) != null ||
          _categoryGender(row, 'GIRLS', category) != null ||
          _categoryGender(row, 'UNSPECIFIED', category) != null) return true;
    }
    return false;
  }

  CategoryCounts _sourceCounts(GenderMetricRow row) {
    switch (metric) {
      case 'registered': return row.registered;
      case 'present': return row.present;
      case 'mdm': return row.mdm;
      default: return CategoryCounts();
    }
  }

  int _legacyTotal(GenderMetricRow row, Category category) {
    switch (metric) {
      case 'registered': return row.registered[category];
      case 'present': return row.present[category];
      case 'mdm': return row.mdm[category];
      default: return 0;
    }
  }

  ({int? boys, int? girls, int? total, int unassigned}) _cellValues(GenderMetricRow row, Category? category) {
    final official = category == null
        ? (metric == 'breakfast' ? row.breakfastTotal : _sourceCounts(row).total)
        : (metric == 'breakfast' ? 0 : _legacyTotal(row, category));

    if (category == null) {
      // Legacy sheets stored breakfast only as a whole-class total. When the
      // backend can safely map that historic total to a single-sex school, show
      // it in the overall row while leaving category-level breakfast blank.
      if (metric == 'breakfast') {
        final overallBoys = _overallValue(row, 'BOYS');
        final overallGirls = _overallValue(row, 'GIRLS');
        final overallUnknown = _overallValue(row, 'UNSPECIFIED');
        if (overallBoys != null || overallGirls != null) {
          final boys = overallBoys ?? 0;
          final girls = overallGirls ?? 0;
          final knownTotal = boys + girls;
          final notAssigned = (official - knownTotal).clamp(0, official).toInt();
          return (boys: boys, girls: girls, total: knownTotal, unassigned: overallUnknown != null && overallUnknown > notAssigned ? overallUnknown : notAssigned);
        }
        if (overallUnknown != null) {
          return (boys: null, girls: null, total: official, unassigned: official > overallUnknown ? official : overallUnknown);
        }
      }
      var boys = 0, girls = 0, explicitUnknown = 0;
      var hasGenderSplit = false;
      for (final cat in _categories) {
        final b = _value(row, 'BOYS', cat);
        final g = _value(row, 'GIRLS', cat);
        final u = _value(row, 'UNSPECIFIED', cat);
        if (b != null || g != null) hasGenderSplit = true;
        boys += b ?? 0;
        girls += g ?? 0;
        explicitUnknown += u ?? 0;
      }
      if (!hasGenderSplit) {
        // Historical aggregate-only data cannot be truthfully divided by gender.
        // Retain its original total and show Boys/Girls as unavailable.
        return (boys: null, girls: null, total: official, unassigned: official);
      }
      final knownTotal = boys + girls;
      final totalUnassigned = metric == 'breakfast'
          ? (row.breakfastTotal - knownTotal).clamp(0, row.breakfastTotal).toInt()
          : (official - knownTotal).clamp(0, official).toInt();
      // For fully classified data, Total is exactly Boys + Girls. Legacy unknowns
      // remain visible in the note instead of silently breaking that invariant.
      return (boys: boys, girls: girls, total: knownTotal, unassigned: totalUnassigned > explicitUnknown ? totalUnassigned : explicitUnknown);
    }

    if (metric == 'breakfast') {
      // The class-sheet schema stores Breakfast as an overall Boys/Girls/Total group only.
      return (boys: null, girls: null, total: null, unassigned: 0);
    }
    final b = _value(row, 'BOYS', category);
    final g = _value(row, 'GIRLS', category);
    final u = _value(row, 'UNSPECIFIED', category);
    final hasGenderSplit = b != null || g != null;
    if (!hasGenderSplit) {
      return (boys: null, girls: null, total: official, unassigned: official);
    }
    final boys = b ?? 0;
    final girls = g ?? 0;
    final knownTotal = boys + girls;
    final unassigned = metric == 'breakfast'
        ? (u ?? 0)
        : (official - knownTotal).clamp(0, official).toInt();
    final explicitUnknown = u ?? 0;
    return (boys: boys, girls: girls, total: knownTotal, unassigned: unassigned > explicitUnknown ? unassigned : explicitUnknown);
  }

  Widget _tableCell(String text, double width, {Color? bg, Color? fg, FontWeight weight = FontWeight.w700, double fontSize = 10}) {
    return Container(
      width: width,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
      decoration: BoxDecoration(color: bg, border: Border.all(color: AppColors.border, width: 0.5)),
      child: Text(text, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
        style: guFont(fontSize: fontSize, fontWeight: weight, color: fg ?? AppColors.navy)),
    );
  }

  double get _categoryGroupWidth =>
      _genderWidth * 2 + (showCategoryTotal ? _totalWidth : 0);

  Widget _groupCell(String text, double width) => Container(
    width: width,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 3),
    decoration: BoxDecoration(color: AppColors.navy, border: Border.all(color: Colors.white, width: 0.5)),
    child: Text(text, textAlign: TextAlign.center, style: guFont(fontSize: 10, fontWeight: FontWeight.w900, color: Colors.white)),
  );

  Widget _subHeader(String text, double width, {bool total = false}) => _tableCell(text, width,
    bg: total ? const Color(0xFFE6F7EF) : const Color(0xFFE2E8F0),
    fg: total ? AppColors.teal : AppColors.navy, weight: FontWeight.w800, fontSize: 9);

  @override
  Widget build(BuildContext context) {
    final hasUnassigned = rows.any((r) => _categories.any((c) => _cellValues(r, c).unassigned > 0) || _cellValues(r, null).unassigned > 0);
    final hasLegacyOverallBreakfast = metric == 'breakfast' && rows.any((r) =>
      _overallValue(r, 'BOYS') != null || _overallValue(r, 'GIRLS') != null || _overallValue(r, 'UNSPECIFIED') != null);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9), color: AppColors.navyMid,
          child: Text(title, style: guFont(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white))),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            _tableCell('વર્ગ', _labelWidth, bg: AppColors.navy, fg: Colors.white, weight: FontWeight.w900),
            for (final c in _categories) _groupCell(c.shortLabel, _categoryGroupWidth),
            // IMPORTANT: overall TOTAL always remains Boys / Girls / Total.
            _groupCell('કુલ', _genderWidth * 2 + _totalWidth),
          ]),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _subHeader('', _labelWidth),
            for (int i = 0; i < _categories.length; i++) ...[
              _subHeader('BOYS', _genderWidth),
              _subHeader('GIRLS', _genderWidth),
              if (showCategoryTotal) _subHeader('TOTAL', _totalWidth, total: true),
            ],
            _subHeader('BOYS', _genderWidth),
            _subHeader('GIRLS', _genderWidth),
            _subHeader('TOTAL', _totalWidth, total: true),
          ]),
          for (int index = 0; index < rows.length; index++) _buildRow(rows[index], index),
        ])),
        if (hasUnassigned)
          Padding(padding: const EdgeInsets.fromLTRB(10, 7, 10, 9), child: Text(
            'નોંધ: Boys + Girls = Total. જૂના/અપૂર્ણ રેકોર્ડમાં લિંગ નોંધાયેલ ન હોય તે ગણતરી Totalમાં ઉમેર્યા વગર અલગ બાકી રહે છે; બાકી લિંગ નોંધવાથી જ સંપૂર્ણ સરવાળો મળશે.',
            style: guFont(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepOrange.shade800))),
        if (hasLegacyOverallBreakfast)
          Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 9), child: Text(
            'જૂના રેકોર્ડમાં અલ્પાહારનો કુલ આંકડો ઉપલબ્ધ છે, પરંતુ કેટેગરી પ્રમાણે અલ્પાહારનું વિભાજન ઉપલબ્ધ નથી.',
            style: guFont(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.deepOrange.shade800))),
      ]),
    );
  }

  Widget _buildRow(GenderMetricRow row, int index) {
    final bg = row.isSubtotal ? const Color(0xFFFFF4D6) : (index.isOdd ? const Color(0xFFF8FAFC) : Colors.white);
    Widget value(int? n, double width, {bool total = false}) => _tableCell(n == null ? '-' : '$n', width,
      bg: total ? const Color(0xFFE6F7EF) : bg,
      fg: total ? AppColors.teal : AppColors.navy,
      weight: total || row.isSubtotal ? FontWeight.w900 : FontWeight.w600,
      fontSize: 10);
    final cells = <Widget>[_tableCell(row.label, _labelWidth, bg: bg, weight: FontWeight.w800, fontSize: 10)];
    for (final category in _categories) {
      final v = _cellValues(row, category);
      cells.add(value(v.boys, _genderWidth));
      cells.add(value(v.girls, _genderWidth));
      if (showCategoryTotal) {
        cells.add(value(v.total, _totalWidth, total: true));
      }
    }

    // Overall TOTAL is always B / G / T.
    final overall = _cellValues(row, null);
    cells.add(value(overall.boys, _genderWidth));
    cells.add(value(overall.girls, _genderWidth));
    cells.add(value(overall.total, _totalWidth, total: true));
    return Row(mainAxisSize: MainAxisSize.min, children: cells);
  }

} // End of GenderCategoryMetricTable

