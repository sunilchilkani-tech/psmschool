import 'package:flutter/material.dart';

/// Visible navigation entry for modules still being migrated from the legacy
/// spreadsheet session to the authenticated Supabase workflow.
class SupabaseModulePlaceholderScreen extends StatelessWidget {
  const SupabaseModulePlaceholderScreen({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.construction_outlined, size: 52),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(description, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            const Text('આ મેનુ દેખાય છે, પરંતુ જૂની Google Sheets session પર આધારિત આવૃત્તિ આ Supabase login સાથે હજી જોડાયેલી નથી. ખોટા/અધૂરા ડેટા પર પ્રમાણપત્ર બનાવવાને બદલે તેને Supabase સાથે જોડ્યા પછી કાર્યરત કરવામાં આવશે.', textAlign: TextAlign.center),
          ]),
        ),
      ),
    ),
  );
}
