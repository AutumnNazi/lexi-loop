import 'dart:async';

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
  });
  final AppDependencies dependencies;
  final int? senseId;
  final String? wordbookId;
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  StudyItem? _item;
  bool _revealed = false, _busy = false, _loading = true;
  String? _error;
  String _eventId = newReviewEventId();
  DateTime? _shownAt;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.dependencies.repository.changes.listen((_) {
      if (!_busy) _load();
    });
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final deps = widget.dependencies;
    _timer?.cancel();
    try {
      final queue = await deps.repository.queue(wordbookId: widget.wordbookId);
      final matches = widget.senseId == null
          ? queue
          : queue.where((item) => item.sense.id == widget.senseId).toList();
      final next = matches.isEmpty ? null : matches.first;
      final due = await deps.repository.nextDue();
      if (!mounted || generation != _generation) return;
      setState(() {
        if (_item?.sense.id != next?.sense.id ||
            _item?.memory != next?.memory) {
          _revealed = false;
          _eventId = newReviewEventId();
          _shownAt = deps.nowUtc();
        }
        _item = next;
        _loading = false;
        _error = null;
      });
      final now = deps.nowUtc();
      final midnight = deps.repository.calendar.nextMidnightUtc(now);
      final wakeAt = due != null && due.isBefore(midnight) ? due : midnight;
      final delay = wakeAt.difference(now);
      _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
        if (!_busy) _load();
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
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
      final elapsed = widget.dependencies
          .nowUtc()
          .difference(_shownAt!)
          .inMilliseconds;
      await widget.dependencies.repository.score(
        _item!,
        rating,
        eventId: _eventId,
        durationMs: elapsed < 0 ? 0 : elapsed,
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final item = _item;
    final labels = {
      fsrs.Rating.again: 'Again · 忘记',
      fsrs.Rating.hard: 'Hard · 困难',
      fsrs.Rating.good: 'Good · 记得',
      fsrs.Rating.easy: 'Easy · 轻松',
    };
    final now = widget.dependencies.nowUtc();
    final card = item?.card(widget.dependencies.engine, now);
    final clockMovedBack = card?.lastReview?.isAfter(now) ?? false;
    final predictions = card == null || clockMovedBack
        ? <fsrs.Rating, Duration>{}
        : widget.dependencies.engine.predict(card, now);
    return Scaffold(
      appBar: AppBar(
        leading: journalBackButton(context),
        title: const Text('词义回忆'),
      ),
      body: SafeArea(
        child: PageFrame(
          title: '给回忆一点时间',
          subtitle: '想一想它的意思，再揭晓答案。',
          children: [
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (clockMovedBack)
              MessagePanel(
                title: '请检查系统时间',
                message: '当前时间早于上次学习。校准时间后刷新，即可继续复习。',
                action: OutlinedButton(
                  onPressed: _load,
                  child: const Text('刷新学习队列'),
                ),
              )
            else if (item == null)
              MessagePanel(
                title: '这一轮，完成了',
                message: '当前没有可学习的词义。到期或跨日后会自动更新。',
                action: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              )
            else ...[
              JournalPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      item.memory == null ? '新词义' : '复习',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      item.word.spelling,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (!_revealed)
                Align(
                  child: FilledButton(
                    onPressed: () => setState(() => _revealed = true),
                    child: const Text('回忆 · 揭晓释义'),
                  ),
                )
              else ...[
                Text(
                  item.sense.definition,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                Text(
                  item.sense.example,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: labels.entries
                        .map(
                          (entry) => SizedBox(
                            width: constraints.maxWidth < 640
                                ? (constraints.maxWidth - 12) / 2
                                : (constraints.maxWidth - 36) / 4,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                backgroundColor: entry.key == fsrs.Rating.good
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : Theme.of(context).colorScheme.surface,
                              ),
                              onPressed: _busy ? null : () => _rate(entry.key),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      entry.value,
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      intervalLabel(predictions[entry.key]!),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('刷新学习队列'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
