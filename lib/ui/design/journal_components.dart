import 'package:material_ui/material_ui.dart';

import 'journal_tokens.dart';

enum JournalSurfaceVariant { standard, hero, muted, elevated }

/// 分层纸面容器：根据页面职责区分普通卡片、主任务卡、弱化信息块与浮动卡片。
class JournalSurface extends StatelessWidget {
  const JournalSurface({
    super.key,
    required this.child,
    this.variant = JournalSurfaceVariant.standard,
    this.padding = const EdgeInsets.all(20),
    this.radius = JournalTokens.radiusLg,
    this.color,
    this.borderColor,
    this.elevated = false,
    this.onTap,
  });

  final Widget child;
  final JournalSurfaceVariant variant;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool elevated;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final resolvedColor =
        color ??
        switch (variant) {
          JournalSurfaceVariant.standard => tokens.surface,
          JournalSurfaceVariant.hero => tokens.heroSurface,
          JournalSurfaceVariant.muted => tokens.surfaceMuted,
          JournalSurfaceVariant.elevated => tokens.surfaceElevated,
        };
    final resolvedBorder =
        borderColor ??
        switch (variant) {
          JournalSurfaceVariant.hero => tokens.primary.withValues(alpha: .16),
          JournalSurfaceVariant.muted => tokens.border.withValues(alpha: .7),
          JournalSurfaceVariant.standard ||
          JournalSurfaceVariant.elevated => tokens.border,
        };
    final useShadow = elevated || variant == JournalSurfaceVariant.elevated;
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvedColor,
        borderRadius: borderRadius,
        border: Border.all(color: resolvedBorder),
        boxShadow: useShadow ? tokens.elevatedShadow : null,
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : Material(
              color: Colors.transparent,
              borderRadius: borderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
  }
}

enum StatusBadgeTone {
  newWord,
  learning,
  review,
  relearning,
  due,
  accent,
  neutral,
}

/// 记忆阶段或计数状态胶囊，带 6px 状态圆点与紧凑文字。
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusBadgeTone.neutral,
    this.showDot = true,
  });

  final String label;
  final StatusBadgeTone tone;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final colors = switch (tone) {
      StatusBadgeTone.newWord => (
        fg: tokens.inkSecondary,
        bg: tokens.surfaceMuted,
        border: tokens.border,
      ),
      StatusBadgeTone.learning => (
        fg: tokens.easy.foreground,
        bg: tokens.easy.background,
        border: tokens.easy.border,
      ),
      StatusBadgeTone.review => (
        fg: tokens.good.foreground,
        bg: tokens.good.background,
        border: tokens.good.border,
      ),
      StatusBadgeTone.relearning => (
        fg: tokens.again.foreground,
        bg: tokens.again.background,
        border: tokens.again.border,
      ),
      StatusBadgeTone.due || StatusBadgeTone.accent => (
        fg: tokens.accent,
        bg: tokens.accentSoft,
        border: tokens.accent.withValues(alpha: .32),
      ),
      StatusBadgeTone.neutral => (
        fg: tokens.inkSecondary,
        bg: tokens.surfaceMuted,
        border: tokens.border,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.fg,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.fg, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// 精装数据指标单元，数字采用等宽对齐。
class MetricCell extends StatelessWidget {
  const MetricCell({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
    this.footnote,
  });

  final String label;
  final String value;
  final bool accent;
  final Widget? footnote;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final valueStyle = JournalTokens.tabular(
      Theme.of(context).textTheme.headlineSmall?.copyWith(
        color: accent ? tokens.accent : tokens.inkPrimary,
        fontWeight: FontWeight.w700,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: valueStyle),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.inkSecondary),
        ),
        if (footnote != null) ...[const SizedBox(height: 8), footnote!],
      ],
    );
  }
}

/// 圆润手账进度条，带有限时长平滑过渡与语义标签。
class JournalProgressBar extends StatelessWidget {
  const JournalProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.color,
    this.trackColor,
    this.semanticsLabel,
  });

  final double value;
  final double height;
  final Color? color;
  final Color? trackColor;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final clamped = value.clamp(0.0, 1.0);
    final bar = Semantics(
      label: semanticsLabel,
      value: '${(clamped * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: height,
          color: trackColor ?? tokens.surfaceMuted,
          alignment: Alignment.centerLeft,
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: constraints.maxWidth * clamped,
              height: height,
              decoration: BoxDecoration(
                color: color ?? tokens.primary,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ),
    );
    return bar;
  }
}

/// 分区标题栏：左侧主标题，右侧可选补充说明或操作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: tokens.inkPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing!],
      ],
    );
  }
}

/// 桌面端键盘快捷键纸质键帽徽标。
class KeyHintBadge extends StatelessWidget {
  const KeyHintBadge(this.label, {super.key, this.foreground, this.border});

  final String label;
  final Color? foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border ?? tokens.border),
      ),
      child: Text(
        label,
        style: JournalTokens.tabular(
          Theme.of(context).textTheme.labelSmall?.copyWith(
            color: foreground ?? tokens.inkSecondary,
            fontWeight: FontWeight.w600,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
