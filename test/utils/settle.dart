import 'package:flutter_test/flutter_test.dart';

/// Lets the asynchronous work of a scope actually run.
///
/// A disposal is a chain of real futures, and `pump`/`pumpAndSettle` advance
/// only the fake clock: they never let a `Future.delayed` on the real event
/// loop finish. Each round here escapes the fake-async zone with `runAsync`,
/// then draws a frame, until [until] holds or the rounds run out.
///
/// Passing an [until] that never holds is a way to give the work a fair chance
/// and then assert that it did *not* happen.
Future<void> settle(
  WidgetTester tester, {
  required bool Function() until,
  int rounds = 20,
  Duration step = const Duration(milliseconds: 10),
}) async {
  for (var i = 0; i < rounds && !until(); i++) {
    await tester.runAsync(() => Future<void>.delayed(step));
    await tester.pump(step);
  }
}
