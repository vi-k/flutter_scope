part of '../scope.dart';

/// {@category AsyncScope}
sealed class AsyncScopeState {
  AsyncScopeState();
}

/// {@category AsyncScope}
final class AsyncScopeWaiting extends AsyncScopeState {
  /// Creates the waiting state.
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
  /// Whatever the initialization reported — a caption, a fraction, a step.
  final Object? progress;

  /// Reports that the initialization has advanced.
  AsyncScopeProgress([this.progress]);

  @override
  String toString() =>
      '$AsyncScopeProgress${progress == null ? '' : '($progress)'}';
}

/// {@category AsyncScope}
final class AsyncScopeReady extends AsyncScopeInitState {
  /// Reports that the initialization is over.
  AsyncScopeReady();

  @override
  String toString() => '$AsyncScopeReady';
}

/// {@category AsyncScope}
final class AsyncScopeError extends AsyncScopeState {
  /// What the initialization failed with.
  final Object error;

  /// The stack trace of [error].
  final StackTrace stackTrace;

  /// The last progress reported before the failure.
  final Object? progress;

  /// Creates the failed state.
  AsyncScopeError(this.error, this.stackTrace, {this.progress});

  @override
  String toString() => '$AsyncScopeError($error, $stackTrace'
      '${progress == null ? '' : ', progress: $progress'})';
}
