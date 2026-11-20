import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/school_class_order.dart';

/// Guided, School Admin password-protected Annual Year-End Student Promotion Wizard.
/// Promotes all active students from each class to the next class (or marks final-year
/// classes as Passed Out / LC) in one batch while preserving all previous year
/// attendance and result archives intact.
class SupabaseStudentPromotionScreen extends StatefulWidget {
  const SupabaseStudentPromotionScreen({super.key});

  @override
  State<SupabaseStudentPromotionScreen> createState() =>
      _SupabaseStudentPromotionScreenState();
}

class _SupabaseStudentPromotionScreenState
    extends State<SupabaseStudentPromotionScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _yearLabelCtrl = TextEditingController();

  bool _loading = true;
  bool _running = false;
  String? _error;
  String _schoolRef = '';
  List<Map<String, dynamic>> _classes = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _activeStudents = <Map<String, dynamic>>[];
  Map<String, int> _countByClassId = <String, int>{};

  /// Maps source classId -> destination classId OR '__PASS_OUT__' OR '__KEEP__'
  Map<String, String> _mappings = <String, String>{};
  final Set<String> _excludedStudentIds = <String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _yearLabelCtrl.text = '${now.year - 1}-${now.year}';
    _load();
  }

  @override
  void dispose() {
    _yearLabelCtrl.dispose();
    super.dispose();
  }

  String _text(dynamic v) => (v ?? '').toString().trim();

  String _classLabel(Map<String, dynamic> c) =>
      _text(c['label']).isNotEmpty ? _text(c['label']) : _text(c['class_key']);

  int? _extractStandardNumber(Map<String, dynamic> c) {
    final raw = '${c['standard'] ?? ''} ${c['label'] ?? ''} ${c['class_key'] ?? ''}';
    if (raw.toLowerCase().contains('balvatika') || raw.contains('બાલવાટિકા')) {
      return 0;
    }
    final m = RegExp(r'(\d{1,2})').firstMatch(raw);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  String _extractSection(Map<String, dynamic> c) {
    final sec = _text(c['section']).toUpperCase();
    if (sec.isNotEmpty) return sec;
    final lbl = _classLabel(c).toUpperCase();
    final m = RegExp(r'\d+\s*[-–]?\s*([A-Z])\b').firstMatch(lbl);
    return m?.group(1) ?? '';
  }

  String _suggestNextTarget(
    Map<String, dynamic> src,
    List<Map<String, dynamic>> allClasses,
  ) {
    final std = _extractStandardNumber(src);
    if (std == null) return '__KEEP__';
    final nextStd = std + 1;
    final srcSec = _extractSection(src);

    // First try matching exact next standard + same section (e.g. 6A -> 7A)
    if (srcSec.isNotEmpty) {
      for (final candidate in allClasses) {
        if (_extractStandardNumber(candidate) == nextStd &&
            _extractSection(candidate) == srcSec) {
          return _text(candidate['id']);
        }
      }
    }
    // Otherwise match any class in the next standard
    for (final candidate in allClasses) {
      if (_extractStandardNumber(candidate) == nextStd) {
        return _text(candidate['id']);
      }
    }
    // Highest standard in school -> default to Passed Out / LC
    return '__PASS_OUT__';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ref = _text(await _client.rpc('current_school_ref'));
      if (ref.isEmpty) throw StateError('સક્રિય શાળા login મળ્યું નથી.');
      final rawClasses = await _client
          .from('school_classes')
          .select('id,class_key,label,standard,section,report_group,sort_order,is_active')
          .eq('school_ref', ref)
          .eq('is_active', true);
      final classes = SchoolClassOrder.sorted(
        rawClasses.map((e) => Map<String, dynamic>.from(e)),
      );
      final rawStudents = await _client
          .from('students')
          .select('id,class_id,roll_number,name,gr,is_active,leaving_date,exit_date')
          .eq('school_ref', ref)
          .eq('is_active', true);
      final activeStudents = rawStudents
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (s) =>
                s['is_active'] == true &&
                _text(s['leaving_date']).isEmpty &&
                _text(s['exit_date']).isEmpty,
          )
          .toList();

      final counts = <String, int>{};
      for (final st in activeStudents) {
        final cid = _text(st['class_id']);
        counts[cid] = (counts[cid] ?? 0) + 1;
      }

      final mappings = <String, String>{};
      for (final c in classes) {
        final cid = _text(c['id']);
        mappings[cid] = _suggestNextTarget(c, classes);
      }

      if (!mounted) return;
      setState(() {
        _schoolRef = ref;
        _classes = classes;
        _activeStudents = activeStudents;
        _countByClassId = counts;
        _mappings = mappings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openExclusionsDialog(Map<String, dynamic> cls) async {
    final cid = _text(cls['id']);
    final classStudents = _activeStudents
        .where((s) => _text(s['class_id']) == cid)
        .toList()
      ..sort((a, b) {
        final ra = int.tryParse(_text(a['roll_number'])) ?? 999999;
        final rb = int.tryParse(_text(b['roll_number'])) ?? 999999;
        if (ra != rb) return ra.compareTo(rb);
        return _text(a['name']).compareTo(_text(b['name']));
      });

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('વર્ગમાં જ રાખવાના વિદ્યાર્થીઓ • ${_classLabel(cls)}'),
          content: SizedBox(
            width: 460,
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'જે વિદ્યાર્થીઓને આ જ વર્ગમાં રાખવા હોય (બઢતી ન આપવી હોય) તેમના નામ સામે ટીક કરો:',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: classStudents.length,
                    itemBuilder: (_, i) {
                      final st = classStudents[i];
                      final sid = _text(st['id']);
                      final isExcl = _excludedStudentIds.contains(sid);
                      return CheckboxListTile(
                        dense: true,
                        value: isExcl,
                        title: Text(
                          '${_text(st['roll_number']).isEmpty ? '' : '${_text(st['roll_number'])}. '}${_text(st['name'])}',
                        ),
                        subtitle: _text(st['gr']).isEmpty
                            ? null
                            : Text('GR: ${_text(st['gr'])}'),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              _excludedStudentIds.add(sid);
                            } else {
                              _excludedStudentIds.remove(sid);
                            }
                          });
                          setState(() {});
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _executePromotionWithPassword() async {
    var totalPromote = 0;
    var totalPassOut = 0;
    var totalKeep = 0;
    for (final st in _activeStudents) {
      final sid = _text(st['id']);
      final cid = _text(st['class_id']);
      final target = _mappings[cid] ?? '__KEEP__';
      if (_excludedStudentIds.contains(sid) ||
          target == '__KEEP__' ||
          target == cid) {
        totalKeep++;
      } else if (target == '__PASS_OUT__') {
        totalPassOut++;
      } else {
        totalPromote++;
      }
    }

    if (totalPromote == 0 && totalPassOut == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('બઢતી અથવા ઉતીર્ણ માટે કોઈ વર્ગ પસંદ કરેલ નથી.'),
        ),
      );
      return;
    }

    final pwdCtrl = TextEditingController();
    var obscure = true;
    var submitting = false;
    String? dialogError;
    Map<String, dynamic>? resultMap;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final pwd = pwdCtrl.text.trim();
            if (pwd.isEmpty) {
              setDialogState(
                () => dialogError = 'કૃપા કરીને School Admin પાસવર્ડ દાખલ કરો.',
              );
              return;
            }
            setDialogState(() {
              submitting = true;
              dialogError = null;
            });
            try {
              final res = await _client.rpc(
                'psm_admin_promote_students_with_password',
                params: <String, dynamic>{
                  'p_admin_password': pwd,
                  'p_class_mappings': _mappings,
                  'p_exclude_student_ids': _excludedStudentIds.toList(),
                  'p_academic_year_label': _yearLabelCtrl.text.trim(),
                },
              );
              if (res is Map) {
                resultMap = Map<String, dynamic>.from(res);
              }
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
            } catch (e) {
              setDialogState(() {
                submitting = false;
                dialogError = '$e'.replaceFirst('Exception: ', '');
              });
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.upgrade_rounded, color: Color(0xFF1D4ED8)),
                SizedBox(width: 8),
                Expanded(child: Text('વાર્ષિક વર્ગ બઢતી કન્ફર્મ કરો')),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF93C5FD)),
                      ),
                      child: Text(
                        '• આગળના વર્ગમાં બઢતી (Promoted): $totalPromote વિદ્યાર્થીઓ\n'
                        '• ઉતીર્ણ / શાળા છોડેલ (Passed Out / LC): $totalPassOut વિદ્યાર્થીઓ\n'
                        '• તે જ વર્ગમાં રહેશે (Kept Same): $totalKeep વિદ્યાર્થીઓ\n\n'
                        '✅ અગાઉના વર્ષના હાજરી અને પરિણામના તમામ રેકોર્ડ સુરક્ષિત રહેશે.',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: pwdCtrl,
                      obscureText: obscure,
                      autofocus: true,
                      enabled: !submitting,
                      decoration: InputDecoration(
                        labelText: 'School Admin પાસવર્ડ દાખલ કરો',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        errorText: dialogError,
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setDialogState(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => submit(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogCtx).pop(),
                child: const Text('રદ કરો'),
              ),
              FilledButton.icon(
                onPressed: submitting ? null : submit,
                icon: submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  submitting ? 'બઢતી ચાલુ છે…' : 'પાસવર્ડથી બઢતી પૂર્ણ કરો',
                ),
              ),
            ],
          );
        },
      ),
    );
    pwdCtrl.dispose();

    if (resultMap != null && mounted) {
      _excludedStudentIds.clear();
      await _load();
      if (!mounted) return;
      final pCount = resultMap!['promoted_count'] ?? 0;
      final outCount = resultMap!['passed_out_count'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'વાર્ષિક વર્ગ બઢતી પૂર્ણ: $pCount બઢતી, $outCount ઉતીર્ણ (Passed Out). જૂનો રેકોર્ડ સુરક્ષિત છે.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('વાર્ષિક વર્ગ બઢતી / Annual Student Promotion'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _running ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xFFEFF6FF),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🎓 વાર્ષિક વર્ગ બઢતી વિઝાર્ડ (Annual Promotion Wizard)',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '• શૈક્ષણિક વર્ષના અંતે એકસાથે તમામ સક્રિય વિદ્યાર્થીઓને આગળના ધોરણમાં બઢતી આપો (દા.ત. ધોરણ 1 → 2, ..., ધોરણ 8 → Passed Out / LC).\n'
                          '• અગાઉના વર્ષના તમામ હાજરી રેકોર્ડ અને પરિણામ પત્રક સંપૂર્ણપણે સુરક્ષિત રહેશે.\n'
                          '• બઢતી માટે School Admin પાસવર્ડ ફરજિયાત છે.',
                          style: TextStyle(fontSize: 13, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _yearLabelCtrl,
                  decoration: const InputDecoration(
                    labelText: 'પૂર્ણ થયેલ શૈક્ષણિક વર્ષ (દા.ત. 2025-2026)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                for (final cls in _classes) ...[
                  Builder(
                    builder: (context) {
                      final cid = _text(cls['id']);
                      final count = _countByClassId[cid] ?? 0;
                      final excludedInCls = _activeStudents
                          .where(
                            (s) =>
                                _text(s['class_id']) == cid &&
                                _excludedStudentIds.contains(_text(s['id'])),
                          )
                          .length;
                      final currentTarget = _mappings[cid] ?? '__KEEP__';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${_classLabel(cls)}  •  $count સક્રિય વિદ્યાર્થીઓ',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  if (count > 0)
                                    TextButton.icon(
                                      onPressed: () =>
                                          _openExclusionsDialog(cls),
                                      icon: const Icon(
                                        Icons.person_off_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        excludedInCls > 0
                                            ? 'બાકાત: $excludedInCls'
                                            : 'વિદ્યાર્થી બાકાત રાખો',
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: currentTarget,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'નવો વર્ગ / સ્થિતિ પસંદ કરો',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: <DropdownMenuItem<String>>[
                                  const DropdownMenuItem<String>(
                                    value: '__KEEP__',
                                    child: Text(
                                      '⏸️ તે જ વર્ગમાં રાખો (Keep Same)',
                                    ),
                                  ),
                                  const DropdownMenuItem<String>(
                                    value: '__PASS_OUT__',
                                    child: Text(
                                      '🎓 ઉતીર્ણ / શાળા છોડેલ (Passed Out / LC Archive)',
                                    ),
                                  ),
                                  for (final dst in _classes)
                                    if (_text(dst['id']) != cid)
                                      DropdownMenuItem<String>(
                                        value: _text(dst['id']),
                                        child: Text(
                                          '⬆️ ${_classLabel(dst)} માં બઢતી આપો',
                                        ),
                                      ),
                                ],
                                onChanged: (v) {
                                  if (v != null) {
                                    setState(() => _mappings[cid] = v);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _running || _schoolRef.isEmpty
                      ? null
                      : _executePromotionWithPassword,
                  icon: const Icon(Icons.upgrade_rounded),
                  label: const Text(
                    'પાસવર્ડથી વાર્ષિક વર્ગ બઢતી શરૂ કરો (Promote Students)',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
              ],
            ),
    );
  }
}
