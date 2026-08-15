import 'package:flutter/material.dart';

import 'journal.dart';
import 'screen_scope.dart';
import 'system_back.dart';

/// One thing about `NavigationNode`, shown on a screen of its own.
class Lesson {
  /// Shown in the list and in the app bar.
  final String title;

  /// One sentence for the list: what this lesson is about.
  final String summary;

  /// The paragraphs shown above the stage, in plain words.
  final List<String> explanation;

  /// What to try, once the stage is on screen.
  final String instruction;

  /// The live part of the lesson.
  final WidgetBuilder stage;

  /// Creates a lesson.
  const Lesson({
    required this.title,
    required this.summary,
    required this.explanation,
    required this.instruction,
    required this.stage,
  });
}

/// The frame every lesson shares: explanation, stage, and the back panel.
///
/// The panel stays reachable at all times, including while a dialog or an
/// inner page covers the stage — that is what makes the system back testable
/// on a desktop, where there is no system back to press.
class LessonPage extends StatefulWidget {
  /// The lesson to show.
  final Lesson lesson;

  /// Creates the page.
  const LessonPage({required this.lesson, super.key});

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  /// Whether anything below can close a route of its own.
  ///
  /// This is the very signal `NavigationNode` reads to decide whether a system
  /// back belongs inside it, and Flutter hands it to anyone who listens.
  bool _subtreeCanHandlePop = false;

  bool _watchSubtree(NavigationNotification notification) {
    if (notification.canHandlePop != _subtreeCanHandlePop) {
      setState(() => _subtreeCanHandlePop = notification.canHandlePop);
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lesson = widget.lesson;

    return Scaffold(
      appBar: AppBar(title: Text(lesson.title)),
      body: LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            // The words never take more than a third of the window: the stage
            // is what has to fit, and a node's own box is a slice of whatever
            // is left over.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: constraints.maxHeight / 3,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final paragraph in lesson.explanation)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          paragraph,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Try: ${lesson.instruction}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: NotificationListener<NavigationNotification>(
                onNotification: _watchSubtree,
                child: Builder(builder: lesson.stage),
              ),
            ),
            const Divider(height: 1),
            SystemBackBar(subtreeCanHandlePop: _subtreeCanHandlePop),
          ],
        ),
      ),
    );
  }
}

/// The stage's own frame: a labelled box, so it is clear where the node ends.
class Stage extends StatelessWidget {
  /// What the box is called.
  final String label;

  /// Whether this box is the one a `NavigationNode` wraps.
  final bool isNode;

  /// The content of the box.
  final Widget child;

  /// Creates the box.
  const Stage({
    required this.label,
    required this.child,
    this.isNode = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isNode ? theme.colorScheme.tertiary : theme.dividerColor;

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: isNode ? 2 : 1),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: color.withValues(alpha: 0.15),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(label, style: theme.textTheme.labelMedium),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A button that pushes a page and tells the journal when it comes and goes.
///
/// The future a push returns completes when the route is *popped*, which is how
/// the lesson notices a page that the system back closed without asking it.
class PushButton extends StatelessWidget {
  /// The button's label.
  final String label;

  /// The name the journal uses for the pushed page.
  final String pageName;

  /// Builds the page to push.
  final WidgetBuilder builder;

  /// Creates the button.
  const PushButton({
    required this.label,
    required this.pageName,
    required this.builder,
    super.key,
  });

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
        onPressed: () {
          final journal = JournalScope.of(context, listen: false);

          journal.log('pushed "$pageName"');
          Navigator.of(context)
              .push<void>(MaterialPageRoute<void>(builder: builder))
              .then((_) => journal.log('"$pageName" was closed'));
        },
        child: Text(label),
      );
}

/// Centres its child, and scrolls instead of overflowing when the box is small.
///
/// A node's box is a slice of the window, and the window can be any size. This
/// is the difference between a lesson that degrades and one that throws.
class ScrollIfTight extends StatelessWidget {
  /// What to centre.
  final Widget child;

  /// Creates the box.
  const ScrollIfTight({required this.child, super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 16).clamp(0, double.infinity),
            ),
            child: Center(child: child),
          ),
        ),
      );
}

/// A dialog sized for the room a node actually has.
///
/// A dialog opened with `useRootNavigator: false` belongs to the node, so it is
/// drawn inside the node's box — a slice of an already small window, not the
/// whole screen. Material's default insets and padding assume the latter, and
/// the difference is enough to push the buttons out of sight.
class NodeDialog extends StatelessWidget {
  /// The dialog's title.
  final String title;

  /// What the dialog says.
  final Widget content;

  /// The buttons along its bottom.
  final List<Widget> actions;

  /// Creates the dialog.
  const NodeDialog({
    required this.title,
    required this.content,
    required this.actions,
    super.key,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
        // Whatever is still too tall scrolls instead of overflowing.
        scrollable: true,
        insetPadding: const EdgeInsets.all(8),
        titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        content: content,
        actions: actions,
      );
}

/// The first page of a node, with an `AppBar` so its back arrow is visible.
///
/// The arrow is worth watching. Flutter draws it when the route thinks a pop
/// would lead somewhere, and on a node's first page that is decided by the node
/// itself: a forwarding node marks the page as having a way out, so the arrow
/// appears even though nothing sits below it. A node marked `isRoot` has no way
/// out and no arrow. Pressing the arrow does what the node says it does —
/// forwards, or nothing at all.
class NodeHome extends StatelessWidget {
  /// What the page is called.
  final String title;

  /// The content of the page.
  final Widget child;

  /// Creates the page.
  const NodeHome({required this.title, required this.child, super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(title, style: Theme.of(context).textTheme.titleSmall),
          primary: false,
          toolbarHeight: 44,
        ),
        body: child,
      );
}

/// A plain page to push, so the lessons do not each invent one.
///
/// It wears an `AppBar` on purpose. Flutter draws a back arrow there whenever
/// the route believes a pop would lead somewhere — including the first page of
/// a forwarding node, which has no route below it but does have a way out. The
/// arrow is therefore a readout of the node's own state, free of charge.
class SamplePage extends StatelessWidget {
  /// The page's title.
  final String title;

  /// Anything to add under the title.
  final Widget? extra;

  /// Creates the page.
  const SamplePage({required this.title, this.extra, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(title), primary: false),
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      body: ScrollIfTight(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ScopeReadout(),
            if (extra case final extra?) ...[
              const SizedBox(height: 12),
              extra,
            ],
            const SizedBox(height: 12),
            const SystemBackButton(compact: true),
          ],
        ),
      ),
    );
  }
}
