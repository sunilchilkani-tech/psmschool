import 'dart:convert';
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import 'firebase_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/supabase_config.dart';
import 'screens/supabase_platform_entry_screen.dart';
import 'screens/supabase_signed_in_home.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';
import 'theme/display_scale.dart';
import 'theme/responsive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Device-only display preference loads in parallel with Firebase start-up.
  final displayScale = DisplayScale.load();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );
  await displayScale;
  runApp(const AttendanceApp());
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Keep AppState available for existing widgets, but do not automatically
    // restore the legacy Apps Script session as the app's root route. During
    // the Supabase transition, that stale session can otherwise bypass the new
    // School Login / Developer screen and open the old Google-Sheets Admin UI.
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'Professional School Management',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        scrollBehavior: AppScrollBehavior(),
        // User-selected Zoom In / Zoom Out & pinch-to-zoom applies to every screen.
        builder: (context, child) => MobileZoomViewport(
          child: ResponsiveTheme(child: child ?? const SizedBox.shrink()),
        ),
        home: const _RootGate(),
      ),
    );
  }
}

class _RootGate extends StatefulWidget {
  const _RootGate();

  @override
  State<_RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<_RootGate> {
  static const String _supabaseProfileCacheKey = 'psm_supabase_profile_v1';
  static const String _supabaseProfileUidCacheKey =
      'psm_supabase_profile_uid_v1';
  static const String _lastDiseCodeCacheKey = 'psm_last_logged_in_dise_code_v1';

  Map<String, dynamic>? _supabaseProfile;
  String _lastDiseCode = '';
  bool _restoringSession = true;

  @override
  void initState() {
    super.initState();
    unawaited(_restoreSupabaseProfile());
  }

  Future<void> _clearSupabaseProfileCache(SharedPreferences prefs) async {
    await prefs.remove(_supabaseProfileCacheKey);
    await prefs.remove(_supabaseProfileUidCacheKey);
  }

  Future<void> _restoreSupabaseProfile() async {
    final client = Supabase.instance.client;
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      if (mounted) setState(() => _restoringSession = false);
      return;
    }

    _lastDiseCode = (prefs.getString(_lastDiseCodeCacheKey) ?? '').trim();
    final user = client.auth.currentUser;
    final rawProfile = prefs.getString(_supabaseProfileCacheKey);
    final cachedUserId = prefs.getString(_supabaseProfileUidCacheKey);

    if (user == null) {
      await _clearSupabaseProfileCache(prefs);
      if (mounted) setState(() => _restoringSession = false);
      return;
    }
    if (rawProfile == null || cachedUserId != user.id) {
      await _clearSupabaseProfileCache(prefs);
      if (mounted) setState(() => _restoringSession = false);
      return;
    }

    late Map<String, dynamic> profile;
    try {
      final decoded = jsonDecode(rawProfile);
      if (decoded is! Map)
        throw const FormatException('Cached profile is not an object.');
      profile = Map<String, dynamic>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      await _clearSupabaseProfileCache(prefs);
      if (mounted) setState(() => _restoringSession = false);
      return;
    }

    // Validate the cached profile against the authenticated database identity.
    // If the network is temporarily unavailable, retain the cached view only;
    // all actual data reads/writes remain subject to Supabase auth/RLS checks.
    try {
      final teacherId = await client.rpc('current_teacher_id');
      final schoolRef = await client.rpc('current_school_ref');
      final isAdmin = await client.rpc('is_school_admin');
      final cachedTeacherId = '${profile['teacher_id'] ?? ''}'.trim();
      final cachedSchoolRef = '${profile['school_ref'] ?? ''}'.trim();

      if (teacherId == null ||
          schoolRef == null ||
          (cachedTeacherId.isNotEmpty && cachedTeacherId != '$teacherId') ||
          (cachedSchoolRef.isNotEmpty && cachedSchoolRef != '$schoolRef')) {
        await client.auth.signOut();
        await _clearSupabaseProfileCache(prefs);
        if (mounted) setState(() => _restoringSession = false);
        return;
      }

      profile['teacher_id'] = '$teacherId';
      profile['school_ref'] = '$schoolRef';
      final cachedRole = '${profile['role'] ?? ''}'.trim().toLowerCase();
      profile['role'] = cachedRole == 'developer'
          ? 'developer'
          : (isAdmin == true ? 'admin' : 'teacher');
      await prefs.setString(_supabaseProfileCacheKey, jsonEncode(profile));
    } catch (_) {
      // Use the cached profile for the home screen during a temporary network
      // failure. Server-side access control remains authoritative for data.
    }

    if (mounted) {
      setState(() {
        _supabaseProfile = profile;
        _restoringSession = false;
      });
    }
  }

  Future<void> _saveSupabaseProfile(Map<String, dynamic> profile) async {
    try {
      final dise = '${profile['school_id'] ?? ''}'.trim();
      if (dise.isNotEmpty) {
        _lastDiseCode = dise;
      }
      final prefs = await SharedPreferences.getInstance();
      if (dise.isNotEmpty) {
        await prefs.setString(_lastDiseCodeCacheKey, dise);
      }
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      await prefs.setString(_supabaseProfileCacheKey, jsonEncode(profile));
      await prefs.setString(_supabaseProfileUidCacheKey, user.id);
    } catch (_) {
      // A save failure must not prevent a successful sign-in.
    }
  }

  void _onSupabaseAuthenticated(Map<String, dynamic> profile) {
    if (!mounted) return;
    final copy = Map<String, dynamic>.from(profile);
    setState(() {
      _supabaseProfile = copy;
      _restoringSession = false;
    });
    unawaited(_saveSupabaseProfile(copy));
  }

  Future<void> _logoutSupabase() async {
    final client = Supabase.instance.client;
    final currentDise = '${_supabaseProfile?['school_id'] ?? ''}'.trim();
    if (currentDise.isNotEmpty) {
      _lastDiseCode = currentDise;
    }
    try {
      await client.auth.signOut();
    } finally {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (currentDise.isNotEmpty) {
          await prefs.setString(_lastDiseCodeCacheKey, currentDise);
        } else {
          final savedDise = (prefs.getString(_lastDiseCodeCacheKey) ?? '').trim();
          if (savedDise.isNotEmpty) _lastDiseCode = savedDise;
        }
        await _clearSupabaseProfileCache(prefs);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _supabaseProfile = null;
          _restoringSession = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoringSession) {
      return Scaffold(
        body: Container(
          decoration: AppTheme.headerGradient,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_rounded,
                    size: 64, color: Colors.white),
                SizedBox(height: 24),
                CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        ),
      );
    }

    final profile = _supabaseProfile;
    if (profile != null) {
      return SupabaseSignedInHome(
        profile: profile,
        onLogout: _logoutSupabase,
      );
    }

    return SupabasePlatformEntryScreen(
      onAuthenticated: _onSupabaseAuthenticated,
      initialSchoolId: _lastDiseCode,
    );
  }
}
