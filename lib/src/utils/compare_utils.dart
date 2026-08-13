// [CompareUtils] is a namespace for comparison helpers and has no instance
// members by design. The suppression is file-wide for the same reason as in
// `scope_config.dart`: analyzers disagree on where a documented declaration
// starts, so a single-line `ignore` lands on the wrong side of it.
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:core';
import 'dart:core' as core;

/// {@category utils}
abstract final class CompareUtils {
  /// `a == b`, as a function that can be passed around.
  static bool equals(Object? a, Object? b) => a == b;

  /// `a != b`, as a function that can be passed around.
  static bool notEquals(Object? a, Object? b) => a != b;

  /// Whether [a] and [b] are the same object.
  ///
  /// The comparison to pass as `compare:` for a value that is replaced
  /// rather than mutated.
  static bool identical(Object? a, Object? b) => core.identical(a, b);

  /// Whether [a] and [b] are different objects.
  static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
}
