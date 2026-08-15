import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../journal.dart';
import '../lesson.dart';
import '../system_back.dart';

/// Lesson 2: a dialog is a route too, and the node closes it first.
final dialogInsideLesson = Lesson(
  title: '2. A dialog is a route too',
  summary: 'showDialog with useRootNavigator: false belongs to the node',
  explanation: const [
    'showDialog pushes a route like any other, and by default it pushes it on '
        'the application\'s Navigator — above the node, out of its reach.',
    'Pass useRootNavigator: false and the dialog goes to the nearest Navigator '
        'instead, which is the node\'s. The system back then closes the dialog '
        'and stops there, leaving the screen underneath alone.',
  ],
  instruction: 'open both dialogs in turn and close each one with System back. '
      'Watch the line above the journal: it says whether anything inside can '
      'still take a back.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) => Stage(
        label: 'NavigationNode',
        isNode: true,
        child: NavigationNode(
          child: Builder(
            builder: (context) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.tonal(
                    onPressed: () => _open(context, useRootNavigator: false),
                    child: const Text('Dialog in the node'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _open(context, useRootNavigator: true),
                    child: const Text('Dialog on the application'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  void _open(BuildContext context, {required bool useRootNavigator}) {
    final where = useRootNavigator ? 'on the application' : 'in the node';
    final journal = JournalScope.of(context, listen: false)
      ..log('opened a dialog $where');

    showDialog<void>(
      context: context,
      useRootNavigator: useRootNavigator,
      builder: (context) => AlertDialog(
        title: Text('Dialog $where'),
        content: Text(
          useRootNavigator
              ? 'This one sits above the node. The node cannot close it, so '
                  'the back travels past it.'
              : 'This one is a route of the node. The node closes it before '
                  'anything outside hears the back.',
        ),
        actions: const [SystemBackButton(compact: true)],
      ),
    ).then((_) => journal.log('the dialog $where was closed'));
  }
}
