// [ScopeConfig] is a namespace for the package-wide switches and has no
// instance members by design. The suppression is file-wide on purpose: the
// two toolchains anchor this diagnostic at different lines — Flutter 3.29.2
// at the dartdoc comment, 3.44.9 at the class name — so no placement of a
// single-line `ignore` holds for both.
// ignore_for_file: avoid_classes_with_only_static_members

import 'package:logger_builder/logger_builder.dart';

part 'scope_logger.dart';

/// {@category debug}
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
