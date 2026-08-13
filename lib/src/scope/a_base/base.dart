part of '../scope.dart';

/// {@category base}
abstract base class ScopeInheritedWidget extends InheritedWidget {
  /// Names this particular scope in the log.
  ///
  /// Two scopes of the same type are otherwise told apart only by a short
  /// hash. See the `debug` topic for the format.
  final Object? tag;

  /// Creates the inherited widget of a scope.
  ///
  /// The `child` is not what a scope shows — that is [
  /// ScopeInheritedElement.buildChild] — and the default is a placeholder
  /// that refuses to build.
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
  /// The widget of this scope.
  W get widget;

  /// The context of the nearest scope [W] above [context], or `null`.
  ///
  /// With `listen: true` the caller is subscribed to every change of that
  /// scope; with `listen: false` it is not subscribed at all.
  static C? maybeOf<W extends ScopeInheritedWidget, C extends ScopeContext<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      _find<W, C, void>(context, listen: listen)?.$1;

  /// The context of the nearest scope [W] above [context].
  ///
  /// Throws when there is no such scope. [maybeOf] returns `null` instead.
  static C of<W extends ScopeInheritedWidget, C extends ScopeContext<W>>(
    BuildContext context, {
    required bool listen,
  }) =>
      _find<W, C, void>(context, listen: listen)?.$1 ?? _throwNotFound<W>();

  /// Subscribes to one value of the scope and returns it.
  ///
  /// The caller is rebuilt only when `selector` returns something different
  /// from what it returned during its last build. Throws when there is no
  /// such scope.
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

  /// Called once, when the element is created.
  ///
  /// Everything the scope owns is acquired here and released in [dispose].
  void init();

  @mustCallSuper

  /// Called once, when the element is unmounted.
  void dispose();

  /// Builds what the scope shows.
  Widget buildChild();
}
