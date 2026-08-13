part of '../../../scope.dart';

/// {@category Scope}
abstract interface class ScopeDependency {
  factory ScopeDependency(
    String name,
    FutureOr<void> Function(DepHelper dep) init,
  ) =>
      _ScopeDependencyImpl(name, init);

  factory ScopeDependency.sequential(
    String name,
    Iterable<ScopeDependency> dependencies,
  ) = _ScopeDependencySequential;

  factory ScopeDependency.concurrent(
    String name,
    Iterable<ScopeDependency> dependencies,
  ) = _ScopeDependencyConcurrent;

  String get name;

  int get count;

  ScopeDependencyState get state;

  bool get disposalRequired;

  Stream<String> init();
  Stream<String> runInit();

  void unmount();
  Stream<String> dispose();
  Stream<String> runDispose();

  String get wrappedName;
  String stateToString();
}

/// {@category Scope}
extension ScopeDependencyExtension on ScopeDependency {
  bool get isGroup => this is ScopeDependencyGroup;

  bool get initializationRequired => state is ScopeDependencyInitial;

  bool get isInitialized => switch (state) {
        ScopeDependencyInitialized() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyFailedStates() ||
        ScopeDependencyCancelledStates() =>
          false,
      };

  bool get isCancelled => switch (state) {
        ScopeDependencyCancelledStates() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyFailedStates() =>
          false,
      };

  bool get isFailed => switch (state) {
        ScopeDependencyFailedStates() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyCancelledStates() =>
          false,
      };

  bool get isDisposed => switch (state) {
        ScopeDependencyDisposed() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyFailedStates() ||
        ScopeDependencyCancelledStates() =>
          false,
      };
}
