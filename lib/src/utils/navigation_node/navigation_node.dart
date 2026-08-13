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

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: widget.onPop == null,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;

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
        },
        child: _NodeNavigator(
          key: _navigatorKey,
          node: this,
          pages: [MaterialPage<void>(child: widget.child)],
          onDidRemovePage: (_) {},
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

  _NodeNavigatorObserver(this.node);

  void _addHook() {
    final topRoute = _topRoute;
    if (!node.widget.isRoot && topRoute is ModalRoute<void>) {
      topRoute.addLocalHistoryEntry(
        _HookEntry(
          onRemove: () {
            // ignore: discarded_futures
            navigator?.previous?.maybePop(node._navigator._interceptedResult);
          },
        ),
      );
    }
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
