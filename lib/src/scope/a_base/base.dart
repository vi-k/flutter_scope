part of '../scope.dart';

/// {@category base}
abstract base class ScopeInheritedWidget extends InheritedWidget {
  final Object? tag;

  const ScopeInheritedWidget({
    super.key,
    this.tag,
    // Not used by default. You can use it at your own discretion.
    super.child = const _NullWidget(),
  });
}

final class _NullWidget extends Widget {
  const _NullWidget();

  @override
  Element createElement() => throw UnimplementedError();
}

/// {@category base}
abstract interface class ScopeContext<W extends ScopeInheritedWidget> {
  W get widget;

  static C? maybeOf<W extends ScopeInheritedWidget, C extends ScopeContext<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      _find<W, C, void>(context, listen: listen)?.$1;

  static C of<W extends ScopeInheritedWidget, C extends ScopeContext<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      _find<W, C, void>(context, listen: listen)?.$1 ?? _throwNotFound<W>();

  static V select<W extends ScopeInheritedWidget, C extends ScopeContext<W>,
          V extends Object?>(
    BuildContext context,
    V Function(C context) selector,
  ) =>
      (_find<W, C, V>(context, listen: true, selector: selector) ??
              _throwNotFound<W>())
          .$2 as V;

  static (C, V?)? _find<W extends ScopeInheritedWidget,
      C extends ScopeContext<W>, V extends Object?>(
    BuildContext context, {
    required bool listen,
    V Function(C)? selector,
  }) {
    final element = context.getElementForInheritedWidgetOfExactType<W>();
    if (element == null) {
      return null;
    }

    final scopeContext = element is C
        ? element as C
        : throw Exception('The element of $W is not $C');

    if (!listen) {
      return (scopeContext, null);
    }

    V? value;
    if (selector == null) {
      context.dependOnInheritedElement(element);
    } else {
      value = selector(scopeContext);
      context.dependOnInheritedElement(element, aspect: (value, selector));
    }

    return (scopeContext, value);
  }

  static Never _throwNotFound<W extends InheritedWidget>() {
    throw Exception('$W not found in the context');
  }
}

/// {@category base}
abstract interface class ScopeInheritedElement<W extends ScopeInheritedWidget>
    implements ScopeContext<W> {
  @override
  W get widget;

  @mustCallSuper
  void init();

  @mustCallSuper
  void dispose();

  Widget buildChild();
}
