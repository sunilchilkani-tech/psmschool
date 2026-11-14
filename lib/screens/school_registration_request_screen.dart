import 'package:flutter/material.dart';

import '../services/supabase_school_access_service.dart';

/// New-school registration from the login screen. The same details as the
/// Developer's registration form are sent as a pending request; the school
/// is created only after the Developer checks (or edits) and approves it.
class SchoolRegistrationRequestScreen extends StatefulWidget {
  const SchoolRegistrationRequestScreen({super.key, required this.service});

  final SupabaseSchoolAccessService service;

  @override
  State<SchoolRegistrationRequestScreen> createState() => _SchoolRegistrationRequestScreenState();
}

class _SchoolRegistrationRequestScreenState extends State<SchoolRegistrationRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameEn = TextEditingController();
  final _nameGu = TextEditingController();
  final _addressEn = TextEditingController();
  final _addressGu = TextEditingController();
  final _dise = TextEditingController();
  final _adminName = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _password2 = TextEditingController();
  final _note = TextEditingController();
  String _schoolType = 'mixed';
  bool _obscure = true;
  bool _sending = false;
  bool _sent = false;
  String? _error;

  static const _types = <String, String>{
    'mixed': 'મિશ્ર શાળા (Mixed)',
    'boys': 'કુમાર શાળા (Boys)',
    'girls': 'કન્યા શાળા (Girls)',
  };

  @override
  void dispose() {
    for (final c in [_nameEn, _nameGu, _addressEn, _addressGu, _dise, _adminName, _mobile, _password, _password2, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.service.submitSchoolRegistrationRequest(<String, dynamic>{
        'school_name_en': _nameEn.text.trim(),
        'school_name_gu': _nameGu.text.trim(),
        'school_address_en': _addressEn.text.trim(),
        'school_address_gu': _addressGu.text.trim(),
        'dise_number': _dise.text.replaceAll(RegExp(r'\s+'), ''),
        'admin_name': _adminName.text.trim(),
        'admin_mobile': _mobile.text.trim(),
        'admin_password': _password.text,
        'school_type': _schoolType,
        'note': _note.text.trim(),
      });
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  InputDecoration _dec(String label, IconData icon, {String? helper}) => InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      );

  String? _required(String? v, String msg, {int min = 2}) =>
      (v == null || v.trim().length < min) ? msg : null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('નવી શાળા નોંધણી / Register New School')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: _sent ? _successView() : _form(),
          ),
        ),
      ),
    );
  }

  Widget _successView() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.mark_email_read_outlined, size: 72, color: Color(0xFF15803D)),
          const SizedBox(height: 16),
          const Text(
            'નોંધણી વિનંતી મોકલાઈ ગઈ છે',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          Text(
            'DISE ${_dise.text.trim()} — Developer વિગત ચકાસીને મંજૂરી આપશે. મંજૂરી પછી આ DISE નંબર, '
            'Admin નામ અને આપે રાખેલ પાસવર્ડથી School Login કરી શકશો.\n\n'
            'Your request has been sent. After the Developer approves it, sign in with this DISE number and the password you set.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.login),
            label: const Text('School Login પર પાછા જાઓ'),
          ),
        ],
      );

  Widget _form() => Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: const Color(0xFFEFF6FF),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'શાળાની વિગત ભરી "નોંધણી વિનંતી મોકલો" દબાવો. Developer ચકાસીને મંજૂરી આપે ત્યારે શાળા અને Admin એકાઉન્ટ બનશે.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const _Section('1. શાળાની વિગત'),
            TextFormField(
              controller: _dise,
              keyboardType: TextInputType.number,
              decoration: _dec('DISE / UDISE નંબર *', Icons.numbers_outlined, helper: 'માત્ર અંક; આગળના શૂન્ય (0) પણ લખો.'),
              validator: (v) => RegExp(r'^\d{4,20}$').hasMatch((v ?? '').replaceAll(RegExp(r'\s+'), ''))
                  ? null
                  : 'સાચો DISE / UDISE નંબર લખો (4 થી 20 અંક).',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameEn,
              decoration: _dec('School name (English) *', Icons.school_outlined),
              validator: (v) => _required(v, 'શાળાનું નામ English માં લખો.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameGu,
              decoration: _dec('શાળાનું નામ (ગુજરાતી)', Icons.school_outlined),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressEn,
              minLines: 1,
              maxLines: 3,
              decoration: _dec('School address (English)', Icons.location_on_outlined),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressGu,
              minLines: 1,
              maxLines: 3,
              decoration: _dec('શાળાનું સરનામું (ગુજરાતી)', Icons.location_on_outlined),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _schoolType,
              isExpanded: true,
              decoration: _dec('શાળાનો પ્રકાર *', Icons.groups_outlined),
              items: [for (final e in _types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _schoolType = v ?? 'mixed'),
            ),
            const SizedBox(height: 18),
            const _Section('2. Admin (આચાર્ય) ની વિગત'),
            TextFormField(
              controller: _adminName,
              decoration: _dec('Admin નું નામ *', Icons.person_outline),
              validator: (v) => _required(v, 'Admin નું નામ લખો.'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mobile,
              keyboardType: TextInputType.phone,
              decoration: _dec('Admin મોબાઈલ નંબર *', Icons.phone_android_outlined, helper: 'પાસવર્ડ ભૂલી જાઓ તો આ નંબર પર OTP આવશે.'),
              validator: (v) {
                var d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
                if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
                return RegExp(r'^[6-9]\d{9}$').hasMatch(d) ? null : 'સાચો 10 અંકનો મોબાઈલ નંબર લખો.';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              decoration: _dec('Admin પાસવર્ડ *', Icons.password_outlined, helper: '4 થી 15 અક્ષર').copyWith(
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                ),
              ),
              validator: (v) => (v ?? '').length < 4 || (v ?? '').length > 15 ? 'પાસવર્ડ 4 થી 15 અક્ષરનો રાખો.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password2,
              obscureText: _obscure,
              decoration: _dec('પાસવર્ડ ફરી લખો *', Icons.password_outlined),
              validator: (v) => v != _password.text ? 'બંને પાસવર્ડ સરખા નથી.' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              maxLength: 500,
              decoration: _dec('Developer માટે નોંધ (વૈકલ્પિક)', Icons.notes_outlined),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_outline),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!)),
                  ]),
                ),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_outlined),
              label: Text(_sending ? 'મોકલાઈ રહ્યું છે…' : 'નોંધણી વિનંતી મોકલો / Send for Approval'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      );
}
