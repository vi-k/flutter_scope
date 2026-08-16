import 'package:flutter/material.dart';

import 'profile_scope.dart';

int _num = 0;

/// The ordinary path: the controller initializes, runs, and is torn down when
/// the page is restarted -- `onUnmount` first, `dispose` after it.
class AsyncControllerExample1 extends StatelessWidget {
  const AsyncControllerExample1({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ProfileScope(
          debugSource: AsyncControllerExample1,
          debugName: '1.${++_num}',
        ),
      );
}
