import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/src/utils/listenable/notifier.dart';

void main() {
  late TestNotifier notifier;

  void f1() {}
  void f2() {}
  void f3() {}

  setUp(() {
    notifier = TestNotifier();
  });

  group('add listeners', () {
    test('once', () {
      notifier.addListener(f1);
      expect(notifier.listeners, [f1]);
      expect(notifier.count, 1);
    });

    test('twice', () {
      notifier
        ..addListener(f1)
        ..addListener(f2);
      expect(notifier.listeners, [f1, f2]);
      expect(notifier.count, 2);
    });

    test('three times', () {
      notifier
        ..addListener(f1)
        ..addListener(f2)
        ..addListener(f3);
      expect(notifier.listeners, [f1, f2, f3, null]);
      expect(notifier.count, 3);
    });

    test('four times', () {
      notifier
        ..addListener(f1)
        ..addListener(f2)
        ..addListener(f3)
        ..addListener(f1);
      expect(notifier.listeners, [f1, f2, f3, f1]);
      expect(notifier.count, 4);
    });

    test('five times', () {
      notifier
        ..addListener(f1)
        ..addListener(f2)
        ..addListener(f3)
        ..addListener(f1)
        ..addListener(f2);
      expect(notifier.listeners, [f1, f2, f3, f1, f2, null, null, null]);
      expect(notifier.count, 5);
    });
  });

  group('remove listeners', () {
    setUp(() {
      notifier
        ..addListener(f1)
        ..addListener(f2)
        ..addListener(f3)
        ..addListener(f1)
        ..addListener(f2)
        ..addListener(f3);

      expect(notifier.listeners, [f1, f2, f3, f1, f2, f3, null, null]);
      expect(notifier.count, 6);
    });

    test('f1 once', () {
      notifier.removeListener(f1);
      expect(notifier.listeners, [f2, f3, f1, f2, f3, null, null, null]);
      expect(notifier.count, 5);
    });

    test('f1 twice', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f1);
      expect(notifier.listeners, [f2, f3, f2, f3]);
      expect(notifier.count, 4);
    });

    test('f1 three times', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f1)
        ..removeListener(f1);
      expect(notifier.listeners, [f2, f3, f2, f3]);
      expect(notifier.count, 4);
    });

    test('f2 once', () {
      notifier.removeListener(f2);
      expect(notifier.listeners, [f1, f3, f1, f2, f3, null, null, null]);
      expect(notifier.count, 5);
    });

    test('f2 twice', () {
      notifier
        ..removeListener(f2)
        ..removeListener(f2);
      expect(notifier.listeners, [f1, f3, f1, f3]);
      expect(notifier.count, 4);
    });

    test('f3 once', () {
      notifier.removeListener(f3);
      expect(notifier.listeners, [f1, f2, f1, f2, f3, null, null, null]);
      expect(notifier.count, 5);
    });

    test('f3 twice', () {
      notifier
        ..removeListener(f3)
        ..removeListener(f3);
      expect(notifier.listeners, [f1, f2, f1, f2]);
      expect(notifier.count, 4);
    });

    test('f1 and f2 once', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f2);
      expect(notifier.listeners, [f3, f1, f2, f3]);
      expect(notifier.count, 4);
    });

    test('f1 twice and f2 once', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f1)
        ..removeListener(f2);
      expect(notifier.listeners, [f3, f2, f3, null]);
      expect(notifier.count, 3);
    });

    test('f1 and f2 twice', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f2)
        ..removeListener(f1)
        ..removeListener(f2);
      expect(notifier.listeners, [f3, f3]);
      expect(notifier.count, 2);
    });

    test('f1 and f2 and f3 once', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f2)
        ..removeListener(f3);
      expect(notifier.listeners, [f1, f2, f3, null]);
      expect(notifier.count, 3);
    });

    test('f1 twice and f2 and f3 once', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f1)
        ..removeListener(f2)
        ..removeListener(f3);
      expect(notifier.listeners, [f2, f3]);
      expect(notifier.count, 2);
    });

    test('f1 and f2 twice and f3 once', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f1)
        ..removeListener(f2)
        ..removeListener(f2)
        ..removeListener(f3);
      expect(notifier.listeners, [f3]);
      expect(notifier.count, 1);
    });

    test('f1 and add', () {
      notifier
        ..removeListener(f1)
        ..addListener(f1);
      expect(notifier.listeners, [f2, f3, f1, f2, f3, f1, null, null]);
      expect(notifier.count, 6);
    });

    test('f1 twice and add twice', () {
      notifier
        ..removeListener(f1)
        ..removeListener(f1)
        ..addListener(f1)
        ..addListener(f1);
      expect(notifier.listeners, [f2, f3, f2, f3, f1, f1, null, null]);
      expect(notifier.count, 6);
    });
  });
}
