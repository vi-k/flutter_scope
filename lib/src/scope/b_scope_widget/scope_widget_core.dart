part of '../scope.dart';

typedef _ScopeDependency<T extends Object, V extends Object?> = (
  V,
  V Function(T)
);

/// {@category ScopeWidget}
abstract base class ScopeWidgetCore<W extends ScopeWidgetCore<W, E>,
    E extends ScopeWidgetElementBase<W, E>> extends ScopeInheritedWidget {
  const ScopeWidgetCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  E createScopeElement();

  @override
  InheritedElement createElement() => createScopeElement();

  @override
  bool updateShouldNotify(ScopeWidgetCore<W, E> oldWidget) => true;

  @override
  String toStringShort({bool showHashCode = false}) =>
      '$W${tag == null ? showHashCode //
          ? '(#${shortHash(this)})' : '' : '($tag)'}';

  static E? maybeOf<W extends ScopeWidgetCore<W, E>,
          E extends ScopeWidgetElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(context, listen: listen);

  static E of<W extends ScopeWidgetCore<W, E>,
          E extends ScopeWidgetElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, E>(context, listen: listen);

  static V select<W extends ScopeWidgetCore<W, E>,
          E extends ScopeWidgetElementBase<W, E>, V extends Object?>(
    BuildContext context,
    V Function(E element) selector,
  ) =>
      ScopeContext.select<W, E, V>(context, selector);
}

/// {@category ScopeWidget}
abstract base class ScopeWidgetElementBase<W extends ScopeWidgetCore<W, E>,
        E extends ScopeWidgetElementBase<W, E>> extends InheritedElement
    implements ScopeInheritedElement<W> {
  late final _log = log.withAddedName(
    () => widget.toStringShort(showHashCode: true),
  );

  /// The dependencies of the element on itself.
  ///
  /// [InheritedElement] does not support depending on itself (an assert in
  /// [notifyClients] blocks it), so self-dependencies are kept in a separate
  /// field.
  List<_ScopeDependency<E, Object?>>? _selfDependencies;

  /// Whether the next rebuild ([performRebuild]) should only notify the
  /// dependents instead of rebuilding the subtree.
  bool _shouldOnlyNotify = false;

  /// Whether the element must rebuild anyway, ignoring [_shouldOnlyNotify].
  bool _forceRebuild = true;

  ScopeWidgetElementBase(W super.widget) {
    init();
  }

  @override
  W get widget => super.widget as W;

  @override
  void unmount() {
    dispose();
    super.unmount();
  }

  bool get autoSelfDependence => false;

  @override
  void init() {}

  @override
  void dispose() {}

  List<_ScopeDependency<E, Object?>> _createDependencies() => [];

  List<_ScopeDependency<E, Object?>>? _updateDependencies(
    List<_ScopeDependency<E, Object?>>? dependencies,
    Object? aspect,
  ) {
    // Already subscribed to every change.
    if (dependencies != null && dependencies.isEmpty) {
      return null;
    }

    if (aspect == null) {
      // Subscribe to every change.
      return _createDependencies();
    }

    if (aspect case _ScopeDependency<E, Object?>()) {
      return (dependencies ?? _createDependencies())..add(aspect);
    }

    assert(false, '`aspect` must be ${_ScopeDependency<E, Object?>}');

    return null;
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    final newDependencies = _updateDependencies(
      getDependencies(dependent) as List<_ScopeDependency<E, Object?>>?,
      aspect,
    );
    if (newDependencies != null) {
      setDependencies(dependent, newDependencies);
    }
  }

  void _notifyDependent(
    W oldWidget,
    Element dependent,
    List<_ScopeDependency<E, Object?>>? dependencies,
  ) {
    if (dependencies == null) {
      return;
    }

    var dependenciesChanged = false;

    if (dependencies.isEmpty) {
      dependenciesChanged = true;
    } else {
      for (final (value, selector) in dependencies) {
        if (selector(this as E) != value) {
          dependenciesChanged = true;
          break;
        }
      }
    }

    if (dependenciesChanged) {
      if (identical(dependent, this)) {
        _selfDependencies = null;
        _forceRebuild = true;
      } else {
        setDependencies(dependent, null);
      }
      dependent.didChangeDependencies();
    }
  }

  @override
  void notifyDependent(W oldWidget, Element dependent) {
    _notifyDependent(
      oldWidget,
      dependent,
      getDependencies(dependent) as List<_ScopeDependency<E, Object?>>?,
    );
  }

  @override
  InheritedWidget dependOnInheritedElement(
    InheritedElement ancestor, {
    Object? aspect,
  }) {
    if (identical(this, ancestor)) {
      _selfDependencies = _updateDependencies(_selfDependencies, aspect);
      return widget;
    }

    return super.dependOnInheritedElement(ancestor, aspect: aspect);
  }

  /// [InheritedElement.notifyClients] does not support self-subscription,
  /// although this is required in our case.
  @override
  void notifyClients(W oldWidget) {
    if (_selfDependencies case final dependencies?) {
      _notifyDependent(oldWidget, this, dependencies);
    }

    super.notifyClients(oldWidget);
  }

  /// Notifies the dependents of a change.
  ///
  /// The notification goes through [didChangeDependencies], which can only run
  /// while a frame is being built. The only way left is therefore to mark the
  /// element dirty and notify the dependents from [performRebuild].
  @protected
  void notifyDependents() {
    _shouldOnlyNotify = true;
    markNeedsBuild();
  }

  /// Rebuilds the subtree anyway when the parent updates the element while a
  /// notify-only rebuild ([notifyDependents]) is pending.
  @override
  void update(covariant ProxyWidget newWidget) {
    _forceRebuild = true;
    super.update(newWidget);
  }

  /// Skips rebuilding the whole subtree (skips [build]) when the dependents
  /// only have to be notified of a change ([notifyDependents]).
  ///
  /// The subtree is rebuilt anyway when:
  /// 1. [autoSelfDependence] - the element declared an automatic dependency on
  ///    itself (used by initializers during the initialization phases).
  /// 2. [_forceRebuild] - the subtree must be rebuilt because the parent is
  ///    updating the element or the element depends on itself.
  @override
  void performRebuild() {
    if (_shouldOnlyNotify) {
      notifyClients(widget);
      _shouldOnlyNotify = !autoSelfDependence && !_forceRebuild;
    }
    super.performRebuild();
    _forceRebuild = false;
    _shouldOnlyNotify = false;
  }

  @override
  Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) =>
      _shouldOnlyNotify ? child : super.updateChild(child, newWidget, newSlot);

  @nonVirtual
  @override
  Widget build() => buildChild();

  @override
  String toStringShort({bool showHashCode = false}) =>
      '$E(#${shortHash(this)})';
}
