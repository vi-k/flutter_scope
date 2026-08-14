import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

/// Exercises a parent rebuild and a notifier update in the same callback.
/// The widget parameter and notifier value update their own dependents.
class ScopeNotifierExample1Special extends StatefulWidget {
  const ScopeNotifierExample1Special({super.key});

  @override
  State<ScopeNotifierExample1Special> createState() =>
      _ScopeNotifierExample1SpecialState();
}

class _ScopeNotifierExample1SpecialState
    extends State<ScopeNotifierExample1Special> {
  var _counter = 0;

  void _increment() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(child: CounterScope(_increment, _counter));
  }
}

final class CounterModel with ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }
}

final class CounterScope extends ScopeNotifierBase<CounterScope, CounterModel> {
  final int _counter;
  final void Function() _increment;

  CounterScope(this._increment, this._counter, {super.key})
    : super(create: (_) => CounterModel(), dispose: (model) => model.dispose());

  static CounterModel of(BuildContext context) =>
      ScopeNotifierBase.of<CounterScope, CounterModel>(
        context,
        listen: false,
      ).model;

  static int countOf(BuildContext context) =>
      ScopeNotifierBase.select<CounterScope, CounterModel, int>(
        context,
        (context) => context.model.count,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$ScopeNotifierExample1Special'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_counter.toString()),
            FilledButton(
              onPressed: () {
                CounterScope.of(context).increment();
                _increment();
              },
              child: const Text('Increment'),
            ),
            const _CounterView(),
            const _IncrementAction(),
          ],
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
    return Center(child: Text('$count'));
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
