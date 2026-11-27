import 'package:material_ui/material_ui.dart';

import 'journal_style.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions = const [],
  });
  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 22 : 40,
      12,
      MediaQuery.sizeOf(context).width < 600 ? 22 : 40,
      32,
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 12, runSpacing: 12, children: actions),
            ],
            const SizedBox(height: 24),
            ...children,
          ],
        ),
      ),
    ),
  );
}

class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items});
  final List<({String label, String value})> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 16,
      runSpacing: 20,
      children: items
          .map(
            (item) => SizedBox(
              width: constraints.maxWidth < 420
                  ? (constraints.maxWidth - 16) / 2
                  : (constraints.maxWidth - 48) / 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.value,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.label,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      children: [
        JournalIcon(
          icon,
          size: 52,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );
}

Widget journalBackButton(BuildContext context) => IconButton(
  tooltip: '返回',
  onPressed: () => Navigator.of(context).maybePop(),
  icon: const JournalIcon(Icons.arrow_back),
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
