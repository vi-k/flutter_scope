import 'package:flutter/material.dart';

import 'scope_widget_core_example.dart';
import 'scope_widget_example.dart';

class ScopeWidgetDemo extends StatelessWidget {
  const ScopeWidgetDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Expanded(child: ScopeWidgetExample()),
        Divider(),
        Expanded(child: ScopeWidgetCoreExample()),
      ],
    );
  }
}
