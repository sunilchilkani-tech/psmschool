import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Teacher>? _teachers;
  String? _loadError;
  String? _selectedTeacherId;
  final _passwordController = TextEditingController();
  late final TextEditingController _schoolCodeController;
  bool _loadingTeachers = false;
  String? _loginError;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _schoolCodeController = TextEditingController(
      text: context.read<AppState>().schoolCode ?? '',
    );
    if (_schoolCodeController.text.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTeachers());
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _schoolCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadTeachers() async {
    if (_schoolCodeController.text.trim().isEmpty) {
      setState(() {
        _teachers = null;
        _loadError = 'School Code દાખલ કરો.';
      });
      return;
    }
    setState(() {
      _loadingTeachers = true;
      _teachers = null;
      _loadError = null;
      _selectedTeacherId = null;
      _loginError = null;
    });
    try {
      final state = context.read<AppState>();
      final list = await state.loadTeachers(_schoolCodeController.text.trim());
      if (!mounted) return;
      setState(() {
        _teachers = list;
        _loadingTeachers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('ApiException: ', '');
        _loadingTeachers = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_selectedTeacherId == null) {
      setState(() => _loginError = 'Teacher પસંદ કરો.');
      return;
    }
    final password = _passwordController.text;
    if (password.length < 4 || password.length > 15) {
      setState(() => _loginError = 'Password 4 થી 15 અક્ષરનો હોવો જોઈએ.');
      return;
    }
    setState(() {
      _submitting = true;
      _loginError = null;
    });
    final err = await context.read<AppState>().login(
      _selectedTeacherId!,
      password,
    );
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _loginError = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.navy,
                    AppColors.navyMid,
                    Color(0xFF1E4A7A),
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [AppTheme.shadowLg],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      appState.logoUrl.isNotEmpty
                          ? Image.network(
                              appState.logoUrl,
                              height: 56,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.account_balance_rounded,
                                size: 54,
                                color: AppColors.navy,
                              ),
                            )
                          : const Icon(
                              Icons.account_balance_rounded,
                              size: 54,
                              color: AppColors.navy,
                            ),
                      const SizedBox(height: 14),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.goldPale,
                            border: Border.all(
                              color: AppColors.gold,
                              width: 1.5,
                            ),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Text(
                            '🏫 ${appState.schoolName}',
                            style: guFont(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF92400E),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'હાજરી વ્યવસ્થાપન',
                        textAlign: TextAlign.center,
                        style: guFont(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'School Code, teacher name અને password દાખલ કરો',
                        textAlign: TextAlign.center,
                        style: guFont(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate,
                        ),
                      ),
                      const SizedBox(height: 24),
                      LabeledField(
                        label: '🏫 School Code',
                        child: TextField(
                          controller: _schoolCodeController,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          decoration: InputDecoration(
                            hintText:
                                'Enter school code given by your developer',
                            suffixIcon: IconButton(
                              tooltip: 'Load school and teachers',
                              onPressed: _loadingTeachers
                                  ? null
                                  : _loadTeachers,
                              icon: _loadingTeachers
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.download),
                            ),
                          ),
                          onSubmitted: (_) => _loadTeachers(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _loadingTeachers ? null : _loadTeachers,
                          icon: const Icon(Icons.school_outlined),
                          label: Text(
                            _loadingTeachers
                                ? 'Loading school…'
                                : 'Load school / refresh teachers',
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildBody(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AlertBox(kind: AlertKind.error, text: _loadError!),
          const SizedBox(height: 14),
          AppButton(label: '🔄 ફરી પ્રયત્ન કરો', onPressed: _loadTeachers),
        ],
      );
    }

    if (_loadingTeachers) {
      return const LoadingState(label: 'School અને teacher list લોડ થાય છે…');
    }
    if (_teachers == null) {
      return Text(
        'Teacher list લોડ કરવા ઉપર School Code દાખલ કરીને Load school દબાવો.',
        textAlign: TextAlign.center,
        style: guFont(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.slate,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(
          label: '👤 Teacher પસંદ કરો',
          child: DropdownButtonFormField<String>(
            value: _selectedTeacherId,
            isExpanded: true,
            style: guFont(fontSize: 15, fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              filled: true,
              fillColor: AppColors.slateLight,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 2),
              ),
            ),
            hint: Text(
              '-- Teacher પસંદ કરો --',
              style: guFont(fontSize: 14, color: AppColors.slate),
            ),
            items: _teachers!
                .where((t) => (t.id ?? '').isNotEmpty)
                .map(
                  (t) => DropdownMenuItem(
                    value: t.id!,
                    child: Text(
                      t.name,
                      style: guFont(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedTeacherId = v),
          ),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: '🔑 Password દાખલ કરો',
          child: TextField(
            controller: _passwordController,
            obscureText: true,
            maxLength: 15,
            style: guFont(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '4 to 15 characters',
              filled: true,
              fillColor: AppColors.slateLight,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border, width: 2),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ),
        SizedBox(
          height: 32,
          child: _loginError == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _loginError!,
                    style: guFont(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.rose,
                    ),
                  ),
                ),
        ),
        AppButton(
          label: _submitting ? 'લૉગ ઇન થાય છે…' : '🔓 લૉગ ઇન',
          loading: _submitting,
          expand: true,
          onPressed: _submitting ? null : _submit,
        ),
      ],
    );
  }
}
