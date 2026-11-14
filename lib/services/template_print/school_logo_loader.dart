import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Reads the school logo saved in the Admin Centre (school_settings), the
/// same place the old PDF service used.
Future<Uint8List?> loadSchoolLogoBytes(dynamic client, String schoolRef) async {
  if (schoolRef.trim().isEmpty) return null;
  try {
    final raw = await client
        .from('school_settings')
        .select('logo_path,logo_data_uri,config')
        .eq('school_ref', schoolRef)
        .maybeSingle();
    if (raw == null) return null;
    final settings = Map<String, dynamic>.from(raw as Map);
    final uri = '${settings['logo_data_uri'] ?? ''}'.trim();
    if (uri.startsWith('data:') && uri.contains(',')) {
      return base64Decode(uri.split(',').last.trim());
    }
    var path = '${settings['logo_path'] ?? settings['logo_url'] ?? ''}'.trim();
    var config = settings['config'];
    if (config is String && config.trim().startsWith('{')) config = jsonDecode(config);
    if (path.isEmpty && config is Map) path = '${config['logo_path'] ?? config['logo_url'] ?? ''}'.trim();
    if (path.isEmpty) return null;
    if (path.startsWith('http://') || path.startsWith('https://')) {
      final res = await http.get(Uri.parse(path)).timeout(const Duration(seconds: 12));
      return res.statusCode == 200 && res.bodyBytes.isNotEmpty ? Uint8List.fromList(res.bodyBytes) : null;
    }
    final bytes = await client.storage.from('school-assets').download(path).timeout(const Duration(seconds: 12));
    return bytes is Uint8List && bytes.isNotEmpty ? bytes : null;
  } catch (_) {
    return null;
  }
}
