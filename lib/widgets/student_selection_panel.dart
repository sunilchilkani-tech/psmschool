import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import 'data_tables.dart';
import 'common_widgets.dart';
import 'dialogs.dart';
import '../services/certificate_service.dart';
import '../screens/leave_report_screen.dart';
import 'package:pmshri_attendance/services/class_label.dart';

class StudentSelectionPanel extends StatefulWidget {
  final String className;
  final String date;
  final CategoryCounts registered;
  final List<StudentRecord> students;
  final bool enabled;
  final bool canSubmit;
  final Future<void> Function() onReload;
  final Future<Map<String, dynamic>> Function(List<StudentRecord> students)
      onSave;

  const StudentSelectionPanel({
    super.key,
    required this.className,
    required this.date,
    required this.registered,
    required this.students,
    required this.enabled,
    required this.canSubmit,
    required this.onReload,
    required this.onSave,
  });

  @override
  State<StudentSelectionPanel> createState() => _StudentSelectionPanelState();
}

class _StudentSelectionPanelState extends State<StudentSelectionPanel>
    with WidgetsBindingObserver {
  late List<StudentRecord> _students;
  bool _saving = false;
  String? _alert;
  bool _alertError = false;

  // Queue for sending WhatsApp messages one-by-one when returning to the app on mobile
  final List<StudentRecord> _pendingWhatsAppQueue = [];
  bool _launchingWhatsApp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resetFromWidget();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _pendingWhatsAppQueue.isNotEmpty &&
        !_launchingWhatsApp) {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted && _pendingWhatsAppQueue.isNotEmpty) {
          _launchNextInWhatsAppQueue();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant StudentSelectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.className != widget.className ||
        oldWidget.date != widget.date) {
      _resetFromWidget();
    } else if (oldWidget.students != widget.students) {
      _mergeStudentsPreservingMarks();
    }
  }

  void _resetFromWidget() {
    _students = List<StudentRecord>.from(widget.students);
  }

  void _mergeStudentsPreservingMarks() {
    final prevById = <String, StudentRecord>{
      for (final s in _students)
        if (s.id.isNotEmpty) s.id: s,
    };
    _students = widget.students.map((next) {
      final prev = prevById[next.id];
      if (prev == null) return next;
      return next.copyWith(
        present: prev.present,
        mdm: prev.mdm,
        breakfast: prev.breakfast,
      );
    }).toList();
  }

  void _replaceStudent(int index, StudentRecord next) {
    setState(() => _students[index] = next);
  }

  void _setAttendance(int index, bool present) {
    final student = _students[index];
    _replaceStudent(
      index,
      student.copyWith(
        present: present,
        mdm: present ? student.mdm : false,
        breakfast: present ? student.breakfast : false,
      ),
    );
  }

  void _toggleMdm(int index) {
    final student = _students[index];
    if (!student.present || !widget.enabled) return;
    _replaceStudent(index, student.copyWith(mdm: !student.mdm));
  }

  void _toggleBreakfast(int index) {
    final student = _students[index];
    if (!student.present || !widget.enabled) return;
    _replaceStudent(index, student.copyWith(breakfast: !student.breakfast));
  }

  Map<Category, int> _counts(bool Function(StudentRecord) test) {
    final result = {for (final c in Category.values) c: 0};
    for (final s in _students) {
      if (test(s)) result[s.category] = (result[s.category] ?? 0) + 1;
    }
    return result;
  }

  int get _presentTotal => _students.where((s) => s.present).length;
  int get _mdmTotal => _students.where((s) => s.present && s.mdm).length;
  int get _breakfastTotal =>
      _students.where((s) => s.present && s.breakfast).length;

  Widget _buildCoedSummaryTables() {
    final genders = ['BOYS', 'GIRLS', 'UNSPECIFIED'];
    final categories = ['SC', 'ST', 'OBC', 'OTHER'];
    final reg = CategoryCounts(),
        present = CategoryCounts(),
        mdm = CategoryCounts();
    final breakdown = <String, dynamic>{};
    for (final gender in genders) {
      final group = <String, dynamic>{};
      var regOverall = 0,
          presentOverall = 0,
          mdmOverall = 0,
          breakfastOverall = 0;
      for (final category in Category.values) {
        final rawGenderCount = _students
            .where((s) =>
                s.category == category && s.gender.toUpperCase() == gender)
            .length;
        final rawPresent = _students
            .where((s) =>
                s.category == category &&
                s.gender.toUpperCase() == gender &&
                s.present)
            .length;
        final rawMdm = _students
            .where((s) =>
                s.category == category &&
                s.gender.toUpperCase() == gender &&
                s.present &&
                s.mdm)
            .length;
        // UNSPECIFIED records remain separately visible; never guess their gender.
        group[category.apiKey] = {
          'registered': gender == 'UNSPECIFIED'
              ? _students
                  .where((s) =>
                      s.category == category &&
                      !['BOYS', 'GIRLS'].contains(s.gender.toUpperCase()))
                  .length
              : rawGenderCount,
          'present': gender == 'UNSPECIFIED'
              ? _students
                  .where((s) =>
                      s.category == category &&
                      !['BOYS', 'GIRLS'].contains(s.gender.toUpperCase()) &&
                      s.present)
                  .length
              : rawPresent,
          'mdm': gender == 'UNSPECIFIED'
              ? _students
                  .where((s) =>
                      s.category == category &&
                      !['BOYS', 'GIRLS'].contains(s.gender.toUpperCase()) &&
                      s.present &&
                      s.mdm)
                  .length
              : rawMdm,
        };
        if (gender != 'UNSPECIFIED') {
          if (gender == 'BOYS') {
            reg.set(category, reg[category] + rawGenderCount);
            present.set(category, present[category] + rawPresent);
            mdm.set(category, mdm[category] + rawMdm);
          }
        }
        regOverall +=
            int.parse('${(group[category.apiKey] as Map)['registered']}');
        presentOverall +=
            int.parse('${(group[category.apiKey] as Map)['present']}');
        mdmOverall += int.parse('${(group[category.apiKey] as Map)['mdm']}');
        if (gender == 'BOYS')
          breakfastOverall += _students
              .where((s) =>
                  s.category == category &&
                  s.gender.toUpperCase() == 'BOYS' &&
                  s.present &&
                  s.breakfast)
              .length;
        if (gender == 'GIRLS')
          breakfastOverall += _students
              .where((s) =>
                  s.category == category &&
                  s.gender.toUpperCase() == 'GIRLS' &&
                  s.present &&
                  s.breakfast)
              .length;
        if (gender == 'UNSPECIFIED')
          breakfastOverall += _students
              .where((s) =>
                  s.category == category &&
                  !['BOYS', 'GIRLS'].contains(s.gender.toUpperCase()) &&
                  s.present &&
                  s.breakfast)
              .length;
      }
      group['_OVERALL'] = {
        'registered': regOverall,
        'present': presentOverall,
        'mdm': mdmOverall,
        'breakfast': breakfastOverall
      };
      breakdown[gender] = group;
    }
    // Aggregate official values for the table, with the unknown-gender bucket retained in breakdown.
    for (final category in Category.values) {
      reg.set(category, _students.where((s) => s.category == category).length);
      present.set(category,
          _students.where((s) => s.category == category && s.present).length);
      mdm.set(
          category,
          _students
              .where((s) => s.category == category && s.present && s.mdm)
              .length);
    }
    final row = GenderMetricRow(
      label: widget.className,
      registered: reg,
      present: present,
      mdm: mdm,
      breakfastTotal: _breakfastTotal,
      genderBreakdown: breakdown,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final metric in const <(String, String)>[
        ('registered', 'રજિસ્ટર્ડ — Boys / Girls / Total'),
        ('present', 'હાજર — Boys / Girls / Total'),
        ('mdm', 'PM Poshan — Boys / Girls / Total'),
        ('breakfast', 'Breakfast — Boys / Girls / Total'),
      ])
        GenderCategoryMetricTable(
            title: metric.$2, metric: metric.$1, rows: [row]),
      if (breakdown['UNSPECIFIED'] is Map &&
          (breakdown['UNSPECIFIED'] as Map)['_OVERALL'] is Map &&
          (int.tryParse(
                      '${((breakdown['UNSPECIFIED'] as Map)['_OVERALL'] as Map)['registered'] ?? 0}') ??
                  0) >
              0)
        Text(
            'નોંધ: લિંગ નોંધાયેલ ન હોય તેવા વિદ્યાર્થીઓ અલગ રાખ્યા છે; તેમનો લિંગ અંદાજથી નક્કી કરાયો નથી.',
            style: guFont(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.deepOrange)),
    ]);
  }

  Future<void> _save() async {
    if (!widget.enabled || !widget.canSubmit || _saving) return;

    if (_presentTotal == 0) {
      final ok = await showAllZeroConfirm(context);
      if (!ok || !mounted) return;
    } else if (_mdmTotal == 0 || _breakfastTotal == 0) {
      final ok = await showMdmBfZeroConfirm(context);
      if (!ok || !mounted) return;
    }

    setState(() {
      _saving = true;
      _alert = null;
    });

    try {
      final res = await widget.onSave(_students);
      if (!mounted) return;
      if (res['result'] == 'success') {
        setState(() {
          _saving = false;
          _alertError = false;
          // "✅ <class> – <date> ની વિદ્યાર્થીવાર હાજરી સફળતાપૂર્વક સાચવી!"
          _alert =
              '\u{2705} ${widget.className} \u{2013} ${widget.date} \u0AA8\u0AC0 \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0AB5\u0ABE\u0AB0 \u0AB9\u0ABE\u0A9C\u0AB0\u0AC0 \u0AB8\u0AAB\u0AB3\u0AA4\u0ABE\u0AAA\u0AC2\u0AB0\u0ACD\u0AB5\u0A95 \u0AB8\u0ABE\u0A9A\u0AB5\u0AC0!';
        });

        final absentWithPhone = _students
            .where((s) => !s.present && _phone(s.mobile).isNotEmpty)
            .toList();

        if (absentWithPhone.isNotEmpty && mounted) {
          final sendNow = await showConfirmDialog(
            context,
            emoji: '\u{1F4F2}', // 📲
            // "હાજરી સફળતાપૂર્વક સેવ થઈ ગઈ છે!\n\nઆજે કુલ X ગેરહાજર વિદ્યાર્થીઓ છે. શું તમે તેમના વાલીઓને WhatsApp મેસેજ મોકલવા માંગો છો?"
            message:
                '\u0AB9\u0ABE\u0A9C\u0AB0\u0AC0 \u0AB8\u0AAB\u0AB3\u0AA4\u0ABE\u0AAA\u0AC2\u0AB0\u0ACD\u0AB5\u0A95 \u0AB8\u0AC7\u0AB5 \u0AA5\u0A88 \u0A97\u0A88 \u0A9B\u0AC7!\n\n\u0A86\u0A9C\u0AC7 \u0A95\u0AC1\u0AB2 ${absentWithPhone.length} \u0A97\u0AC7\u0AB0\u0AB9\u0ABE\u0A9C\u0AB0 \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0A93 \u0A9B\u0AC7. \u0AB6\u0AC1\u0A82 \u0AA4\u0AAE\u0AC7 \u0AA4\u0AC7\u0AAE\u0AA8\u0ABE \u0AB5\u0ABE\u0AB2\u0AC0\u0A93\u0AA8\u0AC7 WhatsApp \u0AAE\u0AC7\u0AB8\u0AC7\u0A9C \u0AAE\u0ACB\u0A95\u0AB2\u0AB5\u0ABE \u0AAE\u0ABE\u0A82\u0A97\u0ACB \u0A9B\u0ACB?',
            // "📲 હા, WhatsApp મોકલો"
            yesLabel:
                '\u{1F4F2} \u0AB9\u0ABE, WhatsApp \u0AAE\u0ACB\u0A95\u0AB2\u0ACB',
            // "ના, અત્યારે નહીં"
            noLabel:
                '\u0AA8\u0ABE, \u0A85\u0AA4\u0ACD\u0AAF\u0ABE\u0AB0\u0AC7 \u0AA8\u0AB9\u0AC0\u0A82',
          );
          if (sendNow && mounted) {
            await _sendAllAbsent();
          }
        }
      } else {
        setState(() {
          _saving = false;
          _alertError = true;
          // "❌ સેવ કરવામાં ભૂલ."
          _alert =
              '\u{274C} ${res['message'] ?? res['error'] ?? '\u0AB8\u0AC7\u0AB5 \u0A95\u0AB0\u0AB5\u0ABE\u0AAE\u0ABE\u0A82 \u0AAD\u0AC2\u0AB2.'}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _alertError = true;
        // "❌ સાચવી શકાયું નહી: "
        _alert =
            '\u{274C} \u0AB8\u0ABE\u0A9A\u0AB5\u0AC0 \u0AB6\u0A95\u0ABE\u0AAF\u0AC1\u0A82 \u0AA8\u0AB9\u0AC0: $e';
      });
    }
  }

  /// Normalizes Indian mobile numbers cleanly for WhatsApp.
  String _phone(String raw) {
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('0') && digits.length == 11) {
      digits = digits.substring(1);
    }
    if (digits.length == 10) {
      return '91$digits';
    }
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits;
    }
    if (digits.length > 10) {
      return '91${digits.substring(digits.length - 10)}';
    }
    return digits;
  }

  /// WhatsApp message text (Unicode-escaped so encoding can never break)
  String _messageFor(StudentRecord student) {
    final date = DateFormat('dd-MM-yyyy').format(DateTime.parse(widget.date));
    final cleanClass = widget.className.replaceFirst('Class ', '');
    return '*\u0A86\u0A9C\u0AA8\u0ACB \u0A86\u0AAA\u0AA8\u0ABE \u0AAC\u0ABE\u0AB3\u0A95\u0AA8\u0ACB \u0AB9\u0ABE\u0A9C\u0AB0\u0AC0 \u0AB0\u0ABF\u0AAA\u0ACB\u0AB0\u0ACD\u0A9F*\n\n'
        '*\u0AB6\u0ABE\u0AB3\u0ABE: ${context.read<AppState>().schoolName}*\n'
        '*\u0AA7\u0ACB\u0AB0\u0AA3: $cleanClass*\n'
        '*\u0AA4\u0ABE\u0AB0\u0AC0\u0A96: $date*\n'
        '*\u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0: ${student.name}*\n\n'
        '*\u0A86\u0A9C\u0AC7 \u0A86\u0AAA\u0AA8\u0AC1\u0A82 \u0AB8\u0A82\u0AA4\u0ABE\u0AA8 \u0AB6\u0ABE\u0AB3\u0ABE\u0AAE\u0ABE\u0A82 \u0A97\u0AC7\u0AB0\u0AB9\u0ABE\u0A9C\u0AB0 \u0A9B\u0AC7. '
        '\u0AA8\u0ABF\u0AAF\u0AAE\u0ABF\u0AA4 \u0A85\u0AAD\u0ACD\u0AAF\u0ABE\u0AB8 \u0AAE\u0ABE\u0A9F\u0AC7 \u0A86\u0AAA\u0AA8\u0ABE \u0AB8\u0A82\u0AA4\u0ABE\u0AA8\u0AA8\u0AC7 '
        '\u0AB6\u0ABE\u0AB3\u0ABE\u0AAE\u0ABE\u0A82 \u0AA8\u0ABF\u0AAF\u0AAE\u0ABF\u0AA4 \u0AAE\u0ACB\u0A95\u0AB2\u0AB5\u0ABE \u0A86\u0AAA\u0AB6\u0ACD\u0AB0\u0AC0\u0AA8\u0AC7 \u0AB5\u0ABF\u0AA8\u0A82\u0AA4\u0AC0 \u0A9B\u0AC7.*';
  }

  Future<bool> _openWhatsAppForStudent(StudentRecord student) async {
    final phone = _phone(student.mobile);
    if (phone.isEmpty) return false;
    final encodedMsg = Uri.encodeComponent(_messageFor(student));

    if (!kIsWeb) {
      final appUri = Uri.parse('whatsapp://send?phone=$phone&text=$encodedMsg');
      try {
        final launched =
            await launchUrl(appUri, mode: LaunchMode.externalApplication);
        if (launched) return true;
      } catch (_) {}
    }

    final webUri = Uri.parse('https://wa.me/$phone?text=$encodedMsg');
    try {
      final launched = await launchUrl(
        webUri,
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
      if (launched) return true;
    } catch (_) {}

    try {
      return await launchUrl(webUri, mode: LaunchMode.platformDefault);
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendWhatsApp(StudentRecord student) async {
    final phone = _phone(student.mobile);
    if (phone.isEmpty) {
      if (!mounted) return;
      await showInfoOkDialog(
        context,
        emoji: '\u{1F4F1}', // 📱
        // "આ વિદ્યાર્થીનો Mobile Number (AK) દાખલ કરેલ નથી."
        message:
            '\u0A86 \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0AA8\u0ACB Mobile Number (AK) \u0AA6\u0ABE\u0A96\u0AB2 \u0A95\u0AB0\u0AC7\u0AB2 \u0AA8\u0AA5\u0AC0.',
      );
      return;
    }

    final ok = await _openWhatsAppForStudent(student);
    if (!ok && mounted) {
      await showInfoOkDialog(
        context,
        emoji: '\u{26A0}\u{FE0F}', // ⚠️
        // "WhatsApp ખોલી શકાયું નથી."
        message:
            'WhatsApp \u0A96\u0ACB\u0AB2\u0AC0 \u0AB6\u0A95\u0ABE\u0AAF\u0AC1\u0A82 \u0AA8\u0AA5\u0AC0.',
      );
    }
  }

  Future<void> _launchNextInWhatsAppQueue() async {
    if (_pendingWhatsAppQueue.isEmpty || _launchingWhatsApp) return;
    _launchingWhatsApp = true;
    final nextStudent = _pendingWhatsAppQueue.removeAt(0);
    await _openWhatsAppForStudent(nextStudent);
    _launchingWhatsApp = false;
  }

  Future<void> _sendAllAbsent() async {
    final absent = _students
        .where((s) => !s.present && _phone(s.mobile).isNotEmpty)
        .toList();
    if (absent.isEmpty) {
      if (!mounted) return;
      await showInfoOkDialog(
        context,
        emoji: '\u{2705}', // ✅
        // "ગેરહાજર વિદ્યાર્થીઓ અથવા Mobile Number ધરાવતા ગેરહાજર વિદ્યાર્થીઓ મળ્યા નથી."
        message:
            '\u0A97\u0AC7\u0AB0\u0AB9\u0ABE\u0A9C\u0AB0 \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0A93 \u0A85\u0AA5\u0AB5\u0ABE Mobile Number \u0AA7\u0AB0\u0ABE\u0AB5\u0AA4\u0ABE \u0A97\u0AC7\u0AB0\u0AB9\u0ABE\u0A9C\u0AB0 \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0A93 \u0AAE\u0AB3\u0ACD\u0AAF\u0ABE \u0AA8\u0AA5\u0AC0.',
      );
      return;
    }

    if (kIsWeb) {
      for (final student in absent) {
        await _openWhatsAppForStudent(student);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return;
    }

    _pendingWhatsAppQueue
      ..clear()
      ..addAll(absent);
    await _launchNextInWhatsAppQueue();
  }

  Future<void> _openStudentDialog([StudentRecord? student]) async {
    Map<String, dynamic> data = student?.toJson() ??
        StudentRecord(
                id: '',
                rollNumber: '',
                name: '',
                category: Category.obc,
                mobile: '')
            .toJson();

    Widget buildField(String label, String key, {bool isNum = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: LabeledField(
          label: label,
          child: TextFormField(
            initialValue: data[key]?.toString(),
            keyboardType: isNum ? TextInputType.number : TextInputType.text,
            onChanged: (v) => data[key] = v,
          ),
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
              student == null
                  ? '➕ નવો વિદ્યાર્થી ઉમેરો'
                  : '✏️ વિદ્યાર્થીની વિગત સુધારો',
              style: guFont(fontWeight: FontWeight.w800)),
          content: SizedBox(
            width: 500,
            height: 600,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ExpansionTile(
                    title: Text('🏫 બેઝિક વિગતો (કોલમ AA થી AK)',
                        style: guFont(fontWeight: FontWeight.w700)),
                    initiallyExpanded: true,
                    childrenPadding: const EdgeInsets.all(10),
                    children: [
                      Row(children: [
                        Expanded(
                            child: buildField('Roll (AA)', 'rollNumber',
                                isNum: true)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: buildField('GR નં (AB)', 'gr', isNum: true))
                      ]),
                      buildField('નામ (AF)', 'name'),
                      Row(children: [
                        Expanded(
                            child: buildField('DD (AC)', 'dd', isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: buildField('MM (AD)', 'mm', isNum: true)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: buildField('YYYY (AE)', 'yyyy', isNum: true))
                      ]),
                      Row(
                        children: [
                          Expanded(
                              child: buildField('પેટા જ્ઞાતિ (AG)', 'caste')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: LabeledField(
                                  label: 'કેટેગરી (AH)',
                                  child: DropdownButtonFormField<String>(
                                    value: ['SC', 'ST', 'OBC', 'OTHER']
                                            .contains(data['category'])
                                        ? data['category']
                                        : 'OBC',
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'SC', child: Text('અ. જા.')),
                                      DropdownMenuItem(
                                          value: 'ST',
                                          child: Text('અ. જ. જા.')),
                                      DropdownMenuItem(
                                          value: 'OBC',
                                          child: Text('બક્ષીપંચ')),
                                      DropdownMenuItem(
                                          value: 'OTHER', child: Text('અન્ય'))
                                    ],
                                    onChanged: (v) => data['category'] = v!,
                                  ))),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LabeledField(
                        label: 'લિંગ / Gender',
                        child: DropdownButtonFormField<String>(
                          value: ['BOYS', 'GIRLS', 'UNSPECIFIED']
                                  .contains(data['gender'])
                              ? data['gender']
                              : 'UNSPECIFIED',
                          items: const [
                            DropdownMenuItem(
                                value: 'BOYS', child: Text('છોકરો / Boys')),
                            DropdownMenuItem(
                                value: 'GIRLS', child: Text('છોકરી / Girls')),
                            DropdownMenuItem(
                                value: 'UNSPECIFIED',
                                child: Text('નક્કી નથી / Not set')),
                          ],
                          onChanged: (v) =>
                              setD(() => data['gender'] = v ?? 'UNSPECIFIED'),
                        ),
                      ),
                      Row(children: [
                        Expanded(
                            child:
                                buildField('શાળા પ્રવેશ (AI)', 'enrollSchool')),
                        const SizedBox(width: 10),
                        Expanded(
                            child:
                                buildField('વર્ગ પ્રવેશ (AJ)', 'enrollClass'))
                      ]),
                      buildField('મોબાઈલ (AK)', 'mobile', isNum: true),
                      const SizedBox(height: 8),
                      LabeledField(
                        label: 'દિવ્યાંગ વિદ્યાર્થી? (હા / ના)',
                        child: DropdownButtonFormField<String>(
                          value: data['isDivyang'] == 'હા' ? 'હા' : 'ના',
                          items: const [
                            DropdownMenuItem(value: 'હા', child: Text('હા')),
                            DropdownMenuItem(value: 'ના', child: Text('ના')),
                          ],
                          onChanged: (value) =>
                              setD(() => data['isDivyang'] = value ?? 'ના'),
                        ),
                      ),
                    ],
                  ),
                  ExpansionTile(
                    title: Text('🎓 શિષ્યવૃત્તિ અને આઈડી (AL થી AO)',
                        style: guFont(fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.all(10),
                    children: [
                      Row(children: [
                        Expanded(
                            child: buildField('UID નંબર (AL)', 'uid',
                                isNum: true)),
                        const SizedBox(width: 10),
                        Expanded(
                            child:
                                buildField('PEN નંબર (AM)', 'pen', isNum: true))
                      ]),
                      LabeledField(
                          label: 'શિષ્યવૃત્તિ દરખાસ્ત કરેલ છે? (AN)',
                          child: DropdownButtonFormField<String>(
                            // અહીં By Default 'ના' કરી દીધું છે
                            value:
                                data['scholarshipDone'] == 'હા' ? 'હા' : 'ના',
                            items: const [
                              DropdownMenuItem(value: 'હા', child: Text('હા')),
                              DropdownMenuItem(value: 'ના', child: Text('ના'))
                            ],
                            onChanged: (v) => setD(() {
                              data['scholarshipDone'] = v!;
                              // જો શિક્ષક 'હા' કરે, તો કારણ ભૂંસી નાખવું
                              if (v == 'હા') data['scholarshipReason'] = '';
                            }),
                          )),
                      if (data['scholarshipDone'] == 'ના') ...[
                        const SizedBox(height: 10),
                        buildField('શિષ્યવૃત્તિ ન થવાનું કારણ (AO)',
                            'scholarshipReason'),
                      ]
                    ],
                  ),
                  ExpansionTile(
                    title: Text('🏦 બેંક વિગતો (AS થી AW)',
                        style: guFont(fontWeight: FontWeight.w700)),
                    childrenPadding: const EdgeInsets.all(10),
                    children: [
                      Row(children: [
                        Expanded(
                            child: buildField('બેંકનું નામ (AS)', 'bankName')),
                        const SizedBox(width: 10),
                        Expanded(
                            child: buildField('બ્રાન્ચ (AT)', 'bankBranch'))
                      ]),
                      buildField('પાસબુક મુજબ નામ (AU)', 'nameAsPassbook'),
                      Row(children: [
                        Expanded(
                            child: buildField(
                                'એકાઉન્ટ નંબર (AV)', 'accountNumber',
                                isNum: true)),
                        const SizedBox(width: 10),
                        Expanded(child: buildField('IFSC કોડ (AW)', 'ifscCode'))
                      ]),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('રદ કરો')),
            AppButton(
                label: '💾 સેવ કરો',
                background: AppColors.navy,
                onPressed: () => Navigator.pop(ctx, true)),
          ],
        );
      }),
    );

    if (ok == true && mounted) {
      setState(() {
        _saving = true;
        _alert = null;
      });
      try {
        final res = await context.read<AppState>().api!.manageStudentProfile(
              className: widget.className,
              actionType: student == null ? 'ADD' : 'EDIT',
              studentJson: data,
            );
        if (res['result'] == 'success') {
          await widget.onReload();
          if (mounted) {
            setState(() {
              _saving = false;
              _alertError = false;
            });
          }
        } else {
          setState(() {
            _saving = false;
            _alertError = true;
            _alert = '❌ ${res['message']}';
          });
        }
      } catch (e) {
        setState(() {
          _saving = false;
          _alertError = true;
          _alert = '❌ Error: $e';
        });
      }
    }
  }

  void _openMasterEditScreen() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MasterEditScreen(
                  className: widget.className,
                  students: _students,
                  onReload: widget.onReload,
                )));
  }

  Future<void> _openBulkCertificateDialog(String certType) async {
    if (_students.isEmpty) return;

    bool isAll = true;
    bool printCategory = false;
    final rollCtrl = TextEditingController();

    String selectedReason = 'અન્યત્ર અભ્યાસાર્થે જતાં';
    final customReasonGuCtrl = TextEditingController();
    final customReasonEnCtrl = TextEditingController();

    // નવું: LC માટે તારીખ પસંદ કરવાનું વેરીએબલ
    DateTime selectedLcDate = DateTime.now();

    final Map<String, String> predefinedReasons = {
      'અન્યત્ર અભ્યાસાર્થે જતાં': 'GOING ELSEWHERE FOR STUDY',
      'સહપરિવાર સ્થળાંતર થતાં': 'MIGRATING WITH FAMILY',
      'અન્યત્ર રહેવા જવાથી': 'SHIFTING TO ANOTHER PLACE',
      'વતનમાં જતાં': 'GOING TO NATIVE PLACE',
      'બહાર ગામ જતાં': 'RELOCATING TO ANOTHER VILLAGE/TOWN',
      'વાલીની ઇચ્છાથી': 'BY PARENTS WISH',
      'આ શાળામાં ધોરણ 9 ન હોવાથી': 'STD. 9 IS NOT AVAILABLE IN THIS SCHOOL',
      'અન્ય (Other)': '',
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('🎓 $certType પ્રિન્ટ સેટિંગ્સ',
              style:
                  guFont(fontWeight: FontWeight.bold, color: AppColors.navy)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioListTile<bool>(
                  title: Text('આખા વર્ગ માટે (બધા વિદ્યાર્થીઓ)',
                      style: guFont(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: true,
                  groupValue: isAll,
                  onChanged: (v) => setD(() => isAll = v!),
                ),
                RadioListTile<bool>(
                  title: Text('પસંદ કરેલ રોલ નંબર માટે',
                      style: guFont(fontSize: 13, fontWeight: FontWeight.bold)),
                  value: false,
                  groupValue: isAll,
                  onChanged: (v) => setD(() => isAll = v!),
                ),
                if (!isAll) ...[
                  const SizedBox(height: 10),
                  LabeledField(
                    label: 'રોલ નંબર લખો (અલ્પવિરામથી અલગ પાડીને):',
                    child: TextField(
                      controller: rollCtrl,
                      decoration: const InputDecoration(
                          hintText: 'દા.ત. 1, 2, 5, 10, 11'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: printCategory
                        ? AppColors.teal.withValues(alpha: 0.1)
                        : AppColors.slateLight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color:
                            printCategory ? AppColors.teal : AppColors.border),
                  ),
                  child: CheckboxListTile(
                    title: Text(
                        'સર્ટિફિકેટમાં કેટેગરી છાપવી છે? (દા.ત. અ. જા.)',
                        style: guFont(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                    value: printCategory,
                    onChanged: (v) => setD(() => printCategory = v!),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    dense: true,
                  ),
                ),
                if (certType == 'LC') ...[
                  const SizedBox(height: 16),

                  // નવું: LC કાઢવાની તારીખનું Date Picker
                  LabeledField(
                    label: 'LC કાઢવાની તારીખ (શાળા છોડ્યા તારીખ):',
                    child: InkWell(
                      onTap: () async {
                        final DateTime? picked = await showDatePicker(
                          context: context,
                          initialDate: selectedLcDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setD(() => selectedLcDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                                DateFormat('dd/MM/yyyy').format(selectedLcDate),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold)),
                            const Icon(Icons.calendar_month,
                                color: AppColors.teal, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  LabeledField(
                    label: 'શાળા છોડવાનું કારણ (Reason for leaving):',
                    child: DropdownButtonFormField<String>(
                      value: selectedReason,
                      isExpanded: true,
                      items: predefinedReasons.keys
                          .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(r, style: guFont(fontSize: 12.5))))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setD(() => selectedReason = v);
                      },
                    ),
                  ),
                  if (selectedReason == 'અન્ય (Other)') ...[
                    const SizedBox(height: 10),
                    LabeledField(
                      label: 'કારણ (Gujarati) લખો:',
                      child: TextField(
                          controller: customReasonGuCtrl,
                          style: guFont(fontSize: 13),
                          decoration: const InputDecoration(
                              hintText: 'દા.ત. વાલીની ઇચ્છાથી')),
                    ),
                    const SizedBox(height: 10),
                    LabeledField(
                      label: 'Reason (English) લખો:',
                      child: TextField(
                          controller: customReasonEnCtrl,
                          decoration: const InputDecoration(
                              hintText: 'e.g. BY PARENTS WISH')),
                    ),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('રદ કરો')),
            AppButton(
              label: '📄 PDF બનાવો',
              background: AppColors.teal,
              onPressed: () async {
                List<StudentRecord> targetStudents = [];
                if (isAll) {
                  targetStudents =
                      _students.where((s) => s.name.trim().isNotEmpty).toList();
                } else {
                  final input = rollCtrl.text.trim();
                  if (input.isEmpty) return;
                  final rolls = input
                      .split(',')
                      .map((e) => e.trim())
                      .where((e) => e.isNotEmpty)
                      .toList();
                  targetStudents = _students
                      .where((s) =>
                          s.name.trim().isNotEmpty &&
                          rolls.contains(s.rollNumber))
                      .toList();
                }

                if (targetStudents.isEmpty) {
                  if (mounted)
                    showSnack(context, 'કોઈ વિદ્યાર્થી મળ્યા નથી!',
                        error: true);
                  return;
                }

                String finalReasonGu = '';
                String finalReasonEn = '';
                String finalLcDate = DateFormat('dd/MM/yyyy')
                    .format(selectedLcDate); // પસંદ કરેલી તારીખ

                if (certType == 'LC') {
                  if (selectedReason == 'અન્ય (Other)') {
                    finalReasonGu = customReasonGuCtrl.text.trim();
                    finalReasonEn =
                        customReasonEnCtrl.text.trim().toUpperCase();
                  } else {
                    finalReasonGu = selectedReason;
                    finalReasonEn = predefinedReasons[selectedReason] ?? '';
                  }
                }

                Navigator.pop(ctx);
                bool leaveBlank = false;
                Map<String, int?>? presentDaysMap;
                if (certType == 'LC') {
                  final shouldAutoFill = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      title: const Text('હાજર દિવસો (Present Days)'),
                      content: const Text(
                        'તમારે LC માં વિદ્યાર્થીઓના હાજર દિવસો ઓટોમેટિક (દાખલ કરેલ વિગત પરથી) લખવા છે?',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, null),
                          child: const Text('રદ કરો'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dCtx, false),
                          child: const Text('ના, ખાલી રાખો'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dCtx, true),
                          child: const Text('હા, આગળ વધો'),
                        ),
                      ],
                    ),
                  );
                  if (shouldAutoFill == null || !mounted) return;
                  if (!shouldAutoFill) {
                    leaveBlank = true;
                  } else {
                    final ctrls = <TextEditingController>[
                      for (final s in targetStudents)
                        TextEditingController(
                          text: () {
                            final raw = (s.customFields['present_days'] ??
                                    s.customFields['presentDays'] ??
                                    s.customFields['હાજર દિવસો'] ??
                                    '')
                                .trim();
                            final p = int.tryParse(raw);
                            return (p != null && p > 0) ? '$p' : '';
                          }(),
                        ),
                    ];
                    try {
                      presentDaysMap = await showDialog<Map<String, int?>>(
                        context: context,
                        barrierDismissible: false,
                        builder: (dCtx) => AlertDialog(
                          title: const Text(
                              'LC માટે હાજર દિવસો ચકાસો / દાખલ કરો'),
                          content: SizedBox(
                            width: 520,
                            height: 380,
                            child: ListView.separated(
                              itemCount: targetStudents.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, idx) {
                                final st = targetStudents[idx];
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                          width: 52,
                                          child: Text(st.rollNumber)),
                                      Expanded(child: Text(st.name)),
                                      SizedBox(
                                        width: 96,
                                        child: TextField(
                                          controller: ctrls[idx],
                                          keyboardType: TextInputType.number,
                                          textAlign: TextAlign.center,
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            border: OutlineInputBorder(),
                                            hintText: 'ખાલી',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx, null),
                              child: const Text('રદ કરો'),
                            ),
                            FilledButton(
                              onPressed: () {
                                final out = <String, int?>{};
                                for (var i = 0;
                                    i < targetStudents.length;
                                    i++) {
                                  final v =
                                      int.tryParse(ctrls[i].text.trim());
                                  out[targetStudents[i].id] =
                                      (v != null && v > 0) ? v : null;
                                }
                                Navigator.pop(dCtx, out);
                              },
                              child: const Text('સાચવો અને આગળ વધો'),
                            ),
                          ],
                        ),
                      );
                    } finally {
                      for (final c in ctrls) {
                        c.dispose();
                      }
                    }
                    if (presentDaysMap == null || !mounted) return;
                  }
                }

                showBusyDialog(context, '$certType તૈયાર થાય છે...');

                try {
                  final schoolMeta = context.read<AppState>().school;
                  if (certType == 'BONAFIDE') {
                    await CertificateService.generateBulkBonafide(
                      students: targetStudents,
                      className: widget.className,
                      printCategory: printCategory,
                      schoolMeta: schoolMeta,
                    );
                  } else if (certType == 'LC') {
                    await CertificateService.generateBulkLC(
                      students: targetStudents,
                      className: widget.className,
                      printCategory: printCategory,
                      leaveReasonGu: finalReasonGu,
                      leaveReasonEn: finalReasonEn,
                      lcDate: finalLcDate, // નવો પેરામીટર મોકલ્યો
                      schoolMeta: schoolMeta,
                      presentDaysByStudentId: presentDaysMap,
                      leavePresentDaysBlank: leaveBlank,
                    );
                  }
                  if (mounted) hideBusyDialog(context);
                } catch (e) {
                  if (mounted) {
                    hideBusyDialog(context);
                    showSnack(context, '❌ Error: $e', error: true);
                  }
                }
              },
            ),
          ],
        );
      }),
    );
  }

  Future<void> _deleteStudent(StudentRecord student) async {
    final ok = await showConfirmDialog(context,
        message:
            'શું તમે ખરેખર "${student.name}" ને કાઢી નાખવા માંગો છો? (રોલ નંબર આપોઆપ ગોઠવાઈ જશે)');
    if (ok && mounted) {
      setState(() {
        _saving = true;
        _alert = null;
      });
      try {
        // અહીં આપણે {'sheetRow': student.sheetRow} ની જગ્યાએ student.toJson() મોકલી રહ્યા છીએ
        final res = await context.read<AppState>().api!.manageStudentProfile(
            className: widget.className,
            actionType: 'DELETE',
            studentJson: student.toJson());
        if (res['result'] == 'success') {
          await widget.onReload();
          if (mounted) {
            setState(() {
              _saving = false;
              _alertError = false;
            });
          }
        } else {
          setState(() {
            _saving = false;
            _alertError = true;
            _alert = '❌ ${res['message']}';
          });
        }
      } catch (e) {
        setState(() {
          _saving = false;
          _alertError = true;
          _alert = '❌ Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final regFromAh = _counts((_) => true);
    final present = _counts((s) => s.present);
    final mdm = _counts((s) => s.present && s.mdm);
    final breakfast = _counts((s) => s.present && s.breakfast);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InfoBanner(
          // "👥 વિદ્યાર્થીવાર હાજરી (રજિસ્ટર્ડ: Column AH મુજબ)"
          title:
              '\u{1F465} \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0AB5\u0ABE\u0AB0 \u0AB9\u0ABE\u0A9C\u0AB0\u0AC0 (\u0AB0\u0A9C\u0ABF\u0AB8\u0ACD\u0A9F\u0AB0\u0ACD\u0AA1: Column AH \u0AAE\u0AC1\u0A9C\u0AAC)',
          // "✅ Present/❌ Absent પસંદ કરો. PM Poshan અને Breakfast માત્ર Present માટે."
          hint:
              '\u{2705} Present/\u{274C} Absent \u0AAA\u0AB8\u0A82\u0AA6 \u0A95\u0AB0\u0ACB. PM Poshan \u0A85\u0AA8\u0AC7 Breakfast \u0AAE\u0ABE\u0AA4\u0ACD\u0AB0 Present \u0AAE\u0ABE\u0A9F\u0AC7.',
          child: context.watch<AppState>().schoolType.toLowerCase() == 'coed'
              ? _buildCoedSummaryTables()
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in Category.values)
                      StatChip(label: c.shortLabel, value: regFromAh[c] ?? 0),
                    StatChip(
                        label: 'કુલ રજિસ્ટર્ડ',
                        value: _students.length,
                        total: true),
                    StatChip(
                        label: '\u0AB9\u0ABE\u0A9C\u0AB0',
                        value: _presentTotal),
                    StatChip(
                        label: '\u0A97\u0AC7\u0AB0\u0AB9\u0ABE\u0A9C\u0AB0',
                        value: _students.length - _presentTotal),
                    StatChip(label: 'PM Poshan', value: _mdmTotal),
                    StatChip(label: 'Breakfast', value: _breakfastTotal),
                  ],
                ),
        ),
        if (_students.isEmpty)
          const AlertBox(
            kind: AlertKind.error,
            // "⚠️ વિદ્યાર્થી રોસ્ટર મળ્યો નથી. Class sheetમાં AA = Roll, AF = Name, AH = Category અને AK = Mobile Number ભરો. પ્રથમ વિદ્યાર્થી row 6થી શરૂ કરો."
            text:
                '\u{26A0}\u{FE0F} \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0 \u0AB0\u0ACB\u0AB8\u0ACD\u0A9F\u0AB0 \u0AAE\u0AB3\u0ACD\u0AAF\u0ACB \u0AA8\u0AA5\u0AC0. Class sheet\u0AAE\u0ABE\u0A82 AA = Roll, AF = Name, AH = Category \u0A85\u0AA8\u0AC7 AK = Mobile Number \u0AAD\u0AB0\u0ACB. \u0AAA\u0ACD\u0AB0\u0AA5\u0AAE \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0 row 6\u0AA5\u0AC0 \u0AB6\u0AB0\u0AC2 \u0A95\u0AB0\u0ACB.',
          )
        else ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(
                label: '➕ નવો વિદ્યાર્થી ઉમેરો',
                onPressed: !_saving ? () => _openStudentDialog() : null,
                background: AppColors.navy,
              ),
              AppButton(
                label: '📝 વિદ્યાર્થીઓની વિગતો એડિટ કરો',
                onPressed: !_saving ? () => _openMasterEditScreen() : null,
                background: AppColors.amberDeep,
              ),
              AppButton(
                // "📲 ગેરહાજર વાલીઓને WhatsApp"
                label:
                    '\u{1F4F2} \u0A97\u0AC7\u0AB0\u0AB9\u0ABE\u0A9C\u0AB0 \u0AB5\u0ABE\u0AB2\u0AC0\u0A93\u0AA8\u0AC7 WhatsApp',
                onPressed: !_saving ? _sendAllAbsent : null,
                background: AppColors.greenDeep,
                expand: false,
              ),
              AppButton(
                // "🔄 Student list ફરી લાવો"
                label:
                    '\u{1F504} Student list \u0AAB\u0AB0\u0AC0 \u0AB2\u0ABE\u0AB5\u0ACB',
                onPressed: !_saving ? widget.onReload : null,
                background: AppColors.slate,
              ),
              AppButton(
                label: '🎓 બોનાફાઈડ',
                onPressed: !_saving && _students.isNotEmpty
                    ? () => _openBulkCertificateDialog('BONAFIDE')
                    : null,
                background: const Color(0xFF0284C7),
              ),
              const SizedBox(width: 8), // બે બટન વચ્ચે થોડી જગ્યા
              AppButton(
                label: '🎓 LC કાઢો',
                onPressed: !_saving && _students.isNotEmpty
                    ? () => _openBulkCertificateDialog('LC')
                    : null,
                background:
                    const Color(0xFF059669), // LC માટે થોડો લીલો કલર (Green)
              ),
              const SizedBox(width: 8),
              AppButton(
                label: '📝 રજા રિપોર્ટ (Leave)',
                background: Colors.teal,
                onPressed: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const LeaveReportScreen()));
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _summaryTable(regFromAh, present, mdm, breakfast),
          const SizedBox(height: 12),
          for (int index = 0; index < _students.length; index++) ...[
            if (index > 0) const SizedBox(height: 8),
            _studentCard(index),
          ],
          if (_alert != null) ...[
            const SizedBox(height: 12),
            AlertBox(
                kind: _alertError ? AlertKind.error : AlertKind.success,
                text: _alert!),
          ],
          const SizedBox(height: 16),
          if (!widget.enabled)
            const AlertBox(
              kind: AlertKind.lock,
              // "🔒 12:01 PM પછી અથવા જૂની તારીખની પહેલેથી સેવ થયેલી હાજરીમાં ફેરફાર કરી શકાશે નહીં."
              text:
                  '\u{1F512} 12:01 PM \u0AAA\u0A9B\u0AC0 \u0A85\u0AA5\u0AB5\u0ABE \u0A9C\u0AC2\u0AA8\u0AC0 \u0AA4\u0ABE\u0AB0\u0AC0\u0A96\u0AA8\u0AC0 \u0AAA\u0AB9\u0AC7\u0AB2\u0AC7\u0AA5\u0AC0 \u0AB8\u0AC7\u0AB5 \u0AA5\u0AAF\u0AC7\u0AB2\u0AC0 \u0AB9\u0ABE\u0A9C\u0AB0\u0AC0\u0AAE\u0ABE\u0A82 \u0AAB\u0AC7\u0AB0\u0AAB\u0ABE\u0AB0 \u0A95\u0AB0\u0AC0 \u0AB6\u0A95\u0ABE\u0AB6\u0AC7 \u0AA8\u0AB9\u0AC0\u0A82.',
            )
          else if (!widget.canSubmit)
            const AlertBox(
              kind: AlertKind.error,
              // "🚫 તમને આ વર્ગ માટે attendance save કરવાની પરવાનગી નથી."
              text:
                  '\u{1F6AB} \u0AA4\u0AAE\u0AA8\u0AC7 \u0A86 \u0AB5\u0AB0\u0ACD\u0A97 \u0AAE\u0ABE\u0A9F\u0AC7 attendance save \u0A95\u0AB0\u0AB5\u0ABE\u0AA8\u0AC0 \u0AAA\u0AB0\u0AB5\u0ABE\u0AA8\u0A97\u0AC0 \u0AA8\u0AA5\u0AC0.',
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                AppButton(
                  // "સેવ થાય છે…" : "💾 વિદ્યાર્થીવાર સેવ કરો"
                  label: _saving
                      ? '\u0AB8\u0AC7\u0AB5 \u0AA5\u0ABE\u0AAF \u0A9B\u0AC7\u{2026}'
                      : '\u{1F4BE} \u0AB5\u0ABF\u0AA6\u0ACD\u0AAF\u0ABE\u0AB0\u0ACD\u0AA5\u0AC0\u0AB5\u0ABE\u0AB0 \u0AB8\u0AC7\u0AB5 \u0A95\u0AB0\u0ACB',
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _summaryTable(
    Map<Category, int> regFromAh,
    Map<Category, int> present,
    Map<Category, int> mdm,
    Map<Category, int> breakfast,
  ) {
    String n(Map<Category, int> map, Category c) => '${map[c] ?? 0}';
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Table(
        border: TableBorder.symmetric(
            inside: const BorderSide(color: AppColors.border)),
        columnWidths: const {
          0: FlexColumnWidth(1.4),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1),
          3: FlexColumnWidth(1),
          4: FlexColumnWidth(1),
          5: FlexColumnWidth(1),
        },
        children: [
          _tableRow(
            [
              'Category',
              '\u0AB0\u0A9C\u0ABF\u0AB8\u0ACD\u0A9F\u0AB0\u0ACD\u0AA1',
              'Present',
              'Absent',
              'PM Poshan',
              'Breakfast'
            ],
            header: true,
          ),
          for (final c in Category.values)
            _tableRow([
              c.shortLabel,
              n(regFromAh, c),
              n(present, c),
              n(_counts((s) => !s.present), c),
              n(mdm, c),
              n(breakfast, c),
            ]),
          _tableRow([
            '\u0A95\u0AC1\u0AB2', // કુલ
            '${_students.length}',
            '$_presentTotal',
            '${_students.length - _presentTotal}',
            '$_mdmTotal',
            '$_breakfastTotal',
          ], total: true),
        ],
      ),
    );
  }

  TableRow _tableRow(List<String> values,
      {bool header = false, bool total = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: header
            ? AppColors.navy
            : total
                ? AppColors.slateLight
                : Colors.white,
      ),
      children: values
          .map((v) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    v,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: guFont(
                      fontSize: 11,
                      fontWeight:
                          header || total ? FontWeight.w800 : FontWeight.w700,
                      color: header ? Colors.white : AppColors.navy,
                    ),
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _studentCard(int index) {
    final student = _students[index];
    final disabled = !widget.enabled || _saving;
    final absent = !student.present;

    Widget rollBadge() => Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: absent ? AppColors.roseLight : AppColors.greenBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            student.rollNumber.isEmpty ? '${index + 1}' : student.rollNumber,
            style: guFont(fontSize: 12, fontWeight: FontWeight.w900),
          ),
        );

    Widget nameAndMeta() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              student.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: guFont(fontSize: 14.5, fontWeight: FontWeight.w900),
            ),
            Text(
              '${student.category.shortLabel} • ${student.gender == 'BOYS' ? 'Boys' : student.gender == 'GIRLS' ? 'Girls' : 'Gender not set'}${student.mobile.isEmpty ? '' : '  \u{2022}  \u{1F4F1} ${student.mobile}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: guFont(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.slate),
            ),
          ],
        );

    Widget whatsAppBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.only(left: 4),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'WhatsApp',
          onPressed: (!student.present && !_saving)
              ? () => _sendWhatsApp(student)
              : null,
          icon: Icon(Icons.chat,
              size: 20,
              color: (!student.present && !_saving)
                  ? AppColors.greenDeep
                  : AppColors.border),
        );

    Widget editBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'વિગત સુધારો',
          onPressed: !_saving ? () => _openStudentDialog(student) : null,
          icon: Icon(Icons.edit,
              size: 18, color: !_saving ? AppColors.teal : AppColors.border),
        );

    Widget delBtn() => IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'કાઢી નાખો',
          onPressed: !_saving ? () => _deleteStudent(student) : null,
          icon: Icon(Icons.delete,
              size: 18, color: !_saving ? AppColors.rose : AppColors.border),
        );

    List<Widget> buildTabs({required bool expandEach}) {
      final tabs = [
        _actionTab(
            label: '\u{2705} Present',
            selected: student.present,
            enabled: !disabled,
            color: AppColors.greenDeep,
            onTap: () => _setAttendance(index, true)),
        _actionTab(
            label: '\u{274C} Absent',
            selected: !student.present,
            enabled: !disabled,
            color: AppColors.rose,
            onTap: () => _setAttendance(index, false)),
        _actionTab(
            label: '\u{1F37D}\u{FE0F} PM Poshan',
            selected: student.present && student.mdm,
            enabled: !disabled && student.present,
            color: AppColors.gold,
            onTap: () => _toggleMdm(index)),
        _actionTab(
            label: '\u{1F950} Breakfast',
            selected: student.present && student.breakfast,
            enabled: !disabled && student.present,
            color: AppColors.teal,
            onTap: () => _toggleBreakfast(index)),
      ];
      if (!expandEach) return tabs;
      return [
        for (int i = 0; i < tabs.length; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          Expanded(child: tabs[i])
        ]
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
            color: absent
                ? AppColors.rose.withValues(alpha: 0.25)
                : AppColors.border,
            width: 1.5),
        boxShadow: [AppTheme.shadowSm],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth >= 640;
          if (isWideScreen) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                rollBadge(),
                const SizedBox(width: 10),
                Expanded(child: nameAndMeta()),
                const SizedBox(width: 8),
                editBtn(),
                delBtn(),
                Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: buildTabs(expandEach: false)),
                whatsAppBtn(),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  rollBadge(),
                  const SizedBox(width: 8),
                  Expanded(child: nameAndMeta()),
                  editBtn(),
                  delBtn(),
                  whatsAppBtn(),
                ],
              ),
              const SizedBox(height: 7),
              Row(children: buildTabs(expandEach: true)),
            ],
          );
        },
      ),
    );
  }

  Widget _actionTab({
    required String label,
    required bool selected,
    required bool enabled,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? color : AppColors.slateLight,
          border: Border.all(
              color: selected ? color : AppColors.border, width: 1.3),
          borderRadius: BorderRadius.circular(7),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            style: guFont(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: selected
                  ? Colors.white
                  : (enabled ? AppColors.navy : AppColors.slate),
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================
// MASTER EDIT SCREEN (Spreadsheet View with ALL 52 Columns)
// =========================================================
class MasterEditScreen extends StatefulWidget {
  final String className;
  final List<StudentRecord> students;
  final Future<void> Function() onReload;

  const MasterEditScreen(
      {super.key,
      required this.className,
      required this.students,
      required this.onReload});

  @override
  State<MasterEditScreen> createState() => _MasterEditScreenState();
}

class _MasterEditScreenState extends State<MasterEditScreen> {
  late List<Map<String, dynamic>> _editedData;
  final Set<int> _modifiedRows = {};
  bool _isSavingAll = false;
  int _saveProgress = 0;
  bool _loadingHeaders = true;

  // Horizontal Sync માટેના બે Controllers (હેડર અને ડેટાને ડાબે-જમણે એકસાથે ફેરવવા)
  final ScrollController _horizontalHeaderCtrl = ScrollController();
  final ScrollController _horizontalDataCtrl = ScrollController();
  bool _isSyncing = false;

  final List<Map<String, dynamic>> _allColumns = [
    // બેઝિક
    {'key': 'gr', 'label': 'GR નં', 'width': 80.0},
    {'key': 'mobile', 'label': 'મોબાઈલ', 'width': 110.0},
    {'key': 'dd', 'label': 'DD', 'width': 50.0},
    {'key': 'mm', 'label': 'MM', 'width': 50.0},
    {'key': 'yyyy', 'label': 'YYYY', 'width': 60.0},
    {'key': 'caste', 'label': 'પેટા જ્ઞાતિ', 'width': 100.0},
    {
      'key': 'category',
      'label': 'કેટેગરી',
      'width': 90.0,
      'dropdown': ['SC', 'ST', 'OBC', 'OTHER']
    },
    {'key': 'motherName', 'label': 'માતાનું નામ', 'width': 130.0},
    {'key': 'birthPlace', 'label': 'જન્મ સ્થળ', 'width': 120.0},
    {'key': 'dobWords', 'label': 'જન્મ તારીખ શબ્દોમાં', 'width': 180.0},
    {'key': 'lastSchool', 'label': 'પૂર્વ શાળાનું નામ', 'width': 150.0},
    {'key': 'enrollSchClass', 'label': 'શાળામાં દાખલ ધોરણ', 'width': 120.0},
    {
      'key': 'enrollSchClassWords',
      'label': 'શાળા દાખલ ધોરણ શબ્દોમાં',
      'width': 160.0
    },
    // English
    {'key': 'nameEn', 'label': 'NAME IN ENGLISH', 'width': 150.0},
    {'key': 'casteEn', 'label': 'CASTE IN ENG', 'width': 100.0},
    {'key': 'catEn', 'label': 'CATEGORY IN ENG', 'width': 120.0},
    {'key': 'motherEn', 'label': 'MOTHER IN ENG', 'width': 140.0},
    {'key': 'birthPlaceEn', 'label': 'BIRTH PLACE ENG', 'width': 130.0},
    {'key': 'dobEn', 'label': 'DOB IN ENGLISH', 'width': 140.0},
    {'key': 'lastSchoolEn', 'label': 'LAST SCHOOL ENG', 'width': 150.0},
    {'key': 'enrollSchClassEn', 'label': 'ENROLL CLASS ENG', 'width': 140.0},
    {
      'key': 'enrollSchClassWordsEn',
      'label': 'ENROLL CLS WORDS ENG',
      'width': 180.0
    },
    // શિષ્યવૃત્તિ & આઈડી
    {'key': 'uid', 'label': 'UID નંબર', 'width': 130.0},
    {'key': 'pen', 'label': 'PEN નંબર', 'width': 130.0},
    {
      'key': 'isDivyang',
      'label': 'દિવ્યાંગ?',
      'width': 90.0,
      'dropdown': ['ના', 'હા']
    },
    {
      'key': 'scholarshipDone',
      'label': 'શિષ્યવૃત્તિ?',
      'width': 90.0,
      'dropdown': ['ના', 'હા']
    },
    {'key': 'scholarshipReason', 'label': 'શિષ્યવૃત્તિ કારણ', 'width': 150.0},
    {'key': 'scholarshipOther', 'label': 'અન્ય (BC)', 'width': 120.0},
    // બેંક વિગતો (આધાર અને રેશન કાર્ડની વિગતો હવે એકત્રિત થતી નથી)
    {'key': 'bankName', 'label': 'બેંકનું નામ', 'width': 140.0},
    {'key': 'bankBranch', 'label': 'બેંક બ્રાન્ચ', 'width': 120.0},
    {'key': 'nameAsPassbook', 'label': 'પાસબુક મુજબ નામ', 'width': 150.0},
    {'key': 'accountNumber', 'label': 'એકાઉન્ટ નંબર', 'width': 130.0},
    {'key': 'ifscCode', 'label': 'IFSC કોડ', 'width': 110.0},
    {'key': 'enrollSchool', 'label': 'શાળા પ્રવેશ', 'width': 100.0},
    {'key': 'enrollClass', 'label': 'વર્ગ પ્રવેશ', 'width': 100.0},
  ];

  List<String> _selectedKeys = [
    'gr',
    'uid',
    'pen',
    'isDivyang',
    'scholarshipDone',
    'scholarshipReason'
  ];

  @override
  void initState() {
    super.initState();
    _editedData = widget.students.map((s) => s.toJson()).toList();
    _fetchCustomHeaders();

    // હેડર અને ડેટાના Horizontal સ્ક્રોલને એકબીજા સાથે જોડવા માટે
    _horizontalHeaderCtrl.addListener(() {
      if (_horizontalHeaderCtrl.hasClients &&
          _horizontalDataCtrl.hasClients &&
          !_isSyncing) {
        _isSyncing = true;
        _horizontalDataCtrl.jumpTo(_horizontalHeaderCtrl.offset);
        _isSyncing = false;
      }
    });
    _horizontalDataCtrl.addListener(() {
      if (_horizontalHeaderCtrl.hasClients &&
          _horizontalDataCtrl.hasClients &&
          !_isSyncing) {
        _isSyncing = true;
        _horizontalHeaderCtrl.jumpTo(_horizontalDataCtrl.offset);
        _isSyncing = false;
      }
    });
  }

  @override
  void dispose() {
    _horizontalHeaderCtrl.dispose();
    _horizontalDataCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomHeaders() async {
    try {
      final headers = await context.read<AppState>().api!.getCustomHeaders();
      for (int i = 0; i < headers.length; i++) {
        if (headers[i].trim().isNotEmpty) {
          _allColumns.add({
            'key': 'c${i + 1}',
            'label': headers[i],
            'width': 120.0,
            'isCustom': true
          });
          _selectedKeys
              .add('c${i + 1}'); // નવા બનાવેલા Custom ખાના ડાયરેક્ટ દેખાશે
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingHeaders = false);
  }

  Future<void> _saveAll() async {
    if (_modifiedRows.isEmpty) return;
    setState(() {
      _isSavingAll = true;
      _saveProgress = 0;
    });
    List<int> rowsToSave = _modifiedRows.toList();
    bool hasError = false;

    for (int index in rowsToSave) {
      setState(() => _saveProgress++);
      try {
        final res = await context.read<AppState>().api!.manageStudentProfile(
              className: widget.className,
              actionType: 'EDIT',
              studentJson: _editedData[index],
            );
        if (res['result'] == 'success') {
          setState(() => _modifiedRows.remove(index));
        } else {
          if (mounted)
            showSnack(
                context, '❌ ${_editedData[index]['name']}: ${res['message']}',
                error: true);
          hasError = true;
          break;
        }
      } catch (e) {
        if (mounted) showSnack(context, '❌ Error: $e', error: true);
        hasError = true;
        break;
      }
    }
    if (mounted) {
      setState(() => _isSavingAll = false);
      if (!hasError && _modifiedRows.isEmpty) {
        showSnack(context, '✅ તમામ ફેરફારો સેવ થઈ ગયા!');
        await widget.onReload();
        if (!mounted) return;
        Navigator.pop(context);
      }
    }
  }

  void _showColumnSelector() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        return AlertDialog(
          title: Text('કયા ખાના સુધારવા છે?',
              style:
                  guFont(fontWeight: FontWeight.bold, color: AppColors.navy)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _allColumns.map((col) {
                  final key = col['key'] as String;
                  return FilterChip(
                    label: Text(col['label'], style: guFont(fontSize: 12)),
                    selected: _selectedKeys.contains(key),
                    selectedColor: AppColors.goldPale,
                    onSelected: (val) {
                      setD(() {
                        if (val)
                          _selectedKeys.add(key);
                        else
                          _selectedKeys.remove(key);
                      });
                      setState(() {});
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            AppButton(
                label: 'OK',
                background: AppColors.navy,
                onPressed: () => Navigator.pop(ctx))
          ],
        );
      }),
    );
  }

  // Cell Design - Height ફિક્સ કરી દીધી છે જેથી ડાબી-જમણી બાજુ પર્ફેક્ટ મેચ થાય
  Widget _buildCell(Widget child, double width,
      {bool isHeader = false, bool isModified = false}) {
    return Container(
      width: width,
      height: isHeader ? 45 : 68, // Header=45, Data=68 (3 લાઈન માટે)
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isHeader
            ? AppColors.slateLight
            : (isModified ? const Color(0xFFFFFBEB) : Colors.white),
        border: Border(
            bottom:
                BorderSide(color: isHeader ? Colors.black26 : Colors.black12),
            right: const BorderSide(color: Colors.black12)),
      ),
      child: child,
    );
  }

  Widget _buildTextField(int index, String key,
      {bool isDropdown = false,
      List<String>? items,
      bool isCustom = false,
      int maxLines = 1}) {
    if (isDropdown) {
      if (!items!.contains(_editedData[index][key]))
        _editedData[index][key] = 'ના';
      return DropdownButtonFormField<String>(
        value: _editedData[index][key],
        isDense: true,
        decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 4)),
        style: guFont(fontSize: 13, color: Colors.black),
        items: items
            .map((i) => DropdownMenuItem(value: i, child: Text(i)))
            .toList(),
        onChanged: (v) {
          setState(() {
            _editedData[index][key] = v;
            _modifiedRows.add(index);
            if (key == 'scholarshipDone' && v == 'હા')
              _editedData[index]['scholarshipReason'] = '';
          });
        },
      );
    }

    bool isReasonDisabled = key == 'scholarshipReason' &&
        _editedData[index]['scholarshipDone'] != 'ના';
    String getVal() {
      if (isReasonDisabled) return '';
      if (isCustom)
        return (_editedData[index]['customFields'] as Map)[key] ?? '';
      return _editedData[index][key]?.toString() ?? '';
    }

    return TextFormField(
      key: ValueKey('${index}_${key}_$isReasonDisabled'),
      initialValue: getVal(),
      enabled: !isReasonDisabled,
      maxLines: maxLines, // નામના ખાનામાં 3 લાઈન સપોર્ટ
      style: guFont(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: isReasonDisabled ? Colors.grey : Colors.black,
          height: 1.2),
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Colors.black12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: AppColors.teal, width: 1.5),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        fillColor: isReasonDisabled
            ? Colors.black.withValues(alpha: 0.05)
            : Colors.transparent,
        filled: true,
      ),
      onChanged: (val) {
        if (!isReasonDisabled) {
          setState(() {
            if (isCustom)
              (_editedData[index]['customFields'] as Map)[key] = val;
            else
              _editedData[index][key] = val;
            _modifiedRows.add(index);
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingHeaders)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('📝 Edit (ધોરણ ${ClassLabel.bare(widget.className)})',
            style: guFont(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AppColors.navy,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.view_column, size: 18),
              label: Text('કોલમ પસંદ કરો',
                  style: guFont(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.navy),
              onPressed: _showColumnSelector,
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // ----------------------------------------------------
          // 1. STICKY HEADERS ROW (આખી લાઈન ઉપર ચોંટેલી રહેશે)
          // ----------------------------------------------------
          Container(
            decoration: const BoxDecoration(
              color: AppColors.slateLight,
              boxShadow: [
                BoxShadow(
                    color: Colors.black12, blurRadius: 3, offset: Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                // ડાબી બાજુનું ફિક્સ હેડર
                Container(
                  width: 222, // 2 પિક્સલ વધાર્યા જેથી પટ્ટી ના આવે
                  decoration: const BoxDecoration(
                      border: Border(right: BorderSide(color: Colors.black26))),
                  child: Row(
                    children: [
                      _buildCell(
                          Text('Roll',
                              style: guFont(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyMid)),
                          50,
                          isHeader: true),
                      _buildCell(
                          Text('વિદ્યાર્થીનું નામ',
                              style: guFont(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.navyMid)),
                          170,
                          isHeader: true),
                    ],
                  ),
                ),
                // જમણી બાજુના હેડર (Horizontal Scroll)
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontalHeaderCtrl,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _selectedKeys.map((key) {
                        final col =
                            _allColumns.firstWhere((c) => c['key'] == key);
                        return _buildCell(
                            Text(col['label'],
                                style: guFont(
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.navyMid)),
                            col['width'],
                            isHeader: true);
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // 2. SCROLLABLE DATA BODY (1 જ Vertical Scroll બન્ને માટે)
          // ----------------------------------------------------
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis
                  .vertical, // આનાથી ડાબી અને જમણી બાજુ એકસાથે જ ઉપર-નીચે થશે
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ડાબી બાજુનું ડેટા કોલમ
                  Container(
                    width: 222, // 2 પિક્સલ વધાર્યા
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black12,
                            blurRadius: 3,
                            offset: Offset(2, 0))
                      ],
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < _editedData.length; i++)
                          Row(
                            children: [
                              _buildCell(_buildTextField(i, 'rollNumber'), 50,
                                  isModified: _modifiedRows.contains(i)),
                              _buildCell(
                                  _buildTextField(i, 'name', maxLines: 3), 170,
                                  isModified: _modifiedRows.contains(i)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // જમણી બાજુનું ડેટા કોલમ (Horizontal Scroll)
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _horizontalDataCtrl,
                      scrollDirection: Axis.horizontal,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (int i = 0; i < _editedData.length; i++)
                            Row(
                              children: _selectedKeys.map((key) {
                                final col = _allColumns
                                    .firstWhere((c) => c['key'] == key);
                                return _buildCell(
                                  _buildTextField(i, key,
                                      isDropdown: col['dropdown'] != null,
                                      items: col['dropdown'],
                                      isCustom: col['isCustom'] == true),
                                  col['width'],
                                  isModified: _modifiedRows.contains(i),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _modifiedRows.isNotEmpty
          ? BottomAppBar(
              color: Colors.white,
              elevation: 10,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('  ${_modifiedRows.length} વિદ્યાર્થી બદલાયા',
                      style: guFont(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.rose)),
                  AppButton(
                    label: _isSavingAll
                        ? '$_saveProgress / ${_modifiedRows.length} સેવ થાય છે...'
                        : '💾 બધા ફેરફારો સેવ કરો',
                    background: AppColors.greenDeep,
                    loading: _isSavingAll,
                    onPressed: _isSavingAll ? null : _saveAll,
                  )
                ],
              ),
            )
          : null,
    );
  }
}
