import 'package:flutter/material.dart';

import 'counter_scope.dart';

int _num = 0;

/// Demonstrates a keyed parent waiting for its child scope during disposal.
/// The console shows child-first teardown before the next parent starts.
class LiteScopeExample3 extends StatefulWidget {
  const LiteScopeExample3({super.key});

  @override
  State<LiteScopeExample3> createState() => _LiteScopeExample3State();
}

class _LiteScopeExample3State extends State<LiteScopeExample3> {
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
              debugSource: LiteScopeExample3,
              debugName: '3.$_num.parent',
              scopeKey: LiteScopeExample3,
              title: '$LiteScopeExample3 (scopeKey + parent & child)',
              childScope: Center(
                child: CounterScope(
                  debugSource: LiteScopeExample3,
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
