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
  /// rather than as `4/3`. The assertions above and in [ProgressIterator.addSteps]
  /// are what say so out loud, and they are off in a release build.
  double get value => total == 0 ? 1 : (number / total).clamp(0.0, 1.0);

  @override
  String toString() => '$number/$total';
}
