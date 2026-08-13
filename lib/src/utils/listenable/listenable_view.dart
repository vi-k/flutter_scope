import 'package:flutter/foundation.dart';

/// {@category utils}
base class ListenableView<T extends Listenable> implements Listenable {
  final T _listenable;

  ListenableView(T listenable) : _listenable = listenable;

  @override
  void addListener(VoidCallback listener) => _listenable.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _listenable.removeListener(listener);
}
