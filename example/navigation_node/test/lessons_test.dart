import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_node/main.dart';
import 'package:navigation_node/system_back.dart';

/// Presses the panel's own System back, not the ones inside pages.
Future<void> pressSystemBackButton(WidgetTester tester) async {
  await tester.tap(find.byType(SystemBackButton).first);
  await tester.pumpAndSettle();
}

Future<void> openLesson(WidgetTester tester, String title) async {
  await tester.pumpWidget(const NavigationNodeApp());
  await tester.pumpAndSettle();
  await tester.tap(find.text(title).first);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;

    // Two lessons put two stages side by side; the default 800x600 is not
    // enough for their buttons to be hit-testable.
    view.physicalSize = const Size(1400, 1600);
    view.devicePixelRatio = 1.0;
  });

  for (final lesson in lessons) {
    testWidgets('${lesson.title} opens and takes a system back',
        (tester) async {
      await openLesson(tester, lesson.title);
      expect(find.byType(SystemBackButton), findsWidgets);

      await pressSystemBackButton(tester);

      // Whether the lesson kept the back or let it out, the app is alive.
      expect(find.byType(NavigationNodeApp), findsOneWidget);
    });
  }

  testWidgets('lesson 1: the back closes the page inside the node only',
      (tester) async {
    await openLesson(tester, lessons[0].title);

    await tester.tap(find.text('Push a page').last);
    await tester.pumpAndSettle();
    expect(find.text('This stays inside the box'), findsOneWidget);

    await pressSystemBackButton(tester);

    expect(find.text('This stays inside the box'), findsNothing);
    expect(
      find.text(lessons[0].title),
      findsWidgets,
      reason: 'the lesson itself must still be on screen',
    );
  });

  testWidgets('lesson 2: the back closes a dialog opened in the node',
      (tester) async {
    await openLesson(tester, lessons[1].title);

    await tester.tap(find.text('Dialog in the node'));
    await tester.pumpAndSettle();
    expect(find.text('Dialog in the node').hitTestable(), findsWidgets);

    await pressSystemBackButton(tester);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(lessons[1].title), findsWidgets);
  });

  testWidgets('lesson 3: a page that refuses keeps the back', (tester) async {
    await openLesson(tester, lessons[2].title);

    await tester.tap(find.text('Push the guarded page'));
    await tester.pumpAndSettle();
    expect(find.text('Guarded: back does nothing'), findsOneWidget);

    await pressSystemBackButton(tester);

    expect(
      find.text('Guarded: back does nothing'),
      findsOneWidget,
      reason: 'the node asked the page, and the page said no',
    );
  });

  testWidgets('lesson 4: onPop is asked exactly once', (tester) async {
    await openLesson(tester, lessons[3].title);
    expect(find.text('onPop asked 0 times'), findsOneWidget);

    await pressSystemBackButton(tester);

    expect(find.text('Leave this lesson?'), findsOneWidget);
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();

    expect(find.text('onPop asked 1 time'), findsOneWidget);
    expect(
      find.text(lessons[3].title),
      findsWidgets,
      reason: 'onPop answered "stay", so the lesson stays',
    );
  });

  testWidgets('lesson 4: onPop is not asked while the node has a page',
      (tester) async {
    await openLesson(tester, lessons[3].title);

    await tester.tap(find.text('Push a page inside first'));
    await tester.pumpAndSettle();

    await pressSystemBackButton(tester);

    expect(find.text('Leave this lesson?'), findsNothing);
    expect(find.text('onPop asked 0 times'), findsOneWidget);
  });

  testWidgets('lesson 5: a root node keeps the pop, an ordinary one forwards it',
      (tester) async {
    await openLesson(tester, lessons[4].title);

    // The right-hand stage is the root node: its box must keep its content.
    await tester.tap(find.text('pop() the first page').last);
    await tester.pumpAndSettle();

    expect(
      find.text('keeps the pop'),
      findsOneWidget,
      reason: 'a root node must not empty its own box',
    );
    expect(find.text(lessons[4].title), findsWidgets);

    // The left-hand one forwards, which here closes the lesson.
    await tester.tap(find.text('pop() the first page').first);
    await tester.pumpAndSettle();

    expect(
      find.text('keeps the pop'),
      findsNothing,
      reason: 'the forwarded pop closed the lesson around the node',
    );
  });

  testWidgets('lesson 6: the back reaches the innermost node', (tester) async {
    await openLesson(tester, lessons[5].title);

    await tester.tap(find.text('Push in the INNER node'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push in the OUTER node'));
    await tester.pumpAndSettle();
    expect(find.text('Pushed in the outer node'), findsOneWidget);

    // Top first: the outer page covers the inner node.
    await pressSystemBackButton(tester);
    expect(find.text('Pushed in the outer node'), findsNothing);
    expect(find.text('Pushed in the inner node'), findsOneWidget);

    await pressSystemBackButton(tester);
    expect(find.text('Pushed in the inner node'), findsNothing);
    expect(
      find.text(lessons[5].title),
      findsWidgets,
      reason: 'neither back left the lesson',
    );
  });
}
