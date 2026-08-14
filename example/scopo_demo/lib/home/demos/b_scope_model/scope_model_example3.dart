import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo_demo/common/presentation/blinking_box.dart';

/// Exposes a regular Flutter `State` through `ScopeModel.value`.
class ScopeModelExample3 extends StatelessWidget {
  const ScopeModelExample3({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CounterScope());
  }
}

/// Provides typed `of` and `select` accessors for `CounterScopeState`.
class CounterScope extends StatefulWidget {
  const CounterScope({super.key});

  static CounterScopeState of(BuildContext context) =>
      ScopeModel.of<CounterScopeState>(context, listen: false);

  static V select<V>(
    BuildContext context,
    V Function(CounterScopeState state) selector,
  ) =>
      ScopeModel.select<CounterScopeState, V>(context, selector);

  @override
  State<CounterScope> createState() => CounterScopeState();
}

/// Owns the count as normal Flutter state and publishes itself as the scoped
/// model.
class CounterScopeState extends State<CounterScope> {
  int _count = 0;
  int get count => _count;

  void increment() {
    setState(() {
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScopeModel.value(
      value: this,
      builder: (context) => Center(
        child: BlinkingBox(
          blinkingColor:
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$ScopeModelExample3'),
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
