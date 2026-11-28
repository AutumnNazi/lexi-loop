import 'package:material_ui/material_ui.dart';

import '../core/theme_settings.dart';
import 'design/journal_components.dart';
import 'design/journal_tokens.dart';

export 'design/journal_components.dart';
export 'design/journal_tokens.dart';

/// 图标来自项目内的 magpie-image 素材，统一按前景色适配深浅主题。
class JournalIcon extends StatelessWidget {
  const JournalIcon(this.icon, {super.key, this.size = 24, this.color});
  final IconData icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final asset = switch (icon) {
      Icons.wb_sunny_outlined => 'today',
      Icons.menu_book_outlined => 'library',
      Icons.insights_outlined || Icons.show_chart => 'stats',
      Icons.tune => 'settings',
      Icons.arrow_forward || Icons.chevron_right => 'arrow_right',
      Icons.arrow_back => 'arrow_left',
      Icons.edit_outlined => 'pencil',
      Icons.add => 'plus',
      Icons.search || Icons.search_off => 'search',
      Icons.check_circle_outline => 'check',
      Icons.refresh => 'refresh',
      Icons.file_download_outlined => 'download',
      Icons.file_upload_outlined => 'upload',
      Icons.close => 'close',
      Icons.error_outline => 'warning',
      _ => 'cards',
    };
    return Image.asset(
      'assets/icons/$asset.png',
      width: size,
      height: size,
      color:
          color ??
          IconTheme.of(context).color ??
          Theme.of(context).colorScheme.onSurface,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.high,
    );
  }
}

/// 兼容旧调用的纸面容器，内部委托给分层设计组件 `JournalSurface`。
class JournalPanel extends StatelessWidget {
  const JournalPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      JournalSurface(padding: padding, color: color, child: child);
}

ThemeData journalTheme(
  Brightness brightness, {
  String? fontFamily,
  JournalThemeId themeId = JournalThemeId.emerald,
}) {
  final tokens = JournalTokens.forTheme(themeId, brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: tokens.primary,
        brightness: brightness,
      ).copyWith(
        primary: tokens.primary,
        onPrimary: tokens.onPrimary,
        secondary: tokens.accent,
        surface: tokens.surface,
        surfaceContainerHighest: tokens.surfaceMuted,
        onSurface: tokens.inkPrimary,
        onSurfaceVariant: tokens.inkSecondary,
        outline: tokens.inkMuted,
        outlineVariant: tokens.border,
        primaryContainer: tokens.heroSurface,
        onPrimaryContainer: tokens.inkPrimary,
        error: tokens.again.foreground,
      );
  final base = ThemeData(
    fontFamily: fontFamily,
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    extensions: [tokens],
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  );
  return base.copyWith(
    scaffoldBackgroundColor: tokens.canvas,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.primary,
      selectionColor: tokens.primary.withValues(alpha: .18),
      selectionHandleColor: tokens.primary,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(999),
      thumbColor: WidgetStatePropertyAll(
        tokens.inkMuted.withValues(alpha: .35),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      displayMedium: base.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        color: tokens.inkPrimary,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -.6,
        color: tokens.inkPrimary,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.32,
        letterSpacing: -.3,
        color: tokens.inkPrimary,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: tokens.inkPrimary,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.4,
        color: tokens.inkPrimary,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(
        fontSize: 15.5,
        height: 1.55,
        color: tokens.inkPrimary,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
        color: tokens.inkPrimary,
      ),
      bodySmall: base.textTheme.bodySmall?.copyWith(
        fontSize: 12.5,
        height: 1.45,
        color: tokens.inkSecondary,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: tokens.inkPrimary,
        fontWeight: FontWeight.w700,
      ),
      elevation: 0,
      toolbarHeight: 58,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tokens.primary,
        foregroundColor: tokens.onPrimary,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: rounded,
        elevation: 0,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.inkPrimary,
        backgroundColor: tokens.surface,
        minimumSize: const Size(48, 46),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        side: BorderSide(color: tokens.border),
        shape: rounded,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: tokens.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: TextStyle(color: tokens.inkMuted),
      labelStyle: TextStyle(color: tokens.inkSecondary),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: tokens.primary, width: 1.5),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: tokens.primary,
      linearTrackColor: tokens.surfaceMuted,
      borderRadius: BorderRadius.circular(20),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: tokens.heroSurface,
      height: 70,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontFamily: fontFamily,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? tokens.primary : tokens.inkSecondary,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.sidebarSurface,
      indicatorColor: tokens.heroSurface,
      minWidth: 84,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: tokens.surface,
      selectedColor: tokens.heroSurface,
      side: BorderSide(color: tokens.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      labelStyle: TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: tokens.inkPrimary,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: tokens.border),
      ),
    ),
  );
}
