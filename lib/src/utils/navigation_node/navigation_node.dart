import 'dart:async';

import 'package:flutter/foundation.dart';
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
  /// The `context` is one from inside the node, so `Navigator.of(context)` is
  /// the nested navigator and a dialog opened with `useRootNavigator: false`
  /// belongs to the node — which is the point of asking here rather than
  /// anywhere else: what the node stands under is above that dialog too.
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

  /// Whether the node is standing aside while it asks the route it stands on
  /// what a pop there would do. Raised for the length of one read.
  bool _forwarding = false;

  /// Whether an [NavigationNode.onPop] is still deciding about a press.
  bool _deciding = false;

  NodeNavigatorState get _navigator => _navigatorKey.currentState!;

  /// The page list the nested navigator is handed, kept rather than rebuilt.
  ///
  /// [NavigatorState.didUpdateWidget] compares the list it was given by
  /// identity, so a fresh one on every build makes the navigator diff its stack
  /// and report it again for a page that has not changed. What the page is made
  /// of is [NavigationNode.child] and [NavigationNode.isRoot]; while those stay
  /// the same objects — a `const` subtree, or one an application holds in a
  /// field — a rebuild of the node hands over nothing new.
  late List<Page<void>> _pages = _buildPages();

  List<Page<void>> _buildPages() => [
        _NodePage(child: widget.child, leavesTheNode: !widget.isRoot),
      ];

  /// The node's navigator never removes the node's own page, and the pages API
  /// asks for the callback all the same. A method rather than a closure in
  /// `build`, for the same reason [_pages] is a field.
  static void _onDidRemovePage(Page<Object?> page) {}

  @override
  void didUpdateWidget(NavigationNode oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!identical(widget.child, oldWidget.child) ||
        widget.isRoot != oldWidget.isRoot) {
      _pages = _buildPages();
    }
  }

  /// Whether the nested navigator has something of its own to close.
  ///
  /// Asked, never remembered. What it answers about is the local history of the
  /// route the node stands on as much as the stack above it — a `Drawer`, a
  /// bottom sheet, an `addLocalHistoryEntry` of the application's own — and
  /// none of those tell anybody they happened: `LocalHistoryRoute
  /// .addLocalHistoryEntry` ends in `changedInternalState`, which marks the
  /// route dirty and dispatches no notification. A remembered answer is
  /// therefore an answer from before the drawer opened.
  bool get _handlesBackInside {
    final navigator = _navigatorKey.currentState;

    return navigator != null && navigator.mounted && navigator.canPop();
  }

  /// Decides what a system back does once the node itself cannot answer it.
  ///
  /// Refusing takes no undoing: nothing has been spent to get here, so the next
  /// press arrives exactly as this one did.
  ///
  /// [outerContext] is the node's own, from above the nested navigator. It is
  /// what the route the node stands on is found from, and it is not what the
  /// hook is given: a dialog opened from there with `useRootNavigator: false`
  /// would land on the navigator of the application, above everything the node
  /// exists to stay below.
  void _decideOutside(BuildContext outerContext, Object? result) {
    // A decision already under way is the answer to this press too. Nothing
    // queues: a second back while a confirmation is on screen must not ask a
    // second time, and two answers of `true` must not take two routes.
    if (_deciding || _navigator.previous == null) {
      return;
    }

    // ignore: discarded_futures
    switch (widget.onPop?.call(_navigator.context, result)) {
      case final Future<bool> future:
        _deciding = true;
        final route = ModalRoute.of(outerContext);

        // Anything in the chain below that falls over -- the question itself, a
        // confirmation dialog raising, or the pop, which runs user code of its
        // own as the route goes -- fails where nobody is waiting, and the
        // failure then surfaces as an unhandled zone error far from the widget
        // that caused it. Reported instead, the way the package reports
        // everything it cannot re-throw. The press is simply not acted on, and
        // `whenComplete` has already cleared the way for the next one.
        //
        // The handler is `onError` on the chain, not the `onError` of `then`:
        // that one answers for the future it is chained to and not for the
        // callback beside it, so the pop's own failures went unheld.
        unawaited(
          future.whenComplete(() => _deciding = false).then((canPop) {
            // The world does not wait for an answer. The route the node
            // sits on may have been closed by something else, or buried
            // under a newer one -- and a pop would then take whatever is on
            // top instead of what was asked about. A node that is gone
            // answers for itself: its key resolves to nothing, which is why
            // the walk below is null-safe and no `mounted` check is needed
            // on top of it.
            if (!canPop || (route != null && !route.isCurrent)) {
              return;
            }

            _popOutside(route, result);
          }).onError<Object>((error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'scopo',
                context: ErrorDescription(
                  'while deciding what a system back does in a '
                  'NavigationNode',
                ),
              ),
            );
          }),
        );
      case final bool? canPop:
        if (canPop ?? true) {
          _popOutside(ModalRoute.of(outerContext), result);
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
  /// Handing over is asking, not taking. [NavigatorState.pop] takes the last
  /// route it holds and asks nobody, so this used to walk past a [PopScope] the
  /// application had put around the node, and to empty the application's own
  /// navigator when the node stood on its first route — a blank screen, and an
  /// assertion of the framework on the frame after it. Asking [route] what a
  /// pop there would do settles both, and asking is all it does: reading
  /// [ModalRoute.popDisposition] dispatches nothing, where a `maybePop` would
  /// report a refusal of its own to every [PopScope] on that route.
  void _popOutside(ModalRoute<dynamic>? route, Object? result) {
    if (widget.isRoot) {
      return;
    }

    final previous = _navigatorKey.currentState?.previous;
    if (previous == null || route == null) {
      return;
    }

    // The route is asked rather than told, and it is asked with the node's own
    // answer stood aside -- the node's entry is registered on this very route,
    // and it has already had its say. What is left is what the node has no
    // business answering for itself: a `PopScope` the application put around
    // the node, and whether there is a route to give up at all. `maybePop`
    // would ask the same question by telling the route the pop was refused,
    // and the application would then hear one press as two.
    final RoutePopDisposition disposition;

    _forwarding = true;
    try {
      disposition = route.popDisposition;
    } finally {
      // Stepping aside lasts one read, whatever that read does. Reading a route
      // means reading every guard on it, which is user code: one that falls over
      // used to leave the node aside for good, and every later press then took
      // the whole route without the node being asked at all.
      _forwarding = false;
    }

    if (disposition == RoutePopDisposition.pop) {
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
        pages: _pages,
        onDidRemovePage: _onDidRemovePage,
      ),
    );
  }
}

