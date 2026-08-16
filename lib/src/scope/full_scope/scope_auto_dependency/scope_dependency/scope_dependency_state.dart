part of '../../../scope.dart';

/// {@category Scope}
sealed class ScopeDependencyState {
  const ScopeDependencyState();

  /// The state as it appears in a tree dump.
  String get description;

  @override
  String toString() => description;

  /// Thrown when errors are asked of a state that holds none.
  static Never throwNoErrors() => throw StateError('No errors');
}

/// {@category Scope}
sealed class ScopeDependencySuccessStates extends ScopeDependencyState {
  const ScopeDependencySuccessStates();
}

sealed class _ScopeDependencyWithErrors extends ScopeDependencyState {
  final List<AsyncError> _errors;

  _ScopeDependencyWithErrors(Object error, StackTrace stackTrace)
      : _errors = _singleList(AsyncError(error, stackTrace));

  const _ScopeDependencyWithErrors._(this._errors);

  Object get error =>
      _errors.firstOrNull?.error ?? ScopeDependencyState.throwNoErrors();

  StackTrace get stackTrace =>
      _errors.firstOrNull?.stackTrace ?? ScopeDependencyState.throwNoErrors();

  int get count => _errors.length;

  bool get hasErrors => _errors.isNotEmpty;

  /// Returns a copy of the error list.
  List<AsyncError> errors() => List.of(_errors);

  _ScopeDependencyWithErrors addError(Object error, StackTrace stackTrace);

  @override
  String toString({bool? showCount, bool showErrors = true}) {
    final count = this.count;
    showCount ??= count > 1;
    return '$description'
        '${showCount ? ' ($count ${count == 1 ? 'error' : 'errors'})' : ''}'
        '${showErrors && hasErrors ? ': ${!showCount && count == 1 //
            ? error : errors()}' : ''}';
  }
}

/// {@category Scope}
sealed class ScopeDependencyFailedStates extends _ScopeDependencyWithErrors {
  ScopeDependencyFailedStates(super.error, super.stackTrace);

  const ScopeDependencyFailedStates._(super._errors) : super._();
}

/// {@category Scope}
sealed class ScopeDependencyCancelledStates extends _ScopeDependencyWithErrors {
  ScopeDependencyCancelledStates([Object? error, StackTrace? stackTrace])
      : super._(
          error == null
              ? _emptyList<AsyncError>()
              : _singleList(AsyncError(error, stackTrace)),
        );

  const ScopeDependencyCancelledStates._(super._errors) : super._();
}

/// {@category Scope}
final class ScopeDependencyInitial extends ScopeDependencySuccessStates {
  /// Creates the state of a dependency not started yet.
  const ScopeDependencyInitial();

  @override
  String get description => 'not initialized';
}

/// {@category Scope}
final class ScopeDependencyFailed extends ScopeDependencyFailedStates {
  /// Creates the state of a dependency whose initialization failed.
  ScopeDependencyFailed(super.error, super.stackTrace);

  ScopeDependencyFailed._(super._errors) : super._();

  @override
  String get description => 'failed';

  @override
  ScopeDependencyFailed addError(Object error, StackTrace stackTrace) =>
      ScopeDependencyFailed._(
        _errors.withAdded(AsyncError(error, stackTrace)),
      );
}

/// {@category Scope}
final class ScopeDependencyCancelled extends ScopeDependencyCancelledStates {
  /// Creates the state of a dependency whose initialization was cancelled.
  ScopeDependencyCancelled([super.error, super.stackTrace]);

  const ScopeDependencyCancelled._(super._errors) : super._();

  @override
  String get description => count == 0
      ? 'cancelled'
      : 'cancelled with ${count == 1 ? 'error' : 'errors'}';

  @override
  ScopeDependencyCancelled addError(Object error, StackTrace stackTrace) =>
      ScopeDependencyCancelled._(
        _errors.withAdded(AsyncError(error, stackTrace)),
      );
}

/// {@category Scope}
final class ScopeDependencyInitialized extends ScopeDependencySuccessStates {
  /// Creates the state of an initialized dependency.
  const ScopeDependencyInitialized();

  @override
  String get description => 'initialized';
}

/// {@category Scope}
final class ScopeDependencyDisposalFailed extends ScopeDependencyFailedStates {
  /// Creates the state of a dependency whose disposal failed.
  ScopeDependencyDisposalFailed(super.error, super.stackTrace);

  ScopeDependencyDisposalFailed._(super._errors) : super._();

  @override
  String get description => 'disposal failed';

  @override
  ScopeDependencyDisposalFailed addError(Object error, StackTrace stackTrace) =>
      ScopeDependencyDisposalFailed._(
        _errors.withAdded(AsyncError(error, stackTrace)),
      );
}

/// {@category Scope}
final class ScopeDependencyDisposalCancelled
    extends ScopeDependencyCancelledStates {
  /// Creates the state of a dependency whose disposal was cancelled.
  ScopeDependencyDisposalCancelled([super.error, super.stackTrace]);

  const ScopeDependencyDisposalCancelled._(super._errors) : super._();

  @override
  String get description => count == 0
      ? 'disposal cancelled'
      : 'disposal cancelled with ${count == 1 ? 'error' : 'errors'}';

  @override
  ScopeDependencyDisposalCancelled addError(
    Object error,
    StackTrace stackTrace,
  ) =>
      ScopeDependencyDisposalCancelled._(
        _errors.withAdded(AsyncError(error, stackTrace)),
      );
}

/// {@category Scope}
final class ScopeDependencyDisposed extends ScopeDependencySuccessStates {
  /// Creates the state of a disposed dependency.
  const ScopeDependencyDisposed();

  @override
  String get description => 'disposed';
}

/// {@category Scope}
final class ScopeDependencyNoDisposalRequired extends ScopeDependencyDisposed {
  /// Creates the state of a dependency that had nothing to release.
  const ScopeDependencyNoDisposalRequired();

  @override
  String get description => 'no disposal required';
}

/// Returns an empty immutable list.
///
/// This function exists to:
/// 1) prevent the list from being modified,
/// 2) make such lists internally identical.
List<T> _emptyList<T>() =>
    List<T>.generate(0, (i) => throw UnimplementedError(), growable: false);

/// Returns an immutable list of a single element.
///
/// This function exists to:
/// 1) prevent the list from being modified,
/// 2) make such lists internally identical.
List<T> _singleList<T>(T element) =>
    List<T>.generate(1, (i) => element, growable: false);

/// Returns an immutable list holding this list and one more element.
///
/// This function exists to:
/// 1) prevent the list from being modified,
/// 2) make such lists internally identical.
extension<T> on List<T> {
  List<T> withAdded(T element) => List.generate(
        length + 1,
        (i) => i < length ? this[i] : element,
        growable: false,
      );
}
