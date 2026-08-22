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

    final scheduler = SchedulerBinding.instance;

    // The callback needs a frame to run in, and a build is not always inside
    // one: `BuildOwner.buildScope` also runs with no frame in progress, which is
    // how `runApp` builds the first tree. With no frame to come, this flag would
    // stay raised and every dependent from then on would add its selectors to a
    // pass that never ends.
    //
    // Asked for only when nothing else will bring a frame, unlike the
    // neighbouring `runOutsideFrame`, which asks unconditionally: what that one
    // defers marks an element dirty and needs a frame of its own, while this
    // callback resets a field. Asking from inside a frame would order one more,
    // empty, after every frame that built anything.
    if (scheduler.schedulerPhase == SchedulerPhase.idle) {
      scheduler.scheduleFrame();
    }

    scheduler.addPostFrameCallback((_) {
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
    implements ScopeInheritedElement<W>, ScopeObservable {
  @override
  String get debugLabel => widget.toStringShort(showHashCode: true);

  /// The dependencies of the element on itself.
  ///
  /// [InheritedElement] does not support depending on itself (an assert in
  /// [notifyClients] blocks it), so self-dependencies are kept in a separate
  /// field.
  _ScopeDependencies<E>? _selfDependencies;

  /// Whether a notification is waiting for a rebuild to carry it.
  ///
  /// Written by [notifyDependents] and read once, at the top of the next
  /// [performRebuild]. It is deliberately *not* what [updateChild] and
  /// [buildChild] consult: a notification made while this element is building
  /// belongs to the rebuild after this one, and letting it reach the rebuild
  /// in progress left the subtree unmounted.
  bool _notifyPending = false;

  /// Whether the rebuild running right now is a notify-only one.
  ///
  /// Taken from [_notifyPending] at the top of [performRebuild] and put down
  /// at the bottom of it, so it describes one rebuild and cannot be changed
  /// from inside that rebuild.
  bool _rebuildIsNotifyOnly = false;

  /// Whether [performRebuild] is running on this element right now.
  ///
  /// A plain field rather than `SchedulerBinding.isBuilding`: this is about
  /// *this* element, not about the phase, and unlike the binding's answer it
  /// is the same in release as in debug.
  bool _isRebuilding = false;

  /// Whether the element must rebuild anyway, ignoring [_rebuildIsNotifyOnly].
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

  /// Whether [onUnmount] has run.
  bool _didUnmount = false;

  @override
  void unmount() {
    // The observer's pair belongs to a scope that announced `onInit`: an
    // `init()` that threw, or one that never ran, reports neither half of
    // it, even though the teardown below still runs for it -- see the next
    // comment.
    final reportsTeardown = !reportsOwnLifecycle && _didInit;

    if (reportsTeardown) {
      notifyObserver((observer) => observer.onDispose(this));
    }

    // Symmetry, not success: an attempt that failed halfway may still have
    // taken something, and this is the only place left to give it back. The
    // families make their own disposers tolerate that partial state.
    try {
      if (_initPhase != _InitPhase.pending) {
        try {
          unmountScope();
          // ignore: avoid_catching_errors
        } on Object catch (error, stackTrace) {
          // Reported both ways and re-thrown neither. `_performAsyncDispose`
          // guards the same hook and sends `onError` for it, except that it
          // only ever reaches `unmountScope()` first on the path where the
          // scope closes itself and stays on the tree; when the tree takes the
          // element away, `unmount()` gets there first and `_didUnmount` makes
          // the later attempt a no-op. So the two paths ran the same hook and
          // only one of them said anything.
          //
          // And there is nobody here to raise it at. The "caller" of this
          // method is `BuildOwner._inactiveElements._unmountAll()`, a loop
          // with no boundary around any one element, over a list it has
          // already cleared: a throw ends the loop, and every scope behind
          // this one is left mounted for good -- no `unmountScope`, no
          // `dispose`, no asynchronous teardown, its `scopeKey` never given
          // back and its registration with the parent never dropped. The
          // neighbours of a scope whose hook threw are not the audience of
          // that failure. This is the trade the rest of the teardown already
          // makes, in the words of `_reportFailure`: reported, and the
          // teardown goes on.
          notifyObserver(
            (observer) =>
                observer.onError(this, ScopePhase.unmount, error, stackTrace),
          );
          _reportFailure(error, stackTrace, 'while unmounting the scope');
        } finally {
          _disposeReportingFailure();
        }
      }
    } finally {
      if (reportsTeardown) {
        notifyObserver((observer) => observer.onDisposed(this));
      }
      super.unmount();
    }
  }

  /// Runs [dispose], letting the observer hear a failure on its way out.
  ///
  /// It runs from the `finally` of [unmount], outside the guard around the
  /// [unmountScope] beside it, so its failure used to reach the framework and
  /// no further — while the `onDispose`/`onDisposed` pair closed around it as
  /// if the teardown had gone through. For a `ScopeModel` that failure is the
  /// `dispose` callback of a public parameter, which is user code by
  /// definition. Reported rather than re-thrown, for the reason given beside
  /// the guard above: the only caller left is the loop that is unmounting
  /// every other scope of the same batch.
  void _disposeReportingFailure() {
    try {
      dispose();
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      notifyObserver(
        (observer) =>
            observer.onError(this, ScopePhase.disposal, error, stackTrace),
      );
      _reportFailure(error, stackTrace, 'while disposing of the scope');
    }
  }

  /// Whether this element reports its own initialization and teardown.
  ///
  /// `false` here: a family with no phase of its own is announced by this
  /// class, at the two points a bare element has. A family that runs an
  /// initialization — everything on [AsyncScopeElementBase] — overrides this
  /// to `true` and reports the phase itself, in more detail than a pair of
  /// events could carry.
  @protected
  bool get reportsOwnLifecycle => false;

  /// Runs [onUnmount] once, whichever way out reaches it first.
  ///
  /// A scope leaves in one of two ways, and the synchronous half of the
  /// teardown belongs to both: the framework unmounting the element, and the
  /// scope closing itself while it stays on screen. Wired to the first alone,
  /// as it was, a closed scope never dropped what [onUnmount] drops -- and by
  /// the time the element did leave the tree, the asynchronous half had
  /// already run and there was nothing left to drop it from.
  @nonVirtual
  @protected
  void unmountScope() {
    if (_didUnmount) {
      return;
    }
    _didUnmount = true;

    onUnmount();
  }

  /// Lets go of whatever cannot wait for the asynchronous teardown.
  ///
  /// Runs exactly once, before anything is released asynchronously, whether
  /// the scope was removed from the tree or closed with `close()`. This is
  /// where a subscription is cancelled and a listener detached — everything
  /// that must stop reaching a scope that is on its way out.
  @protected
  @mustCallSuper
  void onUnmount() {}

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

    // Loud in debug, and not silent in release either. An `aspect` this
    // element does not recognise can only come from a
    // `dependOnInheritedElement` written by hand, and the two ways of being
    // wrong are not equal: subscribed to everything, the dependent is rebuilt
    // more often than it needs to be; subscribed to nothing, as it was, it is
    // never rebuilt at all and nothing anywhere says why.
    assert(false, '`aspect` must be ${_ScopeDependency<E, Object?>}');
    newDependencies.all = true;

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

  /// Whether [selector] now answers something other than [value].
  ///
  /// The selector is user code, and this is not the framework running it:
  /// [notifyClients] walks the dependents from [performRebuild], with no
  /// boundary of its own around any of them. A throw that got out of here
  /// took the whole walk with it -- every dependent it had not reached yet
  /// simply never heard about the change, and which ones those were came down
  /// to the iteration order of a hash map. The scope's own subscription is
  /// walked first, so a failure there swallowed the notification whole. The
  /// frame then died of a second, derived error that says nothing about the
  /// selector.
  ///
  /// A selector that could not answer counts as changed, so its dependent is
  /// rebuilt and asks it again from inside its own build -- where the
  /// framework's error boundary turns a second failure into an `ErrorWidget`
  /// for that one widget, which is where a failure of its own belongs.
  bool _selectorSaysChanged(Object? Function(E) selector, Object? value) {
    try {
      return selector(this as E) != value;
      // ignore: avoid_catching_errors
    } on Object catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'scopo',
          context: ErrorDescription(
            'while a selector was being asked whether the value it reads from '
            '${widget.toStringShort()} had changed',
          ),
        ),
      );

      return true;
    }
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
        if (_selectorSaysChanged(selector, value)) {
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
    _notifyPending = true;

    // Any build, not this element's own. `markNeedsBuild()` on an element that
    // is building right now does nothing: the framework's assertion lets the
    // self case through, and `if (dirty) return;` swallows the call. On an
    // element that is *not* the one building, the same call is refused
    // outright -- "setState() or markNeedsBuild() called during build" -- and
    // that is what a model touched from the build of a descendant used to
    // get. It is the same ordinary user code either way: a lazy load, a
    // default filled in on first read. Asking for the rebuild after the frame
    // is what turns a lost or refused notification into a late one.
    if (_isRebuilding || SchedulerBinding.instance.isBuilding) {
      // One callback while one is pending, not one per notification. The flag
      // above is what the callback acts on, so a second notification arriving
      // before the frame is over is already carried by the first, and a
      // callback of its own would find nothing left to do.
      if (_notifyDeferred) {
        return;
      }
      _notifyDeferred = true;

      SchedulerBinding.instance
        // The build may be one `runApp` drives outside a frame, and then
        // nothing has asked for the frame this callback needs.
        ..scheduleFrame()
        ..addPostFrameCallback((_) {
          _notifyDeferred = false;
          if (mounted && _notifyPending) {
            markNeedsBuild();
          }
        });
    } else {
      markNeedsBuild();
    }
  }

  /// Whether a deferred notification is already waiting for the frame to end.
  bool _notifyDeferred = false;

  /// Rebuilds the subtree anyway when the parent updates the element while a
  /// notify-only rebuild ([notifyDependents]) is pending.
  @override
  void update(covariant ProxyWidget newWidget) {
    _forceRebuild = true;
    super.update(newWidget);
  }

  /// Keeps the subtree as it is when the dependents only have to be notified
  /// of a change ([notifyDependents]).
  ///
  /// Two halves, because [build] cannot be skipped: [ComponentElement]
  /// calls it either way. It hands back the widget of the last real build,
  /// and this method leaves the child element alone.
  ///
  /// The subtree is rebuilt anyway when:
  /// 1. [autoSelfDependence] - the element declared an automatic dependency on
  ///    itself (used by initializers during the initialization phases).
  /// 2. [_forceRebuild] - the subtree must be rebuilt because the parent is
  ///    updating the element or the element depends on itself.
  @override
  void performRebuild() {
    // Taken once, here, and put down at the end: everything this rebuild does
    // reads `_rebuildIsNotifyOnly`, and `notifyDependents()` writes only to
    // `_notifyPending`. Reading the same field for both let a notification
    // made from inside `build()` turn the rebuild that was already running
    // into a notify-only one -- `updateChild` then kept a child from an
    // earlier real build, and on a first build there is none.
    _isRebuilding = true;
    // Counted for the whole package, not just this element: it is what
    // `SchedulerBinding.isBuilding` has left to go by in a release build,
    // where the build owner's own flag lives inside an assert and a build
    // driven outside a frame is therefore invisible. Everything below is
    // inside the `try`, so a rebuild that throws leaves no count standing.
    beginScopeRebuild();

    try {
      if (_notifyPending) {
        _notifyPending = false;
        notifyClients(widget);
        // `_builtChild` among the conditions, and not as a precaution: a
        // notify-only rebuild hands back what the last real build made and
        // leaves the child element alone, which needs there to have been one.
        // With the cache empty -- a first build that threw, so the boundary
        // above put an `ErrorWidget` in the subtree's place -- `build()` below
        // builds a fresh subtree, `updateChild` keeps the `ErrorWidget`
        // instead, and the cache is filled with what was just thrown away. The
        // scope then stays on the error for the rest of its life: the next
        // notification finds a cache and does not even build.
        _rebuildIsNotifyOnly =
            !autoSelfDependence && !_forceRebuild && _builtChild != null;
      }

      super.performRebuild();
    } finally {
      endScopeRebuild();
      _isRebuilding = false;
      _forceRebuild = false;
      _rebuildIsNotifyOnly = false;
    }
  }

  @override
  Element? updateChild(Element? child, Widget? newWidget, Object? newSlot) =>
      _rebuildIsNotifyOnly
          ? child
          : super.updateChild(child, newWidget, newSlot);

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

        // The only report this failure gets. The boundary above raises it
        // again as an `ErrorWidget`, but that is what the subtree shows, not
        // what the observer hears: without this an observer watching scopes
        // saw one that neither began nor ended, whichever family it belonged
        // to. A family with a phase of its own reports its own failures and
        // would double this -- except that its phase is started only for an
        // `init()` that returned (`_didInit` in `performRebuild`), so a hook
        // that threw leaves it never started and with nothing to say.
        notifyObserver(
          (observer) => observer.onError(
            this,
            ScopePhase.initialization,
            error,
            stackTrace,
          ),
        );

        rethrow;
      } finally {
        assert(() {
          _debugInitializingElement = null;

          return true;
        }());
      }

      _initPhase = _InitPhase.done;
      if (!reportsOwnLifecycle) {
        notifyObserver((observer) => observer.onInit(this));
      }
    } else if (_initFailure case (final error, final stackTrace)) {
      // There is no scope to build on. Raising the original failure again --
      // with its own stack trace -- keeps the boundary showing what actually
      // went wrong, rather than a second, derived error.
      Error.throwWithStackTrace(error, stackTrace);
    }

    // A notify-only rebuild hands back what the last real build made.
    // [ComponentElement.performRebuild] calls this method whatever else
    // happens -- only `updateChild` below is ours to skip -- so without the
    // cache `buildChild()` ran on every notification and everything it
    // returned was thrown away unlooked at. For a scope notified once a frame
    // that is the whole widget graph of its subtree, built and dropped, once
    // a frame.
    //
    // The empty cache is not a case any more: `performRebuild` will not call a
    // rebuild notify-only without one. The pattern stays because it is how a
    // nullable field is read without an assertion, and because reading the
    // same fact twice costs nothing -- not because there is a path here where
    // the flag is set and the cache is empty.
    if (_rebuildIsNotifyOnly) {
      if (_builtChild case final builtChild?) {
        return builtChild;
      }
    }

    try {
      return _builtChild = buildChild();
    } on Object catch (error, stackTrace) {
      // The one point every build of every family passes through: the five
      // `buildOn*` of a state-carrying family, `ScopeWidgetBase.build` and
      // `ScopeModel.build` are all reached from here and nowhere else.
      //
      // Reported *and* re-thrown, unlike a teardown with no caller left to
      // hear it. A build has one, and a load-bearing one: the error boundary
      // of [ComponentElement.performRebuild] above, which puts an
      // `ErrorWidget` in the subtree's place. That is what the subtree shows;
      // this is what the observer hears -- the same split that put a report
      // on the `init()` hook higher up this method.
      notifyObserver(
        (observer) =>
            observer.onError(this, ScopePhase.build, error, stackTrace),
      );

      rethrow;
    }
  }

  /// What the last build that was not notify-only produced.
  Widget? _builtChild;

  @override
  String toStringShort({bool showHashCode = false}) =>
      '$E(#${shortHash(this)})';
}
