import 'package:flutter/material.dart';

import 'scope_notifier_example1.dart';
import 'scope_notifier_example2.dart';
import 'scope_notifier_example3.dart';

/// Compares base, core, and `StateAsNotifier` ways to expose a `Listenable`.
class ScopeNotifierDemo extends StatelessWidget {
  const ScopeNotifierDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: ScopeNotifierExample1()),
        Divider(),
        Expanded(child: ScopeNotifierExample2()),
        Divider(),
        Expanded(child: ScopeNotifierExample3()),
      ],
    );
  }
}
