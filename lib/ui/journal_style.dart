import 'package:material_ui/material_ui.dart';

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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(
        color: Theme.of(context).colorScheme.outlineVariant
            .withValues(alpha: .55),
      ),
    ),
    child: Padding(padding: padding, child: child),
  );
}

ThemeData journalTheme(Brightness brightness, {String? fontFamily}) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xFF183F35),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xFFA8CFB7) : const Color(0xFF183F35),
        onPrimary: dark ? const Color(0xFF183F35) : const Color(0xFFFFFCF4),
        surface: dark ? const Color(0xFF202C26) : const Color(0xFFFFFDF8),
        onSurface: dark ? const Color(0xFFE9EDE5) : const Color(0xFF233D33),
        onSurfaceVariant: dark
            ? const Color(0xFFB4C2B7)
            : const Color(0xFF647369),
        outlineVariant: dark
            ? const Color(0xFF45554A)
            : const Color(0xFFDCE2D7),
        primaryContainer: dark
            ? const Color(0xFF324C3E)
            : const Color(0xFFE5ECDD),
      );
  final base = ThemeData(
    fontFamily: fontFamily,
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );
  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? const Color(0xFF16221C)
        : const Color(0xFFF4F2E9),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -.7,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 23,
        fontWeight: FontWeight.w700,
        height: 1.35,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.55),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.5,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        color: scheme.onSurface,
        fontWeight: FontWeight.w700,
      ),
      elevation: 0,
      toolbarHeight: 64,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: rounded,
        textStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: BorderSide(color: scheme.outlineVariant),
        shape: rounded,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(20),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      height: 76,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
      minWidth: 88,
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    ),
  );
}
