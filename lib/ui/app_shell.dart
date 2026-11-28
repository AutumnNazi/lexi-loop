import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app.dart';
import 'journal_style.dart';
import 'library_page.dart';
import 'settings_page.dart';
import 'stats_page.dart';
import 'today_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  int _revision = 0;
  final ValueNotifier<int> _refreshSignal = ValueNotifier<int>(0);
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  String? _refreshError;

  static const _destinations = [
    (label: '今日', icon: Icons.wb_sunny_outlined),
    (label: '词书', icon: Icons.menu_book_outlined),
    (label: '统计', icon: Icons.insights_outlined),
    (label: '设置', icon: Icons.tune),
  ];

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
    if (_refreshError != null) setState(() => _refreshError = null);
    _refreshSignal.value = revision;
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
    _refreshSignal.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (_index != index) setState(() => _index = index);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final deps = widget.dependencies;
    final tokens = JournalTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    final expandedRail = width >= 1040;

    final bodyContent = Column(
      children: [
        if (_refreshError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: JournalSurface(
              color: tokens.again.background,
              borderColor: tokens.again.border,
              radius: JournalTokens.radiusSm,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  JournalIcon(
                    Icons.error_outline,
                    size: 18,
                    color: tokens.again.foreground,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '自动刷新失败：$_refreshError',
                      style: TextStyle(color: tokens.again.foreground),
                    ),
                  ),
                  TextButton(onPressed: _refresh, child: const Text('重试')),
                ],
              ),
            ),
          ),
        Expanded(
          child: IndexedStack(
            index: _index,
            children: [
              TodayPage(dependencies: deps, refreshListenable: _refreshSignal),
              LibraryPage(
                dependencies: deps,
                refreshListenable: _refreshSignal,
              ),
              StatsPage(dependencies: deps, refreshListenable: _refreshSignal),
              SettingsPage(
                dependencies: deps,
                refreshListenable: _refreshSignal,
              ),
            ],
          ),
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _DesktopSidebar(
                expanded: expandedRail,
                selectedIndex: _index,
                onSelect: _select,
                onRefresh: _refresh,
              ),
              VerticalDivider(width: 1, color: tokens.border),
              Expanded(child: bodyContent),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/images/app-icon.png',
                width: 30,
                height: 30,
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
            icon: const JournalIcon(Icons.refresh, size: 22),
          ),
        ],
      ),
      body: SafeArea(top: false, child: bodyContent),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _select,
          destinations: _destinations
              .map(
                (item) => NavigationDestination(
                  icon: JournalIcon(
                    item.icon,
                    size: 22,
                    color: tokens.inkSecondary,
                  ),
                  selectedIcon: JournalIcon(
                    item.icon,
                    size: 22,
                    color: tokens.primary,
                  ),
                  label: item.label,
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.expanded,
    required this.selectedIndex,
    required this.onSelect,
    required this.onRefresh,
  });

  final bool expanded;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return Container(
      width: expanded ? 224 : 84,
      color: tokens.sidebarSurface,
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? 14 : 10,
        vertical: 20,
      ),
      child: Column(
        crossAxisAlignment: expanded
            ? CrossAxisAlignment.stretch
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: expanded ? 8 : 0),
            child: Row(
              mainAxisAlignment: expanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.asset(
                    'assets/images/app-icon.png',
                    width: 36,
                    height: 36,
                  ),
                ),
                if (expanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lexi Loop',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '离线词汇手账',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: tokens.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: _AppShellState._destinations.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final item = _AppShellState._destinations[index];
                final selected = index == selectedIndex;
                return _SidebarNavItem(
                  label: item.label,
                  icon: item.icon,
                  expanded: expanded,
                  selected: selected,
                  onTap: () => onSelect(index),
                );
              },
            ),
          ),
          Divider(color: tokens.border),
          const SizedBox(height: 10),
          if (expanded)
            InkWell(
              onTap: onRefresh,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    JournalIcon(
                      Icons.refresh,
                      size: 20,
                      color: tokens.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '刷新队列',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.inkSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            IconButton(
              onPressed: onRefresh,
              tooltip: '刷新',
              icon: JournalIcon(
                Icons.refresh,
                size: 22,
                color: tokens.inkSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  const _SidebarNavItem({
    required this.label,
    required this.icon,
    required this.expanded,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool expanded;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final bg = selected ? tokens.heroSurface : Colors.transparent;
    final fg = selected ? tokens.primary : tokens.inkSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 12 : 6,
            vertical: expanded ? 11 : 10,
          ),
          child: expanded
              ? Row(
                  children: [
                    JournalIcon(icon, size: 21, color: fg),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: selected ? tokens.inkPrimary : fg,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    JournalIcon(icon, size: 22, color: fg),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? tokens.inkPrimary : fg,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