/// Sends a system back to the navigator below before anything outside sees it.
///
/// It is a [PopEntry] of its own rather than a [PopScope] because the answer a
/// [PopScope] gives is the one its `canPop` had when it was last built, and the
/// question is asked at moments no build of this subtree is tied to. A drawer
/// opening inside the node is the plain case: the route the node stands on
/// gains a local history entry, nothing is dispatched and nothing rebuilds, and
/// a remembered `true` then lets the whole route go instead of closing the
/// drawer. A [PopEntry] is read at the moment [ModalRoute.popDisposition] asks,
/// which is when the node can still answer correctly.
///
/// It also lives in a widget of its own so that what it keeps never rebuilds
/// the nested navigator: a rebuild would hand that navigator a fresh page list,
/// which makes it report its stack again.
final class _NodeBackDispatcher extends StatefulWidget {
  final _NavigationNodeState node;
  final Widget child;

  const _NodeBackDispatcher({required this.node, required this.child});

  @override
  State<_NodeBackDispatcher> createState() => _NodeBackDispatcherState();
}

final class _NodeBackDispatcherState extends State<_NodeBackDispatcher>
    implements PopEntry<Object?> {
  /// Whether something below the node refuses a pop of its own accord.
  ///
  /// Kept from [NavigationNotification], which is dispatched when a nested
  /// navigator's stack changes and when a [PopScope] below registers or changes
  /// its answer — including navigators deeper than this node's own, so a node
  /// nested in another node is heard here too. This is the half the node cannot
  /// work out by asking its own navigator, and it is the half that does get
  /// announced.
  bool _innerCanPop = false;

  ModalRoute<dynamic>? _route;

  @override
  late final _NodeCanPopOutside canPopNotifier = _NodeCanPopOutside(this);

  /// Whether a system back arriving at the route this node stands on is none of
  /// the node's business.
  bool get _canPopOutside =>
      widget.node._forwarding ||
      (widget.node.widget.onPop == null &&
          !_innerCanPop &&
          !widget.node._handlesBackInside);

  @override
  void onPopInvoked(bool didPop) => throw UnimplementedError();

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop || widget.node._forwarding) {
      return;
    }

    if (_innerCanPop || widget.node._handlesBackInside) {
      // The pop belongs to the navigator below, and only that navigator knows
      // whether its top route accepts it. Nothing outside the node moves, so
      // onPop and isRoot stay out of this.
      // ignore: discarded_futures
      widget.node._navigator._popInside(result);

      return;
    }

    widget.node._decideOutside(context, result);
  }

  bool _watchInnerStack(NavigationNotification notification) {
    if (notification.canHandlePop != _innerCanPop) {
      _innerCanPop = notification.canHandlePop;
      canPopNotifier.notifyOfChange();
    }

    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(this);
      _route = nextRoute;
      _route?.registerPopEntry(this);
    }
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    _route = null;
    canPopNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<NavigationNotification>(
        onNotification: _watchInnerStack,
        child: widget.child,
      );
}

