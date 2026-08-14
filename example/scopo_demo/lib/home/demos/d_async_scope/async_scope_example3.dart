import 'package:flutter/material.dart';

import 'counter_scope.dart';

int _num = 0;

/// Demonstrates a keyed parent waiting for its child scope during disposal.
/// The console shows child-first teardown before the next parent starts.
class AsyncScopeExample3 extends StatefulWidget {
  const AsyncScopeExample3({super.key});

  @override
  State<AsyncScopeExample3> createState() => _AsyncScopeExample3State();
}

class _AsyncScopeExample3State extends State<AsyncScopeExample3> {
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
              debugSource: AsyncScopeExample3,
              debugName: '3.$_num.parent',
              scopeKey: AsyncScopeExample3,
              title: '$AsyncScopeExample3 (scopeKey + parent & child)',
              childScope: Center(
                child: CounterScope(
                  debugSource: AsyncScopeExample3,
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
