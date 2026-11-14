import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores only this device's saved School DISE/UDISE, selected user, and password.
/// The Developer key and Supabase service-role key are never stored here.
class DeviceLoginCredentials {
  const DeviceLoginCredentials({
    required this.schoolId,
    required this.teacherId,
    required this.password,
  });

  final String schoolId;
  final String teacherId;
  final String password;
}

class DeviceLoginStore {
  DeviceLoginStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _schoolIdKey = 'psm.savedLogin.schoolId';
  static const _teacherIdKey = 'psm.savedLogin.teacherId';
  static const _passwordKey = 'psm.savedLogin.password';

  final FlutterSecureStorage _storage;

  Future<DeviceLoginCredentials?> read() async {
    final schoolId = await _storage.read(key: _schoolIdKey);
    final teacherId = await _storage.read(key: _teacherIdKey);
    final password = await _storage.read(key: _passwordKey);
    if ((schoolId ?? '').trim().isEmpty) return null;
    return DeviceLoginCredentials(
      schoolId: schoolId!.trim(),
      teacherId: (teacherId ?? '').trim(),
      password: password ?? '',
    );
  }

  Future<void> save({
    required String schoolId,
    required String teacherId,
    required String password,
  }) async {
    await _storage.write(key: _schoolIdKey, value: schoolId.trim());
    await _storage.write(key: _teacherIdKey, value: teacherId.trim());
    await _storage.write(key: _passwordKey, value: password);
  }

  Future<void> clear() async {
    await _storage.delete(key: _schoolIdKey);
    await _storage.delete(key: _teacherIdKey);
    await _storage.delete(key: _passwordKey);
  }
}
