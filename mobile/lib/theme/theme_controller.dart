import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_palette.dart';
import 'app_theme.dart';

/// Which scheme the person chose: light, dark, or whatever the phone is set to. Until they choose
/// the app is light (owner's decision, 2026-11-06), whatever the phone is set to.
enum AppThemeMode { system, light, dark }

/// The chosen scheme, remembered on the device. Switching it changes every colour at once: the
/// palette in force is replaced and the whole tree is repainted in place (nothing is rebuilt from
/// scratch, so a half-filled cart or form survives the switch).
class ThemeController extends ChangeNotifier {
  ThemeController(this._prefs) : _mode = _read(_prefs);

  static const _key = 'theme.mode';
  final SharedPreferences _prefs;
  AppThemeMode _mode;

  AppThemeMode get mode => _mode;

  ThemeMode get themeMode => switch (_mode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system => ThemeMode.system,
  };

  static AppThemeMode _read(SharedPreferences prefs) =>
      switch (prefs.getString(_key)) {
        'dark' => AppThemeMode.dark,
        'system' => AppThemeMode.system,
        _ => AppThemeMode.light,
      };

  Future<void> setMode(AppThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    await _prefs.setString(_key, mode.name);
  }

  /// The scheme that is in force, given what the phone prefers.
  Brightness resolve(Brightness platform) => switch (_mode) {
    AppThemeMode.light => Brightness.light,
    AppThemeMode.dark => Brightness.dark,
    AppThemeMode.system => platform,
  };

  /// Puts the palette of [brightness] in force. True when that changed it.
  static bool apply(Brightness brightness) {
    final next = brightness == Brightness.dark
        ? AppPalette.dark
        : AppPalette.light;
    if (identical(AppColors.palette, next)) return false;
    AppColors.use(next);
    return true;
  }

  /// Marks every widget of the running app as needing a rebuild, so each one reads the new
  /// palette. State is untouched: only `build` runs again.
  static void repaintEverything() {
    void mark(Element element) {
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(mark);
  }
}

/// Gives any widget the controller (for the toggle in Settings).
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope is missing above this widget');
    return scope!.notifier!;
  }
}
