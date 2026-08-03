import 'package:flutter_test/flutter_test.dart';
import 'package:smiley/core/realtime_client.dart';

void main() {
  group('EventDeduper', () {
    test('passes distinct event ids and blocks repeats', () {
      final deduper = EventDeduper();
      expect(deduper.isDuplicate('a'), isFalse);
      expect(deduper.isDuplicate('b'), isFalse);
      expect(deduper.isDuplicate('a'), isTrue);
      expect(deduper.isDuplicate('b'), isTrue);
    });

    test('never dedupes null or empty ids', () {
      final deduper = EventDeduper();
      expect(deduper.isDuplicate(null), isFalse);
      expect(deduper.isDuplicate(null), isFalse);
      expect(deduper.isDuplicate(''), isFalse);
      expect(deduper.isDuplicate(''), isFalse);
    });

    test('evicts oldest ids beyond capacity', () {
      final deduper = EventDeduper(capacity: 2);
      expect(deduper.isDuplicate('1'), isFalse);
      expect(deduper.isDuplicate('2'), isFalse);
      // '2' is still tracked
      expect(deduper.isDuplicate('2'), isTrue);
      // '3' pushes the set past capacity and evicts the oldest ('1')
      expect(deduper.isDuplicate('3'), isFalse);
      // '1' was evicted, so it is treated as new again
      expect(deduper.isDuplicate('1'), isFalse);
    });
  });
}
