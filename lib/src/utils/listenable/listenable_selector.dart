import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'listen.dart';

/// A widget that rebuilds when a value selected from a `Listenable` changes.
///
/// See [ListenableSelectExtension.select].
///
/// {@category utils}
class ListenableSelector<L extends Listenable, T extends Object?>
    extends StatefulWidget {
  /// The listenable being watched.
  final L listenable;

  /// Extracts the value this widget rebuilds for.
  final T Function(L listenable) selector;

  /// Decides whether the selected value changed; `==` when omitted.
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

class _ListenableSelectorState<L extends Listenable, T extends Object?>
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

    if (widget.listenable != oldWidget.listenable) {
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
