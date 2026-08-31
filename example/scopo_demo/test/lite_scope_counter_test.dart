import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo_demo/home/demos/lite_scope/lite_scope_example1.dart';
import 'package:scopo_demo/utils/console/console.dart';

/// The state of the `LiteScope` demo builds the controller, so the state is
/// what gives it back. It used to build one and release nothing: the
/// asynchronous half of the teardown logged its two lines and let the notifier
/// go, on every close rather than on an unlucky one.
///
/// Read from the console, as the demo's own claims are: the controller stays
/// reachable through the state to the end of the test, so an undisposed one is
/// not a leak the tracker reports.
void main() {
  testWidgets('the state gives back the controller it built', (tester) async {
    console.clearAll();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LiteScopeExample1())),
    );

    // Long enough for `CounterController.init()` and the state behind it.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      console.lines(LiteScopeExample1).where(
            (line) => line.contains('state initialized'),
          ),
      isNotEmpty,
      reason: 'the scope got all the way up, so what follows is the ordinary '
          'way down and not a cancellation',
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    for (var i = 0; i < 60; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    final lines = console.lines(LiteScopeExample1);

    expect(
      lines.where((line) => line.contains('controller disposed')),
      isNotEmpty,
      reason: 'the controller the state built is released by the state',
    );
    expect(
      lines.last,
      contains('state disposed'),
      reason: 'and the release happens inside the teardown, not after it',
    );
  });
}
