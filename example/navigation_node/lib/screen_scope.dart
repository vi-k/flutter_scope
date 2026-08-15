import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

/// Something a screen owns and its child windows are expected to reach.
///
/// A real one would be a controller, a repository or a form's state. A ticket
/// number is enough to answer the only question that matters here: did this
/// route end up under the screen, or above it?
class Ticket {
  /// What the screen would rather not lose track of.
  final String number;

  /// Creates a ticket.
  const Ticket(this.number);
}

/// Puts a [Ticket] over the subtree, the way a screen puts its state over its
/// own content.
class ScreenScope extends StatelessWidget {
  /// The number the scope carries.
  final String number;

  /// The subtree under the scope.
  final Widget child;

  /// Creates the scope.
  const ScreenScope({required this.number, required this.child, super.key});

  @override
  Widget build(BuildContext context) => ScopeModel<Ticket>(
        create: (context) => Ticket(number),
        dispose: (model) {},
        builder: (context) => child,
      );
}

/// Says whether the scope of the screen is reachable from here.
///
/// This is the whole reason `NavigationNode` exists. A route pushed on the
/// application's navigator is built *above* the screen, so the screen's scope
/// is not among its ancestors and this reads "out of reach". A route pushed
/// inside a node is built below it, and the same lookup finds the ticket.
class ScopeReadout extends StatelessWidget {
  /// Creates the readout.
  const ScopeReadout({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ticket = ScopeModel.maybeOf<Ticket>(context, listen: false);
    final found = ticket != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            found ? Icons.link : Icons.link_off,
            size: 18,
            color: found ? theme.colorScheme.tertiary : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              found
                  ? 'ticket ${ticket.number} — the screen\'s scope is right here'
                  : 'no ticket — the screen\'s scope is out of reach',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: found ? null : theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
