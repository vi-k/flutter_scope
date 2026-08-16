import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';

/// Exposes a Flutter `State` as a notifier through `ScopeNotifier.value`.
class ScopeNotifierExample3 extends StatelessWidget {
  const ScopeNotifierExample3({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CounterScope());
  }
}

/// Provides typed access to the `StateAsNotifier` below it.
class CounterScope extends StatefulWidget {
  const CounterScope({super.key});

  static CounterScopeState of(BuildContext context) =>
      ScopeNotifier.of<CounterScopeState>(context, listen: false);

  static V select<V>(
    BuildContext context,
    V Function(CounterScopeState state) selector,
  ) =>
      ScopeNotifier.select<CounterScopeState, V>(context, selector);

  @override
  State<CounterScope> createState() => CounterScopeState();
}

/// Uses `notifyListeners` instead of `setState` so selectors decide what
/// rebuilds.
class CounterScopeState extends State<CounterScope> with StateAsNotifier {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    return ScopeNotifier.value(
      value: this,
      builder: (context) => Center(
        child: BlinkingBox(
          blinkingColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$ScopeNotifierExample3'),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [_CounterView(), _IncrementAction()],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CounterView extends StatelessWidget {
  const _CounterView();

  @override
  Widget build(BuildContext context) {
    final count = CounterScope.select<int>(context, (state) => state.count);
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
