import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo_demo/home/demos/async_controller/async_controller_example3.dart';
import 'package:scopo_demo/utils/console/console.dart';

/// The third example claims something specific: a scope that walks away in the
/// middle of its initialization still unmounts and disposes of its controller.
/// This checks that the demo really shows it, since the console is all the
/// demo has to say it with.
void main() {
  testWidgets('the abandoned controller is unmounted and disposed of',
      (tester) async {
    console.clearAll();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AsyncControllerExample3())),
    );

    // The teardown is a chain of real futures; `pump` alone advances only the
    // fake clock, so each round escapes the fake-async zone first.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    final lines = console.lines(AsyncControllerExample3);

    expect(
      lines.where((line) => line.contains('initialized')),
      isEmpty,
      reason: 'the scope left before the initialization could finish',
    );
    // Both indices are checked for existence first: `indexWhere` answers -1
    // when it finds nothing, and `-1 < 0` is true -- so the comparison alone
    // passed when `onUnmount` was not logged at all, which is the regression
    // it exists to catch.
    final unmountedAt = lines.indexWhere((line) => line.contains('onUnmount'));
    final disposedAt = lines.indexWhere((line) => line.contains('disposed'));

    expect(unmountedAt, isNonNegative, reason: 'the hook ran at all');
    expect(disposedAt, isNonNegative, reason: 'and so did the release');
    expect(
      unmountedAt,
      lessThan(disposedAt),
      reason: 'the synchronous half of the teardown comes first',
    );
    expect(
      lines.last,
      contains('disposed'),
      reason: 'the controller the scope never received is released anyway',
    );
  });
}
