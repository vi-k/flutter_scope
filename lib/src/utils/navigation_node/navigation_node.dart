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
  final GlobalKey<NodeNavigatorState>? navigatorKey;

  /// Intercepts the system back gesture.
  ///
  /// Return `true` to let the pop through, `false` to keep the route, or a
  /// [Future] to decide after asking — a confirmation dialog, usually. The
  /// `result` is what the popped route would have returned.
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
  late final _navigatorKey =
      widget.navigatorKey ?? GlobalKey<NodeNavigatorState>();
  late final _observer = _NodeNavigatorObserver(this);

  NodeNavigatorState get _navigator => _navigatorKey.currentState!;

  /// Decides what a system back does once the node itself cannot answer it.
  void _decideOutside(BuildContext context, Object? result) {
    void restoreMarker() {
      _observer._addHook();
    }

    if (_navigator.previous case final previous?) {
      // ignore: discarded_futures
      switch (widget.onPop?.call(context, result)) {
        case final Future<bool> future:
          // ignore: discarded_futures
          future.then((canPop) {
            if (canPop) {
              previous.pop(result);
            } else {
              restoreMarker();
            }
          });
        case final bool? canPop:
          if (canPop ?? true) {
            previous.pop(result);
          } else {
            restoreMarker();
          }
      }
    }
  }

  @override
  Widget build(BuildContext context) => _NodeBackDispatcher(
        node: this,
        child: _NodeNavigator(
          key: _navigatorKey,
          node: this,
          pages: [MaterialPage<void>(child: widget.child)],
          onDidRemovePage: (_) {},
        ),
      );
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

/// @nodoc
final class NodeNavigatorState extends NavigatorState {
  Object? _interceptedResult;

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
    _interceptedResult = result;
    super.pop(result);
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
    topRoute.addLocalHistoryEntry(
      _HookEntry(
        onRemove: () {
          _hookInstalled = false;
          // ignore: discarded_futures
          navigator?.previous?.maybePop(node._navigator._interceptedResult);
        },
      ),
    );
  }

  @override
  void didPush(Route<void> route, Route<void>? previousRoute) {
    if (_topRoute == null) {
      _topRoute = route;
      _addHook();
    }
  }
}

final class _HookEntry extends LocalHistoryEntry {
  _HookEntry({required super.onRemove});
}
