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
  const ScopeModelBase.value({
    super.key,
    super.tag,
    required this.value,
  })  : hasValue = true,
        create = null,
        dispose = null;

  @override
  // ignore: library_private_types_in_public_api
  _ScopeModelElement<W, M> createScopeElement() =>
      _ScopeModelElement(this as W);

  @override
  Widget build(BuildContext context);

  static ScopeModelContext<W, M>?

      /// The context of the nearest scope [W], or `null` if there is none.
      /// The context of the nearest scope [W], or `null` if there is none.
      maybeOf<W extends ScopeModelBase<W, M>, M extends Object>(
    BuildContext context, {
    required bool listen,
  }) =>
          ScopeContext.maybeOf<W, ScopeModelContext<W, M>>(
            context,
            listen: listen,
          );

  static ScopeModelContext<W, M>

      /// The context of the nearest scope [W].
      ///
      /// Throws when there is no such scope above [context].
      /// The context of the nearest scope [W].
      ///
      /// Throws when there is no such scope above [context].
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
