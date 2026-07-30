import 'package:logger_builder/logger_builder.dart';

part 'scope_logger.dart';

/// {@category debug}
// ignore: avoid_classes_with_only_static_members
abstract final class ScopeConfig {
  static final logger = ScopeLogger('scopo')..level = ScopeLogLevel.off;

  /// Forces pause to be disabled during testing and debugging.
  static bool pauseAfterInitializationEnabled = true;

  /// Timeout for waiting for `scopeKeys` to be released.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultScopeKeysTimeout = const Duration(seconds: 3);

  /// Timeout for waiting for scopes to be disposed of.
  ///
  /// If `null`, then there is no timeout and the wait is unbounded.
  ///
  /// If zero, then the timeout expires immediately.
  static Duration? defaultWaitForChildrenTimeout = const Duration(seconds: 3);
}
