import 'package:flutter/material.dart';

import '../../../utils/console/console_view.dart';
import 'async_controller_example1.dart';
import 'async_controller_example2.dart';
import 'async_controller_example3.dart';

/// Three controllers side by side, each on a different path out of the scope.
///
/// The first one is torn down after it was ready, the second one fails to
/// initialize, and the third one is abandoned in the middle of its
/// initialization. The consoles show that all three are unmounted and disposed
/// of -- the point of the family.
class AsyncControllerDemo extends StatefulWidget {
  const AsyncControllerDemo({super.key});

  @override
  State<AsyncControllerDemo> createState() => _AsyncControllerDemoState();
}

class _AsyncControllerDemoState extends State<AsyncControllerDemo> {
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
            child: AsyncControllerExample1(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncControllerExample1),
          ),
          Expanded(
            child: AsyncControllerExample2(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncControllerExample2),
          ),
          Expanded(
            child: AsyncControllerExample3(
              key: ValueKey(_rebuildCounter),
            ),
          ),
          const Expanded(
            child: ConsoleView(source: AsyncControllerExample3),
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
