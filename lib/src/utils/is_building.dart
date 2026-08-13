import 'package:flutter/scheduler.dart';

/// {@category utils}
extension IsBuildingExtension on SchedulerBinding {
  /// Whether a frame is being built right now.
  ///
  /// Anything that marks an element dirty is unsafe in this phase, which
  /// is what [runOutsideFrame] exists for.
  bool get isBuilding => schedulerPhase == SchedulerPhase.persistentCallbacks;

  /// Runs [action] now, or after the current frame when one is being built.
  void runOutsideFrame(void Function() action) {
    if (isBuilding) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        action();
      });
    } else {
      action();
    }
  }
}
