part of '../scope.dart';

/// {@category ScopeNotifier}
abstract base class ScopeNotifierCore<
    W extends ScopeNotifierCore<W, E, M>,
    E extends ScopeNotifierElementBase<W, E, M>,
    M extends Listenable> extends ScopeModelCore<W, E, M> {
  /// Creates the widget half of a model scope.
  const ScopeNotifierCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// The element of the nearest scope [W], or `null` if there is none.
  static E? maybeOf<W extends ScopeNotifierCore<W, E, M>,
          E extends ScopeNotifierElementBase<W, E, M>, M extends Listenable>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(context, listen: listen);

  /// The element of the nearest scope [W].
  ///
  /// Throws when there is no such scope above [context].
  static E of<W extends ScopeNotifierCore<W, E, M>,
          E extends ScopeNotifierElementBase<W, E, M>, M extends Listenable>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, E>(context, listen: listen);

  /// Subscribes to one value of the scope and returns it.
  static V select<
          W extends ScopeNotifierCore<W, E, M>,
          E extends ScopeNotifierElementBase<W, E, M>,
          M extends Listenable,
          V extends Object?>(
    BuildContext context,
    V Function(E element) selector,
  ) =>
      ScopeContext.select<W, E, V>(context, selector);
}

/// {@category ScopeNotifier}
abstract base class ScopeNotifierElementBase<W extends ScopeModelCore<W, E, M>,
        E extends ScopeNotifierElementBase<W, E, M>, M extends Listenable>
    extends ScopeModelElementBase<W, E, M> implements ScopeModelContext<W, M> {
  /// Creates the element of a notifier scope.
  ///
  /// It subscribes to the model in [init] and unsubscribes in [dispose].
  ScopeNotifierElementBase(super.widget);

  @override
  void init() {
    model.addListener(notifyDependents);
    super.init();
  }

  @override
  void dispose() {
    super.dispose();
    model.removeListener(notifyDependents);
  }
}
