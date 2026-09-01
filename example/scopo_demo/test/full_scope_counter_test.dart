import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo_demo/home/demos/full_scope/scope_example1.dart';
import 'package:scopo_demo/utils/console/console.dart';

/// The `Scope` demo is the sample of the family the topics teach from, and the
/// rule they teach is "acquire, register, then carry on": the disposer goes on
/// the handle between taking the thing and the next step that can fail. Here
/// the controller is constructed before `init()` is awaited, so the
/// registration belongs between those two — which is not the same as "before
/// any `await`". The canonical example in the `Scope` topic registers *after*
/// one, because nothing exists to register until that `await` comes back.
///
/// **This test does not hold that order, and nothing in this suite can.** A
/// leaf initializer is a plain `async` function and cannot be cancelled: it
/// runs to its end and registers the disposer a moment later, and the walk
/// waiting for the cancellation still finds it there. The order tells only when
/// the initializer throws at that `await` or never comes back from it, and this
/// demo's controller does neither. That branch is held where it can be, in the
/// package's own suite — `test/scope_dependency_partial_test.dart`, the
/// synchronous throw and the asynchronous one.
///
/// What is checked here is the property, and it is worth a test of its own: the
/// release of the controller is a line in the console, and the demo has to
/// print it whichever way the scope left. The leak tracker cannot answer for it
/// — the controller stays reachable through the dependency container to the end
/// of the test, so an undisposed one is not a leak it reports.
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
