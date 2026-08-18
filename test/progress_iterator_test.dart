import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('ProgressIterator', () {
    test('counts the steps it is asked for', () {
      final iterator = ProgressIterator(3);

      expect('${iterator.currentStep}', '0/3');
      expect(iterator.isCompleted, isFalse);

      expect('${iterator.nextStep()}', '1/3');
      expect('${iterator.nextStep()}', '2/3');
      expect(iterator.isCompleted, isFalse);

      expect('${iterator.nextStep()}', '3/3');
      expect(
        iterator.isCompleted,
        isTrue,
        reason: 'the last step is the one that completes it',
      );
      expect('${iterator.currentStep}', '3/3');
    });

    test('add moves several steps at once', () {
      final iterator = ProgressIterator(10);

      expect('${iterator.addSteps(4)}', '4/10');
      expect('${iterator.addSteps(6)}', '10/10');
      expect(iterator.isCompleted, isTrue);
    });

    test('a step past the total is a mistake in the caller', () {
      final iterator = ProgressIterator(1)..nextStep();

      expect(iterator.nextStep, throwsA(isA<AssertionError>()));
    });

    test('progress is the fraction of the work reported', () {
      final iterator = ProgressIterator(4);

      expect(iterator.currentStep.value, 0.0);
      expect(iterator.addSteps(1).value, 0.25);
      expect(iterator.addSteps(3).value, 1.0);
    });

    test('a task of no steps is complete rather than NaN', () {
      final iterator = ProgressIterator(0);

      expect(iterator.isCompleted, isTrue);
      expect(iterator.currentStep.value, 1.0);
    });

    test('a step backwards past the start is a mistake in the caller', () {
      final iterator = ProgressIterator(3);

      expect(() => iterator.addSteps(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('Progress', () {
    test('carries the pair it was built from', () {
      const progress = Progress(2, 5);

      expect(progress.number, 2);
      expect(progress.total, 5);
      expect(progress.value, 0.4);
      expect('$progress', '2/5');
    });

    test('the fraction holds its promise where asserts are off', () {
      // The assert in `ProgressIterator.add` is the debug half of the
      // promise. A release build steps past the total without a word, and the
      // fraction still has to be something a progress indicator can take.
      expect(const Progress(4, 3).value, 1.0);
      expect(const Progress(0, 0).value, 1.0);
    });
  });
}
