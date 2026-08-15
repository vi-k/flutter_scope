import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../journal.dart';
import '../lesson.dart';

/// Lesson 5: isRoot decides whether a pop may leave the node.
final rootNodeLesson = Lesson(
  title: '5. isRoot keeps a pop at home',
  summary: 'A pop the node cannot handle: forwarded, or stopped here',
  explanation: const [
    'Call pop() on the node\'s first page and there is nothing left inside to '
        'close. An ordinary node forwards that pop to the Navigator above it, '
        'so the screen around the node closes instead.',
    'A node marked isRoot: true keeps it. The pop finds nothing to do and '
        'nothing happens — useful for the outermost node of a screen, which '
        'should never take the screen down with it.',
  ],
  instruction: 'press "pop() the first page" on each side. The left one closes '
      'this lesson; the right one does nothing at all.',
  stage: (context) => const Row(
    children: [
      Expanded(child: _Node(isRoot: false)),
      Expanded(child: _Node(isRoot: true)),
    ],
  ),
);

class _Node extends StatelessWidget {
  final bool isRoot;

  const _Node({required this.isRoot});

  @override
  Widget build(BuildContext context) => Stage(
        label: isRoot ? 'NavigationNode(isRoot: true)' : 'NavigationNode()',
        isNode: true,
        child: NavigationNode(
          isRoot: isRoot,
          child: Builder(
            builder: (context) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isRoot ? 'keeps the pop' : 'forwards the pop',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () {
                      JournalScope.of(context, listen: false).log(
                        'pop() on the first page of '
                        '${isRoot ? 'the root node' : 'an ordinary node'}',
                      );
                      Navigator.of(context).pop();
                    },
                    child: const Text('pop() the first page'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
