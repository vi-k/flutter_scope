import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';

/// Leak-tracking settings for a test that deliberately breaks an update.
///
/// The suite runs with Flutter's leak tracker on (`flutter_test_config.dart`),
/// and it is on because deterministic teardown is what this package promises.
/// A handful of tests, though, are written to provoke a violation that scopo
/// reports by throwing -- a changed `scopeKey`, a swapped constructor form, a
/// subscription made outside a build. The throw happens while the element is
/// being *updated*, and that is what makes these tests different from every
/// other test that ends on an exception:
///
/// **an exception thrown from an update leaves the subtree it broke unmounted
/// for good.** Pumping the tree away afterwards does not reach it -- the
/// widgets are gone from the tree, no further exception is raised, and the
/// elements and render objects below the break are simply never disposed of.
/// An exception thrown from `build` does not do this; the tree unmounts as
/// usual.
///
/// Nothing there is scopo's to release, and no amount of settling reaches it.
/// Checked by probe: twenty lines of plain Flutter -- a `StatefulWidget` whose
/// `didUpdateWidget` throws, then `pumpWidget(SizedBox())` -- leak seven
/// objects with this package nowhere in sight, while the same widget throwing
/// from `build` leaks none.
///
/// So this is an exemption for a framework consequence of a deliberate error,
/// not a silenced check. Use it only where the test *is* the broken update,
/// and say at the call site which violation is being provoked.
final unmountableTree = LeakTesting.settings.withIgnoredAll();
