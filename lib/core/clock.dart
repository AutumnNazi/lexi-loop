typedef UtcClock = DateTime Function();

DateTime utcMilliseconds(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
  value.millisecondsSinceEpoch,
  isUtc: true,
);

DateTime systemUtcNow() => utcMilliseconds(DateTime.now());
