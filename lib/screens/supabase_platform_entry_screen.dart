import 'package:flutter/material.dart';

import '../services/supabase_school_access_service.dart';
import 'developer_panel.dart';
import 'school_registration_request_screen.dart';

/// Starter entry screen exposing the requested Developer tab and Supabase school
/// login. The app shell should use [onAuthenticated] to open the existing dashboard.
class SupabasePlatformEntryScreen extends StatefulWidget {
  const SupabasePlatformEntryScreen({
    super.key,
    required this.onAuthenticated,
    SupabaseSchoolAccessService? service,
  }) : _service = service;

  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final SupabaseSchoolAccessService? _service;

  @override
  State<SupabasePlatformEntryScreen> createState() =>
      _SupabasePlatformEntryScreenState();
}

class _SupabasePlatformEntryScreenState
    extends State<SupabasePlatformEntryScreen> {
  int _logoTapCount = 0;
  DateTime? _lastLogoTapAt;
  bool _openingDeveloperDialog = false;

  void _handleSecretLogoTap() {
    final now = DateTime.now();
    if (_lastLogoTapAt == null ||
        now.difference(_lastLogoTapAt!) > const Duration(seconds: 3)) {
      _logoTapCount = 1;
    } else {
      _logoTapCount++;
    }
    _lastLogoTapAt = now;
    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _promptDeveloperKeyAndOpenPanel();
    }
  }

  Future<void> _promptDeveloperKeyAndOpenPanel() async {
    if (!mounted || _openingDeveloperDialog) return;
    _openingDeveloperDialog = true;
    final service = widget._service ?? SupabaseSchoolAccessService();
    final keyCtrl = TextEditingController();
    var verifying = false;
    String? dialogError;
    List<Map<String, dynamic>>? verifiedSchools;
    String? verifiedKey;

    try {
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogCtx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> submitKey() async {
              final entered = keyCtrl.text.trim();
              if (entered.isEmpty) {
                setDialogState(() => dialogError = 'Developer key દાખલ કરો.');
                return;
              }
              setDialogState(() {
                verifying = true;
                dialogError = null;
              });
              try {
                final schools = await service.developerListSchools(entered);
                verifiedKey = entered;
                verifiedSchools = schools;
                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop(true);
              } catch (e) {
                setDialogState(() {
                  verifying = false;
                  dialogError = '$e'.replaceFirst('Exception: ', '');
                });
              }
            }

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.developer_mode_outlined),
                  SizedBox(width: 8),
                  Expanded(child: Text('Developer Login')),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter Developer Key to open Developer Panel. The key is never saved and clears automatically when closed.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: keyCtrl,
                      obscureText: true,
                      autofocus: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const <String>[],
                      enabled: !verifying,
                      decoration: InputDecoration(
                        labelText: 'Developer Key',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.key_outlined),
                        errorText: dialogError,
                      ),
                      onSubmitted: (_) => submitKey(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: verifying
                      ? null
                      : () => Navigator.of(dialogCtx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  onPressed: verifying ? null : submitKey,
                  icon: verifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.lock_open_outlined),
                  label: Text(verifying ? 'Verifying…' : 'Login as Developer'),
                ),
              ],
            );
          },
        ),
      );
      keyCtrl.clear();
      keyCtrl.dispose();

      if (approved == true &&
          verifiedKey != null &&
          verifiedKey!.isNotEmpty &&
          mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DeveloperPanel(
              service: service,
              showAppBar: true,
              initialSessionKey: verifiedKey!,
              initialSchools: verifiedSchools,
            ),
          ),
        );
        // Auto-clear key from memory as soon as Developer screen closes
        verifiedKey = null;
        verifiedSchools = null;
      }
    } finally {
      _openingDeveloperDialog = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = widget._service ?? SupabaseSchoolAccessService();
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: GestureDetector(
            onTap: _handleSecretLogoTap,
            onLongPress: _promptDeveloperKeyAndOpenPanel,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/app_icon_padded.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(Icons.school),
              ),
            ),
          ),
        ),
        title: GestureDetector(
          onTap: _handleSecretLogoTap,
          child: const Text('Professional School Management'),
        ),
      ),
      body: _SchoolLoginTab(
        service: service,
        onAuthenticated: widget.onAuthenticated,
        onUnlockDeveloper: _promptDeveloperKeyAndOpenPanel,
        onLogoTap: _handleSecretLogoTap,
      ),
    );
  }
}

