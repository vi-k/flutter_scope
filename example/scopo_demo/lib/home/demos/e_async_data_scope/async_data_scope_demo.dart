import 'package:flutter/material.dart';

import '../../../utils/console/console_view.dart';
import 'async_data_scope_example1.dart';
import 'async_data_scope_example2.dart';
import 'async_data_scope_example3.dart';

/// Rebuilds three asynchronous scope variants together so the console makes
/// their initialization and disposal ordering visible.
///
/// The variants compare no `scopeKey`, a shared `scopeKey`, and a keyed
/// parent with a child scope.
class AsyncDataScopeDemo extends StatefulWidget {
  const AsyncDataScopeDemo({super.key});

  @override
  State<AsyncDataScopeDemo> createState() => _AsyncDataScopeDemoState();
}

class _AsyncDataScopeDemoState extends State<AsyncDataScopeDemo> {
  var _rebuildCounter = 0;

  void _rebuild() {
    setState(() {
      _rebuildCounter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!,
      child: Column(
        children: [
          Expanded(
            child: AsyncDataScopeExample1(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncDataScopeExample1),
          ),
          Expanded(
            child: AsyncDataScopeExample2(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncDataScopeExample2),
          ),
          Expanded(
            child: AsyncDataScopeExample3(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncDataScopeExample3),
          ),
          _RebuildButton(rebuild: _rebuild),
        ],
      ),
    );
  }
}

class _RebuildButton extends StatelessWidget {
  final void Function() rebuild;

  const _RebuildButton({required this.rebuild});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: FilledButton(
        onPressed: rebuild,
        child: const Text('Restart page'),
      ),
    );
  }
}
