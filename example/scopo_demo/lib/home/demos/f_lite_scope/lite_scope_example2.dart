import 'package:flutter/material.dart';

import 'counter_scope.dart';

/// Reuses a `scopeKey` so initialization waits for the previous instance to
/// finish disposing.
class LiteScopeExample2 extends StatelessWidget {
  static int _num = 0;

  const LiteScopeExample2({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CounterScope(
        debugSource: LiteScopeExample2,
        debugName: '2.${++_num}',
        scopeKey: LiteScopeExample2,
        title: '$LiteScopeExample2 (has scopeKey)',
      ),
    );
  }
}
