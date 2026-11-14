import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

/// Shows a one-time birthday reminder popup when an assigned teacher opens
/// the signed-in home. Both class and student rows are protected by existing
/// Supabase RLS / assigned-class policies; this widget does not fetch schoolwide
/// student data for a teacher.
class SupabaseBirthdayReminderOnLogin extends StatefulWidget {
  const SupabaseBirthdayReminderOnLogin({super.key});

  @override
  State<SupabaseBirthdayReminderOnLogin> createState() =>
      _SupabaseBirthdayReminderOnLoginState();
}

class _SupabaseBirthdayReminderOnLoginState
    extends State<SupabaseBirthdayReminderOnLogin> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAndShow();
    });
  }

  DateTime _indiaCalendarDate() {
    // School dates use India Standard Time, independent of the device timezone.
    final indiaNow = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime(indiaNow.year, indiaNow.month, indiaNow.day);
  }

  int? _intValue(dynamic value) => int.tryParse('${value ?? ''}'.trim());

  Future<void> _loadAndShow() async {
    if (_started) return;
    _started = true;

    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;

      final rawSchoolRef = await client.rpc('current_school_ref');
      final schoolRef = '${rawSchoolRef ?? ''}'.trim();
      if (schoolRef.isEmpty) return;

      // RLS makes this list contain only active classes assigned to this teacher.
      final classRows = await client
          .from('school_classes')
          .select('id, class_key, label')
          .eq('school_ref', schoolRef)
          .eq('is_active', true);
      final classLabels = <String, String>{};
      for (final rawClass in classRows) {
        final row = Map<String, dynamic>.from(rawClass);
        final id = '${row['id'] ?? ''}'.trim();
        final label = '${row['label'] ?? row['class_key'] ?? ''}'.trim();
        if (id.isNotEmpty) classLabels[id] = label.isEmpty ? 'વર્ગ' : label;
      }
      if (classLabels.isEmpty) return;

      // The students table also has assigned-class RLS. The class_id filter
      // keeps the query efficient and the policy prevents cross-class leakage.
      final studentRows = await client
          .from('students')
          .select('id, name, dd, mm, yyyy, class_id, roll_number')
          .eq('school_ref', schoolRef)
          .eq('is_active', true)
          .inFilter('class_id', classLabels.keys.toList())
          .order('roll_number');

      final today = _indiaCalendarDate();
      final tomorrow = today.add(const Duration(days: 1));
      final todayBirthdays = <_BirthdayStudent>[];
      final tomorrowBirthdays = <_BirthdayStudent>[];

      for (final rawStudent in studentRows) {
        final row = Map<String, dynamic>.from(rawStudent);
        final name = '${row['name'] ?? ''}'.trim();
        final classId = '${row['class_id'] ?? ''}'.trim();
        final day = _intValue(row['dd']);
        final month = _intValue(row['mm']);
        final birthYear = _intValue(row['yyyy']);
        if (name.isEmpty || day == null || month == null) continue;
        if (day < 1 || day > 31 || month < 1 || month > 12) continue;
        // Validate day/month (using leap year 2000 so 29 February is accepted).
        final validation = DateTime(2000, month, day);
        if (validation.month != month || validation.day != day) continue;

        final student = _BirthdayStudent(
          name: name,
          classLabel: classLabels[classId] ?? 'વર્ગ',
          completedYears: birthYear != null && birthYear >= 1900 && birthYear <= today.year
              ? today.year - birthYear
              : null,
        );
        if (day == today.day && month == today.month) {
          todayBirthdays.add(student);
        } else if (day == tomorrow.day && month == tomorrow.month) {
          tomorrowBirthdays.add(student);
        }
      }

      if (!mounted || (todayBirthdays.isEmpty && tomorrowBirthdays.isEmpty)) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: const Row(
            children: <Widget>[
              Icon(Icons.cake_outlined),
              SizedBox(width: 10),
              Expanded(child: Text('જન્મદિવસ રિમાઇન્ડર')),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 460),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (todayBirthdays.isNotEmpty) ...<Widget>[
                    Text(
                      '🎂 આજનો જન્મદિવસ',
                      style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    for (final student in todayBirthdays)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          'આજનો જન્મદિવસ: ${student.name}'
                          '${student.completedYears == null ? '' : ' — ${student.completedYears} વર્ષ પૂર્ણ'}'
                          ' (${student.classLabel})',
                        ),
                      ),
                  ],
                  if (todayBirthdays.isNotEmpty && tomorrowBirthdays.isNotEmpty)
                    const Divider(height: 24),
                  if (tomorrowBirthdays.isNotEmpty) ...<Widget>[
                    Text(
                      '🎈 આવતીકાલનો જન્મદિવસ',
                      style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 6),
                    for (final student in tomorrowBirthdays)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text(
                          'આવતીકાલે જન્મદિવસ: ${student.name} (${student.classLabel})',
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('બરાબર'),
            ),
          ],
        ),
      );
    } catch (error, stackTrace) {
      // Reminders are non-critical. Do not stop the teacher from opening home.
      debugPrint('Birthday reminder could not load: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _BirthdayStudent {
  const _BirthdayStudent({
    required this.name,
    required this.classLabel,
    required this.completedYears,
  });

  final String name;
  final String classLabel;
  final int? completedYears;
}
