part of '../scope.dart';

/// {@category AsyncScope}
sealed class AsyncScopeState {
  AsyncScopeState();
}

/// {@category AsyncScope}
final class AsyncScopeWaiting extends AsyncScopeState {
  AsyncScopeWaiting();

  @override
  String toString() => '$AsyncScopeWaiting';
}

/// {@category AsyncScope}
sealed class AsyncScopeInitState extends AsyncScopeState {
  AsyncScopeInitState();

  @override
  String toString() => '$AsyncScopeInitState';
}

/// {@category AsyncScope}
final class AsyncScopeProgress extends AsyncScopeInitState {
  final Object? progress;

  AsyncScopeProgress([this.progress]);

  @override
  String toString() =>
      '$AsyncScopeProgress${progress == null ? '' : '($progress)'}';
}

/// {@category AsyncScope}
final class AsyncScopeReady extends AsyncScopeInitState {
  AsyncScopeReady();

  @override
  String toString() => '$AsyncScopeReady';
}

/// {@category AsyncScope}
final class AsyncScopeError extends AsyncScopeState {
  final Object error;
  final StackTrace stackTrace;
  final Object? progress;

  AsyncScopeError(this.error, this.stackTrace, {this.progress});

  @override
  String toString() => '$AsyncScopeError($error, $stackTrace'
      '${progress == null ? '' : ', progress: $progress'})';
}
