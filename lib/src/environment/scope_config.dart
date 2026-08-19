// [ScopeConfig] is a namespace for the package-wide switches and has no
// instance members by design. The suppression is file-wide because analyzers
// disagree on where a documented declaration starts — some anchor this
// diagnostic at the dartdoc comment, some at the class name — and a
// single-line `ignore` then lands on the wrong side of it.
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:flutter/foundation.dart';
import 'package:logger_builder/logger_builder.dart';

part 'scope_logger.dart';

/// {@category debug}
abstract final class ScopeConfig {
  /// The logger of the package.
  ///
  /// Off by default. See the `debug` topic for levels, publishers and
  /// transformers.
  ///
  /// It comes with a handler for failures of the logging path itself; what
  /// that handler is for, and how to replace or remove it, is written on
  /// [_reportLoggerFailure].
  static final logger = ScopeLogger('scopo')
    ..level = ScopeLogLevel.off
    ..onError = _reportLoggerFailure;

  /// Reports a failure of the logging path instead of letting it out.
  ///
  /// The publisher and the transformer are consumer code, and a throwing one
  /// used to come back out of the logging call. Inside this package that call
  /// sits in a build, in an initialization or in a teardown, so a logger that
  /// failed took the scope with it: a scope that never built its ready branch,
  /// or a teardown that stopped halfway with a `scopeKey` still held. A log
  /// line is the one thing in a package that must not be able to do that.
  ///
  /// The failure is reported the way every other failure of consumer code
  /// here is — through [FlutterError.reportError], a red screen in debug and
  /// `FlutterError.onError` in release. Nothing is swallowed, and nothing that
  /// was logging is interrupted.
  ///
  /// Assigning a handler of your own replaces this one, and
  /// `ScopeConfig.logger.onError = null` brings back what a throwing publisher
  /// did before: come out of the logging call. [reset] leaves it alone, as it
  /// leaves the rest of the logger alone.
  static void _reportLoggerFailure(Object error, StackTrace stackTrace) =>
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'scopo',
          context: ErrorDescription('while publishing a log line'),
        ),
      );

  /// Whether a `pauseAfterInitialization` is honoured at all.
  ///
  /// On by default. Set it to `false` to turn every such pause off at once —
  /// in a test suite, say, where a scope that holds its ready branch back only
  /// makes the run longer.
  static bool pauseAfterInitializationEnabled =
      _pauseAfterInitializationEnabled;

  /// Timeout for waiting for a `scopeKey` to be released.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultScopeKeyTimeout = _timeout;

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
  static Duration? defaultDisposeScopeTimeout = _timeout;

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
    defaultScopeKeyTimeout = _timeout;
    defaultWaitForChildrenTimeout = _timeout;
    defaultDisposeScopeTimeout = _timeout;
    defaultInitCancellationTimeout = _timeout;
  }
}
