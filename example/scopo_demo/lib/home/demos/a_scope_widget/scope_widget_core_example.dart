import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';
import 'package:scopo_demo/common/presentation/blinking_box.dart';

/// Demonstrates `ScopeWidgetCore` with mutable state stored in its custom
/// element.
class ScopeWidgetCoreExample extends StatelessWidget {
  const ScopeWidgetCoreExample({super.key});

  @override
  Widget build(BuildContext context) => const CounterScope();
}

/// Publishes a narrow command context through `of` and a selectively watched
/// count through `countOf`.
final class CounterScope
    extends ScopeWidgetCore<CounterScope, CounterScopeElement> {
  const CounterScope({super.key});

  static CounterScopeContext of(BuildContext context) =>
      ScopeWidgetCore.of<CounterScope, CounterScopeElement>(
        context,
        listen: false,
      );

  static int countOf(BuildContext context) =>
      ScopeWidgetCore.select<CounterScope, CounterScopeElement, int>(
        context,
        (element) => element.count,
      );

  Widget build(BuildContext context) => Center(
        child: BlinkingBox(
          blinkingColor: Theme.of(
            context,
          ).colorScheme.primary.withValues(alpha: 0.2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$ScopeWidgetCoreExample'),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [_CounterView(), _IncrementAction()],
              ),
            ],
          ),
        ),
      );

  @override
  CounterScopeElement createScopeElement() => CounterScopeElement(this);
}

/// The command-facing interface exposed to descendants without revealing the
/// element implementation.
abstract interface class CounterScopeContext {
  int get count;
  void increment();
}

/// Owns the count for the lifetime of the mounted scope and notifies selector
/// dependents after each increment.
final class CounterScopeElement
    extends ScopeWidgetElementBase<CounterScope, CounterScopeElement>
    implements CounterScopeContext {
  CounterScopeElement(super.widget);

  int _count = 0;

  @override
  int get count => _count;

  @override
  Widget buildChild() => widget.build(this);

  @override
  void increment() {
    _count++;
    // Re-evaluate selectors after the element-owned value changes.
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
        blinkingColor: Theme.of(
          context,
        ).colorScheme.primary.withValues(alpha: 0.2),
        child: Text('$count'),
      ),
    );
  }
}

class _IncrementAction extends StatelessWidget {
  const _IncrementAction();

  @override
  Widget build(BuildContext context) => IconButton(
        color: Theme.of(context).colorScheme.primary,
        onPressed: CounterScope.of(context).increment,
        icon: const Icon(Icons.add_circle),
      );
}
