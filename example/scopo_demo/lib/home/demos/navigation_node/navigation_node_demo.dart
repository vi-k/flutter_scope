import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'child_screen.dart';
import 'counter_scope.dart';
import 'counter_view.dart';

/// Places identical route use cases beside each other with and without a
/// local `NavigationNode` under the counter scope.
class NavigationNodeDemo extends StatelessWidget {
  const NavigationNodeDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!,
      child: Column(
        children: [
          const Expanded(
            child: Center(child: CounterView()),
          ),
          const Divider(),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Expanded(
                  child: CounterScope(
                    tag: 'w/o node',
                    title: 'Local counter w/o navigation node',
                    child: const Center(
                      child: _CounterAndUsecases(),
                    ),
                  ),
                ),
                const VerticalDivider(),
                Expanded(
                  child: CounterScope(
                    tag: 'with node',
                    title: 'Local counter with navigation node',
                    child: const NavigationNode(
                      child: Center(
                        child: _CounterAndUsecases(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterAndUsecases extends StatelessWidget {
  const _CounterAndUsecases();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CounterView(),
        _Usecases(),
      ],
    );
  }
}

class _Usecases extends StatelessWidget {
  const _Usecases();

  Future<void> _openDialog(BuildContext context) => showAdaptiveDialog<void>(
        // Use the nearest navigator; only a local NavigationNode keeps the
        // dialog under the local counter scope.
        useRootNavigator: false,
        context: context,
        barrierDismissible: true,
        builder: (context) {
          return Dialog(
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surface.withValues(alpha: 0.7),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppBar(title: const Text('Dialog'), primary: false),
                  const SizedBox(height: 20),
                  const CounterView(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      );

  Future<void> _openBottomSheet(BuildContext context) => showModalBottomSheet(
        context: context,
        clipBehavior: Clip.antiAlias,
        builder: (context) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(title: const Text('Bottom sheet')),
                const SizedBox(height: 20),
                const CounterView(),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => _openDialog(context),
          child: const Text('Dialog'),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () => _openBottomSheet(context),
          child: const Text('Bottom sheet'),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const ChildScreen(withNode: true),
              ),
            );
          },
          child: const Text('Child screen'),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
