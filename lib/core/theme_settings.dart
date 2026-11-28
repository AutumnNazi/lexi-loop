enum JournalThemeId {
  emerald('emerald', '墨绿奶白', '沉静的墨绿与暖纸质感'),
  seaSalt('sea_salt', '海盐蓝', '清透的海盐蓝与冷白纸张'),
  warmApricot('warm_apricot', '暖杏棕', '温暖的杏棕与奶油底色'),
  graphite('graphite', '石墨灰', '克制的石墨灰与中性纸面');

  const JournalThemeId(this.storageValue, this.label, this.description);

  final String storageValue;
  final String label;
  final String description;

  static JournalThemeId fromStorage(String? value) {
    for (final theme in values) {
      if (theme.storageValue == value) return theme;
    }
    return JournalThemeId.emerald;
  }
}

enum AppThemeMode {
  system('system', '跟随系统'),
  light('light', '浅色'),
  dark('dark', '深色');

  const AppThemeMode(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static AppThemeMode fromStorage(String? value) {
    for (final mode in values) {
      if (mode.storageValue == value) return mode;
    }
    return AppThemeMode.system;
  }
}

class ThemeSettings {
  const ThemeSettings({required this.themeId, required this.mode});

  static const defaults = ThemeSettings(
    themeId: JournalThemeId.emerald,
    mode: AppThemeMode.system,
  );

  final JournalThemeId themeId;
  final AppThemeMode mode;

  ThemeSettings copyWith({JournalThemeId? themeId, AppThemeMode? mode}) =>
      ThemeSettings(themeId: themeId ?? this.themeId, mode: mode ?? this.mode);

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings && other.themeId == themeId && other.mode == mode;

  @override
  int get hashCode => Object.hash(themeId, mode);
}
