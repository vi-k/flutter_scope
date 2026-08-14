import 'package:flutter/material.dart';

import '../../../utils/console/console_view.dart';
import 'async_scope_example1.dart';
import 'async_scope_example2.dart';
import 'async_scope_example3.dart';

/// Rebuilds three asynchronous scope variants together so the console makes
/// their initialization and disposal ordering visible.
///
/// The variants compare no `scopeKey`, a shared `scopeKey`, and a keyed
/// parent with a child scope.
class AsyncScopeDemo extends StatefulWidget {
  const AsyncScopeDemo({super.key});

  @override
  State<AsyncScopeDemo> createState() => _AsyncScopeDemoState();
}

class _AsyncScopeDemoState extends State<AsyncScopeDemo> {
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
            child: AsyncScopeExample1(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncScopeExample1),
          ),
          Expanded(
            child: AsyncScopeExample2(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncScopeExample2),
          ),
          Expanded(
            child: AsyncScopeExample3(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncScopeExample3),
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
