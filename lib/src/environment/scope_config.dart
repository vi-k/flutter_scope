// [ScopeConfig] is a namespace for the package-wide switches and has no
// instance members by design. The suppression is file-wide because analyzers
// disagree on where a documented declaration starts — some anchor this
// diagnostic at the dartdoc comment, some at the class name — and a
// single-line `ignore` then lands on the wrong side of it.
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:logger_builder/logger_builder.dart';

part 'scope_logger.dart';

/// {@category debug}
abstract final class ScopeConfig {
  /// The logger of the package.
  ///
  /// Off by default. See the `debug` topic for levels, publishers and
  /// transformers.
  static final logger = ScopeLogger('scopo')..level = ScopeLogLevel.off;

  /// Whether a `pauseAfterInitialization` is honoured at all.
  ///
  /// On by default. Set it to `false` to turn every such pause off at once —
  /// in a test suite, say, where a scope that holds its ready branch back only
  /// makes the run longer.
  static bool pauseAfterInitializationEnabled =
      _pauseAfterInitializationEnabled;

  /// Timeout for waiting for `scopeKeys` to be released.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultScopeKeysTimeout = _timeout;

  /// Timeout for waiting for scopes to be disposed of.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultWaitForChildrenTimeout = _timeout;

  /// Timeout for waiting for the asynchronous teardown of one scope.
  ///
  /// A teardown that never completes held the release that follows it, and
  /// with it the `scopeKey` of a scope that had already left the tree. When
  /// this expires, the expiry is reported and the release goes on without
  /// waiting for the teardown to finish.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultDisposeAsyncTimeout = _timeout;

  /// Timeout for waiting for an initialization to be cancelled.
  ///
  /// A generator suspended on a future that never completes cannot be
  /// cancelled, and a teardown that waited for it with no limit never reached
  /// the release that follows. When this expires, the expiry is reported and
  /// the teardown goes on without the initialization.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultInitCancellationTimeout = _timeout;

  /// The default every timeout above starts at.
  static const _timeout = Duration(seconds: 3);

  /// The default of [pauseAfterInitializationEnabled].
  static const _pauseAfterInitializationEnabled = true;

  /// Puts every switch above back to its default.
  ///
  /// These are global and outlive the code that changed them, so a test that
  /// raises a timeout and forgets to put it back hands the next test a
  /// different package. Call this from a `tearDown`, or from a `setUp` — which
  /// also covers a test that failed before its own teardown ran.
  ///
  /// [logger] is left alone: it is an object with publishers and a transformer
  /// of its own rather than a switch, and the level it was given is usually
  /// the whole point of the run it was given for.
  static void reset() {
    pauseAfterInitializationEnabled = _pauseAfterInitializationEnabled;
    defaultScopeKeysTimeout = _timeout;
    defaultWaitForChildrenTimeout = _timeout;
    defaultDisposeAsyncTimeout = _timeout;
    defaultInitCancellationTimeout = _timeout;
  }
}
