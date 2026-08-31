import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo_demo/home/demos/full_scope/scope_example1.dart';
import 'package:scopo_demo/utils/console/console.dart';

/// The `Scope` demo is the sample of the family the topics teach from, and the
/// rule they teach is "acquire, register, then carry on": the disposer goes on
/// the handle before the initializer awaits anything, so a step cancelled
/// half-way still gives back what it took. Registered after the `await` — as
/// this demo had it — a scope that leaves during its initialization creates the
/// controller and leaves nobody able to release it.
///
/// What is checked here is the property, not the shape: the release of the
/// controller is a line in the console, and the demo has to print it whichever
/// way the scope left. The leak tracker cannot answer for it — the controller
/// stays reachable through the dependency container to the end of the test, so
/// an undisposed one is not a leak it reports.
void main() {
  testWidgets('the controller of a scope abandoned mid-init is released',
      (tester) async {
    console.clearAll();

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ScopeExample1())),
    );

    // `CounterController.init()` takes a second; leave in the middle of it.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    // The teardown is a chain of real futures; `pump` alone advances only the
    // fake clock, so each round escapes the fake-async zone first.
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    final lines = console.lines(ScopeExample1);

    expect(
      lines.where((line) => line.contains('initialized')),
      isEmpty,
      reason: 'the scope left before the initialization could finish',
    );
    expect(
      lines.where((line) => line.contains('controller disposed')),
      isNotEmpty,
      reason: 'and the controller that step took is given back all the same',
    );
  });
}
