import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'listen.dart';

/// A widget that rebuilds when a value selected from a `Listenable` changes.
///
/// See [ListenableSelectExtension.select].
///
/// {@category utils}
final class ListenableSelector<L extends Listenable, T extends Object?>
    extends StatefulWidget {
  /// The listenable being watched.
  final L listenable;

  /// Extracts the value this widget rebuilds for.
  ///
  /// Compared by identity when the parent rebuilds, and it has to be: a new
  /// selector may select something else, and there is no way to ask one
  /// closure whether it does what another did. The shape the examples show —
  /// an inline `(model) => model.value` — is therefore a different object on
  /// every build of the parent, so each of those rebuilds cancels the
  /// subscription and takes a new one: one `removeListener`, one
  /// `addListener` and one call of the selector. That is small, and it is not
  /// nothing. Hold the selector in a field or a `static` where the parent
  /// rebuilds often and the listenable does not change.
  final T Function(L listenable) selector;

  /// Decides whether the selected value changed; `!=` when omitted.
  ///
  /// `true` means changed, so the comparison for a value that is replaced
  /// rather than mutated is `CompareUtils.notIdentical`.
  final bool Function(T previous, T current)? compare;

  /// Builds the subtree from the selected value.
  final Widget Function(
    BuildContext context,
    L listenable,
    T value,
    Widget? child,
  ) builder;

  /// Passed back to [builder] untouched, to keep a subtree out of the
  /// rebuild.
  final Widget? child;

  /// Creates a builder that responds to [selector] changes in [listenable].
  const ListenableSelector({
    super.key,
    required this.listenable,
    required this.selector,
    this.compare,
    required this.builder,
    this.child,
  });

  @override
  State<ListenableSelector> createState() => _ListenableSelectorState<L, T>();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Listenable>('listenable', listenable));
  }
}

final class _ListenableSelectorState<L extends Listenable, T extends Object?>
    extends State<ListenableSelector<L, T>> {
  late ListenableSelectSubscription<T> _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(ListenableSelector<L, T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    // The selector and the compare are as much a part of what this widget
    // watches as the listenable is: a parent that hands over a new one is
    // asking for something else to be selected, or for a different answer to
    // "did it change?". Replacing them only together with the source left the
    // state calling the closures of a configuration nobody passes any more.
    // The old subscription goes first, and deliberately so. Subscribing into a
    // temporary before cancelling reads better and behaves worse: `select`
    // reads the value at once, and a selector that raises there would leave the
    // old listener on a listenable the widget no longer watches -- pointing
    // into an element the framework abandons as it replaces this subtree with
    // an error widget. Checked by probe: with the order reversed the listenable
    // still reports a listener afterwards; with this order it reports none.
    //
    // What the raise does leave is a field pointing at a cancelled
    // subscription. Nothing reaches it: the abandoned state is never updated
    // and never disposed of, and the next configuration builds a fresh one.
    if (!identical(widget.listenable, oldWidget.listenable) ||
        !identical(widget.selector, oldWidget.selector) ||
        !identical(widget.compare, oldWidget.compare)) {
      _subscription.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.listenable.select(
      widget.selector,
      (_, __) {
        if (mounted) {
          setState(() {});
        }
      },
      compare: widget.compare,
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        widget.listenable,
        _subscription.value,
        widget.child,
      );
}
