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
  ///
  /// [value] is narrowed to a non-nullable [M] here, though the field it
  /// initializes is not: the field is nullable because the owning constructor
  /// leaves it empty, and that is no reason to let a scope be built over
  /// nothing. The getter dereferences it on the first read -- for a notifier,
  /// the subscription taken in `init()` -- so a `null` used to compile and
  /// then fail on a bare null check, naming neither the scope nor the
  /// parameter.
  const ScopeNotifierBase.value({
    super.key,
    super.tag,
    required M this.value,
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
    // The old model is read before `super.update`, and the subscription is
    // moved after it: the constructor mode is checked there, and a rebuild
    // that has no honest answer must not have moved a listener first.
    final oldValue = widget.value;

    super.update(newWidget);

    // Nothing to move where nothing was ever added. `init()` sets the flag
    // after it subscribes, so a value that refused the listener -- one already
    // disposed of, or any `Listenable` of the caller's own that says no --
    // leaves it down, and that element is an `ErrorWidget` from then on and
    // for good. Moved on regardless, as this used to do, the subscription
    // landed on the new value while the teardown went on asking the flag: the
    // listener stayed behind on a live notifier with nothing left to remove
    // it, and its next notification reached a defunct element.
    if (!_didListen) {
      return;
    }

    // Identity, not equality: a listener belongs to the object that holds the
    // list it is in. Two models that compare equal are still two lists, and
    // reading `==` as "the same subscription" left the listener on the model
    // the scope had just let go of, with every notification of the new one
    // lost.
    if (!identical(oldValue, newWidget.value)) {
      oldValue?.removeListener(notifyDependents);
      newWidget.value?.addListener(notifyDependents);
    }
  }
}

/// The three accessors of one [ScopeNotifierBase], with its type arguments
/// named once.
///
/// ```dart
/// final class CounterScope extends ScopeNotifierBase<CounterScope, Counter> {
///   static const access = ScopeNotifierAccess<CounterScope, Counter>();
///   …
/// }
/// ```
///
/// {@category ScopeNotifier}
final class ScopeNotifierAccess<W extends ScopeNotifierBase<W, M>,
    M extends Listenable> {
  /// Creates an accessor for the scope [W].
  const ScopeNotifierAccess();

  /// Finds and returns the context of the scope, or throws.
  ScopeModelContext<W, M> of(BuildContext context, {required bool listen}) =>
      ScopeNotifierBase.of<W, M>(context, listen: listen);

  /// Tries to find and return the context of the scope.
  ScopeModelContext<W, M>? maybeOf(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeNotifierBase.maybeOf<W, M>(context, listen: listen);

  /// Selects a value from the scope context and **subscribes** to it.
  V select<V extends Object?>(
    BuildContext context,
    V Function(ScopeModelContext<W, M> context) selector,
  ) =>
      ScopeNotifierBase.select<W, M, V>(context, selector);
}
