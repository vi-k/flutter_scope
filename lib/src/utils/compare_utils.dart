// [CompareUtils] is a namespace for comparison helpers and has no instance
// members by design. The suppression is file-wide for the same reason as in
// `scope_config.dart`: analyzers disagree on where a documented declaration
// starts, so a single-line `ignore` lands on the wrong side of it.
// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:core';
import 'dart:core' as core;

/// {@category utils}
abstract final class CompareUtils {
  static bool equals(Object? a, Object? b) => a == b;

  static bool notEquals(Object? a, Object? b) => a != b;

  static bool identical(Object? a, Object? b) => core.identical(a, b);

  static bool notIdentical(Object? a, Object? b) => !core.identical(a, b);
}
