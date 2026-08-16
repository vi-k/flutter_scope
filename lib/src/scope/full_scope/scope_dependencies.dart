part of '../scope.dart';

/// A container for dependencies (e.g., repositories, services).
///
/// {@category Scope}
// ignore: one_member_abstracts
abstract interface class ScopeDependencies {
  /// Lets go of whatever cannot wait for [dispose].
  ///
  /// Cancel subscriptions and detach listeners here. It runs exactly once,
  /// always before [dispose], whether the scope was removed from the tree or
  /// closed with `close()`.
  void onUnmount();

  /// Disposes of the dependencies, releasing any resources they hold.
  FutureOr<void> dispose();
}

/// Extension on [ScopeDependencies] to provide streaming capabilities.
///
/// {@category Scope}
extension ScopeDependenciesExtension<T extends ScopeDependencies> on T {
  /// Converts the dependencies into a stream emitting a [ScopeReady] state.
  ///
  /// The container type is the type of the receiver, so it is inferred rather
  /// than written out. Named separately, as it used to be, it was a downcast
  /// the compiler could not check: `AppDependencies().asStream<String,
  /// OldDependencies>()` compiled and failed on the first frame, and the
  /// shortest way to build an initialization stream was the one that moved a
  /// type error from compilation to run time.
  Stream<ScopeInitState<P, T>> asStream<P extends Object>() =>
      Stream.value(ScopeReady(this));
}
