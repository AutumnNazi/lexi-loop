class LocalCalendar {
  const LocalCalendar({this.fixedOffset});
  // 测试可固定时区；生产环境使用系统本地时区，日界线按日历构造以兼容夏令时。
  final Duration? fixedOffset;

  DateTime local(DateTime utc) =>
      fixedOffset == null ? utc.toLocal() : utc.toUtc().add(fixedOffset!);

  int dayKey(DateTime utc) {
    final date = local(utc);
    return DateTime.utc(
          date.year,
          date.month,
          date.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerDay;
  }

  DateTime midnightUtc(DateTime utc, {int daysAhead = 0}) {
    final date = local(utc);
    if (fixedOffset != null) {
      return DateTime.utc(
        date.year,
        date.month,
        date.day + daysAhead,
      ).subtract(fixedOffset!);
    }
    return DateTime(date.year, date.month, date.day + daysAhead).toUtc();
  }

  DateTime nextMidnightUtc(DateTime utc) => midnightUtc(utc, daysAhead: 1);

  int streak(Iterable<DateTime> reviews, DateTime nowUtc) {
    final today = dayKey(nowUtc);
    final days = reviews.map(dayKey).where((day) => day <= today).toSet();
    var cursor = days.contains(today) ? today : today - 1;
    var count = 0;
    while (days.contains(cursor)) {
      count++;
      cursor--;
    }
    return count;
  }
}
