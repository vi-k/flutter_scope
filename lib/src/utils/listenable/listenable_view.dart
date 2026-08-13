import 'package:flutter/foundation.dart';

/// {@category utils}
base class ListenableView<T extends Listenable> implements Listenable {
  final T _listenable;

  /// Wraps [listenable] so that only listening is reachable through it.
  ListenableView(T listenable) : _listenable = listenable;

  @override
  void addListener(VoidCallback listener) => _listenable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listenable.removeListener(listener);
}
