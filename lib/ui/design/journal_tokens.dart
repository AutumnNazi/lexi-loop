import 'package:material_ui/material_ui.dart';

import '../../core/theme_settings.dart';

/// FSRS 评分档位的语义配色组，确保四档按钮具备一眼可辨的视觉区分。
@immutable
class RatingTone {
  const RatingTone({
    required this.foreground,
    required this.background,
    required this.border,
  });

  final Color foreground;
  final Color background;
  final Color border;

  static RatingTone lerp(RatingTone a, RatingTone b, double t) => RatingTone(
    foreground: Color.lerp(a.foreground, b.foreground, t)!,
    background: Color.lerp(a.background, b.background, t)!,
    border: Color.lerp(a.border, b.border, t)!,
  );
}

/// 精装手账视觉令牌：统一管理暖纸表面层级、墨色对比与语义色组。
@immutable
class JournalTokens extends ThemeExtension<JournalTokens> {
  const JournalTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceElevated,
    required this.surfaceMuted,
    required this.sidebarSurface,
    required this.heroSurface,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.primary,
    required this.onPrimary,
    required this.accent,
    required this.accentSoft,
    required this.border,
    required this.shadow,
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
  });

  static const light = JournalTokens(
    canvas: Color(0xFFF3EFE6),
    surface: Color(0xFFFCFBF7),
    surfaceElevated: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFECE7DB),
    sidebarSurface: Color(0xFFF7F4EC),
    heroSurface: Color(0xFFE2ECE1),
    inkPrimary: Color(0xFF1A332B),
    inkSecondary: Color(0xFF54685E),
    inkMuted: Color(0xFF7A8B82),
    primary: Color(0xFF184438),
    onPrimary: Color(0xFFFCFBF7),
    accent: Color(0xFFB86F24),
    accentSoft: Color(0xFFF6E9D7),
    border: Color(0xFFDCD5C7),
    shadow: Color(0x0E1A332B),
    again: RatingTone(
      foreground: Color(0xFFA63A32),
      background: Color(0xFFFAEBE9),
      border: Color(0xFFE5BEB9),
    ),
    hard: RatingTone(
      foreground: Color(0xFF9A5A18),
      background: Color(0xFFFAF0E1),
      border: Color(0xFFE7CFA9),
    ),
    good: RatingTone(
      foreground: Color(0xFF184438),
      background: Color(0xFFE2EFE6),
      border: Color(0xFF9BC0AA),
    ),
    easy: RatingTone(
      foreground: Color(0xFF1E5C6B),
      background: Color(0xFFE3F1F4),
      border: Color(0xFFA7CED7),
    ),
  );

  static const dark = JournalTokens(
    canvas: Color(0xFF121B17),
    surface: Color(0xFF1A2620),
    surfaceElevated: Color(0xFF22312A),
    surfaceMuted: Color(0xFF15201B),
    sidebarSurface: Color(0xFF16211C),
    heroSurface: Color(0xFF1F352B),
    inkPrimary: Color(0xFFECF0E8),
    inkSecondary: Color(0xFFA7B8AE),
    inkMuted: Color(0xFF7D8F84),
    primary: Color(0xFF9FD0B3),
    onPrimary: Color(0xFF10261E),
    accent: Color(0xFFE0A25B),
    accentSoft: Color(0xFF3A2D1E),
    border: Color(0xFF2E3F36),
    shadow: Color(0x36000000),
    again: RatingTone(
      foreground: Color(0xFFF09992),
      background: Color(0xFF3A201F),
      border: Color(0xFF6A3936),
    ),
    hard: RatingTone(
      foreground: Color(0xFFE6B06E),
      background: Color(0xFF372A1B),
      border: Color(0xFF664D2D),
    ),
    good: RatingTone(
      foreground: Color(0xFFA4D4B7),
      background: Color(0xFF21392D),
      border: Color(0xFF3D6852),
    ),
    easy: RatingTone(
      foreground: Color(0xFF8ECAD8),
      background: Color(0xFF1B3238),
      border: Color(0xFF345E69),
    ),
  );

  static final seaSaltLight = JournalTokens(
    canvas: const Color(0xFFEEF3F4),
    surface: const Color(0xFFFBFCFC),
    surfaceElevated: const Color(0xFFFFFFFF),
    surfaceMuted: const Color(0xFFE1EAEC),
    sidebarSurface: const Color(0xFFF3F7F8),
    heroSurface: const Color(0xFFDCEBED),
    inkPrimary: const Color(0xFF163039),
    inkSecondary: const Color(0xFF4D6871),
    inkMuted: const Color(0xFF748A91),
    primary: const Color(0xFF1B5E6B),
    onPrimary: const Color(0xFFF7FCFD),
    accent: const Color(0xFFB36A4A),
    accentSoft: const Color(0xFFF4E5DD),
    border: const Color(0xFFD3E0E3),
    shadow: const Color(0x0E163039),
    again: light.again,
    hard: light.hard,
    good: light.good,
    easy: light.easy,
  );

  static final seaSaltDark = JournalTokens(
    canvas: const Color(0xFF0E171B),
    surface: const Color(0xFF152329),
    surfaceElevated: const Color(0xFF1D3138),
    surfaceMuted: const Color(0xFF111E23),
    sidebarSurface: const Color(0xFF122026),
    heroSurface: const Color(0xFF1B3740),
    inkPrimary: const Color(0xFFE8F1F3),
    inkSecondary: const Color(0xFFA4BDC4),
    inkMuted: const Color(0xFF7D969D),
    primary: const Color(0xFF8CCBD4),
    onPrimary: const Color(0xFF0C262C),
    accent: const Color(0xFFE2A164),
    accentSoft: const Color(0xFF362A20),
    border: const Color(0xFF294149),
    shadow: const Color(0x36000000),
    again: dark.again,
    hard: dark.hard,
    good: dark.good,
    easy: dark.easy,
  );

  static final warmApricotLight = JournalTokens(
    canvas: const Color(0xFFF5EEE4),
    surface: const Color(0xFFFEFAF4),
    surfaceElevated: const Color(0xFFFFFEFC),
    surfaceMuted: const Color(0xFFEBDFD0),
    sidebarSurface: const Color(0xFFF8F1E8),
    heroSurface: const Color(0xFFF2E1CE),
    inkPrimary: const Color(0xFF3A2A1F),
    inkSecondary: const Color(0xFF6F5848),
    inkMuted: const Color(0xFF907A69),
    primary: const Color(0xFF8B4E2E),
    onPrimary: const Color(0xFFFFF9F2),
    accent: const Color(0xFFA56A2C),
    accentSoft: const Color(0xFFF7E8D6),
    border: const Color(0xFFE2D2C1),
    shadow: const Color(0x0E3A2A1F),
    again: light.again,
    hard: light.hard,
    good: light.good,
    easy: light.easy,
  );

  static final warmApricotDark = JournalTokens(
    canvas: const Color(0xFF1B1410),
    surface: const Color(0xFF271D17),
    surfaceElevated: const Color(0xFF33251C),
    surfaceMuted: const Color(0xFF211811),
    sidebarSurface: const Color(0xFF231A14),
    heroSurface: const Color(0xFF3B2A20),
    inkPrimary: const Color(0xFFF3EADF),
    inkSecondary: const Color(0xFFC7B3A1),
    inkMuted: const Color(0xFF9E8877),
    primary: const Color(0xFFE2AE83),
    onPrimary: const Color(0xFF321D10),
    accent: const Color(0xFFE8B36D),
    accentSoft: const Color(0xFF3B2A1C),
    border: const Color(0xFF463429),
    shadow: const Color(0x36000000),
    again: dark.again,
    hard: dark.hard,
    good: dark.good,
    easy: dark.easy,
  );

  static final graphiteLight = JournalTokens(
    canvas: const Color(0xFFF0F1F2),
    surface: const Color(0xFFFAFAFB),
    surfaceElevated: const Color(0xFFFFFFFF),
    surfaceMuted: const Color(0xFFE4E6E8),
    sidebarSurface: const Color(0xFFF5F6F7),
    heroSurface: const Color(0xFFE2E6E8),
    inkPrimary: const Color(0xFF1E2428),
    inkSecondary: const Color(0xFF5B656C),
    inkMuted: const Color(0xFF7D878E),
    primary: const Color(0xFF37474F),
    onPrimary: const Color(0xFFFAFCFD),
    accent: const Color(0xFFA66A2E),
    accentSoft: const Color(0xFFF2E7D8),
    border: const Color(0xFFD7DBDE),
    shadow: const Color(0x0E1E2428),
    again: light.again,
    hard: light.hard,
    good: light.good,
    easy: light.easy,
  );

  static final graphiteDark = JournalTokens(
    canvas: const Color(0xFF111416),
    surface: const Color(0xFF181D20),
    surfaceElevated: const Color(0xFF20262A),
    surfaceMuted: const Color(0xFF14191C),
    sidebarSurface: const Color(0xFF151A1D),
    heroSurface: const Color(0xFF263238),
    inkPrimary: const Color(0xFFECF0F2),
    inkSecondary: const Color(0xFFA6B0B6),
    inkMuted: const Color(0xFF7C878E),
    primary: const Color(0xFFB7C7D0),
    onPrimary: const Color(0xFF172024),
    accent: const Color(0xFFE2A468),
    accentSoft: const Color(0xFF33291E),
    border: const Color(0xFF2F383D),
    shadow: const Color(0x36000000),
    again: dark.again,
    hard: dark.hard,
    good: dark.good,
    easy: dark.easy,
  );

  static JournalTokens forTheme(JournalThemeId themeId, Brightness brightness) {
    final darkMode = brightness == Brightness.dark;
    return switch (themeId) {
      JournalThemeId.emerald => darkMode ? dark : light,
      JournalThemeId.seaSalt => darkMode ? seaSaltDark : seaSaltLight,
      JournalThemeId.warmApricot =>
        darkMode ? warmApricotDark : warmApricotLight,
      JournalThemeId.graphite => darkMode ? graphiteDark : graphiteLight,
    };
  }

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 24;

  final Color canvas;
  final Color surface;
  final Color surfaceElevated;
  final Color surfaceMuted;
  final Color sidebarSurface;
  final Color heroSurface;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color primary;
  final Color onPrimary;
  final Color accent;
  final Color accentSoft;
  final Color border;
  final Color shadow;
  final RatingTone again;
  final RatingTone hard;
  final RatingTone good;
  final RatingTone easy;

  List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: shadow,
      offset: const Offset(0, 6),
      blurRadius: 18,
      spreadRadius: -4,
    ),
  ];

  static JournalTokens of(BuildContext context) {
    final ext = Theme.of(context).extension<JournalTokens>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  /// 对数值指标统一启用等宽数字，避免刷分或倒计时切换时视觉跳动。
  static TextStyle? tabular(TextStyle? style) =>
      style?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  @override
  JournalTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceElevated,
    Color? surfaceMuted,
    Color? sidebarSurface,
    Color? heroSurface,
    Color? inkPrimary,
    Color? inkSecondary,
    Color? inkMuted,
    Color? primary,
    Color? onPrimary,
    Color? accent,
    Color? accentSoft,
    Color? border,
    Color? shadow,
    RatingTone? again,
    RatingTone? hard,
    RatingTone? good,
    RatingTone? easy,
  }) => JournalTokens(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    sidebarSurface: sidebarSurface ?? this.sidebarSurface,
    heroSurface: heroSurface ?? this.heroSurface,
    inkPrimary: inkPrimary ?? this.inkPrimary,
    inkSecondary: inkSecondary ?? this.inkSecondary,
    inkMuted: inkMuted ?? this.inkMuted,
    primary: primary ?? this.primary,
    onPrimary: onPrimary ?? this.onPrimary,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    again: again ?? this.again,
    hard: hard ?? this.hard,
    good: good ?? this.good,
    easy: easy ?? this.easy,
  );

  @override
  JournalTokens lerp(covariant ThemeExtension<JournalTokens>? other, double t) {
    if (other is! JournalTokens) return this;
    return JournalTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      sidebarSurface: Color.lerp(sidebarSurface, other.sidebarSurface, t)!,
      heroSurface: Color.lerp(heroSurface, other.heroSurface, t)!,
      inkPrimary: Color.lerp(inkPrimary, other.inkPrimary, t)!,
      inkSecondary: Color.lerp(inkSecondary, other.inkSecondary, t)!,
      inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      again: RatingTone.lerp(again, other.again, t),
      hard: RatingTone.lerp(hard, other.hard, t),
      good: RatingTone.lerp(good, other.good, t),
      easy: RatingTone.lerp(easy, other.easy, t),
    );
  }
}
