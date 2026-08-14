import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';

/// Uses `ScopeNotifierCore` to keep the concrete notifier private behind a
/// narrow interface.
class ScopeNotifierExample2 extends StatelessWidget {
  const ScopeNotifierExample2({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CounterScope());
  }
}

/// The public `Listenable` contract exposed without the concrete notifier type.
abstract interface class CounterModel implements Listenable {
  int get count;

  void increment();
}

final class _CounterModelImpl with ChangeNotifier implements CounterModel {
  int _count = 0;

  @override
  int get count => _count;

  @override
  void increment() {
    _count++;
    notifyListeners();
  }
}

/// Returns the interface from `of` while its custom element retains the
/// implementation.
final class CounterScope
    extends ScopeNotifierCore<CounterScope, CounterScopeElement, CounterModel> {
  const CounterScope({super.key});

  // ignore: unused_element
  static _CounterModelImpl _of(BuildContext context) =>
      ScopeNotifierCore.of<CounterScope, CounterScopeElement, CounterModel>(
        context,
        listen: false,
      )._model;

  static CounterModel of(BuildContext context) =>
      ScopeNotifierCore.of<CounterScope, CounterScopeElement, CounterModel>(
        context,
        listen: false,
      ).model;

  static int countOf(BuildContext context) => ScopeNotifierCore.select<
      CounterScope,
      CounterScopeElement,
      CounterModel,
      int>(context, (context) => context.model.count);

  static V select<V>(
    BuildContext context,
    V Function(ScopeModelContext<CounterScope, CounterModel> context) selector,
  ) =>
      ScopeNotifierCore.select<CounterScope, CounterScopeElement, CounterModel,
          V>(context, (context) => selector(context));

  Widget build(BuildContext context) {
    return Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$ScopeNotifierExample2'),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [_CounterView(), _IncrementAction()],
            ),
          ],
        ),
      ),
    );
  }

  @override
  CounterScopeElement createScopeElement() => CounterScopeElement(this);
}

/// Owns the notifier and unsubscribes the scope from it before disposing it.
final class CounterScopeElement extends ScopeNotifierElementBase<CounterScope,
    CounterScopeElement, CounterModel> {
  final _CounterModelImpl _model = _CounterModelImpl();

  CounterScopeElement(super.widget);

  @override
  CounterModel get model => _model;

  @override
  void dispose() {
    // Unsubscribe the scope from the notifier before disposing it.
    super.dispose();
    _model.dispose();
  }

  @override
  Widget buildChild() => widget.build(this);
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
