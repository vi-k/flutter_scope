import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../journal.dart';
import '../lesson.dart';
import '../screen_scope.dart';
import '../system_back.dart';

/// Lesson 2: a dialog is a route too, and the node closes it first.
final dialogInsideLesson = Lesson(
  title: '2. A dialog is a route too',
  summary: 'showDialog with useRootNavigator: false belongs to the node',
  explanation: const [
    'showDialog pushes a route like any other, and by default it pushes it on '
        'the application\'s Navigator — above the node, out of its reach and '
        'out of reach of everything the screen provides.',
    'Pass useRootNavigator: false and the dialog goes to the nearest Navigator '
        'instead, which is the node\'s. It is then built under the screen, so '
        'the screen\'s scope is still there to read; and the system back closes '
        'it and stops there, leaving the screen underneath alone.',
  ],
  instruction: 'open both dialogs in turn: each says whether it can still see '
      'the screen\'s ticket. Close them with System back and watch the line '
      'above the journal.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) => ScreenScope(
        number: 'A-42',
        child: Stage(
          label: 'NavigationNode',
          isNode: true,
          child: NavigationNode(
            child: NodeHome(
              title: 'first page of the node',
              child: Builder(
                builder: (context) => ScrollIfTight(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ScopeReadout(),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () =>
                            _open(context, useRootNavigator: false),
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
      builder: (context) => NodeDialog(
        title: 'Dialog $where',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              useRootNavigator
                  ? 'Above the node — the back travels past it.'
                  : 'A route of the node — closed before anything outside '
                      'hears the back.',
            ),
            const SizedBox(height: 12),
            const ScopeReadout(),
          ],
        ),
        actions: const [SystemBackButton(compact: true)],
      ),
    ).then((_) => journal.log('the dialog $where was closed'));
  }
}
