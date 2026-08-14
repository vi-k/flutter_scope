import 'package:flutter/material.dart';

import '../../../utils/console/console_view.dart';
import 'scope_example1.dart';
import 'scope_example2.dart';
import 'scope_example3.dart';

/// Rebuilds three asynchronous scope variants together so the console makes
/// their initialization and disposal ordering visible.
///
/// The variants compare no `scopeKey`, a shared `scopeKey`, and a keyed
/// parent with a child scope.
class ScopeDemo extends StatefulWidget {
  const ScopeDemo({super.key});

  @override
  State<ScopeDemo> createState() => _ScopeDemoState();
}

class _ScopeDemoState extends State<ScopeDemo> {
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
            child: ScopeExample1(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: ScopeExample1),
          ),
          Expanded(
            child: ScopeExample2(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: ScopeExample2),
          ),
          Expanded(
            child: ScopeExample3(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: ScopeExample3),
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
