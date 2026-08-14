import 'package:flutter/material.dart';

import 'counter_scope.dart';

/// Reuses a `scopeKey` so initialization waits for the previous instance to
/// finish disposing.
class AsyncDataScopeExample2 extends StatelessWidget {
  static int _num = 0;

  const AsyncDataScopeExample2({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CounterScope(
        debugSource: AsyncDataScopeExample2,
        debugName: '2.${++_num}',
        scopeKey: AsyncDataScopeExample2,
        title: '$AsyncDataScopeExample2 (has scopeKey)',
      ),
    );
  }
}
