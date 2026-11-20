import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Weekly PM POSHAN & Breakfast Menu (`સાપ્તાહિક PM POSHAN અને અલ્પાહાર મેનુ`).
/// Admin sets the weekly menu once (Monday to Saturday) with item name and
/// ingredients + quantity. It is shown automatically as a daily popup on login,
/// and any teacher or Admin can open this screen anytime to view today's or the
/// full weekly menu again.
class SupabaseWeeklyMealMenuScreen extends StatefulWidget {
  const SupabaseWeeklyMealMenuScreen({
    super.key,
    required this.profile,
  });

  final Map<String, dynamic> profile;

  @override
  State<SupabaseWeeklyMealMenuScreen> createState() =>
      _SupabaseWeeklyMealMenuScreenState();
}

class _SupabaseWeeklyMealMenuScreenState
    extends State<SupabaseWeeklyMealMenuScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  static const List<(int, String)> _weekDays = <(int, String)>[
    (1, 'સોમવાર (Monday)'),
    (2, 'મંગળવાર (Tuesday)'),
    (3, 'બુધવાર (Wednesday)'),
    (4, 'ગુરુવાર (Thursday)'),
    (5, 'શુક્રવાર (Friday)'),
    (6, 'શનિવાર (Saturday)'),
  ];

  bool _loading = true;
  bool _saving = false;
  bool _enabled = true;
  String? _error;

  final Map<int, TextEditingController> _pmItemCtrls =
      <int, TextEditingController>{};
  final Map<int, TextEditingController> _pmIngCtrls =
      <int, TextEditingController>{};
  final Map<int, TextEditingController> _bfItemCtrls =
      <int, TextEditingController>{};
  final Map<int, TextEditingController> _bfIngCtrls =
      <int, TextEditingController>{};

  bool get _isAdmin {
    final r = '${widget.profile['role'] ?? 'teacher'}'.trim().toLowerCase();
    return r == 'admin' || r == 'developer';
  }

  int get _todayWeekday {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return now.weekday;
  }

  @override
  void initState() {
    super.initState();
    for (final d in _weekDays) {
      _pmItemCtrls[d.$1] = TextEditingController();
      _pmIngCtrls[d.$1] = TextEditingController();
      _bfItemCtrls[d.$1] = TextEditingController();
      _bfIngCtrls[d.$1] = TextEditingController();
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _pmItemCtrls.values) c.dispose();
    for (final c in _pmIngCtrls.values) c.dispose();
    for (final c in _bfItemCtrls.values) c.dispose();
    for (final c in _bfIngCtrls.values) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _client.rpc('psm_get_weekly_meal_menu');
      final map = res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{};
      final days = map['days'] is Map
          ? Map<String, dynamic>.from(map['days'] as Map)
          : <String, dynamic>{};
      for (final d in _weekDays) {
        final entry = days['${d.$1}'] is Map
            ? Map<String, dynamic>.from(days['${d.$1}'] as Map)
            : <String, dynamic>{};
        _pmItemCtrls[d.$1]!.text = '${entry['pm_poshan_item'] ?? ''}'.trim();
        _pmIngCtrls[d.$1]!.text =
            '${entry['pm_poshan_ingredients'] ?? ''}'.trim();
        _bfItemCtrls[d.$1]!.text = '${entry['breakfast_item'] ?? ''}'.trim();
        _bfIngCtrls[d.$1]!.text =
            '${entry['breakfast_ingredients'] ?? ''}'.trim();
      }
      if (!mounted) return;
      setState(() {
        _enabled = map['enabled'] != false;
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

  Future<void> _save() async {
    if (!_isAdmin) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final daysPayload = <String, dynamic>{};
      for (final d in _weekDays) {
        daysPayload['${d.$1}'] = <String, dynamic>{
          'pm_poshan_item': _pmItemCtrls[d.$1]!.text.trim(),
          'pm_poshan_ingredients': _pmIngCtrls[d.$1]!.text.trim(),
          'breakfast_item': _bfItemCtrls[d.$1]!.text.trim(),
          'breakfast_ingredients': _bfIngCtrls[d.$1]!.text.trim(),
        };
      }
      await _client.rpc(
        'psm_save_weekly_meal_menu',
        params: <String, dynamic>{
          'p_enabled': _enabled,
          'p_days': daysPayload,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'સાપ્તાહિક PM POSHAN અને અલ્પાહાર મેનુ સાચવાઈ ગયું છે. હવે દરરોજ લૉગિન વખતે આજનું મેનુ પોપઅપમાં દેખાશે.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayWd = _todayWeekday;
    return Scaffold(
      appBar: AppBar(
        title: const Text('સાપ્તાહિક PM POSHAN અને અલ્પાહાર મેનુ'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (todayWd >= 1 && todayWd <= 6) ...[
                  Builder(
                    builder: (context) {
                      final dayName = _weekDays
                          .firstWhere((e) => e.$1 == todayWd)
                          .$2;
                      final bfItem = _bfItemCtrls[todayWd]!.text.trim();
                      final bfIng = _bfIngCtrls[todayWd]!.text.trim();
                      final pmItem = _pmItemCtrls[todayWd]!.text.trim();
                      final pmIng = _pmIngCtrls[todayWd]!.text.trim();
                      return Card(
                        color: const Color(0xFFECFDF5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(
                            color: Color(0xFF10B981),
                            width: 1.4,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🍽️ આજનું મેનુ — $dayName',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: Color(0xFF065F46),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (bfItem.isEmpty && pmItem.isEmpty)
                                const Text(
                                  'આજના વાર માટે હજુ Admin દ્વારા મેનુ સેટ કરવામાં આવ્યું નથી.',
                                )
                              else ...[
                                if (bfItem.isNotEmpty) ...[
                                  Text(
                                    '🥣 અલ્પાહાર (Breakfast): $bfItem',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  if (bfIng.isNotEmpty)
                                    Text('   સામગ્રી અને જથ્થો: $bfIng'),
                                  const SizedBox(height: 6),
                                ],
                                if (pmItem.isNotEmpty) ...[
                                  Text(
                                    '🍲 PM POSHAN (મધ્યાહન ભોજન): $pmItem',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  if (pmIng.isNotEmpty)
                                    Text('   સામગ્રી અને જથ્થો: $pmIng'),
                                ],
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isAdmin) ...[
                  SwitchListTile.adaptive(
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    title: const Text(
                      'દૈનિક લૉગિન પોપઅપ ચાલુ રાખો (Daily Login Menu Popup)',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: const Text(
                      'એક જ વાર અઠવાડિયાનું મેનુ સેટ કરો; દરરોજ શિક્ષકો અને Admin ને લૉગિન સમયે આજના વારનું મેનુ દેખાશે.',
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                for (final d in _weekDays)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: d.$1 == todayWd ? const Color(0xFFF0FDF4) : null,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${d.$2}${d.$1 == todayWd ? '  •  આજે (Today)' : ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_isAdmin) ...[
                            TextField(
                              controller: _bfItemCtrls[d.$1],
                              decoration: const InputDecoration(
                                labelText: '🥣 અલ્પાહાર વાનગીનું નામ (Breakfast Item)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _bfIngCtrls[d.$1],
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText:
                                    'અલ્પાહાર સામગ્રી અને જથ્થો (દા.ત. ચણા 20 ગ્રામ, ગોળ 10 ગ્રામ)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _pmItemCtrls[d.$1],
                              decoration: const InputDecoration(
                                labelText:
                                    '🍲 PM POSHAN વાનગીનું નામ (Mid-Day Meal Item)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _pmIngCtrls[d.$1],
                              maxLines: 2,
                              decoration: const InputDecoration(
                                labelText:
                                    'PM POSHAN સામગ્રી અને જથ્થો (દા.ત. ચોખા 100 ગ્રામ, દાળ 20 ગ્રામ, તેલ 5 ગ્રામ)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ] else ...[
                            Text(
                              '🥣 અલ્પાહાર: ${_bfItemCtrls[d.$1]!.text.trim().isEmpty ? '—' : _bfItemCtrls[d.$1]!.text.trim()}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (_bfIngCtrls[d.$1]!.text.trim().isNotEmpty)
                              Text(
                                '   સામગ્રી/જથ્થો: ${_bfIngCtrls[d.$1]!.text.trim()}',
                              ),
                            const SizedBox(height: 4),
                            Text(
                              '🍲 PM POSHAN: ${_pmItemCtrls[d.$1]!.text.trim().isEmpty ? '—' : _pmItemCtrls[d.$1]!.text.trim()}',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            if (_pmIngCtrls[d.$1]!.text.trim().isNotEmpty)
                              Text(
                                '   સામગ્રી/જથ્થો: ${_pmIngCtrls[d.$1]!.text.trim()}',
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (_isAdmin) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: Text(
                      _saving
                          ? 'મેનુ સાચવે છે…'
                          : 'સાપ્તાહિક મેનુ સાચવો (Save Weekly Menu)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
