import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../lesson.dart';

/// Lesson 6: with nodes inside nodes, the innermost one answers.
final nestedNodesLesson = Lesson(
  title: '6. Nodes inside nodes',
  summary: 'The innermost node with something to close takes the back',
  explanation: const [
    'Nodes nest. A back does not stop at the first one it meets: each node '
        'passes it down while anything deeper still has a page of its own, so '
        'the innermost one that can answer does.',
    'Everything above it stays exactly where it was — the outer node keeps its '
        'page, and the screen around both keeps its own.',
  ],
  instruction: 'push a page in the inner node, then in the outer one, then '
      'press System back twice and watch which box changes each time.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) => Stage(
        label: 'outer NavigationNode',
        isNode: true,
        child: NavigationNode(
          child: NodeHome(
            title: 'first page of the outer node',
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: PushButton(
                    label: 'Push in the OUTER node',
                    pageName: 'outer page',
                    builder: (context) => const SamplePage(
                      title: 'Pushed in the outer node',
                    ),
                  ),
                ),
                const Expanded(child: _Inner()),
              ],
            ),
          ),
        ),
      );
}

class _Inner extends StatelessWidget {
  const _Inner();

  @override
  Widget build(BuildContext context) => Stage(
        label: 'inner NavigationNode',
        isNode: true,
        child: NavigationNode(
          child: NodeHome(
            title: 'first page of the inner node',
            child: PushButton(
              label: 'Push in the INNER node',
              pageName: 'inner page',
              builder: (context) => const SamplePage(
                title: 'Pushed in the inner node',
              ),
            ),
          ),
        ),
      );
}
