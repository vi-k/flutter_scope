part of '../scope.dart';

/// The read-only model of an asynchronous scope: its [AsyncScopeState], and a
/// notification whenever that state changes.
///
/// This is the third type argument of `AsyncScopeCore` and what
/// `AsyncScopeElementBase.model` returns, so a scope written on the `Core`
/// layer names it. There is nothing to implement: the scope makes the one
/// instance there is, and the interface exists so that nothing outside can
/// write to it.
///
/// {@category AsyncScope}
abstract interface class AsyncScopeModel
    implements ScopeStateModel<AsyncScopeState> {}

final class _AsyncScopeNotifier extends ScopeStateNotifier<AsyncScopeState>
    implements AsyncScopeModel {
  _AsyncScopeNotifier() : super(AsyncScopeWaiting());

  @override
  _AsyncScopeModelView asUnmodifiable() => _AsyncScopeModelView(this);
}

final class _AsyncScopeModelView extends ScopeStateModelView<AsyncScopeState>
    implements AsyncScopeModel {
  _AsyncScopeModelView(_AsyncScopeNotifier super.notifier);
}
