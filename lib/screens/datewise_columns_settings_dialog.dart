import 'package:flutter/material.dart';

import '../services/datewise_report_columns.dart';
import '../services/school_type.dart';
import '../services/supabase_school_settings_service.dart';

/// Opens the school-wide 60-column report selection list.
/// Selected columns apply across Date-wise, Class-wise, Group-wise, Combine,
/// Tarij, and MDM Ekandar reports for this school.
Future<void> showDateWiseColumnSettingsDialog(BuildContext context) async {
  final settings = SupabaseSchoolSettingsService();
  late final Set<String> selected;
  late final String schoolType;
  late final List<DateWiseReportColumn> allowedColumns;
  try {
    schoolType = await settings.loadSchoolType();
    allowedColumns = DateWiseReportColumn.columnsForSchoolType(schoolType);
    selected = (await settings.visibleDateWiseColumns()).toSet();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load report column settings: $error')),
      );
    }
    return;
  }
  if (!context.mounted) return;

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('Report Columns / અહેવાલના કૉલમ (Datewise, Tarij, MDM)'),
        content: SizedBox(
          width: 580,
          height: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'શાળા રજીસ્ટ્રેશન મુજબ પ્રકાર: ${DateWiseReportColumn.schoolTypeDisplayLabel(schoolType)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.indigo.shade900,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: () => setDialogState(() {
                      selected
                        ..clear()
                        ..addAll(allowedColumns.map((column) => column.key));
                    }),
                    child: Text(
                      schoolType == 'boys'
                          ? 'Select All (માત્ર કુમાર)'
                          : schoolType == 'girls'
                              ? 'Select All (માત્ર કન્યા)'
                              : 'Select All (કુમાર + કન્યા + કુલ)',
                    ),
                  ),
                  if (schoolType == 'mixed') ...[
                    OutlinedButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(
                            allowedColumns
                                .where((col) => col.gender == 'BOYS')
                                .map((col) => col.key),
                          );
                      }),
                      child: const Text('માત્ર કુમાર (Boys Only)'),
                    ),
                    OutlinedButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(
                            allowedColumns
                                .where((col) => col.gender == 'GIRLS')
                                .map((col) => col.key),
                          );
                      }),
                      child: const Text('માત્ર કન્યા (Girls Only)'),
                    ),
                    OutlinedButton(
                      onPressed: () => setDialogState(() {
                        selected
                          ..clear()
                          ..addAll(
                            allowedColumns
                                .where((col) => col.gender == 'TOTAL')
                                .map((col) => col.key),
                          );
                      }),
                      child: const Text('માત્ર કુલ (Totals Only)'),
                    ),
                  ],
                  TextButton(
                    onPressed: () => setDialogState(selected.clear),
                    child: const Text('Clear all'),
                  ),
                  Text(
                    '${selected.length} of ${allowedColumns.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: allowedColumns.length,
                  itemBuilder: (context, index) {
                    final column = allowedColumns[index];
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(column.key),
                      title: Text(column.label),
                      onChanged: (checked) => setDialogState(() {
                        if (checked == true) {
                          selected.add(column.key);
                        } else {
                          selected.remove(column.key);
                        }
                      }),
                    );
                  },
                ),
              ),
              if (selected.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Select at least one data column.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );

  if (saved != true || !context.mounted) return;
  try {
    await settings.saveVisibleDateWiseColumns(selected);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Report columns saved for this school.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save report columns: $error')),
    );
  }
}

