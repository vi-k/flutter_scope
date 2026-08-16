part of '../scope.dart';

/// {@category AsyncDataScope}
abstract interface class AsyncDataScopeContext<W extends ScopeInheritedWidget,
    T extends Object?> implements AsyncScopeContext<W> {
  /// The value the initialization produced.
  ///
  /// Throws a [StateError] until there is one; [dataOrNull] is the safe read,
  /// and [hasData] is the question on its own.
  ///
  /// "Until there is one" is a little earlier than [isInitialized]: the value
  /// is caught as it goes past, while the state of the scope is applied at the
  /// end of the frame — or after the whole of `pauseAfterInitialization`,
  /// which is deliberately longer. In that window the scope still builds its
  /// initializing branch and this getter already answers.
  T get data;

  /// The value, or `null` while there is none.
  ///
  /// For a nullable [T] the two are the same answer, and [hasData] is what
  /// tells them apart.
  T? get dataOrNull;

  /// Whether the initialization has produced its value.
  ///
  /// The question [dataOrNull] cannot answer for a nullable [T], and the one
  /// [data] answers by throwing. Not the same as [isInitialized]: this is true
  /// from the moment the value arrives, the other from the moment the scope
  /// shows its ready branch.
  bool get hasData;
}
