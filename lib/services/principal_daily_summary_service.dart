import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'package:universal_html/html.dart' as html;
import 'package:url_launcher/url_launcher.dart';

import 'school_type.dart';

/// Builds a One-Page "Today at a Glance" Principal Summary (Category-wise,
/// with Boys & Girls category-wise breakdown for mixed schools + Teachers on
/// leave with In-Charge teachers) for WhatsApp (CRC/BRC) and A4 Print / PDF.
class PrincipalDailySummaryService {
  PrincipalDailySummaryService._();

  static const List<String> _cats = <String>['SC', 'ST', 'OBC', 'OTHER'];

  static String _normCat(dynamic raw) {
    final s = '${raw ?? ''}'.trim().toUpperCase();
    if (s == 'SC' || s.contains('અનુ.જાતિ') || s.contains('અનુસૂચિત જાતિ')) {
      return 'SC';
    }
    if (s == 'ST' || s.contains('અનુ.જનજાતિ') || s.contains('અનુસૂચિત જનજાતિ')) {
      return 'ST';
    }
    if (s == 'OBC' || s == 'SEBC' || s.contains('બક્ષીપંચ') || s.contains('સા.શૈ.પ.')) {
      return 'OBC';
    }
    return 'OTHER';
  }

  static bool _isGirl(dynamic raw) {
    final s = '${raw ?? ''}'.trim().toLowerCase();
    return s == 'f' ||
        s == 'female' ||
        s == 'girl' ||
        s == 'girls' ||
        s.contains('કન્યા') ||
        s.contains('છોકરી');
  }