/// The answer a [_NodeBackDispatcher] gives, worked out when it is asked.
///
/// A [ValueNotifier] would hold an answer instead, and the node has no moment
/// at which to write one: what the answer depends on changes without telling
/// anybody. Listeners are still notified of what the node does hear about, so
/// that the framework's own idea of who handles the back gesture keeps up.
final class _NodeCanPopOutside extends ChangeNotifier
    implements ValueListenable<bool> {
  final _NodeBackDispatcherState _dispatcher;

  _NodeCanPopOutside(this._dispatcher);

  @override
  bool get value => _dispatcher._canPopOutside;

  void notifyOfChange() => notifyListeners();
}

/// The single page a node starts with.
///
/// It answers [ModalRoute.impliesAppBarDismissal] for itself, so that an
/// `AppBar` on the node's first page draws a back arrow even though the page is
/// the first of its navigator: pressing it leaves the node, which is somewhere
/// to go. The node used to say the same thing with a [LocalHistoryEntry] on the
/// route, and that cost it the ability to tell its own marker from a `Drawer`'s
/// — both are entries in the same list, and a route reports only whether that
/// list is empty.
final class _NodePage extends MaterialPage<void> {
  /// Whether a pop of this page goes on to the navigator above.
  final bool leavesTheNode;

  const _NodePage({required super.child, required this.leavesTheNode});

  @override
  Route<void> createRoute(BuildContext context) => _NodePageRoute(this);
}

final class _NodePageRoute extends PageRoute<void>
    with MaterialRouteTransitionMixin<void> {
  _NodePageRoute(_NodePage page) : super(settings: page);

  _NodePage get _page => settings as _NodePage;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  bool get impliesAppBarDismissal =>
      _page.leavesTheNode || super.impliesAppBarDismissal;
}

final class _NodeNavigator extends Navigator {
  final _NavigationNodeState node;

  const _NodeNavigator({
    super.key,
    required this.node,
    super.pages,
    super.onDidRemovePage,
  });

  @override
  NavigatorState createState() => NodeNavigatorState._();
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
  /// Made by the node, never by hand.
  ///
  /// The type is public because a `navigatorKey` is written with it and resolves
  /// to it, and everything else about it is a [NavigatorState]. What it needs is
  /// the widget a [NavigationNode] builds: that is where it reads the node from,
  /// and installed under any other `Navigator` it would fail on the first pop
  /// instead of at the line where the mistake was made. Nothing outside this
  /// library can put it there.
  NodeNavigatorState._();

  _NavigationNodeState get _node => (widget as _NodeNavigator).node;

  /// Asks this navigator and nothing else.
  ///
  /// [maybePop] leaves the node when the node has nothing of its own to close,
  /// which is what a caller wants and what the back arrow of an `AppBar` on the
  /// first page does. The node itself needs the other half of that answer — did
  /// anything below take the press — before it decides what happens outside.
  // ignore: discarded_futures
  Future<bool> _popInside(Object? result) => super.maybePop(result);

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
    if (!_node.widget.isRoot) {
      // ignore: discarded_futures
      previous?.maybePop(result);
    }
  }

  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async {
    if (await super.maybePop(result)) {
      return true;
    }

    // The base implementation has just said that the first page of the node has
    // nothing to give up and nobody below refuses — which for an ordinary
    // navigator is where a pop stops. For a node it is where it leaves: the way
    // out is the navigator above, and this is the path the back arrow of an
    // `AppBar` takes.
    if (_node.widget.isRoot) {
      return false;
    }

    final previous = this.previous;

    return previous != null && await previous.maybePop(result);
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
