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

/// The element whose initialization hook is running right now.
///
/// Written only from inside `assert`s, so it costs nothing in release builds.
/// It is what lets the lookup below tell a subscription taken from the hook --
/// which can never be honoured -- from an ordinary one.
Element? _debugInitializingElement;

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
    assert(
      !listen || !identical(context, _debugInitializingElement),
      'A scope cannot be subscribed to from the initialization hook. The hook '
      'runs once, before the first build, and is never called again, so a '
      'subscription taken there rebuilds the subtree while the value the hook '
      'read stays behind. Look the scope up with `listen: false` here, and '
      'subscribe from `buildChild()` or from the widgets below instead.',
    );

    assert(
      !listen || context.debugDoingBuild,
      'A scope can only be subscribed to from a build. What a dependent asked '
      'for is remembered per build, and the boundary between one build and '
      'the next is taken from the frame -- Flutter offers no hook for "this '
      'dependent is about to build" -- so a registration made outside a build '
      'belongs to whichever build shares its frame, and is dropped by the '
      'first build that does not. `didChangeDependencies` is the usual way to '
      'get here: it runs in the same frame as the build after it, so the '
      'subscription looks like it works, and then disappears on the first '
      'rebuild that comes from the parent instead of from a change.\n'
      'Subscribe from `build` and read the value there. To react to a change '
      'rather than to show it, keep the subscription in `build` and look the '
      'scope up with `listen: false` from `didChangeDependencies`.',
    );

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

  /// Called once, after the element is mounted and before its first
  /// [buildChild].
  ///
  /// If it throws, the failure is terminal: the hook is not attempted again,
  /// the scope shows an error instead of its subtree, and every later build
  /// reports the same failure. Subscribing to another scope from here is not
  /// supported and is caught by an assertion; looking one up with
  /// `listen: false` is, since the element is already connected to its
  /// ancestors.
  ///
  /// Everything the scope owns is acquired here and released in [dispose].
  @mustCallSuper
  void init();

  /// Called when the element is unmounted, unless [init] never ran at all.
  ///
  /// An [init] that threw halfway is cleaned up here too, so whatever it took
  /// before it failed is given back. Implementations therefore have to expect
  /// a partially initialized scope.
  @mustCallSuper
  void dispose();

  /// Builds what the scope shows.
  Widget buildChild();
}
