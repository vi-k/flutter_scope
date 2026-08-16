import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo_demo/common/presentation/blinking_box.dart';

/// Lets `ScopeNotifierBase` create, listen to, and dispose a `ChangeNotifier`.
class ScopeNotifierExample1 extends StatelessWidget {
  const ScopeNotifierExample1({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(child: CounterScope());
  }
}

/// Notifies the scope whenever its selected count changes.
final class CounterModel with ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }
}

/// Owns the notifier through `create` and `dispose` and exposes command and
/// selector accessors.
final class CounterScope extends ScopeNotifierBase<CounterScope, CounterModel> {
  CounterScope({super.key})
      : super(
          create: (_) => CounterModel(),
          dispose: (model) => model.dispose(),
        );

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
    return Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$ScopeNotifierExample1'),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [_CounterView(), _IncrementAction()],
            ),
          ],
        ),
      ),
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
