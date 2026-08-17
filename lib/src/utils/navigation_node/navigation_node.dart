import 'dart:async';

import 'package:flutter/material.dart';

/// Navigation node.
///
/// A widget that creates a nested `Navigator`. It allows you to include bottom
/// sheets, dialogs, and other screens in the current scope, ensuring they have
/// access to all components located above them in the widget tree.
///
/// {@category utils}
final class NavigationNode extends StatefulWidget {
  /// Whether this node is the outermost one.
  ///
  /// A root node keeps a pop to itself; any other node forwards a pop it
  /// cannot handle to the navigator above it.
  final bool isRoot;

  /// The subtree the nested navigator shows first.
  final Widget child;

  /// Gives access to the nested navigator from outside the node.
  ///
  /// Fixed for the lifetime of the node: it is the key the nested navigator is
  /// built with, so another one would mean another navigator and an empty
  /// stack. Handing over a different one is refused by an assertion — hold the
  /// key in a `State` field rather than writing `GlobalKey()` inside `build`.
  final GlobalKey<NodeNavigatorState>? navigatorKey;

  /// Intercepts the system back gesture.
  ///
  /// Return `true` to let the pop through, `false` to keep the route, or a
  /// [Future] to decide after asking — a confirmation dialog, usually. The
  /// `result` is what the popped route would have returned.
  ///
  /// A [Future] is asked for one press at a time: a back arriving while an
  /// answer is still pending is dropped rather than starting a second
  /// question. And an answer is acted on only while it still applies — if the
  /// route the node sits on has been closed by something else, or buried under
  /// a newer one, a `true` takes nothing, since a pop would otherwise take
  /// whatever is on top instead of what was asked about.
  ///
  /// On a root node the hook is asked as it is anywhere else, but `true` takes
  /// nothing there either: [isRoot] says the node keeps a pop to itself, and
  /// there is nothing outside it to let the pop through to. What such a hook is
  /// for is the press itself — a "press again to exit", or a call to
  /// `SystemNavigator.pop()` the application makes on its own terms.
  final FutureOr<bool> Function(BuildContext context, Object? result)? onPop;

  /// Creates a navigation node around [child].
  const NavigationNode({
    super.key,
    this.navigatorKey,
    this.isRoot = false,
    this.onPop,
    required this.child,
  });

  @override
  State<NavigationNode> createState() => _NavigationNodeState();
}

final class _NavigationNodeState extends State<NavigationNode> {
  /// The key the node was given, kept apart from the one it uses: `null` is an
  /// answer like any other, and a node that is later handed a key has to be
  /// told the same thing as one that is handed a different key.
  late final GlobalKey<NodeNavigatorState>? _declaredKey = widget.navigatorKey;

  late final _navigatorKey = _declaredKey ?? GlobalKey<NodeNavigatorState>();
  late final _observer = _NodeNavigatorObserver(this);

  /// Whether an [NavigationNode.onPop] is still deciding about a press.
  bool _deciding = false;

  NodeNavigatorState get _navigator => _navigatorKey.currentState!;

