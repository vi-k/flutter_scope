part of '../scope.dart';

/// {@category AsyncDataScope}
sealed class AsyncDataScopeInitState<P extends Object, T extends Object?> {
  AsyncDataScopeInitState();
}

/// {@category AsyncDataScope}
final class AsyncDataScopeProgress<P extends Object, T extends Object?>
    extends AsyncDataScopeInitState<P, T> {
  /// Whatever the initialization reported — a caption, a fraction, a step.
  final P? progress;

  /// Reports that the initialization has advanced.
  AsyncDataScopeProgress([this.progress]);
}

/// {@category AsyncDataScope}
final class AsyncDataScopeReady<P extends Object, T extends Object?>
    extends AsyncDataScopeInitState<P, T> {
  /// The value the initialization produced.
  final T data;

  /// Reports that the initialization is over, with its [data].
  AsyncDataScopeReady(this.data);
}
