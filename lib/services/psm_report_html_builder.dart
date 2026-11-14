import 'dart:convert';

import 'datewise_report_columns.dart';

/// Builds the browser-native print layout used on Flutter Web.
/// Chrome shapes Gujarati/Indic text through its browser text engine, unlike
/// the current `pdf` package's direct codepoint-to-glyph table renderer.
class PsmReportHtmlBuilder {
  static const String _signature = 'વર્ગ શિક્ષકની સહી';

  static String build({
    required String filename,
    required String schoolName,
    required String schoolAddress,
    required String title,
    required String periodLabel,
    required String dateLabel,
    required String weekdayLabel,
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final hasSignature = headers.isNotEmpty && headers.last.trim() == _signature;
    final firstHeader = headers.isEmpty ? 'વર્ગ' : headers.first;
    final metricHeaders = headers.length <= 1
        ? <String>[]
        : headers.sublist(1, headers.length - (hasSignature ? 1 : 0));
    final mappedColumns = metricHeaders.map(_findColumn).toList();
    final grouped = (firstHeader.trim() == 'વર્ગ' || firstHeader.trim() == 'તારીખ') &&
        mappedColumns.isNotEmpty && mappedColumns.every((column) => column != null);
    final columns = mappedColumns.whereType<DateWiseReportColumn>().toList();

    final visibleMetricCount = grouped ? columns.length : (headers.length - 1 - (hasSignature ? 1 : 0)).clamp(0, 1000);
    final wide = visibleMetricCount > 24;
    final headerFontSize = visibleMetricCount > 48 ? 5.4 : visibleMetricCount > 28 ? 6.3 : visibleMetricCount > 15 ? 7.2 : 8.5;
    final bodyFontSize = visibleMetricCount > 48 ? 6.4 : visibleMetricCount > 28 ? 7.1 : visibleMetricCount > 15 ? 8.0 : 9.0;
    final pageSize = wide ? 'A3 landscape' : 'A4 landscape';
    final firstWidth = grouped ? 7.5 : 12.0;
    final signatureWidth = hasSignature ? 6.0 : 0.0;
    final remainingWidth = (100.0 - firstWidth - signatureWidth).clamp(1.0, 100.0);
    final dataColCount = (headers.length - 1 - (hasSignature ? 1 : 0)).clamp(1, 1000);
    final dataWidth = remainingWidth / dataColCount;

    final out = StringBuffer();
    out.write('<!doctype html><html lang="gu"><head><meta charset="utf-8">');
    out.write('<meta name="viewport" content="width=device-width,initial-scale=1">');
    out.write('<title>${_e(filename)}</title>');
    out.write('<style>');
    out.write('@page{size:$pageSize;margin:7mm;}');
    out.write('html,body{margin:0;padding:0;color:#111;background:#fff;}');
    out.write('body{font-family:"Nirmala UI","Noto Sans Gujarati","Shruti",sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact;}');
    out.write('.school{text-align:center;font-size:16pt;font-weight:700;line-height:1.25;margin:0 0 1.5mm;}');
    out.write('.address{text-align:center;font-size:9.5pt;line-height:1.2;margin:0 0 1.5mm;min-height:4mm;}');
    out.write('.title{text-align:center;font-size:12pt;font-weight:700;line-height:1.25;margin:0 0 2mm;}');
    out.write('.meta{display:flex;flex-wrap:wrap;justify-content:space-between;gap:2mm 8mm;font-size:8.5pt;margin:0 0 2mm;}');
    out.write('table{width:100%;border-collapse:collapse;table-layout:fixed;}');
    out.write('thead{display:table-header-group;}tfoot{display:table-footer-group;}');
    out.write('tr{break-inside:avoid;page-break-inside:avoid;}');
    out.write('th,td{border:.35pt solid #555;box-sizing:border-box;padding:1.1px .8px;vertical-align:middle;overflow-wrap:anywhere;word-break:normal;white-space:normal;line-height:1.05;}');
    out.write('th{background:#e7e7e7;text-align:center;font-size:${headerFontSize}pt;font-weight:700;}');
    out.write('td{font-size:${bodyFontSize}pt;text-align:center;}td.label{text-align:left;}');
    out.write('th[rowspan]{vertical-align:middle;}');
    out.write('.sign{text-align:center;margin-top:3mm;font-size:8.5pt;}');
    out.write('.note{font-size:7pt;margin-top:2mm;color:#333;}');
    out.write('</style></head><body>');
    out.write('<header>');
    out.write('<div class="school">${_e(schoolName.isEmpty ? 'શાળા' : schoolName)}</div>');
    out.write('<div class="address">શાળાનું સરનામું: ${_e(schoolAddress.trim().isEmpty ? '________________________________________' : schoolAddress.trim())}</div>');
    out.write('<div class="title">${_e(title)}</div>');
    out.write('<div class="meta">');
    if (dateLabel.trim().isNotEmpty) out.write('<span>તારીખ: ${_e(dateLabel)}</span>');
    if (weekdayLabel.trim().isNotEmpty) out.write('<span>વાર: ${_e(weekdayLabel)}</span>');
    if (periodLabel.trim().isNotEmpty) out.write('<span>${_e(periodLabel)}</span>');
    out.write('</div></header>');

    out.write('<table><colgroup>');
    out.write('<col style="width:${firstWidth.toStringAsFixed(2)}%">');
    for (var i = 0; i < dataColCount; i++) {
      out.write('<col style="width:${dataWidth.toStringAsFixed(4)}%">');
    }
    if (hasSignature) out.write('<col style="width:${signatureWidth.toStringAsFixed(2)}%">');
    out.write('</colgroup><thead>');

    if (grouped) {
      out.write('<tr><th rowspan="3">${_e(firstHeader)}</th>');
      for (final metricGroup in _groupByMetric(columns)) {
        out.write('<th colspan="${metricGroup.length}">${_e(_metricTitle(metricGroup.first.metric))}</th>');
      }
      if (hasSignature) out.write('<th rowspan="3">${_e(_signature)}</th>');
      out.write('</tr><tr>');
      for (final metricGroup in _groupByMetric(columns)) {
        for (final categoryGroup in _groupByCategory(metricGroup)) {
          out.write('<th colspan="${categoryGroup.length}">${_e(_categoryTitle(categoryGroup.first.category))}</th>');
        }
      }
      out.write('</tr><tr>');
      for (final column in columns) {
        out.write('<th>${_e(_genderTitle(column.gender))}</th>');
      }
      out.write('</tr>');
    } else {
      out.write('<tr>');
      for (final header in headers) {
        out.write('<th>${_e(header)}</th>');
      }
      out.write('</tr>');
    }

    out.write('</thead><tbody>');
    for (final row in rows) {
      out.write('<tr>');
      for (var index = 0; index < headers.length; index++) {
        final value = index < row.length ? row[index] : '';
        out.write('<td class="${index == 0 ? 'label' : 'value'}">${_e(value)}</td>');
      }
      out.write('</tr>');
    }
    out.write('</tbody></table>');
    out.write('<div class="sign">વર્ગ શિક્ષકની સહી: ______________________________________________</div>');
    out.write('</body></html>');
    return out.toString();
  }

  static DateWiseReportColumn? _findColumn(String label) {
    for (final column in DateWiseReportColumn.all) {
      if (column.label.trim() == label.trim()) return column;
    }
    return null;
  }

  static List<List<DateWiseReportColumn>> _groupByMetric(List<DateWiseReportColumn> columns) {
    final groups = <List<DateWiseReportColumn>>[];
    for (final column in columns) {
      if (groups.isEmpty || groups.last.first.metric != column.metric) {
        groups.add(<DateWiseReportColumn>[column]);
      } else {
        groups.last.add(column);
      }
    }
    return groups;
  }

  static List<List<DateWiseReportColumn>> _groupByCategory(List<DateWiseReportColumn> columns) {
    final groups = <List<DateWiseReportColumn>>[];
    for (final column in columns) {
      if (groups.isEmpty || groups.last.first.category != column.category) {
        groups.add(<DateWiseReportColumn>[column]);
      } else {
        groups.last.add(column);
      }
    }
    return groups;
  }

  static String _metricTitle(String metric) => switch (metric) {
        'registered' => 'રજીસ્ટરર્ડ વિદ્યાર્થીઓની સંખ્યા',
        'present' => 'હાજર વિદ્યાર્થીઓની સંખ્યા',
        'mdm' => 'પીએમ પોષણ યોજનામાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા',
        'breakfast' => 'સીએમ અલ્પાહાર યોજનામાં ભાગ લીધેલ વિદ્યાર્થીઓની સંખ્યા',
        _ => metric,
      };

  static String _categoryTitle(String category) => switch (category) {
        'SC' => 'અ. જા.',
        'ST' => 'અ. જ. જા.',
        'OBC' => 'બક્ષીપંચ',
        'OTHER' => 'અન્ય',
        'CATEGORY_TOTAL' => 'કુલ',
        _ => category,
      };

  static String _genderTitle(String gender) => switch (gender) {
        'BOYS' => 'કુમાર',
        'GIRLS' => 'કન્યા',
        'TOTAL' => 'કુલ',
        _ => gender,
      };

  static String _e(String value) => const HtmlEscape(HtmlEscapeMode.element).convert(value);
}
