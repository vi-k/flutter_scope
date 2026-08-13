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

  /// The name this dependency was declared with.
  String get name;

  /// How many dependencies this subtree holds, itself included.
  int get count;

  /// Where in its lifecycle this dependency is.
  ScopeDependencyState get state;

  /// Whether anything has to be released for this dependency.
  bool get disposalRequired;

  /// Initializes this dependency, yielding the path of each step.
  Stream<String> init();

  /// Runs [init] and keeps [state] in step with how it went.
  Stream<String> runInit();

  /// Called synchronously when the scope leaves the tree.
  void unmount();

  /// Releases this dependency, yielding the path of each step.
  Stream<String> dispose();

  /// Runs [dispose] and keeps [state] in step with how it went.
  Stream<String> runDispose();

  /// The name as it appears in a tree dump — `"dep"` or `[group]`.
  String get wrappedName;

  /// The state as a line of a tree dump.
  String stateToString();
}

/// {@category Scope}
extension ScopeDependencyExtension on ScopeDependency {
  /// Whether this is a group rather than a single dependency.
  bool get isGroup => this is ScopeDependencyGroup;

  /// Whether this dependency has yet to be initialized.
  bool get initializationRequired => state is ScopeDependencyInitial;

  /// Whether the initialization succeeded.
  bool get isInitialized => switch (state) {
        ScopeDependencyInitialized() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyFailedStates() ||
        ScopeDependencyCancelledStates() =>
          false,
      };

  /// Whether the initialization or the disposal was cancelled.
  bool get isCancelled => switch (state) {
        ScopeDependencyCancelledStates() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyFailedStates() =>
          false,
      };

  /// Whether the initialization or the disposal failed.
  bool get isFailed => switch (state) {
        ScopeDependencyFailedStates() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyCancelledStates() =>
          false,
      };

  /// Whether the disposal is over, including when there was nothing to do.
  bool get isDisposed => switch (state) {
        ScopeDependencyDisposed() => true,
        ScopeDependencySuccessStates() ||
        ScopeDependencyFailedStates() ||
        ScopeDependencyCancelledStates() =>
          false,
      };
}
