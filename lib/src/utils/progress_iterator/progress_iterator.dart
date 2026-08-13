/// A helper class to track initialization progress as an [Progress] value.
///
/// ```dart
/// static Stream<ScopeInitState<ProgressValue, MyFeatureDeps>> init() async* {
///   final progressIterator = ProgressIterator(count: 3);
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
  Progress add(int n) {
    final newNum = _currentStep.number + n;
    assert(newNum <= total, 'next step ($newNum) > count ($total)');

    return _currentStep = Progress(newNum, total);
  }

  /// Returns the next step.
  Progress nextStep() => add(1);
}

/// {@category utils}
final class Progress {
  /// The steps taken so far.
  final int number;

  /// The steps there are in total.
  final int total;

  /// Creates a progress value of [number] steps out of [total].
  const Progress(this.number, this.total);

  /// The progress as a fraction between 0 and 1, for a progress indicator.
  double get progress => number / total;

  @override
  String toString() => '$number/$total';
}
