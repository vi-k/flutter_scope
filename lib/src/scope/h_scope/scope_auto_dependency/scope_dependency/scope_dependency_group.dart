part of '../../../scope.dart';

/// {@category Scope}
abstract base class ScopeDependencyGroup with ScopeDependencyMixin {
  @override
  final String name;

  late final List<ScopeDependency> _dependencies;

  /// The children of this group, in declaration order.
  List<ScopeDependency> get dependencies => List.of(_dependencies);

  late final int _count;

  ScopeDependencyGroup._(this.name, Iterable<ScopeDependency> dependencies) {
    _dependencies = List.of(dependencies, growable: false);
    _count = _dependencies.fold<int>(0, (p, e) => p + e.count);
  }

  @override
  int get count => _count;

  /// A group holds nothing of its own, so what it needs disposing of is
  /// whatever its children still hold — which is why a group whose
  /// initialization failed or was cancelled is disposed of too.
  ///
  /// [ScopeDependencyMixin._isDisposalDone], and not the state alone: a group
  /// that was disposed of because something under it failed keeps saying
  /// [ScopeDependencyFailed], so that the caller can still read what failed,
  /// and that must not be mistaken for a disposal that is still due.
  @override
  bool get disposalRequired =>
      !_isDisposalDone &&
      (state is ScopeDependencyInitialized ||
          state is ScopeDependencyFailed ||
          state is ScopeDependencyCancelled);

  /// Unmounts every child, whatever any one of them makes of it.
  ///
  /// The hooks are user code, and one that fails is no reason to leave the
  /// siblings mounted -- each of them has its own subscription to drop. The
  /// first failure is passed on once the walk is over.
  @override
  void unmount() {
    AsyncError? failure;

    for (final dependency in _dependencies) {
      try {
        dependency.unmount();
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        failure ??= AsyncError(error, stackTrace);
      }
    }

    if (failure case final failure?) {
      Error.throwWithStackTrace(failure.error, failure.stackTrace);
    }
  }

  String _path(String name) => this.name.isEmpty ? name : '${this.name}/$name';

  @override
  String get wrappedName => '[${name.isEmpty ? 'group' : name}]';

  @override
  String stateToString() {
    switch (state) {
      case final ScopeDependencyFailedStates state:
        final failedChildren = state
            .errors()
            .where((e) => e.error is ScopeDependencyException)
            .map(
              (e) => switch (e.error) {
                ScopeDependencyException(:final name) => name,
                _ => null,
              },
            )
            .nonNulls
            .toList();
        final errors = state
            .errors()
            .where((e) => e.error is! ScopeDependencyException)
            .toList();

        return '${state.toString(showCount: false, showErrors: false)}'
            ': ${failedChildren.join(', ')}'
            '${errors.isEmpty //
                ? '' : '. Unresolved errors: $errors'}';

      case final ScopeDependencyState state:
        return '$state';
    }
  }
}

/// {@category Scope}
final class _ScopeDependencySequential extends ScopeDependencyGroup {
  _ScopeDependencySequential(super.name, super._dependencies) : super._();

  @override
  Stream<String> init() async* {
    final dependencies = _dependencies //
        .where((d) => d.initializationRequired);
    for (final dependency in dependencies) {
      yield* dependency.runInit().map(_path);
    }
  }

  @override
  Stream<String> dispose() async* {
    final dependencies = _dependencies //
        .reversed
        .where((dep) => dep.disposalRequired);
    final errors = <AsyncError>[];

    for (final dependency in dependencies) {
      try {
        // Iterated rather than `yield*`-ed: an error inside a delegated stream
        // goes straight to the listener, where no `catch` of ours can see it.
        await for (final path in dependency.runDispose()) {
          yield _path(path);
        }
        // ignore: avoid_catching_errors
      } on Object catch (error, stackTrace) {
        // One dependency that cannot let go is no reason to walk away from the
        // ones below it, which are still holding resources of their own. Each
        // failure is already recorded on the dependency it belongs to; the
        // first one is passed upwards once the walk is over.
        errors.add(AsyncError(error, stackTrace));
      }
    }

    if (errors.firstOrNull case final first?) {
      Error.throwWithStackTrace(first.error, first.stackTrace);
    }
  }
}

/// {@category Scope}
final class _ScopeDependencyConcurrent extends ScopeDependencyGroup {
  _ScopeDependencyConcurrent(super.name, super._dependencies) : super._();

  @override
  Stream<String> init() async* {
    yield* _dependencies //
        .where((dep) => dep.initializationRequired)
        .map((dep) => dep.runInit())
        ._mergeStreams()
        .map(_path);
  }

  @override
  Stream<String> dispose() async* {
    yield* _dependencies.reversed
        .where((dep) => dep.disposalRequired)
        .map((dep) => dep.runDispose())
        ._mergeStreams()
        .map(_path);
  }
}

extension<T> on Iterable<Stream<T>> {
  /// Merges the streams into one, running them in parallel.
  Stream<T> _mergeStreams() {
    final controller = StreamController<T>(sync: true);

    controller.onListen = () {
      if (isEmpty) {
        controller.close(); // ignore: discarded_futures
        return;
      }

      final subscriptions = <StreamSubscription<T>>[];

      for (final stream in this) {
        final subscription =
            stream.listen(controller.add, onError: controller.addError);
        subscriptions.add(subscription);
      }

      // The onDone handlers are attached only after `subscriptions` is fully
      // populated, so that no handler can ever observe a partially filled list
      // and close the controller prematurely.
      for (final subscription in subscriptions) {
        subscription.onDone(() {
          subscriptions.remove(subscription);
          if (subscriptions.isEmpty) {
            controller.close(); // ignore: discarded_futures
          }
        });
      }

      controller
        ..onPause = () {
          for (final subscription in subscriptions) {
            subscription.pause();
          }
        }
        ..onResume = () {
          for (final subscription in subscriptions) {
            subscription.resume();
          }
        }
        ..onCancel = () {
          if (subscriptions.isEmpty) {
            return null;
          }

          return subscriptions
              .map((s) => s.cancel()) // ignore: discarded_futures
              .wait
              .then((_) => null); // ignore: discarded_futures
        };
    };
    return controller.stream;
  }
}