class _SchoolLoginTab extends StatefulWidget {
  const _SchoolLoginTab({
    required this.service,
    required this.onAuthenticated,
    this.onUnlockDeveloper,
    this.onLogoTap,
  });
  final SupabaseSchoolAccessService service;
  final ValueChanged<Map<String, dynamic>> onAuthenticated;
  final VoidCallback? onUnlockDeveloper;
  final VoidCallback? onLogoTap;

  @override
  State<_SchoolLoginTab> createState() => _SchoolLoginTabState();
}

class _SchoolLoginTabState extends State<_SchoolLoginTab> {
  final _schoolId = TextEditingController();
  final _password = TextEditingController();
  String? _teacherId;
  Map<String, dynamic>? _school;
  List<Map<String, dynamic>> _teachers = <Map<String, dynamic>>[];
  bool _loadingOptions = false;
  bool _signingIn = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _schoolId.dispose();
    _password.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map)
      return raw.map((key, value) => MapEntry(key.toString(), value));
    return <String, dynamic>{};
  }

  void _showError(String message) {
    if (mounted)
      setState(() => _error = message.replaceFirst('Exception: ', ''));
  }

  Future<void> _findSchool() async {
    final schoolId = _schoolId.text.trim();
    if (schoolId.isEmpty) {
      _showError('Enter the School DISE/UDISE number.');
      return;
    }
    final upperCode = schoolId.toUpperCase();
    if (upperCode == 'DEV' ||
        upperCode == 'DEVELOPER' ||
        upperCode == '#DEV#') {
      _schoolId.clear();
      widget.onUnlockDeveloper?.call();
      return;
    }
    setState(() {
      _loadingOptions = true;
      _error = null;
      _school = null;
      _teachers = [];
      _teacherId = null;
    });
    try {
      final result = await widget.service.loadLoginOptions(schoolId);
      final school = _toMap(result['school']);
      final rawTeachers = result['teachers'];
      final teachers = rawTeachers is List
          ? rawTeachers
                .whereType<Map>()
                .map(
                  (row) =>
                      row.map((key, value) => MapEntry(key.toString(), value)),
                )
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _school = school;
        _teachers = teachers;
        _teacherId = teachers.isEmpty ? null : '${teachers.first['id']}';
      });
      if (teachers.isEmpty)
        _showError(
          'No active Admin or teacher account exists for this school yet.',
        );
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _resetPasswordWithOtp() async {
    if (_school == null || _teachers.isEmpty || (_teacherId ?? '').isEmpty) {
      _showError(
        'First find your school and select your Admin/Teacher account.',
      );
      return;
    }
    setState(() {
      _loadingOptions = true;
      _error = null;
    });
    try {
      final requested = await widget.service.requestPasswordResetOtp(
        schoolId: _schoolId.text.trim(),
        teacherId: _teacherId!,
      );
      if (!mounted) return;
      final challengeId = '${requested['challengeId'] ?? ''}';
      if (challengeId.isEmpty)
        throw Exception('SMS OTP could not be requested. Please try again.');
      final otp = TextEditingController();
      final nextPassword = TextEditingController();
      final confirmPassword = TextEditingController();
      final formKey = GlobalKey<FormState>();
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Reset password using SMS OTP'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'OTP sent to registered mobile ${requested['maskedMobile'] ?? ''}. It expires in 5 minutes.',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: otp,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: '6-digit OTP',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          !RegExp(r'^\d{6}$').hasMatch((v ?? '').trim())
                          ? 'Enter the 6-digit OTP.'
                          : null,
                    ),
                    TextFormField(
                      controller: nextPassword,
                      obscureText: true,
                      maxLength: 15,
                      decoration: const InputDecoration(
                        labelText: 'New password',
                        helperText: '4 to 15 characters.',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          ((v ?? '').length < 4 || (v ?? '').length > 15)
                          ? 'Use 4 to 15 characters.'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: confirmPassword,
                      obscureText: true,
                      maxLength: 15,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => (v ?? '') != nextPassword.text
                          ? 'Passwords do not match.'
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  await widget.service.completePasswordResetOtp(
                    schoolId: _schoolId.text.trim(),
                    teacherId: _teacherId!,
                    challengeId: challengeId,
                    otp: otp.text,
                    newPassword: nextPassword.text,
                  );
                  if (dialogContext.mounted) Navigator.pop(dialogContext, true);
                } catch (error) {
                  if (dialogContext.mounted)
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          error.toString().replaceFirst('Exception: ', ''),
                        ),
                      ),
                    );
                }
              },
              child: const Text('Verify OTP & Reset'),
            ),
          ],
        ),
      );
      otp.dispose();
      nextPassword.dispose();
      confirmPassword.dispose();
      if (saved == true && mounted) {
        _password.clear();
        setState(() => _error = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Password reset successfully. Sign in using your new password.',
            ),
          ),
        );
      }
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  Future<void> _showDuePopupsAfterLogin() async {
    try {
      final popups = await widget.service.loadDuePopups();
      for (final popup in popups) {
        if (!mounted) return;
        final kind = '${popup['kind'] ?? ''}';
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              '${popup['title'] ?? (kind == 'validity_reminder' ? 'School Validity Reminder' : 'Developer Message')}',
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: SelectableText('${popup['message'] ?? ''}'),
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (!mounted) return;
        try {
          await widget.service.dismissDuePopup(popup);
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Popup acknowledgement could not be saved; it may appear again: ${error.toString().replaceFirst('Exception: ', '')}',
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          }
        }
      }
    } catch (error) {
      // Messaging is additive and must not prevent an otherwise valid school login.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not check Developer notices: ${error.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _login() async {
    if ((_schoolId.text.trim()).isEmpty) {
      _showError('Enter School DISE/UDISE number.');
      return;
    }
    if (_school == null || _teachers.isEmpty) {
      await _findSchool();
      if (!mounted || _school == null) return;
    }
    if ((_teacherId ?? '').isEmpty) {
      _showError('Select Admin or teacher.');
      return;
    }
    if (_password.text.isEmpty) {
      _showError('Enter password.');
      return;
    }
    setState(() {
      _signingIn = true;
      _error = null;
    });
    try {
      final profile = await widget.service.signInSchoolUser(
        schoolId: _schoolId.text.trim(),
        teacherId: _teacherId!,
        password: _password.text,
      );
      if (!mounted) return;
      await _showDuePopupsAfterLogin();
      if (!mounted) return;
      widget.onAuthenticated(profile);
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
  }

  String _typeLabel(dynamic type) => switch ('${type ?? 'mixed'}') {
    'boys' => 'કુમાર શાળા',
    'girls' => 'કન્યા શાળા',
    _ => 'મિશ્ર શાળા',
  };

  @override
  Widget build(BuildContext context) {
    final schoolName = '${_school?['school_name'] ?? ''}'.trim();
    final blocked = _school?['is_blocked'] == true;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: widget.onLogoTap,
            onLongPress: widget.onUnlockDeveloper,
            child: Container(
              width: 132,
              height: 100,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Image.asset(
                'assets/images/app_icon_padded.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.school, size: 54),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'School Login',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in using the School DISE/UDISE number, user name and password.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _schoolId,
          keyboardType: TextInputType.text,
          decoration: const InputDecoration(
            labelText: 'School DISE / UDISE number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers_outlined),
          ),
          onSubmitted: (_) => _findSchool(),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _loadingOptions || _signingIn ? null : _findSchool,
          icon: _loadingOptions
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(
            _loadingOptions ? 'Searching…' : 'Find School / Load Users',
          ),
        ),
        if (_school != null) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: const Icon(Icons.account_balance_outlined),
              title: Text(
                schoolName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                '${_typeLabel(_school?['school_type'])} • Valid through ${_school?['validity_date'] ?? ''}',
              ),
              trailing: blocked ? const Chip(label: Text('READ ONLY')) : null,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _teacherId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Admin / Teacher',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            items: _teachers
                .map(
                  (teacher) => DropdownMenuItem<String>(
                    value: '${teacher['id']}',
                    child: Text(
                      '${teacher['name'] ?? ''} (${('${teacher['role'] ?? 'teacher'}').toLowerCase() == 'admin' ? 'Admin' : 'Teacher'})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _signingIn
                ? null
                : (value) => setState(() => _teacherId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.password_outlined),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            onSubmitted: (_) => _login(),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _signingIn ? null : _login,
              icon: _signingIn
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: Text(_signingIn ? 'Signing in…' : 'Sign In'),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _signingIn || _loadingOptions
                  ? null
                  : _resetPasswordWithOtp,
              icon: const Icon(Icons.sms_outlined),
              label: const Text('Forgot password? Reset with SMS OTP'),
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!)),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 22),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'તમારી શાળા હજુ નોંધાયેલ નથી?',
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _signingIn
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SchoolRegistrationRequestScreen(service: widget.service),
                  )),
          icon: const Icon(Icons.app_registration_rounded),
          label: const Text('નવી શાળા નોંધણી / Register New School'),
        ),
      ],
    );
  }
}
