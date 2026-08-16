import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// {@category utils}
extension IsBuildingExtension on SchedulerBinding {
  /// Whether a build is running right now.
  ///
  /// Anything that marks an element dirty is unsafe in this phase, which
  /// is what [runOutsideFrame] exists for.
  ///
  /// The phase is not the whole answer: `BuildOwner.buildScope` also runs with
  /// no frame in progress, which is how `runApp` builds the first tree, and
  /// `markNeedsBuild` from inside *that* is refused just the same. The build
  /// owner is asked as well — behind an assertion, since that is the only
  /// place it keeps the flag, so in a release build the phase is all there is
  /// to go by.
  bool get isBuilding =>
      schedulerPhase == SchedulerPhase.persistentCallbacks ||
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
