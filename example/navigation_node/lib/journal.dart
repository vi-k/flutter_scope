import 'package:flutter/material.dart';

/// What happened, in the order it happened.
///
/// Every lesson writes here, and the panel at the bottom of the screen shows
/// the tail of it. Seeing the order is the whole point: a system back that
/// closes an inner page and a system back that asks `onPop` look identical on
/// screen until you read what came in between.
class Journal extends ChangeNotifier {
  final _entries = <JournalEntry>[];

  /// Newest last.
  List<JournalEntry> get entries => List.unmodifiable(_entries);

  /// Records something the app did on its own.
  void log(String message) => _add(JournalEntry(message, JournalKind.plain));

  /// Records the press of the system back button.
  void logBack(String message) => _add(JournalEntry(message, JournalKind.back));

  /// Records what the node decided, once the press reached it.
  void logNode(String message) => _add(JournalEntry(message, JournalKind.node));

  /// Empties the log.
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _add(JournalEntry entry) {
    _entries.add(entry);
    notifyListeners();
  }
}

/// One line of the [Journal].
class JournalEntry {
  /// What to show.
  final String message;

  /// What kind of event this was, which decides its colour and marker.
  final JournalKind kind;

  /// Creates an entry.
  const JournalEntry(this.message, this.kind);
}

/// The three kinds of line the journal tells apart.
enum JournalKind {
  /// Something the lesson did: a page was pushed, a dialog was opened.
  plain,

  /// The system back button was pressed.
  back,

  /// The node answered that press.
  node,
}

/// Hands the [Journal] down to the lesson without a global.
class JournalScope extends InheritedNotifier<Journal> {
  /// Wraps [child] so that [of] finds [journal] below it.
  const JournalScope({
    required Journal journal,
    required super.child,
    super.key,
  }) : super(notifier: journal);

  /// The journal above [context].
  ///
  /// Pass `listen: false` from a callback — a button that only writes to the
  /// journal has no reason to rebuild when it changes.
  static Journal of(BuildContext context, {bool listen = true}) {
    final scope = listen
        ? context.dependOnInheritedWidgetOfExactType<JournalScope>()
        : context.getInheritedWidgetOfExactType<JournalScope>();

    return scope!.notifier!;
  }
}

/// Shows the tail of the journal.
class JournalView extends StatelessWidget {
  /// How many lines to keep on screen.
  static const visibleLines = 7;

  /// Creates the view.
  const JournalView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = JournalScope.of(context).entries;
    final tail = entries.length > visibleLines
        ? entries.sublist(entries.length - visibleLines)
        : entries;

    if (tail.isEmpty) {
      return Text(
        'The journal is empty. Press System back.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.disabledColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final entry in tail) _JournalLine(entry: entry),
      ],
    );
  }
}

class _JournalLine extends StatelessWidget {
  final JournalEntry entry;

  const _JournalLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (marker, color) = switch (entry.kind) {
      JournalKind.plain => ('  ', theme.textTheme.bodySmall?.color),
      JournalKind.back => ('◀ ', theme.colorScheme.primary),
      JournalKind.node => ('  ↳ ', theme.colorScheme.tertiary),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        '$marker${entry.message}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: color,
          fontFamily: 'monospace',
          fontWeight:
              entry.kind == JournalKind.back ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}