  /// Decides what a system back does once the node itself cannot answer it.
  ///
  /// Refusing takes no undoing: the node's marker stays where it is, so the
  /// next press arrives here exactly as this one did.
  void _decideOutside(BuildContext context, Object? result) {
    // A decision already under way is the answer to this press too. Nothing
    // queues: a second back while a confirmation is on screen must not ask a
    // second time, and two answers of `true` must not take two routes.
    if (_deciding || _navigator.previous == null) {
      return;
    }

    // ignore: discarded_futures
    switch (widget.onPop?.call(context, result)) {
      case final Future<bool> future:
        _deciding = true;
        final route = ModalRoute.of(context);

        // ignore: discarded_futures
        future.whenComplete(() => _deciding = false).then(
          (canPop) {
            // The world does not wait for an answer. The route the node sits
            // on may have been closed by something else, or buried under a
            // newer one -- and a pop would then take whatever is on top
            // instead of what was asked about. A node that is gone answers for
            // itself: its key resolves to nothing, which is why the walk below
            // is null-safe and no `mounted` check is needed on top of it.
            if (!canPop || (route != null && !route.isCurrent)) {
              return;
            }

            _popOutside(result);
          },
          // A question that falls over -- a confirmation dialog raising, most
          // likely -- fails inside a chain nobody holds, and the failure then
          // surfaces as an unhandled zone error far from the widget that
          // caused it. Reported instead, the way the package reports
          // everything it cannot re-throw. The press itself is simply not
          // acted on, and `whenComplete` above has already cleared the way for
          // the next one.
          onError: (Object error, StackTrace stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'scopo',
                context: ErrorDescription(
                  'while deciding what a system back does in a NavigationNode',
                ),
              ),
            );
          },
        );
      case final bool? canPop:
        if (canPop ?? true) {
          _popOutside(result);
        }
    }
  }

  /// Hands the pop to the navigator above, unless this node is the outermost
  /// one.
  ///
  /// [NavigationNode.isRoot] says the node keeps a pop to itself, and
  /// [NodeNavigatorState.pop] has always honoured that. The system back arrives
  /// by this other path, where the promise held only for as long as nobody
  /// wrote an [NavigationNode.onPop]: a root node with one that allowed the pop
  /// took the route below it, and a root node placed as `home` took the last
  /// route of the application's own navigator and left a blank screen.
  ///
  /// The hook is still asked — it is where an application decides what its own
  /// outermost back means, and it may act on the press itself. What a root node
  /// no longer does is leave.
  ///
  /// A pop is handed over only when the navigator above has a route to give up.
  /// [NavigatorState.pop] takes the last one it holds without asking whether it
  /// is the last, so a node placed on the first route of the application used to
  /// empty the application's own navigator: a blank screen, and an assertion of
  /// the framework on the frame after it.
  void _popOutside(Object? result) {
    if (widget.isRoot) {
      return;
    }

    final previous = _navigatorKey.currentState?.previous;

    // `maybePop` would be the natural way to ask, and it is what the imperative
    // path uses. Not here: the node's own `PopScope` is registered on the very
    // route being asked about, so the navigator above hands the press straight
    // back to this node, which decides again, and so on without end. Asking the
    // navigator instead settles the one thing this path gets wrong. What it
    // leaves is a `PopScope` the application put around the node: `pop` walks
    // past it. That is the older, narrower defect, recorded in
    // `docs/handoff.md`.
    if (previous != null && previous.canPop()) {
      previous.pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // In `build`, not in `didUpdateWidget`: a failure here is caught by
    // Flutter's build error boundary, while one raised from `didUpdateWidget`
    // abandons the update halfway and takes the frame down with it.
    assert(
      identical(widget.navigatorKey, _declaredKey),
      'The `navigatorKey` of a NavigationNode cannot change. It is the key the '
      'nested navigator is built with, so another one would mean another '
      'navigator and an empty stack -- which is why the node keeps the first '
      'one, and the new key simply never resolves. Give the widget a different '
      '`Widget.key` when a fresh navigator is what you want. If this fired on '
      'a `GlobalKey()` written inside `build`, hold it in a `State` field '
      'instead: that expression makes a new key on every rebuild.',
    );

    return _NodeBackDispatcher(
      node: this,
      child: _NodeNavigator(
        key: _navigatorKey,
        node: this,
        pages: [MaterialPage<void>(child: widget.child)],
        onDidRemovePage: (_) {},
      ),
    );
  }
}

/// Sends a system back to the navigator below before anything outside sees it.
///
/// This lives in a widget of its own so that the flag it keeps never rebuilds
/// the nested navigator: a rebuild would hand that navigator a fresh page list,
/// which makes it report its stack again, which sets the flag again.
final class _NodeBackDispatcher extends StatefulWidget {
  final _NavigationNodeState node;
  final Widget child;

  const _NodeBackDispatcher({required this.node, required this.child});

  @override
  State<_NodeBackDispatcher> createState() => _NodeBackDispatcherState();
}

final class _NodeBackDispatcherState extends State<_NodeBackDispatcher> {
  /// Whether the subtree below holds a route it can close on its own.
  ///
  /// Kept from [NavigationNotification], which every nested navigator sends
  /// after its stack changes — including navigators deeper than this node's
  /// own, so a node nested in another node is heard here too.
  bool _innerCanPop = false;

