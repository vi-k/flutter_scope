import 'package:flutter/material.dart';

import 'profile_scope.dart';

int _num = 0;

/// A failed initialization. The error branch is built, and the controller is
/// still unmounted and disposed of: it may have taken something before it
/// failed.
class AsyncControllerExample2 extends StatelessWidget {
  const AsyncControllerExample2({super.key});

  @override
  Widget build(BuildContext context) => Center(
        child: ProfileScope(
          debugSource: AsyncControllerExample2,
          debugName: '2.${++_num}',
          failOnInit: true,
        ),
      );
}
