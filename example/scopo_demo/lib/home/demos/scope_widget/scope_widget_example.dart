import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';

/// Demonstrates `ScopeWidgetBase` exposing a value owned and updated by the
/// parent widget.
class ScopeWidgetExample extends StatefulWidget {
  const ScopeWidgetExample({super.key});

  @override
  State<ScopeWidgetExample> createState() => _ScopeWidgetExampleState();
}

class _ScopeWidgetExampleState extends State<ScopeWidgetExample> {
  var _count = 0;

  void _increment() {
    setState(() {
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$ScopeWidgetExample'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CounterScope(count: _count),
                IconButton(
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _increment,
                  icon: const Icon(Icons.add_circle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Exposes the current widget parameter and lets only dependents whose selected
/// value changed rebuild.
final class CounterScope extends ScopeWidgetBase<CounterScope> {
  final int count;

  const CounterScope({super.key, required this.count});

  static int countOf(BuildContext context) =>
      ScopeWidgetBase.select<CounterScope, int>(
        context,
        (widget) => widget.count,
      );

  @override
  Widget build(BuildContext context) {
    return const _CounterView();
  }
}

class _CounterView extends StatelessWidget {
  const _CounterView();

  @override
  Widget build(BuildContext context) {
    final count = CounterScope.countOf(context);
    return Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Text('$count'),
      ),
    );
  }
}
