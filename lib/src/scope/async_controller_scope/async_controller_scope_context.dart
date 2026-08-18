part of '../scope.dart';

/// What a descendant reads off a scope owning a controller.
///
/// The same three answers [AsyncDataScopeContext] gives about a value, said in
/// the word this family uses: the value here is a [ScopeController], and
/// calling it `data` made every read of it read as though it were a payload.
/// The inherited `data`, `dataOrNull` and `hasData` still answer — this is the
/// same object under a name that fits.
///
/// {@category AsyncControllerScope}
abstract interface class AsyncControllerScopeContext<
    W extends ScopeInheritedWidget,
    C extends ScopeController> implements AsyncDataScopeContext<W, C> {
  /// The controller this scope owns.
  ///
  /// Throws a [StateError] until there is one; [controllerOrNull] is the safe
  /// read, and [hasController] is the question on its own. The window in which
  /// the controller exists and the scope is not yet `isInitialized` is the one
  /// [AsyncDataScopeContext.data] describes.
  C get controller;

  /// The controller, or `null` while there is none.
  C? get controllerOrNull;

  /// Whether the controller has been created.
  bool get hasController;
}
