import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo_demo/common/presentation/blinking_box.dart';

/// A plain mutable value whose owner is responsible for rebuilding the scope
/// widget.
final class CounterModel {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
  }
}

/// Passes a parent-owned `CounterModel` through `ScopeModelBase.value`.
class ScopeModelExample1 extends StatefulWidget {
  const ScopeModelExample1({super.key});

  @override
  State<ScopeModelExample1> createState() => _ScopeModelExample1State();
}

class _ScopeModelExample1State extends State<ScopeModelExample1> {
  final _model = CounterModel();

  void _increment() {
    setState(_model.increment);
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
            Text('$ScopeModelExample1'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CounterScope(model: _model),
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

/// Selects the count from the externally owned model without taking over its
/// lifecycle.
final class CounterScope extends ScopeModelBase<CounterScope, CounterModel> {
  const CounterScope({super.key, required CounterModel model})
      : super.value(value: model);

  static int countOf(BuildContext context) =>
      ScopeModelBase.select<CounterScope, CounterModel, int>(
        context,
        (context) => context.model.count,
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
