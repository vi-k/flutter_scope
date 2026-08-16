import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo_demo/common/presentation/blinking_box.dart';

/// Lets a `ScopeModelCore` element create, own, and expose a plain model.
class ScopeModelExample2 extends StatelessWidget {
  const ScopeModelExample2({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CounterScope());
  }
}

/// The plain model kept inside `CounterScopeElement` for the element lifetime.
final class CounterModel {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
  }
}

/// Separates commands through `of` from selective reads through `countOf`.
final class CounterScope
    extends ScopeModelCore<CounterScope, CounterScopeElement, CounterModel> {
  const CounterScope({super.key});

  static CounterScopeContext of(BuildContext context) =>
      ScopeModelCore.of<CounterScope, CounterScopeElement, CounterModel>(
        context,
        listen: false,
      );

  static int countOf(BuildContext context) => ScopeModelCore.select<
      CounterScope,
      CounterScopeElement,
      CounterModel,
      int>(context, (element) => element.model.count);

  Widget build(BuildContext context) {
    return Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$ScopeModelExample2'),
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

/// The public model-and-command surface implemented by the custom element.
abstract interface class CounterScopeContext {
  CounterModel get model;
  void increment();
}

/// Owns the model and explicitly notifies dependents after mutating it.
final class CounterScopeElement extends ScopeModelElementBase<CounterScope,
    CounterScopeElement, CounterModel> implements CounterScopeContext {
  CounterScopeElement(super.widget);

  @override
  final CounterModel model = CounterModel();

  @override
  Widget buildChild() => widget.build(this);

  @override
  void increment() {
    model.increment();
    // A plain model cannot notify the scope, so the owning element does it.
    notifyDependents();
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
