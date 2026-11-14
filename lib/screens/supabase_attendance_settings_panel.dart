import 'package:flutter/material.dart';

import '../services/supabase_school_settings_service.dart';
import '../services/datewise_report_columns.dart';
import 'datewise_columns_settings_dialog.dart';

/// School Admin setting for the daily attendance save cutoff.
/// The database trigger uses the same setting, so hiding the Save button is
/// not the only enforcement layer.
class SupabaseAttendanceSettingsPanel extends StatefulWidget {
  const SupabaseAttendanceSettingsPanel({super.key, this.readOnly = false});
  final bool readOnly;

  @override
  State<SupabaseAttendanceSettingsPanel> createState() =>
      _SupabaseAttendanceSettingsPanelState();
}

class _SupabaseAttendanceSettingsPanelState
    extends State<SupabaseAttendanceSettingsPanel> {
  final SupabaseSchoolSettingsService _settings = SupabaseSchoolSettingsService();
  String _lockTime = SupabaseSchoolSettingsService.defaultAttendanceLockTime;
  bool _threeStepSaveMode = false;
  bool _directEntryEnabled = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _status;
  int _visibleColumnCount = DateWiseReportColumn.all.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final config = await _settings.loadConfig();
      final visibleColumns = await _settings.visibleDateWiseColumns();
      final candidate = '${config['attendance_lock_time'] ?? SupabaseSchoolSettingsService.defaultAttendanceLockTime}'.trim();
      final lockTime = _settings.isValidLockTime(candidate)
          ? candidate
          : SupabaseSchoolSettingsService.defaultAttendanceLockTime;
      final threeStep = config['three_step_attendance_save_mode'] == true;
      final directEnabled = config['direct_attendance_entry_enabled'] != false;
      if (!mounted) return;
      setState(() {
        _lockTime = lockTime;
        _threeStepSaveMode = threeStep;
        _directEntryEnabled = directEnabled;
        _visibleColumnCount = visibleColumns.length;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _error = '$error'.replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  TimeOfDay _parsedLockTime() {
    final parts = _lockTime.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 12,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '01') ?? 1,
    );
  }

  Future<void> _chooseTime() async {
    if (widget.readOnly || _saving) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: _parsedLockTime(),
      helpText: 'Daily attendance save lock (India time)',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lockTime = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      _status = null;
    });
  }

  Future<void> _save() async {
    if (widget.readOnly || _saving) return;
    setState(() { _saving = true; _error = null; _status = null; });
    try {
      await _settings.saveAttendanceLockTime(_lockTime);
      await _settings.saveThreeStepAttendanceSaveMode(_threeStepSaveMode);
      await _settings.saveDirectAttendanceEntryEnabled(_directEntryEnabled);
      if (!mounted) return;
      setState(() => _status = 'Daily attendance lock time saved for this school.');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance lock time saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _lockTime.isEmpty) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Try again')),
        ]),
      ));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Attendance Settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Set the time after which teachers cannot change or save attendance. The time is interpreted in Asia/Kolkata (India). The default is 12:01 PM.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily attendance lock time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text(_parsedLockTime().format(context), style: Theme.of(context).textTheme.headlineSmall)),
                    OutlinedButton.icon(
                      onPressed: widget.readOnly || _saving ? null : _chooseTime,
                      icon: const Icon(Icons.schedule),
                      label: const Text('Choose time'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('24-hour value saved: $_lockTime', style: Theme.of(context).textTheme.bodySmall),
                if (widget.readOnly) ...[
                  const SizedBox(height: 8),
                  const Text('This school is read-only. Settings cannot be changed until it is active, valid, and unblocked.'),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '૩ તબક્કામાં હાજરી સેવ મોડ (3-Step Separate Save Mode)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _threeStepSaveMode,
                  onChanged: widget.readOnly || _saving
                      ? null
                      : (val) async {
                          setState(() {
                            _threeStepSaveMode = val;
                            _status = null;
                          });
                          try {
                            await _settings.saveThreeStepAttendanceSaveMode(val);
                            if (!mounted) return;
                            setState(() {
                              _status = val
                                  ? '૩-તબક્કા સેવ મોડ ચાલુ કરવામાં આવ્યો (1. Present/Absent -> 2. PM POSHAN / 3. Breakfast).'
                                  : 'સિંગલ સેવ બટન મોડ ચાલુ કરવામાં આવ્યો (૧ જ બટનથી ત્રણેય સેવ).';
                            });
                          } catch (e) {
                            if (mounted) {
                              setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
                            }
                          }
                        },
                  title: Text(
                    _threeStepSaveMode
                        ? 'ચાલુ (Active): ૩ અલગ સેવ બટન (Present/Absent, PM POSHAN, Breakfast)'
                        : 'બંધ (Deactive): ૧ જ સેવ બટનથી ત્રણેય વિગત સાથે સેવ (Default)',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'ચાલુ કરવાથી શિક્ષકે પહેલા હાજર-ગેરહાજર (Present/Absent) સેવ કરવું પડશે (જે સેવ થતાં ફ્રીઝ થશે), અને ત્યારબાદ કોઈપણ ક્રમમાં અલ્પાહાર (Breakfast) અથવા PM POSHAN અલગ-અલગ સમયે સેવ કરી શકાશે.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ડાયરેક્ટ હાજરી એન્ટ્રી મોડ (Direct Entry Mode — Active / Deactive)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _directEntryEnabled,
                  onChanged: widget.readOnly || _saving
                      ? null
                      : (val) async {
                          setState(() {
                            _directEntryEnabled = val;
                            _status = null;
                          });
                          try {
                            await _settings.saveDirectAttendanceEntryEnabled(val);
                            if (!mounted) return;
                            setState(() {
                              _status = val
                                  ? 'Direct Entry મોડ ચાલુ કરવામાં આવ્યો (Student Selection અને Direct Entry બંને દેખાશે).'
                                  : 'Direct Entry મોડ બંધ કરવામાં આવ્યો (માત્ર Student Selection જ દેખાશે).';
                            });
                          } catch (e) {
                            if (mounted) {
                              setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
                            }
                          }
                        },
                  title: Text(
                    _directEntryEnabled
                        ? 'ચાલુ (Active): Student Selection અને Direct Entry બંને વિકલ્પ દેખાશે'
                        : 'બંધ (Deactive): માત્ર વિદ્યાર્થીવાર હાજરી (Student Selection) જ દેખાશે',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'બંધ કરવાથી શિક્ષકની હાજરી સ્ક્રીન પર Direct Entry ટેબ બંધ રહેશે અને માત્ર વિદ્યાર્થીવાર હાજરી (Student Selection) જ ભરી શકાશે.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('School-wide report settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                const SizedBox(height: 6),
                Text('DATE WISE columns selected: $_visibleColumnCount of ${DateWiseReportColumn.all.length}. The Class column is always shown; this setting applies to all users in this school.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.readOnly || _saving ? null : () async {
                    await showDateWiseColumnSettingsDialog(context);
                    if (!mounted) return;
                    try {
                      final count = (await _settings.visibleDateWiseColumns()).length;
                      if (mounted) setState(() => _visibleColumnCount = count);
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.view_column_outlined),
                  label: const Text('Configure DATE WISE columns'),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(_status!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: widget.readOnly || _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
          label: Text(_saving ? 'Saving…' : 'Save attendance settings'),
        ),
      ],
    );
  }
}
