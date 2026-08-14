import 'package:flutter/material.dart';

import 'counter_scope.dart';

int _num = 0;

/// Demonstrates a keyed parent waiting for its child scope during disposal.
/// The console shows child-first teardown before the next parent starts.
/// The child is mounted only after the parent state reports initialization.
class ScopeExample3 extends StatefulWidget {
  const ScopeExample3({super.key});

  @override
  State<ScopeExample3> createState() => _ScopeExample3State();
}

class _ScopeExample3State extends State<ScopeExample3> {
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
              debugSource: ScopeExample3,
              debugName: '3.$_num.parent',
              scopeKey: ScopeExample3,
              title: '$ScopeExample3 (scopeKey + parent & child)',
              childScope: Center(
                child: Builder(
                  builder: (context) {
                    return !CounterScope.isInitializedOf(context)
                        ? const Text('Parent initializing…')
                        : CounterScope(
                            debugSource: ScopeExample3,
                            debugName: '3.$_num.child',
                          );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
