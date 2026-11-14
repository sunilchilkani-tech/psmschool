import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

class _TeacherValtarRule {
  _TeacherValtarRule({
    required this.teacherId,
    required this.teacherName,
    required this.role,
    required this.enabled,
    required String maxDays,
  }) : maxDaysController = TextEditingController(text: maxDays);

  final String teacherId;
  final String teacherName;
  final String role;
  bool enabled;
  final TextEditingController maxDaysController;

  void dispose() => maxDaysController.dispose();
}

/// School Admin configuration for annual leave limits and application-month windows.
/// All rule changes are made through a SECURITY DEFINER RPC; clients cannot update rules directly.
class SupabaseLeaveRulesScreen extends StatefulWidget {
  const SupabaseLeaveRulesScreen({super.key});

  @override
  State<SupabaseLeaveRulesScreen> createState() => _SupabaseLeaveRulesScreenState();
}

class _SupabaseLeaveRulesScreenState extends State<SupabaseLeaveRulesScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _clCap = TextEditingController(text: '12');
  final TextEditingController _marajiyatCap = TextEditingController(text: '2');
  final TextEditingController _valtarCap = TextEditingController(text: '0');

  static const List<String> _months = <String>[
    'જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન',
    'જુલાઈ', 'ઑગસ્ટ', 'સપ્ટેમ્બર', 'ઑક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર',
  ];

  bool _loading = true;
  bool _saving = false;
  bool _isAdmin = false;
  String? _error;
  List<_TeacherValtarRule> _teacherValtarRules = <_TeacherValtarRule>[];

  // Annual cap periods: CL defaults to June-May; Marajiyat defaults to Jan-Dec.
  int _clStart = 6;
  int _clEnd = 5;
  int _marajiyatStart = 1;
  int _marajiyatEnd = 12;

  // Permitted application months can be narrower than the annual cap period.
  // Defaults remain January-December so the update does not silently block leave types.
  int _clAllowedStart = 1;
  int _clAllowedEnd = 12;
  int _marajiyatAllowedStart = 1;
  int _marajiyatAllowedEnd = 12;

  // Valtar uses its configured month window both as the allowed window and cap period,
  // matching the existing backend contract.
  int _valtarStart = 1;
  int _valtarEnd = 12;

  int _int(dynamic value, int fallback) =>
      value is int ? value : int.tryParse('$value') ?? fallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _clCap.dispose();
    _marajiyatCap.dispose();
    _valtarCap.dispose();
    for (final rule in _teacherValtarRules) { rule.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_client.auth.currentUser == null) {
        throw StateError('કૃપા કરીને ફરીથી login કરો.');
      }
      final roleValue = await _client.rpc('is_school_admin');
      final roleIsAdmin = roleValue == true ||
          const <String>{'true', 't', '1'}.contains('$roleValue'.toLowerCase());
      if (!roleIsAdmin) {
        throw StateError('રજા મર્યાદા બદલવા માટે શાળા Admin ની મંજૂરી જરૂરી છે.');
      }
      final school = '${await _client.rpc('current_school_ref')}'.trim();
      if (school.isEmpty) throw StateError('સક્રિય શાળા મળી નથી.');
      final row = await _client
          .from('school_leave_settings')
          .select(
            'cl_max_days,cl_year_start_month,cl_year_end_month,'
            'cl_allowed_start_month,cl_allowed_end_month,'
            'marajiyat_max_days,marajiyat_year_start_month,marajiyat_year_end_month,'
            'marajiyat_allowed_start_month,marajiyat_allowed_end_month,'
            'valtar_max_days,valtar_start_month,valtar_end_month',
          )
          .eq('school_ref', school)
          .maybeSingle();
      final teacherRuleResult = await _client.rpc('psm_leave_list_teacher_valtar_rules');
      final teacherRuleRows = teacherRuleResult is List ? teacherRuleResult : const <dynamic>[];
      final loadedTeacherRules = <_TeacherValtarRule>[];
      for (final dynamic item in teacherRuleRows) {
        if (item is! Map) continue;
        final values = item.map((key, value) => MapEntry(key.toString(), value));
        final id = '${values['teacher_id'] ?? values['id'] ?? ''}'.trim();
        final name = '${values['teacher_name'] ?? values['name'] ?? ''}'.trim();
        if (id.isEmpty || name.isEmpty) continue;
        final enabledValue = values['enabled'];
        final enabled = enabledValue == true || const <String>{'true', 't', '1'}.contains('$enabledValue'.toLowerCase());
        loadedTeacherRules.add(_TeacherValtarRule(
          teacherId: id,
          teacherName: name,
          role: '${values['role'] ?? 'teacher'}',
          enabled: enabled,
          maxDays: '${values['max_days'] ?? 0}',
        ));
      }
      if (!mounted) {
        for (final rule in loadedTeacherRules) { rule.dispose(); }
        return;
      }
      for (final rule in _teacherValtarRules) { rule.dispose(); }
      setState(() {
        _teacherValtarRules = loadedTeacherRules;
        _isAdmin = true;
        _clCap.text = '${row?['cl_max_days'] ?? 12}';
        _marajiyatCap.text = '${row?['marajiyat_max_days'] ?? 2}';
        _valtarCap.text = '${row?['valtar_max_days'] ?? 0}';
        _clStart = _int(row?['cl_year_start_month'], 6);
        _clEnd = _int(row?['cl_year_end_month'], 5);
        _clAllowedStart = _int(row?['cl_allowed_start_month'], 1);
        _clAllowedEnd = _int(row?['cl_allowed_end_month'], 12);
        _marajiyatStart = _int(row?['marajiyat_year_start_month'], 1);
        _marajiyatEnd = _int(row?['marajiyat_year_end_month'], 12);
        _marajiyatAllowedStart = _int(row?['marajiyat_allowed_start_month'], 1);
        _marajiyatAllowedEnd = _int(row?['marajiyat_allowed_end_month'], 12);
        _valtarStart = _int(row?['valtar_start_month'], 1);
        _valtarEnd = _int(row?['valtar_end_month'], 12);
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = '$error'
              .replaceFirst('Exception: ', '')
              .replaceFirst('Bad state: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_isAdmin || _saving) return;
    final cl = double.tryParse(_clCap.text.trim());
    final marajiyat = double.tryParse(_marajiyatCap.text.trim());
    final valtar = double.tryParse(_valtarCap.text.trim());
    if (cl == null || marajiyat == null || valtar == null ||
        cl < 0 || marajiyat < 0 || valtar < 0 ||
        cl > 365 || marajiyat > 365 || valtar > 365) {
      setState(() => _error = 'દરેક રજાની મર્યાદા 0 થી 365 દિવસ વચ્ચે લખો.');
      return;
    }

    for (final teacherRule in _teacherValtarRules) {
      final parsedDays = double.tryParse(teacherRule.maxDaysController.text.trim());
      final days = parsedDays ?? (teacherRule.enabled ? null : 0.0);
      if (days == null || days < 0 || days > 365 || (teacherRule.enabled && days <= 0)) {
        setState(() => _error = 'દરેક શિક્ષક માટે વળતર રજાના દિવસો 0 થી 365 વચ્ચે લખો. Checkbox ચાલુ હોય તો દિવસો 0 કરતાં વધુ હોવા જોઈએ.');
        return;
      }
    }

    // The annual cap period must remain a full 12-month cycle. The allowed-application
    // start/end months below are separate and can be any month window, including Dec-May.
    final expectedClEnd = _clStart == 1 ? 12 : _clStart - 1;
    final expectedMarajiyatEnd = _marajiyatStart == 1 ? 12 : _marajiyatStart - 1;
    if (_clEnd != expectedClEnd || _marajiyatEnd != expectedMarajiyatEnd) {
      setState(() => _error =
          'વાર્ષિક મર્યાદા માટે C.L. અને મરજિયાત રજાનો અંતિમ મહિનો શરૂઆતના મહિના પહેલાંનો મહિનો હોવો જોઈએ. મંજૂર અરજીના મહિના અલગથી પસંદ કરો.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _client.rpc('psm_leave_save_rules', params: <String, dynamic>{
        'p_cl_max_days': cl,
        'p_cl_start_month': _clStart,
        'p_cl_end_month': _clEnd,
        'p_marajiyat_max_days': marajiyat,
        'p_marajiyat_start_month': _marajiyatStart,
        'p_marajiyat_end_month': _marajiyatEnd,
        // Retain the legacy school-level value for backward compatibility. The
        // Valtar leave guard now enforces each teacher's own configured cap.
        'p_valtar_max_days': valtar,
        'p_valtar_start_month': _valtarStart,
        'p_valtar_end_month': _valtarEnd,
        'p_cl_allowed_start_month': _clAllowedStart,
        'p_cl_allowed_end_month': _clAllowedEnd,
        'p_marajiyat_allowed_start_month': _marajiyatAllowedStart,
        'p_marajiyat_allowed_end_month': _marajiyatAllowedEnd,
      });
      await _client.rpc('psm_leave_save_teacher_valtar_rules', params: <String, dynamic>{
        'p_rules': _teacherValtarRules.map((rule) => <String, dynamic>{
          'teacher_id': rule.teacherId,
          'enabled': rule.enabled,
          'max_days': double.tryParse(rule.maxDaysController.text.trim()) ?? 0.0,
        }).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('રજાના નિયમો, મંજૂર મહિના અને શિક્ષકવાર વળતર રજા સાચવાઈ ગઈ.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error'
            .replaceFirst('Exception: ', '')
            .replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _monthDropdown(
    String label,
    int value,
    ValueChanged<int?> onChanged,
  ) => DropdownButtonFormField<int>(
        value: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        items: List<DropdownMenuItem<int>>.generate(
          12,
          (index) => DropdownMenuItem<int>(
            value: index + 1,
            child: Text(_months[index]),
          ),
        ),
        onChanged: _saving ? null : onChanged,
      );

  Widget _monthRange({
    required String title,
    required String startLabel,
    required String endLabel,
    required int start,
    required int end,
    required ValueChanged<int?> onStart,
    required ValueChanged<int?> onEnd,
  }) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final startField = _monthDropdown(startLabel, start, onStart);
            final endField = _monthDropdown(endLabel, end, onEnd);
            if (constraints.maxWidth >= 480) {
              return Row(children: [
                Expanded(child: startField),
                const SizedBox(width: 12),
                Expanded(child: endField),
              ]);
            }
            return Column(children: [
              startField,
              const SizedBox(height: 10),
              endField,
            ]);
          }),
        ],
      );

  Widget _ruleCard({
    required String title,
    required String helper,
    required TextEditingController cap,
    required int start,
    required int end,
    required ValueChanged<int?> onStart,
    required ValueChanged<int?> onEnd,
    required String periodLabel,
    int? allowedStart,
    int? allowedEnd,
    ValueChanged<int?>? onAllowedStart,
    ValueChanged<int?>? onAllowedEnd,
    String? allowedHelper,
    bool showCap = true,
  }) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 4),
              Text(helper, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (showCap) ...[
                TextField(
                  controller: cap,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'મહત્તમ દિવસો / Annual Cap',
                    helperText: '0 લખવાથી આ પ્રકારની નવી રજા અરજી પરવાનગી નહીં પામે.',
                    prefixIcon: Icon(Icons.speed),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              _monthRange(
                title: periodLabel,
                startLabel: 'મર્યાદા વર્ષનો શરૂઆતનો મહિનો',
                endLabel: 'મર્યાદા વર્ષનો અંતિમ મહિનો',
                start: start,
                end: end,
                onStart: onStart,
                onEnd: onEnd,
              ),
              if (allowedStart != null && allowedEnd != null && onAllowedStart != null && onAllowedEnd != null) ...[
                const SizedBox(height: 16),
                if (allowedHelper != null) ...[
                  Text(allowedHelper, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                ],
                _monthRange(
                  title: 'અરજી માટે મંજૂર મહિના',
                  startLabel: 'મંજૂર શરૂઆતનો મહિનો',
                  endLabel: 'મંજૂર અંતિમ મહિનો',
                  start: allowedStart,
                  end: allowedEnd,
                  onStart: onAllowedStart,
                  onEnd: onAllowedEnd,
                ),
              ],
            ],
          ),
        ),
      );

  Widget _teacherValtarCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('શિક્ષકવાર વળતર રજા / Teacher-wise Valtar Raja',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 6),
              Text(
                'દરેક નોંધાયેલા સક્રિય શિક્ષક માટે અલગથી checkbox ચાલુ કરો અને તે શિક્ષકને મળતા વળતર રજાના વાર્ષિક મહત્તમ દિવસો લખો. Checkbox બંધ હોય તો તે શિક્ષક નવી વળતર રજાની અરજી કરી શકશે નહીં.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_teacherValtarRules.isEmpty)
                const Text('આ શાળામાં કોઈ સક્રિય શિક્ષક મળ્યો નથી.'),
              for (final rule in _teacherValtarRules)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final checkbox = CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: rule.enabled,
                        onChanged: _saving ? null : (value) => setState(() => rule.enabled = value ?? false),
                        title: Text(rule.teacherName, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(rule.role.toLowerCase() == 'admin' ? 'School Admin' : 'Registered teacher'),
                        controlAffinity: ListTileControlAffinity.leading,
                      );
                      final daysField = SizedBox(
                        width: constraints.maxWidth >= 560 ? 170 : double.infinity,
                        child: TextField(
                          controller: rule.maxDaysController,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'વળતર દિવસો / Year',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      );
                      if (constraints.maxWidth >= 560) {
                        return Row(children: [Expanded(child: checkbox), const SizedBox(width: 12), daysField]);
                      }
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [checkbox, const SizedBox(height: 6), daysField]);
                    }),
                  ),
                ),
              const SizedBox(height: 4),
              const Text(' નોંધ: આ મર્યાદા શિક્ષક પ્રમાણે અલગ છે; શાળાના Valtar મંજૂર મહિના ઉપરના વિભાગમાંથી જ લાગુ પડશે.'),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('રજા નિયમો / Leave Rules')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('રજા નિયમો / Leave Month Settings'),
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
          'આ નિયમો શાળા માટે લાગુ પડશે. વાર્ષિક મર્યાદા ગણતરીનો સમયગાળો અને અરજી કરવા માટે મંજૂર મહિના અલગથી સેટ કરી શકાય છે. નવી અરજી અને Admin દ્વારા દાખલ કરેલી હસ્તલિખિત નોંધ બંને પર સર્વર મર્યાદા ચકાસશે. નામંજૂર થયેલી અરજી મર્યાદામાં ગણાશે નહીં.',
          style: TextStyle(height: 1.4),
        ),
        const SizedBox(height: 12),
        _ruleCard(
          title: 'પ્રાસંગિક રજા (C.L.)',
          helper: 'ડિફૉલ્ટ 12 દિવસ; વાર્ષિક ગણતરી જૂનથી મે. 0.5 દિવસની ગણતરી માત્ર C.L. માટે છે.',
          cap: _clCap,
          start: _clStart,
          end: _clEnd,
          onStart: (value) { if (value != null) setState(() => _clStart = value); },
          onEnd: (value) { if (value != null) setState(() => _clEnd = value); },
          periodLabel: 'વાર્ષિક મર્યાદા ગણતરીનો સમયગાળો',
          allowedStart: _clAllowedStart,
          allowedEnd: _clAllowedEnd,
          onAllowedStart: (value) { if (value != null) setState(() => _clAllowedStart = value); },
          onAllowedEnd: (value) { if (value != null) setState(() => _clAllowedEnd = value); },
          allowedHelper: 'C.L. માટે કયા મહિનાઓમાં અરજી કરી શકાય તે પસંદ કરો. આ પસંદગી જૂન-મે વાર્ષિક મર્યાદા ગણતરીથી અલગ છે.',
        ),
        _ruleCard(
          title: 'મરજિયાત રજા',
          helper: 'ડિફૉલ્ટ 2 દિવસ; વાર્ષિક ગણતરી જાન્યુઆરીથી ડિસેમ્બર.',
          cap: _marajiyatCap,
          start: _marajiyatStart,
          end: _marajiyatEnd,
          onStart: (value) { if (value != null) setState(() => _marajiyatStart = value); },
          onEnd: (value) { if (value != null) setState(() => _marajiyatEnd = value); },
          periodLabel: 'વાર્ષિક મર્યાદા ગણતરીનો સમયગાળો',
          allowedStart: _marajiyatAllowedStart,
          allowedEnd: _marajiyatAllowedEnd,
          onAllowedStart: (value) { if (value != null) setState(() => _marajiyatAllowedStart = value); },
          onAllowedEnd: (value) { if (value != null) setState(() => _marajiyatAllowedEnd = value); },
          allowedHelper: 'મરજિયાત રજા માટે કયા મહિનાઓમાં અરજી કરી શકાય તે પસંદ કરો. આ પસંદગી જાન્યુઆરી-ડિસેમ્બર વાર્ષિક મર્યાદાથી અલગ છે.',
        ),
        _ruleCard(
          title: 'વળતર રજા (VAP / Valtar)',
          helper: 'અહીં વળતર રજાના મંજૂર મહિના સેટ કરો. દરેક શિક્ષકની Valtar Raja ચાલુ/બંધ અને વાર્ષિક દિવસોની મર્યાદા નીચે અલગથી સેટ કરો.',
          cap: _valtarCap,
          start: _valtarStart,
          end: _valtarEnd,
          onStart: (value) { if (value != null) setState(() => _valtarStart = value); },
          onEnd: (value) { if (value != null) setState(() => _valtarEnd = value); },
          periodLabel: 'વળતર રજા માટે મંજૂર મહિના અને મર્યાદા સમયગાળો',
          showCap: false,
        ),
        _teacherValtarCard(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: const Text('રજાના નિયમો સાચવો'),
        ),
      ]),
    );
  }
}
