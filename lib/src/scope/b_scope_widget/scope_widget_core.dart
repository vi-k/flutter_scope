part of '../scope.dart';

typedef _ScopeDependency<T extends Object, V extends Object?> = (
  V,
  V Function(T)
);

/// The build the registrations arriving right now belong to.
///
/// A widget selects what it needs *in a given build*, and a build later it may
/// select something else entirely. Flutter offers no "this dependent is about
/// to build" hook — its own [InheritedModel] piles aspects up for want of one —
/// so the boundary is taken from the frame: a dependent registers only while it
/// is being built, and two builds of the same dependent are two frames apart.
///
/// The one case this cannot tell apart is a dependent rebuilt twice within a
/// single frame. A scope's own notification is not that case: it clears the
/// registration outright before the dependent rebuilds.
Object _buildPass = Object();

/// Whether the end of [_buildPass] has already been asked for.
bool _buildPassEnding = false;

Object _currentBuildPass() {
  if (!_buildPassEnding) {
    _buildPassEnding = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _buildPass = Object();
      _buildPassEnding = false;
    });
  }

  return _buildPass;
}

/// What one dependent asked to hear about, and the build it asked in.
final class _ScopeDependencies<E extends Object> {
  /// The build [pairs] and [all] were collected in.
  Object pass;

  /// Whether the dependent asked to hear about every change.
  bool all = false;

  /// The `(value, selector)` pairs the dependent registered.
  final pairs = <_ScopeDependency<E, Object?>>[];

  _ScopeDependencies(this.pass);

  /// Starts over for [pass], dropping what an earlier build asked for.
  void reset(Object pass) {
    this.pass = pass;
    all = false;
    pairs.clear();
  }
}

/// The phase of the one-shot initialization hook of a scope element.
enum _InitPhase {
  /// The hook has not run yet.
  pending,

  /// The hook returned successfully.
  done,

  /// The hook threw. It is not attempted again.
  failed,
}

/// {@category ScopeWidget}
abstract base class ScopeWidgetCore<W extends ScopeWidgetCore<W, E>,
    E extends ScopeWidgetElementBase<W, E>> extends ScopeInheritedWidget {
  /// Creates the widget half of a scope.
  const ScopeWidgetCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// Creates the element of this scope.
  ///
  /// The one method a family has to provide here.
  E createScopeElement();

  @override
  InheritedElement createElement() => createScopeElement();

  @override
  bool updateShouldNotify(ScopeWidgetCore<W, E> oldWidget) => true;

  @override
  String toStringShort({bool showHashCode = false}) =>
      '$W${tag == null ? showHashCode //
          ? '(#${shortHash(this)})' : '' : '($tag)'}';

  /// The element of the nearest scope [W] above [context], or `null`.
  static E? maybeOf<W extends ScopeWidgetCore<W, E>,
          E extends ScopeWidgetElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(context, listen: listen);

  /// The element of the nearest scope [W] above [context].
  ///
  /// Throws when there is no such scope.
  static E of<W extends ScopeWidgetCore<W, E>,
          E extends ScopeWidgetElementBase<W, E>>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, E>(context, listen: listen);

  /// Subscribes to one value of the scope and returns it.
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
  _ScopeDependencies<E>? _selfDependencies;

  /// Whether the next rebuild ([performRebuild]) should only notify the
  /// dependents instead of rebuilding the subtree.
  bool _shouldOnlyNotify = false;

  /// Whether the element must rebuild anyway, ignoring [_shouldOnlyNotify].
  bool _forceRebuild = true;

  /// How far the one-shot [init] hook got.
  _InitPhase _initPhase = _InitPhase.pending;

  /// What [init] threw, kept so that every later build reports the same
  /// failure instead of building a subtree the scope cannot serve.
  (Object, StackTrace)? _initFailure;

  /// Whether [init] has completed successfully.
  bool get _didInit => _initPhase == _InitPhase.done;

  /// Creates the element.
  ScopeWidgetElementBase(W super.widget);

  @override
  W get widget => super.widget as W;

  @override
  void unmount() {
    // Symmetry, not success: an attempt that failed halfway may still have
    // taken something, and this is the only place left to give it back. The
    // families make their own disposers tolerate that partial state.
    if (_initPhase != _InitPhase.pending) {
      dispose();
    }
    super.unmount();
  }

  /// Whether the subtree must be rebuilt on every notification.
  ///
  /// A scope whose [buildChild] returns a different branch as its state
  /// advances sets this; the rest keep the notify-only rebuild.
  bool get autoSelfDependence => false;

  @override
  void init() {}

  @override
  void dispose() {}

  _ScopeDependencies<E> _updateDependencies(
    _ScopeDependencies<E>? dependencies,
    Object? aspect,
  ) {
    final pass = _currentBuildPass();
    final newDependencies = dependencies ?? _ScopeDependencies<E>(pass);

    // What an earlier build asked for is not what this one reads. Kept, the
    // pairs of every build since the last change would pile up, and a change
    // to any of them -- to a value the dependent stopped reading builds ago --
    // would rebuild it.
    if (newDependencies.pass != pass) {
      newDependencies.reset(pass);
    }

    if (aspect == null) {
      // Subscribe to every change.
      newDependencies.all = true;

      return newDependencies;
    }

    if (aspect case final _ScopeDependency<E, Object?> dependency) {
      newDependencies.pairs.add(dependency);

      return newDependencies;
    }

    assert(false, '`aspect` must be ${_ScopeDependency<E, Object?>}');

    return newDependencies;
  }

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    setDependencies(
      dependent,
      _updateDependencies(
        getDependencies(dependent) as _ScopeDependencies<E>?,
        aspect,
      ),
    );
  }

  void _notifyDependent(
    W oldWidget,
    Element dependent,
    _ScopeDependencies<E>? dependencies,
  ) {
    if (dependencies == null) {
      return;
    }

    var dependenciesChanged = dependencies.all;

    if (!dependenciesChanged) {
      for (final (value, selector) in dependencies.pairs) {
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
      getDependencies(dependent) as _ScopeDependencies<E>?,
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

  /// Runs [init] once, inside the build error boundary of
  /// [ComponentElement.performRebuild], and only then builds the subtree.
  ///
  /// This is the first point at which the element is connected to its
  /// ancestors and the subtree has not been built yet: [Element.mount] has
  /// assigned the parent and the inherited map, and `buildChild` has not run.
  @nonVirtual
  @override
  Widget build() {
    if (_initPhase == _InitPhase.pending) {
      assert(() {
        _debugInitializingElement = this;

        return true;
      }());
      try {
        init();
      } on Object catch (error, stackTrace) {
        // Terminal, not retried: a hook that failed halfway may already hold
        // something, and running it again would take a second copy of it
        // while the first stays out of reach. The boundary above turns this
        // into an `ErrorWidget`, and `unmount` still calls `dispose`.
        _initPhase = _InitPhase.failed;
        _initFailure = (error, stackTrace);

        rethrow;
      } finally {
        assert(() {
          _debugInitializingElement = null;

          return true;
        }());
      }

      _initPhase = _InitPhase.done;
    } else if (_initFailure case (final error, final stackTrace)) {
      // There is no scope to build on. Raising the original failure again --
      // with its own stack trace -- keeps the boundary showing what actually
      // went wrong, rather than a second, derived error.
      Error.throwWithStackTrace(error, stackTrace);
    }

    return buildChild();
  }

  @override
  String toStringShort({bool showHashCode = false}) =>
      '$E(#${shortHash(this)})';
}
