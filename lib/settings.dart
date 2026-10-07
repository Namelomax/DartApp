import 'package:shared_preferences/shared_preferences.dart';

/// Адрес сервера и пароль, сохраняются на телефоне.
class ServerSettings {
  final String serverUrl;
  final String token;

  const ServerSettings({required this.serverUrl, required this.token});

  bool get isComplete => serverUrl.trim().isNotEmpty && token.isNotEmpty;

  static const _urlKey = 'server_url';
  static const _tokenKey = 'server_token';

  static Future<ServerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ServerSettings(
      serverUrl: prefs.getString(_urlKey) ?? '',
      token: prefs.getString(_tokenKey) ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, serverUrl.trim());
    await prefs.setString(_tokenKey, token);
  }
}
