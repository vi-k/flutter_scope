import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo_demo/app/theme_manager/theme_manager.dart';
import 'package:scopo_demo/common/data/real_services/key_value_storage.dart';
import 'package:scopo_demo/home/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'the app bar toggles the theme on a tap and resets it on a long press',
    (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final preferences = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        MaterialApp(
          home: ThemeManager(
            keyValueService: KeyValueStorage(
              sharedPreferences: preferences,
              prefix: 'theme.',
            ),
            builder: (context) => Scaffold(
              appBar: HomeAppBar(context, withTabs: false),
            ),
          ),
        ),
      );

      // Nothing is stored, so the mode is the system's, and the platform a
      // test runs on is light. The icon shows what a press would switch to.
      expect(find.byIcon(Icons.dark_mode), findsOneWidget);

      await tester.tap(find.byIcon(Icons.dark_mode));
      await tester.pump();

      expect(find.byIcon(Icons.light_mode), findsOneWidget);

      // The long press is what `IconButton.onLongPress` would have carried from
      // Flutter 3.29 on; below that floor it hangs on a `GestureDetector`
      // above the button, so this asks whether the wrapping still works. The
      // reset also has to be the only thing that runs: the long-press
      // recognizer takes the arena at its deadline, and the button's tap is
      // rejected rather than fired on the release.
      await tester.longPress(find.byIcon(Icons.light_mode));
      await tester.pump();

      expect(find.byIcon(Icons.dark_mode), findsOneWidget);
    },
  );
}
