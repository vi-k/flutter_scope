import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../journal.dart';
import '../lesson.dart';

/// Lesson 3: the node hands the back to the page and takes no for an answer.
final guardedRouteLesson = Lesson(
  title: '3. A page inside can refuse',
  summary: 'The node asks the page; a PopScope that says no is obeyed',
  explanation: const [
    'The node does not close its top page itself. It asks that page, the same '
        'way any Navigator does, so a PopScope the page put up is asked too.',
    'A page that answers "no" stays. The back is spent — it does not fall '
        "through to the node's own policy, and nothing outside moves either.",
  ],
  instruction: 'push the guarded page and press System back a few times. Then '
      'let it through with the switch and press again.',
  stage: (context) => const _Stage(),
);

class _Stage extends StatelessWidget {
  const _Stage();

  @override
  Widget build(BuildContext context) => const Stage(
        label: 'NavigationNode',
        isNode: true,
        child: NavigationNode(
          child: NodeHome(
            title: 'first page of the node',
            child: ScrollIfTight(
              child: PushButton(
                label: 'Push the guarded page',
                pageName: 'guarded page',
                builder: _buildPage,
              ),
            ),
          ),
        ),
      );

  static Widget _buildPage(BuildContext context) => const _GuardedPage();
}

class _GuardedPage extends StatefulWidget {
  const _GuardedPage();

  @override
  State<_GuardedPage> createState() => _GuardedPageState();
}

class _GuardedPageState extends State<_GuardedPage> {
  bool _locked = true;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_locked,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;

          JournalScope.of(context, listen: false)
              .logNode('the guarded page refused the pop');
        },
        child: SamplePage(
          title: _locked ? 'Guarded: back does nothing' : 'Unlocked',
          extra: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: !_locked,
                  onChanged: (value) => setState(() => _locked = !value),
                  title: const Text('Let the back through'),
                  dense: true,
                ),
                const Text('PopScope(canPop: …) lives on this page'),
              ],
            ),
          ),
        ),
      );
}
