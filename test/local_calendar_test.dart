import 'package:flutter_test/flutter_test.dart';
import 'package:lexi_loop/core/local_calendar.dart';

void main() {
  test('北京时间午夜与 UTC 日期不同，下一日边界仍正确', () {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: 8));
    final before = DateTime.utc(2026, 11, 27, 15, 59, 59);
    final after = before.add(const Duration(seconds: 2));
    expect(calendar.nextMidnightUtc(before), DateTime.utc(2026, 11, 27, 16));
    expect(calendar.dayKey(after) - calendar.dayKey(before), 1);
    expect(calendar.nextMidnightUtc(after), DateTime.utc(2026, 11, 28, 16));
    expect(calendar.streak([before, before, after], after), 2);
  });
  test('昨天学过但今天还没学，连续天数仍然保留', () {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: -5));
    final now = DateTime.utc(2026, 11, 27, 12);
    expect(
      calendar.streak([
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 2)),
      ], now),
      2,
    );
    expect(calendar.streak([now.subtract(const Duration(days: 2))], now), 0);
  });
}
