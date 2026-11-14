import 'package:flutter/material.dart';

import '../models/report_preferences.dart';

Future<ReportPreferences?> showReportPreferencesDialog(
  BuildContext context, {
  required ReportPreferences initialValue,
  required String schoolType,
}) {
  return showDialog<ReportPreferences>(
    context: context,
    builder: (_) => _ReportPreferencesDialog(
      initialValue: initialValue,
      schoolType: schoolType,
    ),
  );
}

class _ReportPreferencesDialog extends StatefulWidget {
  const _ReportPreferencesDialog({required this.initialValue, required this.schoolType});
  final ReportPreferences initialValue;
  final String schoolType;

  @override
  State<_ReportPreferencesDialog> createState() => _ReportPreferencesDialogState();
}

class _ReportPreferencesDialogState extends State<_ReportPreferencesDialog> {
  late ReportPreferences _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
  }

  void _gender(String key, bool checked) {
    var next = _value.copyWith(
      boys: key == 'boys' ? checked : _value.boys,
      girls: key == 'girls' ? checked : _value.girls,
      total: key == 'total' ? checked : _value.total,
    );
    if (!(next.boys || next.girls || next.total)) {
      next = next.copyWith(boys: true);
    }
    setState(() => _value = next);
  }

  void _category(String key, bool checked) {
    setState(() => _value = _value.copyWith(
      sc: key == 'SC' ? checked : _value.sc,
      st: key == 'ST' ? checked : _value.st,
      obc: key == 'OBC' ? checked : _value.obc,
      other: key == 'OTHER' ? checked : _value.other,
      categoryTotal: key == 'TOTAL' ? checked : _value.categoryTotal,
    ));
  }

  @override
  Widget build(BuildContext context) {
    // widget.schoolType is retained for caller context; print selections stay independent.
    return AlertDialog(
      title: const Text('Print / Report Options'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Gender columns', style: TextStyle(fontWeight: FontWeight.bold)),
              // Printing is deliberately independent of school entry gender. A boys-only
              // school may print a Girls column as zero, and vice versa.
              CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Boys'),
                value: _value.boys, onChanged: (v) => _gender('boys', v ?? false)),
              CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Girls'),
                value: _value.girls, onChanged: (v) => _gender('girls', v ?? false)),
              CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, title: const Text('Total (Boys + Girls)'),
                value: _value.total, onChanged: (v) => _gender('total', v ?? false)),
              const Divider(),
              const Text('Category rows', style: TextStyle(fontWeight: FontWeight.bold)),
              for (final entry in const [('SC','SC'),('ST','ST'),('OBC','OBC'),('OTHER','Other'),('TOTAL','Category Total')])
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.$2),
                  value: switch (entry.$1) {
                    'SC' => _value.sc,
                    'ST' => _value.st,
                    'OBC' => _value.obc,
                    'OTHER' => _value.other,
                    _ => _value.categoryTotal,
                  },
                  onChanged: (v) => _category(entry.$1, v ?? false),
                ),
              const Divider(),
              const Text('Breakfast display mode', style: TextStyle(fontWeight: FontWeight.bold)),
              RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Total only'), value: 'total', groupValue: _value.breakfastMode,
                onChanged: (v) => setState(() => _value = _value.copyWith(breakfastMode: v))),
              RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Gender-wise'), value: 'gender', groupValue: _value.breakfastMode,
                onChanged: (v) => setState(() => _value = _value.copyWith(breakfastMode: v))),
              RadioListTile<String>(dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Same as Present / PM POSHAN'), value: 'same_as_present', groupValue: _value.breakfastMode,
                onChanged: (v) => setState(() => _value = _value.copyWith(breakfastMode: v))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _value.ensuringValidColumns()), child: const Text('Save')),
      ],
    );
  }
}
