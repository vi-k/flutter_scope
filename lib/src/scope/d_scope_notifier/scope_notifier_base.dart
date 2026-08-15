part of '../scope.dart';

/// {@category ScopeNotifier}
abstract base class ScopeNotifierBase<W extends ScopeNotifierBase<W, M>,
        M extends Listenable>
    extends ScopeNotifierCore<W, _ScopeNotifierElement<W, M>, M>
    with _ScopeModelBaseMixin<M> {
  @override
  final M? value;

  @override
  final bool hasValue;

  @override
  final M Function(BuildContext context)? create;

  @override
  final void Function(M model)? dispose;

  /// Creates a scope that owns the model [create] returns.
  const ScopeNotifierBase({
    super.key,
    super.tag,
    required this.create,
    required this.dispose,
    super.child, // Not used by default. You can use it at your own discretion.
  })  : hasValue = false,
        value = null;

  /// Creates a scope over a model somebody else owns.
  const ScopeNotifierBase.value({
    super.key,
    super.tag,
    required this.value,
  })  : hasValue = true,
        create = null,
        dispose = null;

  @override
  // ignore: library_private_types_in_public_api
  _ScopeNotifierElement<W, M> createScopeElement() =>
      _ScopeNotifierElement(this as W);

  @override
  Widget build(BuildContext context);

  /// The context of the nearest scope [W], or `null` if there is none.
  static ScopeModelContext<W, M>?
      maybeOf<W extends ScopeNotifierBase<W, M>, M extends Listenable>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<W, ScopeModelContext<W, M>>(
            context,
            listen: listen,
          );

  /// The context of the nearest scope [W].
  ///
  /// Throws when there is no such scope above [context].
  static ScopeModelContext<W, M>
      of<W extends ScopeNotifierBase<W, M>, M extends Listenable>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<W, ScopeModelContext<W, M>>(
            context,
            listen: listen,
          );

  /// Subscribes to one value of the scope and returns it.
  static V select<W extends ScopeNotifierBase<W, M>, M extends Listenable,
          V extends Object?>(
    BuildContext context,
    V Function(ScopeModelContext<W, M> context) selector,
  ) =>
      ScopeContext.select<W, ScopeModelContext<W, M>, V>(
        context,
        selector,
      );
}

final class _ScopeNotifierElement<W extends ScopeNotifierBase<W, M>,
        M extends Listenable>
    extends ScopeNotifierElementBase<W, _ScopeNotifierElement<W, M>, M>
    with _ScopeModelElementMixin<W, M> {
  _ScopeNotifierElement(super.widget);

  @override
  void update(W newWidget) {
    // Identity, not equality: a listener belongs to the object that holds the
    // list it is in. Two models that compare equal are still two lists, and
    // reading `==` as "the same subscription" left the listener on the model
    // the scope had just let go of, with every notification of the new one
    // lost.
    if (!identical(widget.value, newWidget.value)) {
      widget.value?.removeListener(notifyDependents);
      newWidget.value?.addListener(notifyDependents);
    }
    super.update(newWidget);
  }
}
