import 'package:flutter/material.dart';

import 'counter_scope.dart';

/// Recreates the scope without a `scopeKey`, allowing the new instance to
/// initialize while the previous one is still disposing.
class AsyncDataScopeExample1 extends StatelessWidget {
  static int _num = 0;

  const AsyncDataScopeExample1({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CounterScope(
        debugSource: AsyncDataScopeExample1,
        debugName: '1.${++_num}',
        title: '$AsyncDataScopeExample1 (no scopeKey)',
      ),
    );
  }
}
