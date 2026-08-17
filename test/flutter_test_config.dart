import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Turns Flutter's leak tracker on for every test under `test/`.
///
/// The tracker is off by default (`LeakTesting.enabled` starts as `false`),
/// and this file is the only place that can switch it on for the whole suite:
/// `flutter_test_config.dart` wraps `main()` of every test in the directory
/// tree below it.
///
/// It matters here more than in most packages. Deterministic teardown is what
/// scopo promises, so an object the package builds and forgets to dispose is a
/// defect in the package, not in the test. `ChangeNotifier` is instrumented by
/// the framework itself, which puts every notifier scopo owns —
/// `ScopeStateNotifier`, the model of an `AsyncScope`, the selectors — under
/// the tracker without a single line of per-test bookkeeping.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  LeakTesting.enable();
  await testMain();
}
