import 'package:flutter/scheduler.dart';

/// {@category utils}
extension IsBuildingExtension on SchedulerBinding {
  bool get isBuilding => schedulerPhase == SchedulerPhase.persistentCallbacks;

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
