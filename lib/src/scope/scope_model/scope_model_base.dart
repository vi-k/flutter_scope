part of '../scope.dart';

/// {@category ScopeModel}
abstract base class ScopeModelBase<W extends ScopeModelBase<W, M>,
        M extends Object> extends ScopeModelCore<W, _ScopeModelElement<W, M>, M>
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
  const ScopeModelBase({
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
  const ScopeModelBase.value({
    super.key,
    super.tag,
    required M this.value,
  })  : hasValue = true,
        create = null,
        dispose = null;

  @override
  // ignore: library_private_types_in_public_api
  _ScopeModelElement<W, M> createScopeElement() =>
      _ScopeModelElement(this as W);

  @override
  Widget build(BuildContext context);

  /// The context of the nearest scope [W], or `null` if there is none.
  static ScopeModelContext<W, M>?
      maybeOf<W extends ScopeModelBase<W, M>, M extends Object>(
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
      of<W extends ScopeModelBase<W, M>, M extends Object>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.of<W, ScopeModelContext<W, M>>(
            context,
            listen: listen,
          );

  /// Subscribes to one value of the scope and returns it.
  static V select<W extends ScopeModelBase<W, M>, M extends Object,
          V extends Object?>(
    BuildContext context,
    V Function(ScopeModelContext<W, M> context) selector,
  ) =>
      ScopeContext.select<W, ScopeModelContext<W, M>, V>(
        context,
        selector,
      );
}

final class _ScopeModelElement<W extends ScopeModelBase<W, M>, M extends Object>
    extends ScopeModelElementBase<W, _ScopeModelElement<W, M>, M>
    with _ScopeModelElementMixin<W, M>
    implements ScopeModelContext<W, M> {
  _ScopeModelElement(super.widget);

  Object? get tag => widget.tag;
}

/// The three accessors of one [ScopeModelBase], with its type arguments named
/// once.
///
/// ```dart
/// final class UserScope extends ScopeModelBase<UserScope, UserModel> {
///   static const access = ScopeModelAccess<UserScope, UserModel>();
///   …
/// }
///
/// final name = UserScope.access.select(context, (c) => c.model.name);
/// ```
///
/// {@category ScopeModel}
final class ScopeModelAccess<W extends ScopeModelBase<W, M>, M extends Object> {
  /// Creates an accessor for the scope [W].
  const ScopeModelAccess();

  /// Finds and returns the context of the scope, or throws.
  ScopeModelContext<W, M> of(BuildContext context, {required bool listen}) =>
      ScopeModelBase.of<W, M>(context, listen: listen);

  /// Tries to find and return the context of the scope.
  ScopeModelContext<W, M>? maybeOf(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeModelBase.maybeOf<W, M>(context, listen: listen);

  /// Selects a value from the scope context and **subscribes** to it.
  V select<V extends Object?>(
    BuildContext context,
    V Function(ScopeModelContext<W, M> context) selector,
  ) =>
      ScopeModelBase.select<W, M, V>(context, selector);
}
