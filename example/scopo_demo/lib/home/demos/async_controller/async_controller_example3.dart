import 'dart:async';

import 'package:flutter/material.dart';

import 'profile_scope.dart';

int _num = 0;

/// The path this family exists for: the scope leaves the tree while the
/// initialization is still running, so it never receives the controller. It is
/// unmounted and disposed of anyway -- watch the console for `onUnmount` and
/// `disposed` without an `initialized` between them.
class AsyncControllerExample3 extends StatefulWidget {
  const AsyncControllerExample3({super.key});

  @override
  State<AsyncControllerExample3> createState() =>
      _AsyncControllerExample3State();
}

class _AsyncControllerExample3State extends State<AsyncControllerExample3> {
  Timer? _timer;
  var _showScope = true;

  @override
  void initState() {
    super.initState();
    _num++;

    // Half of what the initialization needs: the scope walks away in the
    // middle of it.
    _timer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _showScope = false);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: _showScope
            ? ProfileScope(
                debugSource: AsyncControllerExample3,
                debugName: '3.$_num',
              )
            : const Text('The scope left in the middle of its init'),
      );
}
