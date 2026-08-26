import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'palette.dart';

/// تفضيلُ العديل: عاديّ أو ليليّ، محفوظٌ على هاتفه.
///
/// ⚠ ON THE HANDSET, NOT IN THE DATABASE, and for the same reason the chat's
///   read-marks are: nobody but the reader needs to know, no figure depends on
///   it, and losing it costs one screen opening in the other palette. It also
///   matches the shape the app already has — `my_adeel_id()` reads the
///   `x-device-id` header, so a member IS one handset by design.
///
/// ⚠ AND IT USES THE SAME SECURE STORE the refresh token lives in. Not because
///   a theme is a secret, but because adding a second storage plugin for one
///   string is a dependency the association would carry for ever.
class ThemeModeStore {
  const ThemeModeStore(this._storage);

  final FlutterSecureStorage _storage;

  static const String _key = 'app_theme_mode';

  Future<AppThemeMode> read() async {
    try {
      final String? v = await _storage.read(key: _key);
      return v == 'dark' ? AppThemeMode.dark : AppThemeMode.light;
    } on Object {
      // A handset that will not give up the value gets the ordinary palette.
      return AppThemeMode.light;
    }
  }

  Future<void> write(AppThemeMode mode) async {
    try {
      await _storage.write(key: _key, value: mode.name);
    } on Object {
      // Best effort. A preference that failed to save is one screen, not a
      // reason to refuse the change he just made.
    }
  }
}

final Provider<ThemeModeStore> themeModeStoreProvider = Provider<ThemeModeStore>(
  (Ref ref) => const ThemeModeStore(FlutterSecureStorage()),
);

/// الوضعُ الحاليّ. تُشاهده الجذرُ فيُعيد بناء التطبيق كلَّه.
///
/// ⚠ IT APPLIES THE PALETTE IN THE SETTER, BEFORE THE STATE CHANGES. The
///   tokens are plain statics — see palette.dart — so every widget rebuilt
///   after this reads the new values. Assigning the state first would rebuild
///   part of the tree against the old palette.
class ThemeModeController extends Notifier<AppThemeMode> {
  @override
  AppThemeMode build() {
    // ⚠ SYNCHRONOUS, AND THE STORED VALUE ARRIVES LATER. main() has already
    //   applied the saved palette before runApp, so the first frame is
    //   correct; this default only matters to a test that builds the provider
    //   without one.
    return AppThemeMode.light;
  }

  Future<void> load() async {
    final AppThemeMode saved = await ref.read(themeModeStoreProvider).read();
    if (saved == state) return;
    applyAppTheme(saved);
    state = saved;
  }

  Future<void> set(AppThemeMode mode) async {
    if (mode == state) return;
    applyAppTheme(mode);
    state = mode;
    await ref.read(themeModeStoreProvider).write(mode);
  }

  /// بدّل.
  Future<void> toggle() => set(
    state == AppThemeMode.dark ? AppThemeMode.light : AppThemeMode.dark,
  );
}

final NotifierProvider<ThemeModeController, AppThemeMode> themeModeProvider =
    NotifierProvider<ThemeModeController, AppThemeMode>(
      ThemeModeController.new,
    );

/// يُقرأ قبل runApp حتى يكون أوّلُ إطارٍ باللوحة الصحيحة.
///
/// ⚠ WITHOUT THIS THE APP FLASHES. The provider cannot be read before the
///   ProviderScope exists, so the first frame would paint light and then jump
///   to dark a moment later — which on every launch reads as a fault.
Future<AppThemeMode> readSavedThemeMode() async {
  try {
    return await const ThemeModeStore(FlutterSecureStorage()).read();
  } on Object {
    debugPrint('theme mode: falling back to light');
    return AppThemeMode.light;
  }
}