  static int _int(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim()) ?? 0;
  }

  static Future<void> openSummaryDialog(
    BuildContext context, {
    required String schoolRef,
    required String schoolName,
    required String schoolType,
    required DateTime date,
  }) async {
    final client = Supabase.instance.client;
    final dateIso =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final dateDmy = DateFormat('dd-MM-yyyy').format(date);
    final isMixed = SchoolType.canonical(schoolType) == 'mixed';

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Expanded(child: Text('આજનો સારાંશ (Category-wise & Leave) તૈયાર થાય છે…')),
          ],
        ),
      ),
    );

    try {
      final results = await Future.wait<dynamic>([
        client
            .from('students')
            .select('id,class_id,gender,category,is_active,leaving_date,exit_date')
            .eq('school_ref', schoolRef)
            .eq('is_active', true),
        client
            .from('attendance_days')
            .select('id,class_id,attendance_date,attendance_mode,present_saved,mdm_saved,breakfast_saved,gender_breakdown,breakfast_total,student_marks')
            .eq('school_ref', schoolRef)
            .eq('attendance_date', dateIso),
        client.rpc('psm_school_active_leave_charges'),
      ]);

      final rawStudents = (results[0] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .where(
            (s) =>
                s['is_active'] == true &&
                '${s['leaving_date'] ?? ''}'.trim().isEmpty &&
                '${s['exit_date'] ?? ''}'.trim().isEmpty,
          )
          .toList();
      final rawDays = (results[1] as List)
          .whereType<Map>()
          .map((m) => m.map((k, v) => MapEntry('$k', v)))
          .toList();
      final rawLeaves = results[2] is List
          ? (results[2] as List)
              .whereType<Map>()
              .map((m) => m.map((k, v) => MapEntry('$k', v)))
              .where((l) {
                final s = '${l['start_date'] ?? ''}'.trim();
                final e = '${l['end_date'] ?? s}'.trim();
                return s.isNotEmpty &&
                    dateIso.compareTo(s) >= 0 &&
                    dateIso.compareTo(e) <= 0;
              })
              .toList()
          : <Map<String, dynamic>>[];

      // Accumulators: metric -> gender ('B'|'G') -> cat ('SC'|'ST'|'OBC'|'OTHER') -> int
      Map<String, Map<String, Map<String, int>>> initMetrics() {
        final out = <String, Map<String, Map<String, int>>>{};
        for (final m in const ['reg', 'pres', 'abs', 'mdm', 'bf']) {
          out[m] = <String, Map<String, int>>{
            'B': <String, int>{for (final c in _cats) c: 0},
            'G': <String, int>{for (final c in _cats) c: 0},
          };
        }
        return out;
      }

      final metrics = initMetrics();
      final studentById = <String, Map<String, dynamic>>{};
      final studentsByClass = <String, List<Map<String, dynamic>>>{};

      for (final st in rawStudents) {
        final sid = '${st['id'] ?? ''}'.trim();
        final cid = '${st['class_id'] ?? ''}'.trim();
        final g = _isGirl(st['gender']) ? 'G' : 'B';
        final cat = _normCat(st['category']);
        studentById[sid] = st;
        studentsByClass.putIfAbsent(cid, () => <Map<String, dynamic>>[]).add(st);
        metrics['reg']![g]![cat] = (metrics['reg']![g]![cat] ?? 0) + 1;
      }

      for (final d in rawDays) {
        final cid = '${d['class_id'] ?? ''}'.trim();
        final mode = '${d['attendance_mode'] ?? 'student'}'.trim().toLowerCase();
        final hasStudentMarks =
            mode != 'direct' && d['student_marks'] is Map && (d['student_marks'] as Map).isNotEmpty;

        if (hasStudentMarks) {
          final marks = d['student_marks'] as Map;
          final clsStudents = studentsByClass[cid] ?? const <Map<String, dynamic>>[];
          for (final st in clsStudents) {
            final sid = '${st['id'] ?? ''}'.trim();
            final m = marks[sid];
            if (m is! Map) continue;
            final g = _isGirl(st['gender']) ? 'G' : 'B';
            final cat = _normCat(st['category']);
            if (d['present_saved'] != false) {
              if (m['present'] == true) {
                metrics['pres']![g]![cat] = (metrics['pres']![g]![cat] ?? 0) + 1;
              } else {
                metrics['abs']![g]![cat] = (metrics['abs']![g]![cat] ?? 0) + 1;
              }
            }
            if (d['mdm_saved'] != false && m['mdm'] == true) {
              metrics['mdm']![g]![cat] = (metrics['mdm']![g]![cat] ?? 0) + 1;
            }
            if (d['breakfast_saved'] != false && m['breakfast'] == true) {
              metrics['bf']![g]![cat] = (metrics['bf']![g]![cat] ?? 0) + 1;
            }
          }
        } else {
          // Direct entry or fallback using gender_breakdown
          final gb = d['gender_breakdown'] is Map
              ? Map<String, dynamic>.from(d['gender_breakdown'] as Map)
              : <String, dynamic>{};
          final catMap = gb['category_breakdown'] is Map
              ? Map<String, dynamic>.from(gb['category_breakdown'] as Map)
              : <String, dynamic>{};
          if (catMap.isNotEmpty) {
            for (final cat in _cats) {
              final cData = catMap[cat] is Map
                  ? Map<String, dynamic>.from(catMap[cat] as Map)
                  : <String, dynamic>{};
              for (final gKey in const [('B', 'boys'), ('G', 'girls')]) {
                final g = gKey.$1;
                final gName = gKey.$2;
                final pVal = _int(cData['present_$gName']);
                final mVal = _int(cData['mdm_$gName']);
                final bVal = _int(cData['breakfast_$gName']);
                metrics['pres']![g]![cat] = (metrics['pres']![g]![cat] ?? 0) + pVal;
                metrics['mdm']![g]![cat] = (metrics['mdm']![g]![cat] ?? 0) + mVal;
                metrics['bf']![g]![cat] = (metrics['bf']![g]![cat] ?? 0) + bVal;
              }
            }
          } else {
            final pb = _int(gb['present_boys']);
            final pg = _int(gb['present_girls']);
            final mb = _int(gb['mdm_boys']);
            final mg = _int(gb['mdm_girls']);
            final bb = _int(gb['breakfast_boys']);
            final bg = _int(gb['breakfast_girls']);
            metrics['pres']!['B']!['OTHER'] = (metrics['pres']!['B']!['OTHER'] ?? 0) + pb;
            metrics['pres']!['G']!['OTHER'] = (metrics['pres']!['G']!['OTHER'] ?? 0) + pg;
            metrics['mdm']!['B']!['OTHER'] = (metrics['mdm']!['B']!['OTHER'] ?? 0) + mb;
            metrics['mdm']!['G']!['OTHER'] = (metrics['mdm']!['G']!['OTHER'] ?? 0) + mg;
            metrics['bf']!['B']!['OTHER'] = (metrics['bf']!['B']!['OTHER'] ?? 0) + bb;
            metrics['bf']!['G']!['OTHER'] = (metrics['bf']!['G']!['OTHER'] ?? 0) + bg;
          }
        }
      }

      // Recompute absent cleanly = max(0, reg - pres) per gender & category
      for (final g in const ['B', 'G']) {
        for (final cat in _cats) {
          final r = metrics['reg']![g]![cat] ?? 0;
          final p = metrics['pres']![g]![cat] ?? 0;
          metrics['abs']![g]![cat] = (r - p).clamp(0, 999999);
        }
      }

      int sumCat(String m, String cat, {String? gender}) {
        if (gender != null) return metrics[m]![gender]![cat] ?? 0;
        return (metrics[m]!['B']![cat] ?? 0) + (metrics[m]!['G']![cat] ?? 0);
      }

      int sumMetric(String m, {String? gender}) {
        var total = 0;
        for (final c in _cats) {
          total += sumCat(m, c, gender: gender);
        }
        return total;
      }

      String formatRowLine(String label, String mKey, {String? gender}) {
        final sc = sumCat(mKey, 'SC', gender: gender);
        final st = sumCat(mKey, 'ST', gender: gender);
        final obc = sumCat(mKey, 'OBC', gender: gender);
        final oth = sumCat(mKey, 'OTHER', gender: gender);
        final tot = sumMetric(mKey, gender: gender);
        return '$label: SC $sc | ST $st | OBC $obc | Other $oth | *કુલ: $tot*';
      }

      final wa = StringBuffer()
        ..writeln('🏫 *$schoolName*')
        ..writeln('📅 *દૈનિક શાળા સારાંશ (Today at a Glance) — $dateDmy*')
        ..writeln('────────────────────');

      if (isMixed) {
        wa
          ..writeln('👦 *કુમાર (Boys) — કેટેગરી મુજબ:*')
          ..writeln('• ${formatRowLine('નોંધાયેલ', 'reg', gender: 'B')}')
          ..writeln('• ${formatRowLine('હાજર', 'pres', gender: 'B')}')
          ..writeln('• ${formatRowLine('ગેરહાજર', 'abs', gender: 'B')}')
          ..writeln('• ${formatRowLine('PM POSHAN', 'mdm', gender: 'B')}')
          ..writeln('• ${formatRowLine('અલ્પાહાર', 'bf', gender: 'B')}')
          ..writeln('')
          ..writeln('👧 *કન્યા (Girls) — કેટેગરી મુજબ:*')
          ..writeln('• ${formatRowLine('નોંધાયેલ', 'reg', gender: 'G')}')
          ..writeln('• ${formatRowLine('હાજર', 'pres', gender: 'G')}')
          ..writeln('• ${formatRowLine('ગેરહાજર', 'abs', gender: 'G')}')
          ..writeln('• ${formatRowLine('PM POSHAN', 'mdm', gender: 'G')}')
          ..writeln('• ${formatRowLine('અલ્પાહાર', 'bf', gender: 'G')}')
          ..writeln('');
      }

      wa
        ..writeln('📊 *કુલ શાળા (Total) — કેટેગરી મુજબ:*')
        ..writeln('• ${formatRowLine('નોંધાયેલ', 'reg')}')
        ..writeln('• ${formatRowLine('હાજર', 'pres')}')
        ..writeln('• ${formatRowLine('ગેરહાજર', 'abs')}')
        ..writeln('• ${formatRowLine('PM POSHAN', 'mdm')}')
        ..writeln('• ${formatRowLine('અલ્પાહાર', 'bf')}')
        ..writeln('────────────────────')
        ..writeln('👩‍🏫 *આજે રજા પર રહેલા શિક્ષકો:*');

      if (rawLeaves.isEmpty) {
        wa.writeln('• આજે તમામ શિક્ષકો હાજર છે (કોઈ શિક્ષક રજા પર નથી).');
      } else {
        for (var i = 0; i < rawLeaves.length; i++) {
          final l = rawLeaves[i];
          final tName = '${l['teacher_name'] ?? 'શિક્ષક'}'.trim();
          final tCls = '${l['teacher_class'] ?? ''}'.trim();
          final lType = '${l['leave_type'] ?? ''}'.trim();
          final cName = '${l['charge_teacher_name'] ?? '—'}'.trim();
          wa.writeln(
            '${i + 1}. $tName${tCls.isNotEmpty && tCls != '—' ? ' ($tCls)' : ''} — $lType | ચાર્જ: $cName',
          );
        }
      }

      final waText = wa.toString().trim();

      if (context.mounted) Navigator.of(context).pop();
      if (!context.mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.summarize_rounded, color: Color(0xFF0F766E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('આજનો શાળા સારાંશ (CRC/BRC) • $dateDmy'),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: SelectableText(
                waText,
                style: const TextStyle(fontSize: 13.5, height: 1.45),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('બંધ કરો'),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: waText));
                if (dialogCtx.mounted) {
                  ScaffoldMessenger.of(dialogCtx).showSnackBar(
                    const SnackBar(content: Text('સારાંશ કોપી થઈ ગયો છે.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('કોપી કરો'),
            ),
            OutlinedButton.icon(
              onPressed: () => _printA4HtmlSlip(
                schoolName: schoolName,
                dateDmy: dateDmy,
                isMixed: isMixed,
                metrics: metrics,
                leaves: rawLeaves,
              ),
              icon: const Icon(Icons.print_rounded, size: 18),
              label: const Text('A4 પ્રિન્ટ / PDF'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final uri = Uri.parse(
                  'https://wa.me/?text=${Uri.encodeComponent(waText)}',
                );
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.share_rounded, size: 18),
              label: const Text('WhatsApp શેર'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('સારાંશ તૈયાર કરવામાં ભૂલ: $e')),
        );
      }
    }
  }

  static void _printA4HtmlSlip({
    required String schoolName,
    required String dateDmy,
    required bool isMixed,
    required Map<String, Map<String, Map<String, int>>> metrics,
    required List<Map<String, dynamic>> leaves,
  }) {
    if (!kIsWeb) return;
    int val(String m, String c, {String? g}) => g != null
        ? (metrics[m]![g]![c] ?? 0)
        : ((metrics[m]!['B']![c] ?? 0) + (metrics[m]!['G']![c] ?? 0));
    int tot(String m, {String? g}) =>
        _cats.fold(0, (acc, c) => acc + val(m, c, g: g));

    String buildTable(String title, {String? g}) {
      const rows = <(String, String)>[
        ('કુલ નોંધાયેલ (Registered)', 'reg'),
        ('હાજર (Present)', 'pres'),
        ('ગેરહાજર (Absent)', 'abs'),
        ('PM POSHAN (મધ્યાહન ભોજન)', 'mdm'),
        ('અલ્પાહાર (Breakfast)', 'bf'),
      ];
      final sb = StringBuffer()
        ..writeln('<h3>$title</h3>')
        ..writeln('<table><thead><tr><th>વિગત</th><th>SC</th><th>ST</th><th>OBC</th><th>OTHER</th><th>કુલ</th></tr></thead><tbody>');
      for (final r in rows) {
        sb.writeln(
          '<tr><td style="text-align:left;font-weight:700">${r.$1}</td>'
          '<td>${val(r.$2, 'SC', g: g)}</td>'
          '<td>${val(r.$2, 'ST', g: g)}</td>'
          '<td>${val(r.$2, 'OBC', g: g)}</td>'
          '<td>${val(r.$2, 'OTHER', g: g)}</td>'
          '<td style="font-weight:800">${tot(r.$2, g: g)}</td></tr>',
        );
      }
      sb.writeln('</tbody></table>');
      return sb.toString();
    }

    final leaveRows = leaves.isEmpty
        ? '<tr><td colspan="4">આજે તમામ શિક્ષકો હાજર છે (કોઈ શિક્ષક રજા પર નથી).</td></tr>'
        : leaves.asMap().entries.map((e) {
            final l = e.value;
            return '<tr><td>${e.key + 1}</td><td>${l['teacher_name'] ?? ''} (${l['teacher_class'] ?? '—'})</td><td>${l['leave_type'] ?? ''}</td><td>${l['charge_teacher_name'] ?? '—'}</td></tr>';
          }).join();

    final docHtml = '''
<!DOCTYPE html>
<html lang="gu"><head><meta charset="utf-8"><title>Daily Summary - $dateDmy</title>
<style>
  @page { size: A4 portrait; margin: 12mm; }
  body { font-family: "Noto Sans Gujarati", Arial, sans-serif; color: #111; font-size: 12.5px; }
  h1 { text-align: center; font-size: 18px; margin: 0 0 4px 0; }
  h2 { text-align: center; font-size: 14px; margin: 0 0 12px 0; color: #1e3a8a; }
  h3 { font-size: 13.5px; margin: 12px 0 6px 0; color: #0f766e; }
  table { width: 100%; border-collapse: collapse; margin-bottom: 8px; }
  th, td { border: 1px solid #334155; padding: 5px 7px; text-align: center; }
  th { background: #e2e8f0; font-weight: 800; }
  .sign { margin-top: 28px; display: flex; justify-content: space-between; font-weight: 700; }
</style></head><body>
<h1>$schoolName</h1>
<h2>દૈનિક શાળા સારાંશ (Today at a Glance — CRC/BRC Summary) • તારીખ: $dateDmy</h2>
${isMixed ? buildTable('૧. કુમાર (Boys) — કેટેગરી મુજબ', g: 'B') : ''}
${isMixed ? buildTable('૨. કન્યા (Girls) — કેટેગરી મુજબ', g: 'G') : ''}
${buildTable(isMixed ? '૩. કુલ શાળા (Total Boys + Girls) — કેટેગરી મુજબ' : '૧. કુલ શાળા — કેટેગરી મુજબ')}
<h3>આજે રજા પર રહેલા શિક્ષકો અને ચાર્જ વિગત</h3>
<table><thead><tr><th>ક્રમ</th><th>રજા પર રહેલ શિક્ષક</th><th>રજાનો પ્રકાર</th><th>વર્ગ સંભાળનાર / ચાર્જ શિક્ષક</th></tr></thead><tbody>$leaveRows</tbody></table>
<div class="sign"><span>તારીખ: $dateDmy</span><span>આચાર્ય / મુખ્ય શિક્ષકની સહી</span></div>
<script>window.onload = function() { window.print(); };</script>
</body></html>''';

    final blob = html.Blob(<dynamic>[docHtml], 'text/html;charset=utf-8');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
  }
}
