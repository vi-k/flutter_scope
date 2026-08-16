part of '../scope.dart';

/// @nodoc
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
