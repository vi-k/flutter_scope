part of '../scope.dart';

/// {@category ScopeWidget}
abstract base class ScopeWidgetBase<W extends ScopeWidgetBase<W>>
    extends ScopeWidgetCore<W, _ScopeWidgetElement<W>> {
  /// Creates a scope over the parameters of the widget itself.
  const ScopeWidgetBase({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  @override
  // ignore: library_private_types_in_public_api
  _ScopeWidgetElement<W> createScopeElement() => _ScopeWidgetElement(this as W);

  /// Builds what the scope shows.
  ///
  /// The `context` is the scope's own element, so a lookup from it finds
  /// this very scope: read the parameters as fields instead.
  Widget build(BuildContext context);

  /// The nearest scope widget [W] above [context], or `null`.
  static W? maybeOf<W extends ScopeWidgetBase<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, ScopeContext<W>>(context, listen: listen)?.widget;

  /// The nearest scope widget [W] above [context].
  ///
  /// Throws when there is no such scope.
  static W of<W extends ScopeWidgetBase<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, ScopeContext<W>>(context, listen: listen).widget;

  /// Subscribes to one parameter of the scope widget and returns it.
  static V select<W extends ScopeWidgetBase<W>, V extends Object?>(
    BuildContext context,
    V Function(W widget) selector,
  ) =>
      ScopeContext.select<W, ScopeContext<W>, V>(
        context,
        (context) => selector(context.widget),
      );
}

final class _ScopeWidgetElement<W extends ScopeWidgetBase<W>>
    extends ScopeWidgetElementBase<W, _ScopeWidgetElement<W>>
    implements ScopeInheritedElement<W> {
  _ScopeWidgetElement(super.widget);

  @override
  Widget buildChild() => widget.build(this);
}
