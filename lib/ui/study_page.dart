import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/ids.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'journal_style.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({
    super.key,
    required this.dependencies,
    this.senseId,
    this.wordbookId,
    this.todayPlan = false,
  });
  final AppDependencies dependencies;
  final int? senseId;
  final String? wordbookId;
  final bool todayPlan;
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  StudyItem? _item;
  StudyQueueStatus? _status;
  bool _revealed = false, _busy = false, _loading = true;
  bool _loadFailed = false;
  String? _error;
  String? _summaryError;
  String _eventId = newReviewEventId();
  String? _lastUndoEventId;
  DateTime? _shownAt;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  int _generation = 0;
  int _completedCount = 0;
  int _summaryRevision = 0;
  final Set<String> _sessionEventIds = {};
  StudySessionSummary? _sessionSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.dependencies.repository.changes.listen((_) {
      if (!_busy) {
        _refreshSessionSummary();
        _load();
      }
    });
    _load();
    _refreshSessionSummary();
  }

  Future<void> _load({int? preferSenseId}) async {
    final generation = ++_generation;
    final deps = widget.dependencies;
    _timer?.cancel();
    try {
      final status = widget.todayPlan
          ? await deps.repository.queueStatus(todayPlan: true)
          : await deps.repository.queueStatus(
              wordbookId: widget.wordbookId,
              senseId: widget.senseId,
            );
      final matches = status.items;
      final next = matches.isEmpty
          ? null
          : preferSenseId == null
          ? matches.first
          : matches.firstWhere(
              (item) => item.sense.id == preferSenseId,
              orElse: () => matches.first,
            );
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_item?.sense.id != next?.sense.id ||
            _item?.memory != next?.memory) {
          _revealed = false;
          _eventId = newReviewEventId();
          _shownAt = deps.nowUtc();
        }
        _item = next;
        _status = status;
        _loading = false;
        _loadFailed = false;
        _error = null;
      });
      final now = deps.nowUtc();
      final midnight = deps.repository.calendar.nextMidnightUtc(now);
      final due = status.nextDue;
      final wakeAt = due != null && due.isBefore(midnight) ? due : midnight;
      final delay = wakeAt.difference(now);
      _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (!_busy) _load();
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        _timer?.cancel();
        setState(() {
          _loading = false;
          _loadFailed = true;
          _item = null;
          _status = null;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _rate(fsrs.Rating rating) async {
    if (_busy || !_revealed || _item == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final eventId = _eventId;
      final elapsed = widget.dependencies
          .nowUtc()
          .difference(_shownAt!)
          .inMilliseconds;
      await widget.dependencies.repository.score(
        _item!,
        rating,
        eventId: eventId,
        durationMs: elapsed < 0 ? 0 : elapsed,
      );
      _completedCount++;
      _sessionEventIds.add(eventId);
      _lastUndoEventId = eventId;
      await _refreshSessionSummary();
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _sameSessionEvents(Set<String> ids) =>
      ids.length == _sessionEventIds.length &&
      ids.every(_sessionEventIds.contains);

  Future<void> _refreshSessionSummary() async {
    final ids = Set<String>.of(_sessionEventIds);
    final revision = ++_summaryRevision;
    try {
      final summary = await widget.dependencies.repository.sessionSummary(ids);
      if (!mounted ||
          revision != _summaryRevision ||
          !_sameSessionEvents(ids)) {
        return;
      }
      setState(() {
        _sessionSummary = summary;
        _summaryError = null;
      });
    } catch (error) {
      if (mounted && revision == _summaryRevision && _sameSessionEvents(ids)) {
        setState(() => _summaryError = '$error');
      }
    }
  }

  Future<void> _undo() async {
    final eventId = _lastUndoEventId;
    if (eventId == null || _busy || _loading) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.dependencies.repository.undoLastReview(
        eventId,
      );
      _sessionEventIds.remove(eventId);
      _lastUndoEventId = null;
      _completedCount = math.max(0, _completedCount - 1);
      await _refreshSessionSummary();
      _timer?.cancel();
      await _load(preferSenseId: result.wordSenseId);
      if (mounted && _item?.sense.id != result.wordSenseId) {
        final item = await widget.dependencies.repository.itemBySenseId(
          result.wordSenseId,
        );
        if (item != null && mounted) {
          setState(() {
            _item = item;
            _revealed = false;
            _eventId = newReviewEventId();
            _shownAt = widget.dependencies.nowUtc();
            _loading = false;
            _loadFailed = false;
          });
        }
      }
    } on UndoUnavailable catch (error) {
      if (mounted) {
        setState(() {
          _lastUndoEventId = null;
          _error = '$error';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '撤销失败，记忆状态未变：$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSummary() async {
    await _refreshSessionSummary();
    if (!mounted) return;
    final endRound = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('本轮学习小结'),
          content: SingleChildScrollView(
            child: SizedBox(
              width: math.min(520, MediaQuery.sizeOf(context).width - 96),
              child: _summaryContent(
                context,
                onRetry: () async {
                  await _refreshSessionSummary();
                  if (context.mounted) setDialogState(() {});
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续学习'),
            ),
            if (_item != null)
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('结束本轮并返回'),
              ),
          ],
        ),
      ),
    );
    if (endRound == true && mounted) Navigator.of(context).pop();
  }

  Widget _summaryContent(BuildContext context, {VoidCallback? onRetry}) {
    final tokens = JournalTokens.of(context);
    final summary = _sessionSummary;
    if (_summaryError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '本轮统计暂时无法读取：$_summaryError',
            style: TextStyle(color: tokens.again.foreground),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onRetry ?? _refreshSessionSummary,
            child: const Text('重试统计'),
          ),
        ],
      );
    }
    if (summary == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final rate = summary.successRate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatStrip(
          items: [
            (label: '本轮评分', value: '${summary.ratingCount} 次'),
            (label: '首次学习', value: '${summary.firstLearnedSenses} 个词义'),
            (label: '复习评分', value: '${summary.reviewCount} 次'),
            (
              label: 'Good+Easy 成功率',
              value: rate == null ? '—' : '${(rate * 100).round()}%',
            ),
          ],
        ),
        if (summary.ratingCount == 0) ...[
          const SizedBox(height: 10),
          Text(
            '本轮还没有评分记录，成功率显示为 —。',
            key: const ValueKey('session-no-ratings'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '同一词义本轮多次学习按评分次数统计；已撤销的评分不计入。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.inkSecondary),
        ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context) => JournalSurface(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '本轮小结'),
        const SizedBox(height: 12),
        _summaryContent(context),
      ],
    ),
  );

  KeyEventResult _handleKey(KeyEvent event, bool clockMovedBack) {
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (event is! KeyDownEvent ||
        _loading ||
        _busy ||
        clockMovedBack ||
        _error != null) {
      return KeyEventResult.ignored;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final commandPressed = keyboard.isControlPressed || keyboard.isMetaPressed;
    final disallowedCommandModifier =
        keyboard.isAltPressed || keyboard.isShiftPressed;
    if (commandPressed &&
        !disallowedCommandModifier &&
        key == LogicalKeyboardKey.keyZ) {
      if (_lastUndoEventId != null) {
        _undo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (_item == null) return KeyEventResult.ignored;
    if (!_revealed) {
      if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
        setState(() => _revealed = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final rating = switch (key) {
      LogicalKeyboardKey.digit1 ||
      LogicalKeyboardKey.numpad1 => fsrs.Rating.again,
      LogicalKeyboardKey.digit2 ||
      LogicalKeyboardKey.numpad2 => fsrs.Rating.hard,
      LogicalKeyboardKey.digit3 ||
      LogicalKeyboardKey.numpad3 => fsrs.Rating.good,
      LogicalKeyboardKey.digit4 ||
      LogicalKeyboardKey.numpad4 => fsrs.Rating.easy,
      _ => null,
    };
    if (rating != null) {
      _rate(rating);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final item = _item;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    final now = widget.dependencies.nowUtc();
    final card = item?.card(widget.dependencies.engine, now);
    final clockMovedBack = card?.lastReview?.isAfter(now) ?? false;
    final predictions = card == null || clockMovedBack
        ? <fsrs.Rating, Duration>{}
        : widget.dependencies.engine.predict(card, now);
    final ratingCount = _sessionSummary?.ratingCount ?? _completedCount;
    final waitingCount = _status?.items.length ?? 0;

    final ratings = [
      (
        rating: fsrs.Rating.again,
        label: 'Again · 忘记',
        tone: tokens.again,
        shortcut: '1',
      ),
      (
        rating: fsrs.Rating.hard,
        label: 'Hard · 困难',
        tone: tokens.hard,
        shortcut: '2',
      ),
      (
        rating: fsrs.Rating.good,
        label: 'Good · 记得',
        tone: tokens.good,
        shortcut: '3',
      ),
      (
        rating: fsrs.Rating.easy,
        label: 'Easy · 轻松',
        tone: tokens.easy,
        shortcut: '4',
      ),
    ];

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) => _handleKey(event, clockMovedBack),
      child: Scaffold(
        appBar: AppBar(
          leading: journalBackButton(context),
          title: const Text('词义回忆'),
          actions: [
            IconButton(
              tooltip: '本轮小结',
              onPressed: _loading || _busy ? null : _openSummary,
              icon: const JournalIcon(Icons.insights_outlined, size: 21),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              width < 600 ? 18 : 36,
              width < 600 ? 12 : 28,
              width < 600 ? 18 : 36,
              32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!_loading && !_loadFailed) ...[
                      Text(
                        '本轮已评 $ratingCount 次 · 当前待学 $waitingCount',
                        style: JournalTokens.tabular(
                          Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.inkSecondary),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(64),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_loadFailed)
                      MessagePanel(
                        icon: Icons.error_outline,
                        title: '暂时无法读取学习队列',
                        message: '$_error',
                        action: OutlinedButton(
                          onPressed: _load,
                          child: const Text('刷新学习队列'),
                        ),
                      )
                    else if (clockMovedBack)
                      MessagePanel(
                        icon: Icons.error_outline,
                        title: '请检查系统时间',
                        message: '当前时间早于上次学习。校准时间后刷新，即可继续复习。',
                        action: OutlinedButton(
                          onPressed: _load,
                          child: const Text('刷新学习队列'),
                        ),
                      )
                    else if (item == null)
                      _buildEmptyQueue(context, now)
                    else ...[
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: JournalSurface(
                          key: ValueKey(
                            '${item.sense.id}-${item.memory?.due ?? 'new'}',
                          ),
                          variant: JournalSurfaceVariant.elevated,
                          padding: EdgeInsets.symmetric(
                            horizontal: width < 600 ? 22 : 34,
                            vertical: width < 600 ? 28 : 36,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: StatusBadge(
                                  label: item.memory == null ? '新词义' : '复习',
                                  tone: item.memory == null
                                      ? StatusBadgeTone.accent
                                      : StatusBadgeTone.review,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Text(
                                item.word.spelling,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.displayMedium
                                    ?.copyWith(
                                      fontSize: wide ? 52 : 42,
                                      height: 1.12,
                                    ),
                              ),
                              if (item.sense.phonetics != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  item.sense.phonetics!,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: tokens.inkMuted),
                                ),
                              ],
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                alignment: Alignment.topCenter,
                                child: !_revealed
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 22),
                                        child: Text(
                                          '先想一想它的意思，再揭晓答案。',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: tokens.inkMuted,
                                              ),
                                        ),
                                      )
                                    : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const SizedBox(height: 26),
                                          Divider(color: tokens.border),
                                          const SizedBox(height: 24),
                                          Text(
                                            item.sense.definition,
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall,
                                          ),
                                          const SizedBox(height: 18),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: tokens.surfaceMuted,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                            child: Text(
                                              item.sense.example.isEmpty
                                                  ? '这份词库没有提供例句。'
                                                  : item.sense.example,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodyLarge
                                                  ?.copyWith(
                                                    color: tokens.inkSecondary,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (!_revealed)
                        Center(
                          child: FilledButton(
                            onPressed: () => setState(() => _revealed = true),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('回忆 · 揭晓释义'),
                                if (wide) ...[
                                  const SizedBox(width: 10),
                                  KeyHintBadge(
                                    'Space',
                                    foreground: tokens.primary,
                                    border: tokens.onPrimary.withValues(
                                      alpha: .3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                      else
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final fourInRow = constraints.maxWidth >= 540;
                            final cellWidth = fourInRow
                                ? (constraints.maxWidth - 30) / 4
                                : (constraints.maxWidth - 10) / 2;
                            return Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: ratings
                                  .map(
                                    (entry) => SizedBox(
                                      width: cellWidth,
                                      child: _RatingButton(
                                        label: entry.label,
                                        interval: intervalLabel(
                                          predictions[entry.rating]!,
                                        ),
                                        tone: entry.tone,
                                        shortcut: wide ? entry.shortcut : null,
                                        highlighted:
                                            entry.rating == fsrs.Rating.good,
                                        onPressed: _busy
                                            ? null
                                            : () => _rate(entry.rating),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                    ],
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 18),
                        child: LinearProgressIndicator(),
                      ),
                    if (_error != null && !_loadFailed) ...[
                      const SizedBox(height: 16),
                      JournalSurface(
                        color: tokens.again.background,
                        borderColor: tokens.again.border,
                        radius: JournalTokens.radiusSm,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _error!,
                              style: TextStyle(color: tokens.again.foreground),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _busy ? null : _load,
                              child: const Text('刷新学习队列'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!_loading && !_loadFailed) ...[
                      if (_lastUndoEventId != null) ...[
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            key: const ValueKey('undo-last-score'),
                            onPressed: _busy ? null : _undo,
                            icon: const JournalIcon(Icons.arrow_back, size: 17),
                            label: const Text('撤销上一评分'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        '键盘：Space / Enter 揭晓 · 1–4 评分 · Ctrl / Cmd + Z 撤销',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: tokens.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyQueue(BuildContext context, DateTime now) {
    final status = _status;
    if (status == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MessagePanel(
            title: '当前没有可学词义',
            message: '到期或跨日后会自动更新。',
            action: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ),
          const SizedBox(height: 14),
          _summaryCard(context),
        ],
      );
    }
    final messages = <String>[];
    if (status.dailyGoal == 0) {
      messages.add('每日新词目标为 0，当前只安排复习。');
    } else if (status.quotaExhausted) {
      messages.add('今天的新词额度已用完（${status.learnedToday} / ${status.dailyGoal}）。');
    }
    if (status.unlearnedCount > 0) {
      messages.add(
        '${status.scopeLabel}仍有 ${status.unlearnedCount} 个未学词义。'
        '${status.dailyGoal == 0 ? '可在设置中调整目标后继续。' : '明天会按每日额度继续。'}',
      );
    } else {
      messages.add('${status.scopeLabel}暂无未学词义。');
    }
    final due = status.nextDue;
    if (due != null) {
      messages.add(
        '下次复习：${localDateTimeLabel(due)}'
        '（${intervalLabel(due.difference(now))}后）。',
      );
    } else {
      messages.add('当前也没有未来的复习安排。');
    }
    final onlyReview = status.dailyGoal == 0;
    final quotaExhausted = status.quotaExhausted && !onlyReview;
    final title = onlyReview
        ? '今天只安排复习'
        : quotaExhausted
        ? '今天的新词额度已用完'
        : '当前没有可学词义';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessagePanel(
          icon: quotaExhausted ? Icons.hourglass_empty : Icons.event_available,
          title: title,
          message: messages.join('\n\n'),
          action: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: _load, child: const Text('刷新学习队列')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _summaryCard(context),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.interval,
    required this.tone,
    required this.highlighted,
    this.shortcut,
    this.onPressed,
  });

  final String label;
  final String interval;
  final RatingTone tone;
  final bool highlighted;
  final String? shortcut;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      backgroundColor: tone.background,
      foregroundColor: tone.foreground,
      side: BorderSide(color: tone.border, width: highlighted ? 1.6 : 1.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    onPressed: onPressed,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tone.foreground, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                interval,
                style: JournalTokens.tabular(
                  Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tone.foreground.withValues(alpha: .88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 6),
              KeyHintBadge(
                shortcut!,
                foreground: tone.foreground,
                border: tone.border,
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
