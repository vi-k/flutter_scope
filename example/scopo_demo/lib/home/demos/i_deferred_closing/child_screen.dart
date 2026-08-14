import 'package:flutter/material.dart';

import 'screen_scope.dart';

/// The route body that installs `ScreenScope` as the screen itself.
class ChildScreen extends StatelessWidget {
  const ChildScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScope();
  }
}
