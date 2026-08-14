import 'package:flutter/material.dart';

import 'counter_scope.dart';

/// Recreates the scope without a `scopeKey`, allowing the new instance to
/// initialize while the previous one is still disposing.
class AsyncScopeExample1 extends StatelessWidget {
  static int _num = 0;

  const AsyncScopeExample1({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CounterScope(
        debugSource: AsyncScopeExample1,
        debugName: '1.${++_num}',
        title: '$AsyncScopeExample1 (no scopeKey)',
      ),
    );
  }
}
