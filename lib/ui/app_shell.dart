import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'today_page.dart';
import 'journal_style.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  int _revision = 0;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  String? _refreshError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.dependencies.repository.changes.listen(
      (_) => _refresh(),
    );
    _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final revision = ++_revision;
    _timer?.cancel();
    setState(() => _refreshError = null);
    final dependencies = widget.dependencies;
    try {
      final due = await dependencies.repository.nextDue();
      if (!mounted || revision != _revision) return;
      final now = dependencies.nowUtc();
      final midnight = dependencies.repository.calendar.nextMidnightUtc(now);
      final next = due != null && due.isBefore(midnight) ? due : midnight;
      final delay = next.difference(now);
      _timer = Timer(delay.isNegative ? Duration.zero : delay, _refresh);
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _refreshError = '$error');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const destinations = [
      (label: '今日', icon: Icons.wb_sunny_outlined),
      (label: '词书', icon: Icons.menu_book_outlined),
      (label: '统计', icon: Icons.insights_outlined),
      (label: '设置', icon: Icons.tune),
    ];
    final deps = widget.dependencies;
    final page = switch (_index) {
      0 => TodayPage(key: ValueKey('today-$_revision'), dependencies: deps),
      1 => LibraryPage(dependencies: deps),
      2 => StatsPage(key: ValueKey('stats-$_revision'), dependencies: deps),
      _ => SettingsPage(dependencies: deps),
    };
    void select(int index) {
      setState(() => _index = index);
      _refresh();
    }

    final wide = MediaQuery.sizeOf(context).width >= 760;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/app-icon.png',
                width: 32,
                height: 32,
              ),
            ),
            const SizedBox(width: 10),
            const Text('Lexi Loop'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: '刷新',
            icon: const JournalIcon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) ...[
              NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: select,
                labelType: NavigationRailLabelType.all,
                destinations: destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: JournalIcon(item.icon),
                        label: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                children: [
                  if (_refreshError != null)
                    MaterialBanner(
                      content: Text('自动刷新失败：$_refreshError'),
                      actions: [
                        TextButton(
                          onPressed: _refresh,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  Expanded(child: page),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: select,
              destinations: destinations
                  .map(
                    (item) => NavigationDestination(
                      icon: JournalIcon(item.icon),
                      label: item.label,
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