/// TARIJ column settings: every printed column (32 for a single-gender school;
/// Boys / Girls / Total for a mixed school) can be ticked and given its own
/// column number. The order is saved school-wide and used for the preview,
/// PDF and Excel (Page 1 and Page 2).
Future<void> showTarijColumnSettingsDialog(BuildContext context) async {
  final settings = SupabaseSchoolSettingsService();
  late final String schoolType;
  late final List<TarijColumnSpec> allSpecs;
  late final List<String> orderedAllKeys;
  late final Set<String> selected;
  try {
    schoolType = await settings.loadSchoolType();
    allSpecs = TarijColumnSpec.allFor(schoolType);
    final saved = TarijColumnSpec.resolve(
      await settings.visibleTarijColumnKeys(),
      schoolType,
    );
    selected = saved.map((s) => s.key).toSet();
    orderedAllKeys = <String>[
      ...saved.map((s) => s.key),
      for (final s in allSpecs)
        if (!selected.contains(s.key)) s.key,
    ];
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load TARIJ column settings: $error')),
      );
    }
    return;
  }
  if (!context.mounted) return;

  final titleByKey = <String, String>{for (final s in allSpecs) s.key: s.title};
  final specByKey = <String, TarijColumnSpec>{for (final s in allSpecs) s.key: s};
  final isMixed = SchoolType.isMixed(schoolType);
  var filter = '';

  List<String> activeOrdered() =>
      orderedAllKeys.where(selected.contains).toList();

  void moveTo(String key, int pos1Based) {
    final active = activeOrdered()..remove(key);
    final idx = (pos1Based - 1).clamp(0, active.length);
    active.insert(idx, key);
    final inactive = orderedAllKeys.where((k) => !selected.contains(k)).toList();
    orderedAllKeys
      ..clear()
      ..addAll(active)
      ..addAll(inactive);
  }

  void setSelection(Iterable<String> keys) {
    selected
      ..clear()
      ..addAll(keys);
    final active = <String>[
      for (final k in orderedAllKeys)
        if (selected.contains(k)) k,
    ];
    final inactive = orderedAllKeys.where((k) => !selected.contains(k)).toList();
    orderedAllKeys
      ..clear()
      ..addAll(active)
      ..addAll(inactive);
  }

  void resetDefaultOrder() {
    final defaults = allSpecs.map((s) => s.key).toList();
    final active = defaults.where(selected.contains).toList();
    final inactive = defaults.where((k) => !selected.contains(k)).toList();
    orderedAllKeys
      ..clear()
      ..addAll(active)
      ..addAll(inactive);
  }

  bool genderOn(String g) => allSpecs
      .where((s) => s.gender == g)
      .any((s) => selected.contains(s.key));

  void toggleGender(String g, bool on) {
    final keys = allSpecs.where((s) => s.gender == g).map((s) => s.key);
    if (on) {
      setSelection(<String>{...selected, ...keys});
    } else {
      setSelection(selected.difference(keys.toSet()));
    }
  }

  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final active = activeOrdered();
        final shown = orderedAllKeys
            .where((k) =>
                filter.isEmpty ||
                (titleByKey[k] ?? '').toLowerCase().contains(filter.toLowerCase()))
            .toList();
        return AlertDialog(
          title: const Text('TARIJ કૉલમ પસંદગી અને કૉલમ નંબર'),
          content: SizedBox(
            width: 760,
            height: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${DateWiseReportColumn.schoolTypeDisplayLabel(schoolType)} — કુલ ${allSpecs.length} કૉલમ. દરેક કૉલમ અલગથી પસંદ કરો અને "કૉલમ નં." થી ક્રમ નક્કી કરો. Page 1 અને Page 2 બંનેમાં એ જ ક્રમ લાગુ થશે.',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (isMixed) ...[
                      const Text('જાતિ:', style: TextStyle(fontWeight: FontWeight.w800)),
                      for (final g in const ['BOYS', 'GIRLS', 'TOTAL'])
                        FilterChip(
                          label: Text(TarijColumnSpec.genderLabel(g)),
                          selected: genderOn(g),
                          onSelected: (v) => setDialogState(() => toggleGender(g, v)),
                        ),
                    ],
                    OutlinedButton(
                      onPressed: () => setDialogState(
                          () => setSelection(allSpecs.map((s) => s.key))),
                      child: Text('બધા ${allSpecs.length} કૉલમ'),
                    ),
                    OutlinedButton(
                      onPressed: () => setDialogState(() => setSelection(allSpecs
                          .where((s) => const {'core', 'mdm'}
                              .contains(TarijReportColumn.byKey(s.section)?.group))
                          .map((s) => s.key))),
                      child: const Text('હાજરી + મ.ભો.'),
                    ),
                    OutlinedButton(
                      onPressed: () => setDialogState(() => setSelection(allSpecs
                          .where((s) => TarijReportColumn.byKey(s.section)?.group == 'core')
                          .map((s) => s.key))),
                      child: const Text('માત્ર હાજરી'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => setDialogState(resetDefaultOrder),
                      icon: const Icon(Icons.restart_alt, size: 16),
                      label: const Text('મૂળ ક્રમ'),
                    ),
                    TextButton(
                      onPressed: () => setDialogState(() => setSelection(const <String>[])),
                      child: const Text('બધા હટાવો'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'કૉલમ શોધો (દા.ત. સરેરાશ, કન્યા, અ.જા.)',
                          isDense: true,
                        ),
                        onChanged: (v) => setDialogState(() => filter = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${selected.length} / ${allSpecs.length} પસંદ',
                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final key = shown[index];
                      final spec = specByKey[key];
                      if (spec == null) return const SizedBox.shrink();
                      final isChecked = selected.contains(key);
                      final pos = isChecked ? active.indexOf(key) + 1 : 0;
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: isChecked ? const Color(0xFFEEF2FF) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isChecked ? const Color(0xFFC7D2FE) : const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isChecked,
                              onChanged: (v) => setDialogState(() {
                                if (v == true) {
                                  setSelection(<String>{...selected, key});
                                } else {
                                  setSelection(selected.difference({key}));
                                }
                              }),
                            ),
                            if (isChecked)
                              DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  isDense: true,
                                  value: pos,
                                  items: [
                                    for (var n = 1; n <= active.length; n++)
                                      DropdownMenuItem<int>(
                                        value: n,
                                        child: Text('કૉલમ નં. $n',
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF3730A3))),
                                      ),
                                  ],
                                  onChanged: (n) {
                                    if (n != null) setDialogState(() => moveTo(key, n));
                                  },
                                ),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                isChecked ? '$pos. ${spec.title}' : '— ${spec.title}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isChecked ? FontWeight.w700 : FontWeight.w500,
                                  color: isChecked ? Colors.black87 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                            if (isChecked) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'ઉપર',
                                icon: const Icon(Icons.arrow_upward, size: 18),
                                onPressed: pos <= 1 ? null : () => setDialogState(() => moveTo(key, pos - 1)),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                tooltip: 'નીચે',
                                icon: const Icon(Icons.arrow_downward, size: 18),
                                onPressed: pos >= active.length
                                    ? null
                                    : () => setDialogState(() => moveTo(key, pos + 1)),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (selected.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text('ઓછામાં ઓછો એક કૉલમ પસંદ કરો.',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.save_outlined),
              label: const Text('સેવ કરો (કાયમી)'),
            ),
          ],
        );
      },
    ),
  );

  if (saved != true || !context.mounted) return;
  try {
    await settings.saveTarijColumnKeys(activeOrdered());
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('TARIJ: ${selected.length} કૉલમ અને તેમનો ક્રમ સેવ થયો.')),
    );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save TARIJ columns: $error')),
    );
  }
}
