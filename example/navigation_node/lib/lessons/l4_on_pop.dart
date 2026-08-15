import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../journal.dart';
import '../lesson.dart';

/// Lesson 4: what happens once the node has nothing left of its own.
final onPopLesson = Lesson(
  title: '4. onPop: the last word',
  summary: 'Asked once, when the node has nothing of its own left to close',
  explanation: const [
    'While the node holds a page of its own, the back is spent inside and '
        'onPop never hears about it. Empty the node\'s stack and the next back '
        'is the one that would leave: that is when onPop is asked.',
    'Return false and the screen stays. Return true and the pop goes on '
        'outwards — here that closes the lesson and returns to the list. It is '
        'asked exactly once per press; the counter below says so.',
  ],
  instruction: 'press System back with the node empty and answer "Stay". Then '
      'push a page first and press again — onPop is not asked that time.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatefulWidget {
  const _Stage();

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  int _asked = 0;

  Future<bool> _onPop(BuildContext context, Object? result) async {
    setState(() => _asked++);

    final journal = JournalScope.of(context, listen: false)
      ..logNode('onPop was asked (call #$_asked)');

    final leave = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: const Text('Leave this lesson?'),
        content: const Text(
          'This dialog is what onPop returning a Future looks like: the route '
          'is held until you answer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    journal.logNode(
      (leave ?? false) ? 'onPop answered: leave' : 'onPop answered: stay',
    );

    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stage(
      label: 'NavigationNode(onPop: …)',
      isNode: true,
      child: NavigationNode(
        onPop: _onPop,
        child: NodeHome(
          title: 'first page of the node',
          child: Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'onPop asked $_asked ${_asked == 1 ? 'time' : 'times'}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                const PushButton(
                  label: 'Push a page inside first',
                  pageName: 'page inside the node',
                  builder: _buildPage,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildPage(BuildContext context) => const SamplePage(
        title: 'While this is here, onPop is not asked',
      );
}
