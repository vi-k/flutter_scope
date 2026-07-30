import 'package:flutter/material.dart';
import 'package:scopo_demo/utils/console/console_view.dart';

import '../../../utils/console/console.dart';
import 'screen_scope.dart';

class DeferredClosingDemo extends StatelessWidget {
  const DeferredClosingDemo({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodySmall!,
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: FilledButton(
                onPressed: () {
                  console.log(ScreenScope, 'open');
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const ScreenScope(),
                    ),
                  );
                },
                child: const Text('Open screen scope'),
              ),
            ),
          ),
          const ConsoleView(source: ScreenScope),
        ],
      ),
    );
  }
}
