import 'package:flutter/material.dart';

import '../../../common/presentation/blinking_box.dart';
import 'counter_scope.dart';

/// Reads and updates the nearest tagged counter from both the original
/// subtree and routes pushed by the local navigator.
class CounterView extends StatelessWidget {
  const CounterView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          CounterScope.titleOf(context),
          textAlign: TextAlign.center,
        ),
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [_CounterView(), _IncrementAction()],
        ),
      ],
    );
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

class _IncrementAction extends StatelessWidget {
  const _IncrementAction();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      color: Theme.of(context).colorScheme.primary,
      onPressed: CounterScope.of(context).increment,
      icon: const Icon(Icons.add_circle),
    );
  }
}