  bool _watchInnerStack(NavigationNotification notification) {
    if (notification.canHandlePop != _innerCanPop) {
      // Navigators dispatch this outside of build, so a rebuild is safe here.
      setState(() => _innerCanPop = notification.canHandlePop);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: widget.node.widget.onPop == null && !_innerCanPop,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;

          if (_innerCanPop) {
            // The pop belongs to the navigator below, and only that navigator
            // knows whether its top route accepts it. Nothing outside the node
            // moves, so onPop and isRoot stay out of this.
            // ignore: discarded_futures
            widget.node._navigator.maybePop(result);

            return;
          }

          widget.node._decideOutside(context, result);
        },
        child: NotificationListener<NavigationNotification>(
          onNotification: _watchInnerStack,
          child: widget.child,
        ),
      );
}

final class _NodeNavigator extends Navigator {
  final _NavigationNodeState node;

  _NodeNavigator({
    super.key,
    required this.node,
    super.pages,
    super.onDidRemovePage,
  }) : super(observers: [node._observer]);

  @override
  NavigatorState createState() => NodeNavigatorState();
}

/// The state of the nested navigator a [NavigationNode] builds.
///
/// This is the type a `navigatorKey` is made of —
/// `GlobalKey<NodeNavigatorState>()` — and what that key resolves to, so a
/// caller outside the node can push, pop and read the stack of the navigator
/// inside it. Everything a [NavigatorState] offers is available here; what the
/// node changes is how a pop that the nested navigator cannot handle is
/// answered.
///
/// {@category utils}
final class NodeNavigatorState extends NavigatorState {
  _NodeNavigatorObserver get _observer =>
      (widget as _NodeNavigator).node._observer;

  @override
  bool canPop() {
    // A node that forwards keeps a local history marker on its first route,
    // and while that route is the only one on screen the marker alone would
    // make the base implementation answer `true`. The marker is how a pop
    // leaves the node, not a route the node can close, so it must not pass for
    // one: everything above reads this answer to decide whether the back
    // gesture belongs inside.
    if (_observer._hookInstalled && (_observer._topRoute?.isCurrent ?? false)) {
      return false;
    }

    return super.canPop();
  }

  @override
  void pop<T extends Object?>([T? result]) {
    if (canPop()) {
      super.pop(result);

      return;
    }

    // Nothing of the node's own is left to close, and letting the base
    // implementation take the first page would leave the node with an empty
    // stack — a hole where the screen used to be. A root node keeps the pop
    // instead; any other node hands it to the navigator above, every time and
    // not merely the first.
    if (!_observer.node.widget.isRoot) {
      // ignore: discarded_futures
      previous?.maybePop(result);
    }
  }
}

/// {@category utils}
extension PreviousNavigatorExtension on NavigatorState {
  /// The navigator above this one, if any.
  ///
  /// This is how a [NavigationNode] forwards a pop it cannot handle itself.
  NavigatorState? get previous {
    NavigatorState? prevNavigator;

    if (context.mounted) {
      context.visitAncestorElements((element) {
        prevNavigator = Navigator.maybeOf(element);
        return false;
      });
    }

    return prevNavigator;
  }
}

final class _NodeNavigatorObserver extends NavigatorObserver {
  final _NavigationNodeState node;
  Route<void>? _topRoute;

  /// Whether the forwarding marker currently sits on [_topRoute].
  bool _hookInstalled = false;

  _NodeNavigatorObserver(this.node);

  void _addHook() {
    final topRoute = _topRoute;
    if (_hookInstalled || node.widget.isRoot || topRoute is! ModalRoute<void>) {
      return;
    }

    _hookInstalled = true;
    topRoute.addLocalHistoryEntry(_HookEntry());
  }

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) {
    if (_topRoute == null) {
      _topRoute = route;
      _addHook();
    }
  }
}

/// Keeps a forwarding node reachable from a pop.
///
/// It makes the node's first page answer `willHandlePopInternally`, so a
/// `maybePop` lands in [NodeNavigatorState.pop] instead of bubbling straight
/// past the node — and it is what draws the back arrow in an `AppBar` on that
/// page. The entry is never removed: forwarding is decided in
/// [NodeNavigatorState.pop] rather than by spending this marker, so it works as
/// many times as the user presses back.
final class _HookEntry extends LocalHistoryEntry {}
