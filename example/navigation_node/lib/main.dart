import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'journal.dart';
import 'lesson.dart';
import 'lessons/l1_why_a_node.dart';
import 'lessons/l2_dialog_inside.dart';
import 'lessons/l3_guarded_route.dart';
import 'lessons/l4_on_pop.dart';
import 'lessons/l5_root_node.dart';
import 'lessons/l6_nested_nodes.dart';

/// The six lessons, in the order they build on each other.
final lessons = <Lesson>[
  whyANodeLesson,
  dialogInsideLesson,
  guardedRouteLesson,
  onPopLesson,
  rootNodeLesson,
  nestedNodesLesson,
];

void main() {
  ScopeConfig.observer = const ScopePrintObserver();

  runApp(const NavigationNodeApp());
}

/// Shows what `NavigationNode` does, one lesson at a time.
class NavigationNodeApp extends StatefulWidget {
  /// Creates the app.
  const NavigationNodeApp({super.key});

  @override
  State<NavigationNodeApp> createState() => _NavigationNodeAppState();
}

class _NavigationNodeAppState extends State<NavigationNodeApp> {
  final _journal = Journal();

  @override
  void dispose() {
    _journal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => JournalScope(
        // Above MaterialApp on purpose: every route, dialog and pushed page
        // below can then reach the same journal.
        journal: _journal,
        child: MaterialApp(
          title: 'NavigationNode',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorSchemeSeed: Colors.indigo,
            useMaterial3: true,
          ),
          home: const _LessonList(),
        ),
      );
}

class _LessonList extends StatelessWidget {
  const _LessonList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('NavigationNode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'NavigationNode is a Navigator placed in the middle of a screen '
            'instead of above it. Routes it opens belong to that screen, and a '
            'system back reaches them before it reaches anything outside.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Every lesson carries a "System back" button. It calls the same '
              'entry point the Android back button and gesture call, so it is '
              'the real system back — on a desktop, where there is none to '
              'press, it is the only way to see any of this.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final lesson in lessons)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(lesson.title),
                subtitle: Text(lesson.summary),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => LessonPage(lesson: lesson),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
