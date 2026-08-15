import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../lesson.dart';
import '../screen_scope.dart';

/// Lesson 1: what a pushed page can still reach, with and without a node.
final whyANodeLesson = Lesson(
  title: '1. Why a node at all',
  summary: 'Whether a pushed page can still reach the screen it came from',
  explanation: const [
    'A push always goes to the nearest Navigator above it. Without a node that '
        'is the application\'s own one, which sits above every screen — so the '
        'new page is built above the screen too, and whatever the screen set up '
        'around itself is no longer among its ancestors.',
    'Both stages below stand under the same scope, a screen holding onto ticket '
        'A-42. The left one pushes on the application; the right one has a '
        'NavigationNode, so the same push lands inside the box and under the '
        'scope. Each pushed page says which of the two happened to it.',
  ],
  instruction: 'push a page on each side and read the line at the top of it. '
      'Then press System back and watch which page it closes.',
  stage: (context) => const ScreenScope(
    number: 'A-42',
    child: Row(
      children: [
        Expanded(child: _WithoutNode()),
        Expanded(child: _WithNode()),
      ],
    ),
  ),
);

class _WithoutNode extends StatelessWidget {
  const _WithoutNode();

  @override
  Widget build(BuildContext context) => const Stage(
        label: 'no node — pushes onto the application',
        child: _StageBody(
          pushLabel: 'Push a page',
          pageName: 'page without a node',
          builder: _buildPage,
        ),
      );

  static Widget _buildPage(BuildContext context) => const SamplePage(
        title: 'Pushed above the screen',
      );
}

class _WithNode extends StatelessWidget {
  const _WithNode();

  @override
  Widget build(BuildContext context) => Stage(
        label: 'NavigationNode — pushes stay in here',
        isNode: true,
        child: NavigationNode(
          child: const NodeHome(
            title: 'first page of the node',
            child: _StageBody(
              pushLabel: 'Push a page',
              pageName: 'page inside the node',
              builder: _buildPage,
            ),
          ),
        ),
      );

  static Widget _buildPage(BuildContext context) => const SamplePage(
        title: 'Pushed inside the node',
      );
}

class _StageBody extends StatelessWidget {
  final String pushLabel;
  final String pageName;
  final WidgetBuilder builder;

  const _StageBody({
    required this.pushLabel,
    required this.pageName,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ScopeReadout(),
            const SizedBox(height: 12),
            PushButton(
              label: pushLabel,
              pageName: pageName,
              builder: builder,
            ),
          ],
        ),
      );
}
