part of '../../../scope.dart';

/// {@category Scope}
abstract interface class ScopeDependency {
  factory ScopeDependency(
    String name,
    FutureOr<void> Function(ScopeDependencyHandle dep) init,
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

  /// How many steps this subtree reports while it initializes.
  ///
  /// A leaf counts as one. A group counts what is under it and not itself: it
  /// holds nothing and yields no step of its own, so counting it would promise a
  /// step that never arrives. That is what makes this number the denominator a
  /// progress indicator wants.
  int get count;

  /// Where in its lifecycle this dependency is.
  ScopeDependencyState get state;

  /// Whether anything has to be released for this dependency.
  bool get disposalRequired;

  /// Initializes this dependency, yielding the path of each step.
  ///
  /// Keeps [state] in step with how it went. The step itself lives in the
  /// implementation and is not part of this interface: there is one way to
  /// initialize a dependency, and it is this one.
  Stream<String> init();

  /// Lets go of whatever cannot wait for [dispose].
  ///
  /// Runs exactly once, always before [dispose], whether the scope was removed
  /// from the tree or closed with `close()`.
  void onUnmount();

  /// Releases this dependency, yielding the path of each step.
  ///
  /// Keeps [state] in step with how it went, the same way [init] does.
  Stream<String> dispose();

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
        ScopeDependencyAnySuccess() ||
        ScopeDependencyAnyFailed() ||
        ScopeDependencyAnyCancelled() =>
          false,
      };

  /// Whether the initialization or the disposal was cancelled.
  bool get isCancelled => switch (state) {
        ScopeDependencyAnyCancelled() => true,
        ScopeDependencyAnySuccess() || ScopeDependencyAnyFailed() => false,
      };

  /// Whether the initialization or the disposal failed.
  bool get isFailed => switch (state) {
        ScopeDependencyAnyFailed() => true,
        ScopeDependencyAnySuccess() || ScopeDependencyAnyCancelled() => false,
      };

  /// Whether this dependency stands in [ScopeDependencyDisposed].
  ///
  /// Not the same question as "has the teardown run", and it used to be
  /// written as though it were. A dependency that failed keeps
  /// [ScopeDependencyFailed] through its own disposal on purpose — the list of
  /// errors is the only record of what went wrong, and the state is where that
  /// list lives — so a tree released by `autoDisposeOnError` is disposed of,
  /// holds nothing, and answers `false` here.
  ///
  /// What says there is nothing left to release is [disposalRequired]. This
  /// getter names the state.
  bool get isDisposed => switch (state) {
        ScopeDependencyDisposed() => true,
        ScopeDependencyAnySuccess() ||
        ScopeDependencyAnyFailed() ||
        ScopeDependencyAnyCancelled() =>
          false,
      };
}
