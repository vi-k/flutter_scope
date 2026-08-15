import 'package:flutter/material.dart';

import 'journal.dart';

/// Presses the system back, the same way the platform does.
///
/// The Android back button and back gesture arrive as a `popRoute` message on
/// the `flutter/navigation` channel, and the only thing the binding does with
/// that message is call [WidgetsBinding.handlePopRoute] — so calling it here is
/// the real gesture, not an imitation. Everything downstream (`WidgetsApp`,
/// `PopScope`, `NavigationNode`, `onPop`) cannot tell the two apart.
///
/// Flutter marks the method `@visibleForTesting`, because an application has no
/// reason to raise a back gesture against itself. Demonstrating one is that
/// reason, and it is why the two warnings are suppressed here — and why you
/// should not copy this line into an app of your own.
///
/// Returns whether anything in the app handled it. `false` means the app would
/// have closed on a phone.
Future<bool> pressSystemBack() =>
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    WidgetsBinding.instance.handlePopRoute();

/// Presses the system back for you, on a machine that has none.
///
/// See [pressSystemBack] for why this is the real system back rather than an
/// imitation of it.
///
/// The button appears inside pushed pages and dialogs too. Without that you
/// could open one on a desktop and have no way back out.
class SystemBackButton extends StatelessWidget {
  /// Whether to draw the small, unobtrusive variant.
  final bool compact;

  /// Creates the button.
  const SystemBackButton({this.compact = false, super.key});

  Future<void> _press(BuildContext context) async {
    final journal = JournalScope.of(context, listen: false)
      ..logBack('system back pressed');

    // false means nothing handled it: on a phone the app would close here.
    final handled = await pressSystemBack();

    journal.logNode(
      handled
          ? 'handled inside the app'
          : 'nobody handled it — a phone would close the app now',
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(Icons.arrow_back);
    const label = Text('System back');

    return compact
        ? OutlinedButton.icon(
            onPressed: () => _press(context),
            icon: icon,
            label: label,
          )
        : FilledButton.icon(
            onPressed: () => _press(context),
            icon: icon,
            label: label,
          );
  }
}

/// The panel every lesson carries at the bottom.
class SystemBackBar extends StatelessWidget {
  /// Whether anything below the lesson can close a route of its own.
  final bool subtreeCanHandlePop;

  /// Creates the panel.
  const SystemBackBar({required this.subtreeCanHandlePop, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const SystemBackButton(),
              const SizedBox(width: 12),
              Expanded(child: _SubtreeState(canHandlePop: subtreeCanHandlePop)),
              IconButton(
                onPressed: JournalScope.of(context, listen: false).clear,
                icon: const Icon(Icons.clear_all),
                tooltip: 'Clear the journal',
              ),
            ],
          ),
          const SizedBox(height: 6),
          const JournalView(),
        ],
      ),
    );
  }
}

/// Shows the signal the node itself reads before it decides anything.
class _SubtreeState extends StatelessWidget {
  final bool canHandlePop;

  const _SubtreeState({required this.canHandlePop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(
          canHandlePop ? Icons.subdirectory_arrow_left : Icons.north_east,
          size: 16,
          color: canHandlePop
              ? theme.colorScheme.tertiary
              : theme.colorScheme.outline,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            canHandlePop
                ? 'the stage has a route of its own to close'
                : 'nothing left inside — the next back goes outwards',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
