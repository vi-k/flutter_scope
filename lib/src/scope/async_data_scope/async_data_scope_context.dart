part of '../scope.dart';

/// {@category AsyncDataScope}
abstract interface class AsyncDataScopeContext<W extends ScopeInheritedWidget,
    T extends Object?> implements AsyncScopeContext<W> {
  /// The value the initialization produced.
  ///
  /// Throws a [StateError] before the scope is ready; [dataOrNull] is the
  /// safe read.
  T get data;

  /// The value, or `null` while the scope is not ready.
  T? get dataOrNull;
}
