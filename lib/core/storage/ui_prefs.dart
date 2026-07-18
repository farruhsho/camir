import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final uiPrefsProvider = Provider<UiPrefs>((ref) => UiPrefs());

/// Small, non-sensitive UI preferences (remembered login email, theme choice).
///
/// Same `shared_preferences` foundation as [TokenStorage]; nothing here is a
/// secret, so it never needs to move to platform secure storage.
class UiPrefs {
  static const _emailKey = 'remembered_email';
  static const _themeKey = 'theme_mode';

  Future<String?> readRememberedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  /// Passing `null` (or an empty string) clears the remembered email.
  Future<void> writeRememberedEmail(String? email) async {
    final prefs = await SharedPreferences.getInstance();
    if (email == null || email.isEmpty) {
      await prefs.remove(_emailKey);
    } else {
      await prefs.setString(_emailKey, email);
    }
  }

  /// Returns 'system' | 'light' | 'dark' (or null when never set).
  Future<String?> readThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeKey);
  }

  Future<void> writeThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode);
  }
}
