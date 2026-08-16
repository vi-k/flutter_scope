import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo_demo/home/demos/scope_widget/scope_widget_core_example.dart';

void main() {
  testWidgets('ScopeWidgetCore example increments its element-owned count', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ScopeWidgetCoreExample()),
    );

    expect(find.text('0'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add_circle));
    await tester.pump();

    expect(find.text('1'), findsOneWidget);
  });
}
