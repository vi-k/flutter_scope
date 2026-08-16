import 'package:flutter/material.dart';

import 'counter_scope.dart';

int _num = 0;

/// Demonstrates a keyed parent waiting for its child scope during disposal.
/// The console shows child-first teardown before the next parent starts.
class AsyncDataScopeExample3 extends StatefulWidget {
  const AsyncDataScopeExample3({super.key});

  @override
  State<AsyncDataScopeExample3> createState() => _AsyncDataScopeExample3State();
}

class _AsyncDataScopeExample3State extends State<AsyncDataScopeExample3> {
  @override
  void initState() {
    super.initState();
    _num++;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: CounterScope(
              debugSource: AsyncDataScopeExample3,
              debugName: '3.$_num.parent',
              scopeKey: AsyncDataScopeExample3,
              title: '$AsyncDataScopeExample3 (scopeKey + parent & child)',
              childScope: Center(
                child: CounterScope(
                  debugSource: AsyncDataScopeExample3,
                  debugName: '3.$_num.child',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
