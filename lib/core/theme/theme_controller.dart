import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/ui_prefs.dart';

/// App-wide theme mode. Watched by [MaterialApp.themeMode]; the shell's
/// toggle button calls `ref.read(themeModeProvider.notifier).cycle()`.
final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Human-readable label for tooltips/menus.
String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'системная',
      ThemeMode.light => 'светлая',
      ThemeMode.dark => 'тёмная',
    };

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // Пока общий набop виджетов (koz_widgets) захардкожен под светлую тему,
    // приложение стартует в СВЕТЛОЙ теме (единый законченный вид), а не в
    // системной — иначе тёмный режим ОС давал бы «полу-тёмный» UI. Тёмная тема
    // реализована и готова к включению, когда koz_widgets станет
    // theme-aware (см. README, раздел «Дальше»). Затем восстанавливаем
    // сохранённый выбор (идиома как в AuthController).
    Future.microtask(_restore);
    return ThemeMode.light;
  }

  String get label => themeModeLabel(state);

  Future<void> _restore() async {
    final saved = await ref.read(uiPrefsProvider).readThemeMode();
    final restored = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => null, // never set / unknown value → keep system
    };
    if (restored != null) state = restored;
  }

  /// system → light → dark → system; persists the new choice.
  Future<void> cycle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    state = next;
    await ref.read(uiPrefsProvider).writeThemeMode(switch (next) {
      ThemeMode.system => 'system',
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
    });
  }
}
