import 'package:flutter/foundation.dart';

/// A helper class to track initialization progress as an [Progress] value.
///
/// ```dart
/// static Stream<ScopeInitState<Progress, MyFeatureDeps>> init() async* {
///   final progressIterator = ProgressIterator(3);
///
///   // Step 1
///   yield ScopeProgress(progressIterator.nextStep()); // 1/3
///
///   // Step 2
///   yield ScopeProgress(progressIterator.nextStep()); // 2/3
///
///   // Step 3
///   yield ScopeProgress(progressIterator.nextStep()); // 3/3
///
///   ...
/// }
/// ```
///
/// {@category utils}
final class ProgressIterator {
  /// The total number of steps.
  final int total;

  /// The current step.
  Progress _currentStep;

  /// Creates an iterator over [total] steps, starting at `0/total`.
  ProgressIterator(this.total) : _currentStep = Progress(0, total);

  /// The current step.
  Progress get currentStep => _currentStep;

  /// Whether every step has been taken.
  bool get isCompleted => _currentStep.number >= total;

  /// Add [n] steps.
  ///
  /// A negative [n] moves back, and a step past [total] is a mistake in the
  /// caller — caught by an assertion here, and by the bounds of
  /// [Progress.value] where assertions are off.
  Progress addSteps(int n) {
    final newNum = _currentStep.number + n;
    assert(newNum <= total, 'next step ($newNum) > total ($total)');

    return _currentStep = Progress(newNum, total);
  }

  /// Returns the next step.
  Progress nextStep() => addSteps(1);
}

/// {@category utils}
@immutable
final class Progress {
  /// The steps taken so far.
  final int number;

  /// The steps there are in total.
  final int total;

  /// Creates a progress value of [number] steps out of [total].
  ///
  /// Neither may be negative. A [number] past [total] is *not* refused here:
  /// that is what a release build does when it steps past the end, and
  /// [value] answers for it.
  const Progress(this.number, this.total)
      : assert(total >= 0, 'total ($total) cannot be negative'),
        assert(number >= 0, 'number ($number) cannot be negative');

  /// The progress as a fraction between 0 and 1, for a progress indicator.
  ///
  /// Between 0 and 1 whatever it was built from, since that is what a progress
  /// indicator is handed: a task of no steps at all is complete rather than
  /// the `NaN` of `0 / 0`, and a count that ran past its total reads as 1
  /// rather than as `4/3`. The assertions above and in
  /// [ProgressIterator.addSteps] are what say so out loud, and they are off in
  /// a release build.
  ///
  /// [num.clamp] answers for all three, the empty task included: it compares
  /// with [Comparable.compareTo], which treats `NaN` as the maximal double, so
  /// `0 / 0` comes back as the upper limit. An explicit `total == 0` branch
  /// stood here as well and said the same thing twice — no test could tell the
  /// two apart, because there is no case where they disagree.
  double get value => (number / total).clamp(0.0, 1.0);

  /// Two readings of the same step are the same value.
  ///
  /// This arrives in `buildOnProgress` and inside `AsyncScopeProgress`, and
  /// both of those are compared: a selector holding one asks whether it
  /// changed, and so does the model of a scope. By identity the answer for two
  /// readings of one step is "changed", and a subtree rebuilds for a step that
  /// did not move.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Progress && other.number == number && other.total == total;

  @override
  int get hashCode => Object.hash(number, total);

  @override
  String toString() => '$number/$total';
}
