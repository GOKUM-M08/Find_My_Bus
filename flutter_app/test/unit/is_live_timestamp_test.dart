import 'package:flutter_test/flutter_test.dart';
import 'package:bustrack/utils/time_utils.dart';

void main() {
  group('isLiveTimestamp Unit Tests', () {
    test('fresh timestamp (now) returns true', () {
      final nowUtc = DateTime.now().toUtc().toIso8601String();
      expect(isLiveTimestamp(nowUtc), isTrue);

      final fresh = DateTime.now().toUtc().subtract(const Duration(seconds: 5)).toIso8601String();
      expect(isLiveTimestamp(fresh), isTrue);
    });

    test('59 seconds old timestamp returns true', () {
      final fiftyNineSecAgo =
          DateTime.now().toUtc().subtract(const Duration(seconds: 59)).toIso8601String();
      expect(isLiveTimestamp(fiftyNineSecAgo), isTrue);
    });

    test('61 seconds old timestamp returns false', () {
      final sixtyOneSecAgo =
          DateTime.now().toUtc().subtract(const Duration(seconds: 61)).toIso8601String();
      expect(isLiveTimestamp(sixtyOneSecAgo), isFalse);
    });

    test('5 hours in the future returns false', () {
      final fiveHoursFuture =
          DateTime.now().toUtc().add(const Duration(hours: 5)).toIso8601String();
      expect(isLiveTimestamp(fiveHoursFuture), isFalse);
    });

    test('null returns false', () {
      expect(isLiveTimestamp(null), isFalse);
    });

    test('garbage and unparseable values return false', () {
      expect(isLiveTimestamp(''), isFalse);
      expect(isLiveTimestamp('garbage'), isFalse);
      expect(isLiveTimestamp('not-a-timestamp-12345'), isFalse);
      expect(isLiveTimestamp('2026-99-99T99:99:99'), isFalse);
    });

    test('within 30 seconds future clock skew returns true', () {
      final tenSecFuture =
          DateTime.now().toUtc().add(const Duration(seconds: 10)).toIso8601String();
      expect(isLiveTimestamp(tenSecFuture), isTrue);
    });

    test('beyond 30 seconds future clock skew returns false', () {
      final thirtyFiveSecFuture =
          DateTime.now().toUtc().add(const Duration(seconds: 35)).toIso8601String();
      expect(isLiveTimestamp(thirtyFiveSecFuture), isFalse);
    });
  });
}
