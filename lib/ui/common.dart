import 'package:material_ui/material_ui.dart';

import '../data/app_database.dart';
import 'journal_style.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions = const [],
    this.maxWidth = 1040,
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final double maxWidth;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 600;
    final horizontal = compact ? 18.0 : 36.0;
    final top = compact ? 8.0 : 28.0;
    final inlineActions = width >= 720 && actions.isNotEmpty;

    final headerText = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.inkSecondary),
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (inlineActions)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: headerText),
              const SizedBox(width: 20),
              Wrap(spacing: 10, runSpacing: 10, children: actions),
            ],
          )
        else ...[
          headerText,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 10, runSpacing: 10, children: actions),
          ],
        ],
        SizedBox(height: compact ? 18 : 24),
        ...children,
      ],
    );

    final inner = Padding(
      padding: EdgeInsets.fromLTRB(horizontal, top, horizontal, 28),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: content,
        ),
      ),
    );

    if (!scrollable) return inner;
    return SingleChildScrollView(child: inner);
  }
}

class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items, this.accentIndex});
  final List<({String label, String value})> items;
  final int? accentIndex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns = constraints.maxWidth < 480;
      final spacing = 16.0;
      final cellWidth = twoColumns
          ? (constraints.maxWidth - spacing) / 2
          : (constraints.maxWidth - spacing * 3) / 4;
      return Wrap(
        spacing: spacing,
        runSpacing: 16,
        children: List.generate(items.length, (i) {
          final item = items[i];
          return SizedBox(
            width: cellWidth,
            child: MetricCell(
              label: item.label,
              value: item.value,
              accent: accentIndex == i,
            ),
          );
        }),
      );
    },
  );
}

class MessagePanel extends StatelessWidget {
  const MessagePanel({
    super.key,
    required this.title,
    required this.message,
    this.action,
    this.icon = Icons.check_circle_outline,
  });
  final String title;
  final String message;
  final Widget? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return JournalSurface(
      variant: JournalSurfaceVariant.muted,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: tokens.surface,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.border),
            ),
            alignment: Alignment.center,
            child: JournalIcon(icon, size: 28, color: tokens.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.inkSecondary),
          ),
          if (action != null) ...[const SizedBox(height: 20), action!],
        ],
      ),
    );
  }
}

Widget journalBackButton(BuildContext context) => IconButton(
  tooltip: '返回',
  onPressed: () => Navigator.of(context).maybePop(),
  icon: const JournalIcon(Icons.arrow_back, size: 22),
);

class AsyncContent<T> extends StatelessWidget {
  const AsyncContent({
    super.key,
    required this.future,
    required this.builder,
    this.retry,
  });
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback? retry;

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return MessagePanel(
          title: '暂时无法读取数据',
          message: '${snapshot.error}',
          icon: Icons.error_outline,
          action: retry == null
              ? null
              : OutlinedButton(onPressed: retry, child: const Text('重试')),
        );
      }
      if (!snapshot.hasData) {
        return const Padding(
          padding: EdgeInsets.all(48),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return builder(snapshot.data as T);
    },
  );
}

({String label, bool isDue, StatusBadgeTone tone}) memoryStageInfo(
  MemoryStateRow? memory,
  DateTime nowUtc,
) {
  if (memory == null) {
    return (label: '尚未学习', isDue: false, tone: StatusBadgeTone.newWord);
  }
  final isDue = memory.due <= nowUtc.millisecondsSinceEpoch;
  if (isDue) {
    return (label: '待复习', isDue: true, tone: StatusBadgeTone.due);
  }
  return switch (memory.state) {
    1 => (label: '学习中', isDue: false, tone: StatusBadgeTone.learning),
    2 => (label: '复习中', isDue: false, tone: StatusBadgeTone.review),
    _ => (label: '重新学习', isDue: false, tone: StatusBadgeTone.relearning),
  };
}

String intervalLabel(Duration duration) {
  if (duration.inDays >= 1) return '${duration.inDays} 天';
  if (duration.inHours >= 1) return '${duration.inHours} 小时';
  if (duration.inMinutes >= 1) return '${duration.inMinutes} 分钟';
  return '${duration.inSeconds.clamp(1, 59)} 秒';
}

String localDateTimeLabel(DateTime value) {
  final date = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.month} 月 ${date.day} 日 ${two(date.hour)}:${two(date.minute)}';
}

String localDateTimeWithYearLabel(DateTime value) {
  final date = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}

class DialogResponse<T> {
  bool _responded = false;

  void close(BuildContext context, T result) {
    // 同帧重复点击或已关闭弹框的旧回调，不能继续退出外层页面。
    if (_responded ||
        !context.mounted ||
        ModalRoute.of(context)?.isCurrent != true) {
      return;
    }
    _responded = true;
    Navigator.of(context).pop(result);
  }
}

Future<bool> confirmDiscardChanges(
  BuildContext context, {
  required String title,
  required String message,
  String keepLabel = '继续编辑',
  String discardLabel = '放弃并返回',
}) async {
  final response = DialogResponse<bool>();
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        constraints: const BoxConstraints(maxWidth: 440),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => response.close(context, false),
            child: Text(keepLabel),
          ),
          FilledButton(
            onPressed: () => response.close(context, true),
            child: Text(discardLabel),
          ),
        ],
      );
    },
  );
  return discard == true;
}
