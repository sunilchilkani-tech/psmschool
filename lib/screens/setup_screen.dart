import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Shown before login whenever no backend URL is saved yet. Also
/// reachable later from the admin panel's "🔗 લિંક (URL) બદલો" button.
class SetupScreen extends StatefulWidget {
  final bool isChangeFlow;
  const SetupScreen({super.key, this.isChangeFlow = false});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _urlController;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = context.read<AppState>().backendUrl;
    _urlController = TextEditingController(text: existing ?? '');
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = _urlController.text.trim();
    final isFirebase = url.toLowerCase().startsWith('firebase://') || url.toUpperCase() == 'FIREBASE';
    if (url.isEmpty || (!isFirebase && !(url.startsWith('http://') || url.startsWith('https://')))) {
      setState(() => _error = 'Apps Script URL અથવા firebase://asia-south1 દાખલ કરો. Firebase વાપરવા પહેલાં flutterfire configure જરૂરી છે.');
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final ok = await ApiService(url).ping();
    if (!mounted) return;
    setState(() => _checking = false);
    if (!ok) {
      setState(() => _error = isFirebase
          ? 'Firebase જોડાણ નિષ્ફળ. પહેલાં flutterfire configure ચલાવો, યોગ્ય Firebase project પસંદ કરો અને Functions ને asia-south1 માં deploy કરો.'
          : 'આ URL સાથે જોડાણ થઈ શક્યું નથી. Apps Script deployment URL તપાસો.');
      return;
    }
    await context.read<AppState>().setBackendUrl(url);
    if (!mounted) return;
    if (widget.isChangeFlow) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: AppTheme.headerGradient,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [AppTheme.shadowLg],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.account_balance_rounded, size: 58, color: AppColors.navy),
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.goldPale,
                          border: Border.all(color: AppColors.gold, width: 1.5),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          'PROFESSIONAL SCHOOL MANAGEMENT',
                          style: guFont(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF92400E), letterSpacing: 1),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.isChangeFlow ? '🔗 સર્વર લિંક બદલો' : '⚙️ પ્રથમ સેટઅપ',
                      textAlign: TextAlign.center,
                      style: guFont(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Apps Script URL અથવા Firebase backend પસંદ કરો. Firebase માટે firebase://asia-south1 દાખલ કરો.',
                      textAlign: TextAlign.center,
                      style: guFont(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.slate),
                    ),
                    const SizedBox(height: 22),
                    LabeledField(
                      label: '🔗 Web App URL',
                      child: TextField(
                        controller: _urlController,
                        keyboardType: TextInputType.url,
                        style: guFont(fontSize: 13, fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          hintText: 'firebase://asia-south1  અથવા  https://.../exec',
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!, style: guFont(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.rose)),
                    ],
                    const SizedBox(height: 18),
                    AppButton(
                      label: _checking ? 'તપાસ થાય છે…' : '✅ જોડાણ કરો',
                      loading: _checking,
                      expand: true,
                      onPressed: _checking ? null : _connect,
                    ),
                    if (widget.isChangeFlow) ...[
                      const SizedBox(height: 10),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text('રદ કરો', style: guFont(fontWeight: FontWeight.w700, color: AppColors.slate)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Firebase માટે પહેલાં: flutterfire configure. Legacy Apps Script URL હજુ fallback તરીકે ચાલે છે.',
                      textAlign: TextAlign.center,
                      style: guFont(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
