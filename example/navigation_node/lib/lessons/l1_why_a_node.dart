import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../lesson.dart';

/// Lesson 1: where a pushed page lands, with and without a node.
final whyANodeLesson = Lesson(
  title: '1. Why a node at all',
  summary: 'Where a pushed page lands: over everything, or inside the box',
  explanation: const [
    'A push always goes to the nearest Navigator above it. Without a node that '
        'is the application\'s own one, sitting above every screen, so the new '
        'page covers the whole window — and whatever the screen had set up '
        'around it is left behind.',
    'NavigationNode puts a Navigator right here instead. The same push now '
        'lands inside the box, under everything the screen provides.',
  ],
  instruction: 'push a page on each side, then press System back and watch '
      'which one it closes.',
  stage: (context) => const Row(
    children: [
      Expanded(child: _WithoutNode()),
      Expanded(child: _WithNode()),
    ],
  ),
);

class _WithoutNode extends StatelessWidget {
  const _WithoutNode();

  @override
  Widget build(BuildContext context) => const Stage(
        label: 'no node — pushes onto the application',
        child: Center(
          child: PushButton(
            label: 'Push a page',
            pageName: 'page without a node',
            builder: _buildPage,
          ),
        ),
      );

  static Widget _buildPage(BuildContext context) => const SamplePage(
        title: 'This covers the whole window',
      );
}

class _WithNode extends StatelessWidget {
  const _WithNode();

  @override
  Widget build(BuildContext context) => Stage(
        label: 'NavigationNode — pushes stay in here',
        isNode: true,
        child: NavigationNode(
          child: Builder(
            builder: (context) => const Center(
              child: PushButton(
                label: 'Push a page',
                pageName: 'page inside the node',
                builder: _buildPage,
              ),
            ),
          ),
        ),
      );

  static Widget _buildPage(BuildContext context) => const SamplePage(
        title: 'This stays inside the box',
      );
}
