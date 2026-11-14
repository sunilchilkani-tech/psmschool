import 'package:flutter/material.dart';
import '../services/device_preferences_service.dart';

/// Controlled selector for the persisted breakfast-entry mode.
class BreakfastEntryTypeSelector extends StatelessWidget {
  const BreakfastEntryTypeSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: ValueKey('breakfast-entry-type-$value'),
        initialValue: const {'total', 'gender', 'same_as_present'}.contains(value)
            ? value
            : 'same_as_present',
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Breakfast Entry Type',
          border: OutlineInputBorder(),
          helperText: 'This preference is saved on this device.',
        ),
        items: const [
          DropdownMenuItem(value: 'total', child: Text('Total')),
          DropdownMenuItem(value: 'gender', child: Text('Gender Wise')),
          DropdownMenuItem(value: 'same_as_present', child: Text('Same as Present / PM POSHAN')),
        ],
        onChanged: (next) async {
          if (next == null) return;
          await DevicePreferencesService().saveBreakfastEntryType(next);
          onChanged(next);
        },
      );
}
