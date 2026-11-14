import 'package:flutter/material.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';

import '../services/school_name_language_service.dart';

/// Reusable selector. It persists to the same per-school browser preference
/// already used by Hajari Patrak; callers can rebuild report text immediately.
class SchoolNameLanguageSelector extends StatefulWidget {
  const SchoolNameLanguageSelector({
    super.key,
    this.schoolRef,
    this.label = 'School name in reports / રિપોર્ટમાં શાળાનું નામ',
    this.helperText = 'છેલ્લી પસંદગી આ શાળા માટે આ browser માં સાચવાશે.',
    this.onChanged,
  });

  final String? schoolRef;
  final String label;
  final String? helperText;
  final ValueChanged<String>? onChanged;

  @override
  State<SchoolNameLanguageSelector> createState() => _SchoolNameLanguageSelectorState();
}

class _SchoolNameLanguageSelectorState extends State<SchoolNameLanguageSelector> {
  String _language = SchoolNameLanguageService.gujarati;
  String _schoolRef = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant SchoolNameLanguageSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schoolRef != widget.schoolRef) _load();
  }

  Future<void> _load() async {
    var ref = (widget.schoolRef ?? '').trim();
    if (ref.isEmpty) {
      try {
        ref = (await Supabase.instance.client.rpc('current_school_ref') ?? '').toString().trim();
      } catch (_) {
        ref = '';
      }
    }
    final language = await SchoolNameLanguageService.loadLanguage(schoolRef: ref);
    if (!mounted) return;
    setState(() {
      _schoolRef = ref;
      _language = language;
      _ready = true;
    });
  }

  Future<void> _change(String? value) async {
    if (value == null || !const <String>{'gu', 'en'}.contains(value)) return;
    setState(() => _language = value);
    try {
      await SchoolNameLanguageService.saveLanguage(schoolRef: _schoolRef, language: value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('પસંદગી લાગુ થઈ છે, પરંતુ આ browser માં save થઈ શકી નથી.'),
        ));
      }
    }
    if (mounted) widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        key: ValueKey<String>('$_schoolRef-$_language'),
        initialValue: _language,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: widget.label,
          helperText: widget.helperText,
          border: const OutlineInputBorder(),
        ),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(value: 'gu', child: Text('ગુજરાતી')),
          DropdownMenuItem<String>(value: 'en', child: Text('English')),
        ],
        onChanged: _ready ? _change : null,
      );
}
