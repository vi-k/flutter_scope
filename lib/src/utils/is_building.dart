import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// How many elements of this package are being rebuilt right now.
///
/// A plain field, deliberately: `BuildOwner.debugBuilding` is written only from
/// inside an `assert`, so a release build has nothing but the frame phase to go
/// by — and a build driven with no frame in progress, which is how `runApp`
/// builds the first tree, looks there like no build at all. An action deferred
/// by [IsBuildingExtension.runOutsideFrame] then ran inside the very build it
/// was being kept out of, and marking an element dirty from there is refused in
/// silence: an `AsyncScope` whose initialization failed before its first
/// `await` showed an empty subtree in release where debug showed
/// `buildOnError`.
///
/// A count rather than a flag, since scopes nest.
int _scopeRebuildDepth = 0;

/// Whether an element of this package is being rebuilt right now.
///
/// The half of [IsBuildingExtension.isBuilding] that survives into a release
/// build — see [_scopeRebuildDepth] for why the other half does not.
bool get scopeIsRebuilding => _scopeRebuildDepth > 0;

/// Marks the beginning of a rebuild of an element of this package.
///
/// Paired with [endScopeRebuild] in a `finally`, so a build that throws leaves
/// no count standing.
void beginScopeRebuild() => _scopeRebuildDepth++;

/// Marks the end of a rebuild of an element of this package.
void endScopeRebuild() => _scopeRebuildDepth--;

/// {@category utils}
extension IsBuildingExtension on SchedulerBinding {
  /// Whether a build is running right now.
  ///
  /// Anything that marks an element dirty is unsafe in this phase, which
  /// is what [runOutsideFrame] exists for.
  ///
  /// The phase is not the whole answer: `BuildOwner.buildScope` also runs with
  /// no frame in progress, which is how `runApp` builds the first tree, and
  /// `markNeedsBuild` from inside *that* is refused just the same. Two more
  /// sources answer for those. The scopes of this package mark their own
  /// rebuilds with a plain field, so those are seen in a release build as well
  /// as in debug; the build owner is asked too, but only behind an assertion,
  /// since that is the only place it keeps the flag. A build this package did
  /// not run, outside a frame, in release, is therefore the one case left
  /// unanswered.
  bool get isBuilding =>
      schedulerPhase == SchedulerPhase.persistentCallbacks ||
      scopeIsRebuilding ||
      (WidgetsBinding.instance.buildOwner?.debugBuilding ?? false);

  /// Runs [action] now, or after the current frame when one is being built.
  void runOutsideFrame(void Function() action) {
    if (isBuilding) {
      SchedulerBinding.instance
        // The build being waited for may be one `runApp` drives outside a
        // frame, and then nothing has asked for the frame this callback needs.
        ..scheduleFrame()
        ..addPostFrameCallback((_) {
          action();
        });
    } else {
      action();
    }
  }
}
