// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:scopo/scopo.dart';
import 'package:test/test.dart';

import 'utils/my_fake_async.dart';
import 'utils/observer.dart';

/// Waits out a disposal and asserts it did not fail.
///
/// `waitFuture` puts a failure in a field instead of throwing it, so a result
/// nobody reads is a failure nobody hears. Every test below compares the
/// lists of what was released and the states the tree ends in -- and a
/// regression where `dispose()` completes with an error *after* releasing
/// everything leaves both of those correct. It would have gone green here.
void expectDisposed(MyFakeAsync async, Future<void> disposal) {
  final result = async.waitFuture(disposal);

  expect(
    result.isFailed,
    isFalse,
    reason: 'the disposal completed with ${result.resultOrError}',
  );
}

final class TestDependencies
    extends ScopeAutoDependencies<TestDependencies, void> {
  static const step = Duration(milliseconds: 100);

  final Set<String> failed;

  TestDependencies({this.failed = const {}});

  @override
  bool get autoDisposeOnError => false;

  FutureOr<void> Function(ScopeDependencyHandle) initDep(
    Duration delay, {
    bool dispose = true,
  }) =>
      (dep) async {
        await Future<void>.delayed(delay);
        if (failed.contains(dep.name)) {
          throw Exception('${dep.name} failed');
        }
        if (dispose) {
          dep.dispose = () async {
            await Future<void>.delayed(step);
          };
        }
      };

  // For debug
  //
  // @override
  // ScopeDependency build(_) => concurrent('#0', [
  //       concurrent('#1', [
  //         dep('#2', processDep(step * 3)),
  //         dep('#3', processDep(step * 2)),
  //         dep('#4', processDep(step)),
  //       ]),
  //     ]);

  // Пример сложной структуры зависимостей. Зависимости пронумерованы в
  // том порядке, в котором они будут инициализироваться.
  @override
  ScopeDependency buildDependencies(_) => sequential('', [
        dep('dep1', initDep(step)),
        concurrent('concurrent1', [
          dep('dep4', initDep(step * 3)),
          sequential('sequential1', [
            dep('dep3', initDep(step * 2, dispose: false)),
            concurrent('concurrent2', [
              dep('dep5', initDep(step)),
              sequential('sequential2', [
                dep('dep7', initDep(step)),
                dep('dep8', initDep(step)),
              ]),
              dep('dep6', initDep(step, dispose: false)),
            ]),
            dep('dep9', initDep(step, dispose: false)),
          ]),
          dep('dep2', initDep(step)),
        ]),
        dep('dep10', initDep(step)),
      ]);

  @override
  String toString() => '$TestDependencies';
}

final class TestDependenciesAnonNested
    extends ScopeAutoDependencies<TestDependenciesAnonNested, void> {
  static const step = Duration(milliseconds: 100);

  final Set<String> failed;

  TestDependenciesAnonNested({this.failed = const {}});

  @override
  bool get autoDisposeOnError => false;

  FutureOr<void> Function(ScopeDependencyHandle) initDep(Duration delay) =>
      (dep) async {
        await Future<void>.delayed(delay);
        if (failed.contains(dep.name)) {
          throw Exception('${dep.name} failed');
        }
      };

  // Корень и вложенная группа — обе безымянные, чтобы проверить, что
  // построение пути не добавляет ведущий '/' и не задваивает разделители.
  @override
  ScopeDependency buildDependencies(_) => sequential('', [
        dep('depA', initDep(step)),
        concurrent('', [
          dep('depB', initDep(step)),
        ]),
      ]);

  @override
  String toString() => '$TestDependenciesAnonNested';
}

/// Дерево с именованной вложенной группой: путь листа состоит из нескольких
/// сегментов, и только на таком дереве видно разницу между полным путём и
/// собственным именем зависимости.
final class TestDependenciesNamedNested
    extends ScopeAutoDependencies<TestDependenciesNamedNested, void> {
  static const step = Duration(milliseconds: 10);

  FutureOr<void> Function(ScopeDependencyHandle) initDep(Duration delay) =>
      (dep) async {
        await Future<void>.delayed(delay);
      };

  @override
  ScopeDependency buildDependencies(_) => sequential('', [
        dep('dep1', initDep(step)),
        sequential('group1', [
          dep('dep2', initDep(step)),
        ]),
      ]);

  @override
  String toString() => '$TestDependenciesNamedNested';
}

/// Two children of one concurrent group, failing in the same instant.
///
/// The question it answers: how many of them the group keeps. A guarded stream
/// closes on the first error, so "sibling errors are all kept" was never true --
/// which is what the `Scope` topic used to promise, and what
/// `failedChildren.join(', ')` still reads as.
final class TestDependenciesTwinFailures
    extends ScopeAutoDependencies<TestDependenciesTwinFailures, void> {
  static const step = Duration(milliseconds: 10);

  @override
  bool get autoDisposeOnError => false;

  FutureOr<void> Function(ScopeDependencyHandle) _failAfterStep(String name) =>
      (dep) async {
        await Future<void>.delayed(step);

        throw Exception('$name failed');
      };

  @override
  ScopeDependency buildDependencies(_) => concurrent('twins', [
        dep('depA', _failAfterStep('depA')),
        dep('depB', _failAfterStep('depB')),
      ]);

  @override
  String toString() => '$TestDependenciesTwinFailures';
}

final class TestDependenciesConcurrentNoDispose
    extends ScopeAutoDependencies<TestDependenciesConcurrentNoDispose, void> {
  static const step = Duration(milliseconds: 10);

  FutureOr<void> Function(ScopeDependencyHandle) initDep(Duration delay) =>
      (dep) async {
        await Future<void>.delayed(delay);
        // Намеренно НЕ назначаем dep.dispose: ни одна из зависимостей не
        // требует disposal, поэтому у concurrent-группы при dispose()
        // набор стримов для объединения оказывается пустым.
      };

  // Корневая группа — сама concurrent, чтобы dispose() концентрированной
  // группы вызывался напрямую из ScopeAutoDependencies.dispose().
  @override
  ScopeDependency buildDependencies(_) => concurrent('g', [
        dep('depA', initDep(step)),
        dep('depB', initDep(step)),
      ]);

  @override
  String toString() => '$TestDependenciesConcurrentNoDispose';
}

/// Зеркало [TestDependenciesConcurrentNoDispose] для инициализации: у
/// concurrent-группы нет детей вовсе, поэтому набор стримов, которые
/// объединяет `init()`, пуст — та же дыра, что была в `dispose()`.
final class TestDependenciesConcurrentEmptyInit
    extends ScopeAutoDependencies<TestDependenciesConcurrentEmptyInit, void> {
  @override
  ScopeDependency buildDependencies(_) => concurrent('g', const []);

  @override
  String toString() => '$TestDependenciesConcurrentEmptyInit';
}

/// A small tree that keeps the default [ScopeAutoDependencies
/// .autoDisposeOnError], so a failing dependency is followed at once by the
/// automatic disposal — the path on which the group-level failure used to be
/// overwritten — and so that a second `init()` runs against whatever that
/// disposal left behind.
/// A container whose dependency takes nothing, so there is nothing to release.
///
/// `late final` is what the `Scope` topic teaches, and it is what makes the
/// second run fail where the guard does not stop it.
final class TestHoldsNothingDependencies
    extends ScopeAutoDependencies<TestHoldsNothingDependencies, void> {
  int buildCount = 0;

  late final String value;

  @override
  ScopeDependency buildDependencies(void context) {
    buildCount++;

    return dep('free', (dep) async => value = 'built');
  }
}

final class TestAutoDisposeDependencies
    extends ScopeAutoDependencies<TestAutoDisposeDependencies, void> {
  static const step = Duration(milliseconds: 10);

  final Set<String> failed;

  /// How many times [buildDependencies] ran, so a rebuilt tree can be told
  /// from the one the previous run left behind.
  int buildCount = 0;

  /// The dependencies whose `dispose` callback ran, in order.
  final disposed = <String>[];

  TestAutoDisposeDependencies({this.failed = const {}});

  FutureOr<void> Function(ScopeDependencyHandle) initDep() => (dep) async {
        await Future<void>.delayed(step);
        if (failed.contains(dep.name)) {
          throw Exception('${dep.name} failed');
        }
        dep.dispose = () {
          disposed.add(dep.name);
        };
      };

  // An anonymous root, like `TestDependencies`, so the paths below carry no
  // group segment and the expectations stay about the states alone.
  @override
  ScopeDependency buildDependencies(_) {
    buildCount++;

    return sequential('', [
      dep('depA', initDep()),
      dep('depB', initDep()),
    ]);
  }

  @override
  String toString() => '$TestAutoDisposeDependencies';
}

/// A container written the way the `Scope` topic shows one: `late final`
/// fields assigned by the initializers. It registers a disposer, because a
/// second `init()` is allowed only after a disposal that ran to its end.
final class TestLateFinalDependencies
    extends ScopeAutoDependencies<TestLateFinalDependencies, void> {
  int buildCount = 0;

  late final String value;

  @override
  ScopeDependency buildDependencies(void context) {
    buildCount++;

    return dep('player', (dep) async {
      value = 'built';
      dep.dispose = () {};
    });
  }

  @override
  String toString() => '$TestLateFinalDependencies';
}

/// The same container with the declaration the topic advises for one meant to
/// be initialized more than once.
final class TestLateDependencies
    extends ScopeAutoDependencies<TestLateDependencies, void> {
  int buildCount = 0;

  late String value;

  @override
  ScopeDependency buildDependencies(void context) {
    buildCount++;

    return dep('player', (dep) async {
      value = 'built';
      dep.dispose = () {};
    });
  }

  @override
  String toString() => '$TestLateDependencies';
}

/// A container whose second run fails for a reason of its own, so that the
/// hint about `late final` can be shown not to be pinned on it.
final class TestSecondRunFailsDependencies
    extends ScopeAutoDependencies<TestSecondRunFailsDependencies, void> {
  int buildCount = 0;

  @override
  ScopeDependency buildDependencies(void context) {
    final run = ++buildCount;

    return dep('player', (dep) async {
      if (run > 1) {
        throw Exception('the second run failed on its own');
      }
      dep.dispose = () {};
    });
  }

  @override
  String toString() => '$TestSecondRunFailsDependencies';
}

/// A container whose *first* run trips the same `late final` refusal, because
/// the field was assigned before `init()` was ever called. The wording of that
/// failure is identical, and it is not the one the hint explains.
final class TestPreassignedDependencies
    extends ScopeAutoDependencies<TestPreassignedDependencies, void> {
  late final String value;

  @override
  ScopeDependency buildDependencies(void context) => dep('player', (dep) async {
        value = 'built';
        dep.dispose = () {};
      });

  @override
  String toString() => '$TestPreassignedDependencies';
}

/// Копия логики `handleInit()` (см. группу `TestDependencies` ниже),
/// параметризованная экземпляром зависимостей и `MyFakeAsync`, чтобы её можно
/// было переиспользовать в других группах тестов этого файла.
List<String> handleInitFor<T extends ScopeAutoDependencies<T, void>>(
  T dependencies,
  MyFakeAsync async, {
  Duration? cancel,
}) {
  final completer = Completer<void>();
  final progress = <String>[];

  void errorToBuf(Object error) {
    progress.add('$error');
  }

  void stateToBuf(ScopeInitState<ScopeAutoDependenciesProgress, T> state) {
    progress.add(
      switch (state) {
        ScopeProgress(:final progress) => '$progress',
        ScopeReady(:final dependencies) => '$dependencies',
      },
    );
  }

  final subscription = dependencies //
      .init(null)
      .handleError(errorToBuf)
      .listen(stateToBuf, onDone: completer.complete);

  if (cancel != null) {
    Future.delayed(cancel, () async {
      await subscription.cancel();
      completer.complete();
    });
  }

  async.waitFuture(completer.future);

  return progress;
}

void main() {
  group('TestDependencies', () {
    Future<List<String>> handleInit(
      TestDependencies dependencies, {
      Duration? cancel,
    }) async {
      final completer = Completer<void>();
      final progress = <String>[];

      void errorToBuf(Object error) {
        progress.add('$error');
      }

      void stateToBuf(
        ScopeInitState<ScopeAutoDependenciesProgress, TestDependencies> state,
      ) {
        progress.add(
          switch (state) {
            ScopeProgress(:final progress) => '$progress',
            ScopeReady(:final dependencies) => '$dependencies',
          },
        );
      }

      final subscription = dependencies //
          .init(null)
          .handleError(errorToBuf)
          .listen(stateToBuf, onDone: completer.complete);

      if (cancel != null) {
        Future.delayed(cancel, () async {
          await subscription.cancel();
          completer.complete();
        });
      }

      await completer.future;

      return progress;
    }

    List<String> states(TestDependencies dependencies) =>
        dependencies.flattenDependencies().map((info) => '$info').toList();

    List<String> failedDependencies(TestDependencies dependencies) =>
        dependencies
            .flattenDependenciesWithErrors()
            .map(
              (info) => '${info.path}${info.dependency.name}'
                  ' ${info.dependency.stateToString()}',
            )
            .toList();

    // For debug
    //
    // test('not failed', () {
    //   myFakeAsync((fakeAsync) {
    //     final dependencies = TestDependencies();
    //     final progress = fakeAsync
    //         .waitFuture(
    //           handleInit(
    //             dependencies,
    //             cancel: const Duration(milliseconds: 50),
    //           ),
    //         )
    //         .result;
    //     print(progress.join('\n'));
    //     print(states(dependencies).join('\n'));
    //   });
    // });

    // The dump of a torn-down tree used to read as though half of it were
    // still alive: a dependency that registered no disposer is skipped by its
    // group -- rightly, there is nothing to run -- and was left saying
    // `initialized`. `ScopeDependencyNoDisposalRequired` exists for exactly
    // this state and was reachable from nowhere.
    test('a dependency that had nothing to release says so', () {
      myFakeAsync((fakeAsync) {
        final dependencies = TestDependencies();
        fakeAsync.waitFuture(handleInit(dependencies));
        expectDisposed(fakeAsync, dependencies.dispose());

        ScopeDependency named(String name) => dependencies
            .flattenDependencies()
            .firstWhere((info) => info.dependency.name == name)
            .dependency;

        expect(named('dep3').state, isA<ScopeDependencyNoDisposalRequired>());
        expect(
          named('dep3').isDisposed,
          isTrue,
          reason: 'nothing left to give back is a finished dependency',
        );
        expect(
          named('dep1').state,
          isA<ScopeDependencyDisposed>(),
          reason: 'one that did release something is plainly disposed',
        );
        expect(
          named('dep1').state,
          isNot(isA<ScopeDependencyNoDisposalRequired>()),
        );
      });
    });

    test('normal', () {
      myFakeAsync((fakeAsync) {
        final dependencies = TestDependencies();
        final progress = fakeAsync.waitFuture(handleInit(dependencies)).result;
        expect(progress, [
          'dep1 (1/10)',
          'concurrent1/dep2 (2/10)',
          'concurrent1/sequential1/dep3 (3/10)',
          'concurrent1/dep4 (4/10)',
          'concurrent1/sequential1/concurrent2/dep5 (5/10)',
          'concurrent1/sequential1/concurrent2/dep6 (6/10)',
          'concurrent1/sequential1/concurrent2/sequential2/dep7 (7/10)',
          'concurrent1/sequential1/concurrent2/sequential2/dep8 (8/10)',
          'concurrent1/sequential1/dep9 (9/10)',
          'dep10 (10/10)',
          'TestDependencies',
        ]);
        expect(states(dependencies), [
          '[group] initialized',
          '  "dep1" initialized',
          '  [concurrent1] initialized',
          '    "dep4" initialized',
          '    [sequential1] initialized',
          '      "dep3" initialized',
          '      [concurrent2] initialized',
          '        "dep5" initialized',
          '        [sequential2] initialized',
          '          "dep7" initialized',
          '          "dep8" initialized',
          '        "dep6" initialized',
          '      "dep9" initialized',
          '    "dep2" initialized',
          '  "dep10" initialized',
        ]);
        expect(dependencies.root.isInitialized, true);
        expect(dependencies.root.isFailed, false);
        expect(dependencies.root.isCancelled, false);
        expect(dependencies.root.isDisposed, false);

        expectDisposed(fakeAsync, dependencies.dispose());
        expect(states(dependencies), [
          '[group] disposed',
          '  "dep1" disposed',
          '  [concurrent1] disposed',
          '    "dep4" disposed',
          '    [sequential1] disposed',
          '      "dep3" no disposal required',
          '      [concurrent2] disposed',
          '        "dep5" disposed',
          '        [sequential2] disposed',
          '          "dep7" disposed',
          '          "dep8" disposed',
          '        "dep6" no disposal required',
          '      "dep9" no disposal required',
          '    "dep2" disposed',
          '  "dep10" disposed',
        ]);
        expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
        expect(dependencies.root.isInitialized, false);
        expect(dependencies.root.isFailed, false);
        expect(dependencies.root.isCancelled, false);
        expect(dependencies.root.isDisposed, true);
      });
    });

    group('one error', () {
      // For debug
      //
      // test('failed: #4', () {
      //   myFakeAsync((fakeAsync) {
      //     final dependencies = TestDependencies(failed: {'#4'});
      //     final progress =
      //         fakeAsync.waitFuture(handleInit(dependencies)).result;
      //     print(progress);
      //     print(states(dependencies).join('\n'));
      //   });
      // });

      // For debug
      //
      // test('failed: #4 and #3', () {
      //   myFakeAsync((fakeAsync) {
      //     final dependencies = TestDependencies(failed: {'#4', '#3'});
      //     final progress =
      //         fakeAsync.waitFuture(handleInit(dependencies)).result;
      //     print(progress);
      //     print(states(dependencies).join('\n'));
      //   });
      // });

      // For debug
      //
      // test('failed: #4, #3 and #2', () {
      //   myFakeAsync((fakeAsync) {
      //     final dependencies = TestDependencies(failed: {'#4', '#3', '#2'});
      //     final progress =
      //         fakeAsync.waitFuture(handleInit(dependencies)).result;
      //     print(progress);
      //     print(states(dependencies).join('\n'));
      //   });
      // });

      test('failed: dep1', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep1'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, ['dep1: Exception: dep1 failed']);
          expect(states(dependencies), [
            '[group] failed: dep1',
            '  "dep1" failed: Exception: dep1 failed',
            '  [concurrent1] not initialized',
            '    "dep4" not initialized',
            '    [sequential1] not initialized',
            '      "dep3" not initialized',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" not initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'dep1 failed: Exception: dep1 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: dep1',
            '  "dep1" failed: Exception: dep1 failed',
            '  [concurrent1] not initialized',
            '    "dep4" not initialized',
            '    [sequential1] not initialized',
            '      "dep3" not initialized',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" not initialized',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep2', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep2'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2: Exception: dep2 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep2',
            '  "dep1" initialized',
            '  [concurrent1] failed: dep2',
            '    "dep4" cancelled',
            '    [sequential1] cancelled',
            '      "dep3" cancelled',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" failed: Exception: dep2 failed',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/dep2 failed: Exception: dep2 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep2',
            '  "dep1" disposed',
            '  [concurrent1] failed: dep2',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" cancelled',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" failed: Exception: dep2 failed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep3', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep3'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3: Exception: dep3 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/dep3',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/dep3',
            '    "dep4" cancelled',
            '    [sequential1] failed: dep3',
            '      "dep3" failed: Exception: dep3 failed',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/dep3 failed: Exception: dep3 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/dep3',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/dep3',
            '    "dep4" disposed',
            '    [sequential1] failed: dep3',
            '      "dep3" failed: Exception: dep3 failed',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep4', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep4'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4: Exception: dep4 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep4',
            '  "dep1" initialized',
            '  [concurrent1] failed: dep4',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] cancelled',
            '      "dep3" initialized',
            '      [concurrent2] cancelled',
            '        "dep5" cancelled',
            '        [sequential2] cancelled',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/dep4 failed: Exception: dep4 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep4',
            '  "dep1" disposed',
            '  [concurrent1] failed: dep4',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] disposed',
            '      "dep3" no disposal required',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep5', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep5'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5: Exception: dep5 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep5',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/concurrent2/dep5',
            '    "dep4" initialized',
            '    [sequential1] failed: concurrent2/dep5',
            '      "dep3" initialized',
            '      [concurrent2] failed: dep5',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] cancelled',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/concurrent2/dep5 failed: Exception: dep5 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep5',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/concurrent2/dep5',
            '    "dep4" disposed',
            '    [sequential1] failed: concurrent2/dep5',
            '      "dep3" no disposal required',
            '      [concurrent2] failed: dep5',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep6', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep6'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5 (5/10)',
            'concurrent1/sequential1/concurrent2/dep6: Exception: dep6 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep6',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/concurrent2/dep6',
            '    "dep4" initialized',
            '    [sequential1] failed: concurrent2/dep6',
            '      "dep3" initialized',
            '      [concurrent2] failed: dep6',
            '        "dep5" initialized',
            '        [sequential2] cancelled',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" failed: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/concurrent2/dep6 failed: Exception: dep6 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep6',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/concurrent2/dep6',
            '    "dep4" disposed',
            '    [sequential1] failed: concurrent2/dep6',
            '      "dep3" no disposal required',
            '      [concurrent2] failed: dep6',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" not initialized',
            '        "dep6" failed: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep7', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep7'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5 (5/10)',
            'concurrent1/sequential1/concurrent2/dep6 (6/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep7: Exception: dep7 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/sequential2/dep7',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/concurrent2/sequential2/dep7',
            '    "dep4" initialized',
            '    [sequential1] failed: concurrent2/sequential2/dep7',
            '      "dep3" initialized',
            '      [concurrent2] failed: sequential2/dep7',
            '        "dep5" initialized',
            '        [sequential2] failed: dep7',
            '          "dep7" failed: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" initialized',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/concurrent2/sequential2/dep7 failed: Exception: dep7 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/sequential2/dep7',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/concurrent2/sequential2/dep7',
            '    "dep4" disposed',
            '    [sequential1] failed: concurrent2/sequential2/dep7',
            '      "dep3" no disposal required',
            '      [concurrent2] failed: sequential2/dep7',
            '        "dep5" disposed',
            '        [sequential2] failed: dep7',
            '          "dep7" failed: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" no disposal required',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep8', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep8'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5 (5/10)',
            'concurrent1/sequential1/concurrent2/dep6 (6/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep7 (7/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep8: Exception: dep8 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/sequential2/dep8',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/concurrent2/sequential2/dep8',
            '    "dep4" initialized',
            '    [sequential1] failed: concurrent2/sequential2/dep8',
            '      "dep3" initialized',
            '      [concurrent2] failed: sequential2/dep8',
            '        "dep5" initialized',
            '        [sequential2] failed: dep8',
            '          "dep7" initialized',
            '          "dep8" failed: Exception: dep8 failed',
            '        "dep6" initialized',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/concurrent2/sequential2/dep8 failed: Exception: dep8 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/sequential2/dep8',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/concurrent2/sequential2/dep8',
            '    "dep4" disposed',
            '    [sequential1] failed: concurrent2/sequential2/dep8',
            '      "dep3" no disposal required',
            '      [concurrent2] failed: sequential2/dep8',
            '        "dep5" disposed',
            '        [sequential2] failed: dep8',
            '          "dep7" disposed',
            '          "dep8" failed: Exception: dep8 failed',
            '        "dep6" no disposal required',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep9', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep9'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5 (5/10)',
            'concurrent1/sequential1/concurrent2/dep6 (6/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep7 (7/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep8 (8/10)',
            'concurrent1/sequential1/dep9: Exception: dep9 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/dep9',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/dep9',
            '    "dep4" initialized',
            '    [sequential1] failed: dep9',
            '      "dep3" initialized',
            '      [concurrent2] initialized',
            '        "dep5" initialized',
            '        [sequential2] initialized',
            '          "dep7" initialized',
            '          "dep8" initialized',
            '        "dep6" initialized',
            '      "dep9" failed: Exception: dep9 failed',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/dep9 failed: Exception: dep9 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/dep9',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/dep9',
            '    "dep4" disposed',
            '    [sequential1] failed: dep9',
            '      "dep3" no disposal required',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" disposed',
            '        "dep6" no disposal required',
            '      "dep9" failed: Exception: dep9 failed',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('failed: dep10', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep10'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5 (5/10)',
            'concurrent1/sequential1/concurrent2/dep6 (6/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep7 (7/10)',
            'concurrent1/sequential1/concurrent2/sequential2/dep8 (8/10)',
            'concurrent1/sequential1/dep9 (9/10)',
            'dep10: Exception: dep10 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: dep10',
            '  "dep1" initialized',
            '  [concurrent1] initialized',
            '    "dep4" initialized',
            '    [sequential1] initialized',
            '      "dep3" initialized',
            '      [concurrent2] initialized',
            '        "dep5" initialized',
            '        [sequential2] initialized',
            '          "dep7" initialized',
            '          "dep8" initialized',
            '        "dep6" initialized',
            '      "dep9" initialized',
            '    "dep2" initialized',
            '  "dep10" failed: Exception: dep10 failed',
          ]);
          expect(failedDependencies(dependencies), [
            'dep10 failed: Exception: dep10 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: dep10',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" no disposal required',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" disposed',
            '        "dep6" no disposal required',
            '      "dep9" no disposal required',
            '    "dep2" disposed',
            '  "dep10" failed: Exception: dep10 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });
    });

    group('many errors', () {
      test('dep3, dep4', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep3', 'dep4'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3: Exception: dep3 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/dep3',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/dep3',
            '    "dep4" cancelled with error: Exception: dep4 failed',
            '    [sequential1] failed: dep3',
            '      "dep3" failed: Exception: dep3 failed',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/dep4 cancelled with error: Exception: dep4 failed',
            'concurrent1/sequential1/dep3 failed: Exception: dep3 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/dep3',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/dep3',
            '    "dep4" cancelled with error: Exception: dep4 failed',
            '    [sequential1] failed: dep3',
            '      "dep3" failed: Exception: dep3 failed',
            '      [concurrent2] not initialized',
            '        "dep5" not initialized',
            '        [sequential2] not initialized',
            '          "dep7" not initialized',
            '          "dep8" not initialized',
            '        "dep6" not initialized',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('dep4, dep7`', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep4', 'dep7'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4: Exception: dep4 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep4',
            '  "dep1" initialized',
            '  [concurrent1] failed: dep4',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] cancelled',
            '      "dep3" initialized',
            '      [concurrent2] cancelled',
            '        "dep5" cancelled',
            '        [sequential2] cancelled',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/dep4 failed: Exception: dep4 failed',
            'concurrent1/sequential1/concurrent2/sequential2/dep7 cancelled with error: Exception: dep7 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep4',
            '  "dep1" disposed',
            '  [concurrent1] failed: dep4',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] disposed',
            '      "dep3" no disposal required',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('dep4, dep5, dep7', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(
            failed: {'dep4', 'dep5', 'dep7'},
          );
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4: Exception: dep4 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep4',
            '  "dep1" initialized',
            '  [concurrent1] failed: dep4',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] cancelled',
            '      "dep3" initialized',
            '      [concurrent2] cancelled',
            '        "dep5" cancelled with error: Exception: dep5 failed',
            '        [sequential2] cancelled',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/dep4 failed: Exception: dep4 failed',
            'concurrent1/sequential1/concurrent2/dep5 cancelled with error: Exception: dep5 failed',
            'concurrent1/sequential1/concurrent2/sequential2/dep7 cancelled with error: Exception: dep7 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/dep4',
            '  "dep1" disposed',
            '  [concurrent1] failed: dep4',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] disposed',
            '      "dep3" no disposal required',
            '      [concurrent2] disposed',
            '        "dep5" cancelled with error: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('dep5, dep6`', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(failed: {'dep5', 'dep6'});
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5: Exception: dep5 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep5',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/concurrent2/dep5',
            '    "dep4" initialized',
            '    [sequential1] failed: concurrent2/dep5',
            '      "dep3" initialized',
            '      [concurrent2] failed: dep5',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] cancelled',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" cancelled with error: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/concurrent2/dep5 failed: Exception: dep5 failed',
            'concurrent1/sequential1/concurrent2/dep6 cancelled with error: Exception: dep6 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep5',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/concurrent2/dep5',
            '    "dep4" disposed',
            '    [sequential1] failed: concurrent2/dep5',
            '      "dep3" no disposal required',
            '      [concurrent2] failed: dep5',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" not initialized',
            '        "dep6" cancelled with error: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });

      test('dep5, dep6, dep7`', () {
        myFakeAsync((fakeAsync) {
          final dependencies = TestDependencies(
            failed: {'dep5', 'dep6', 'dep7'},
          );
          final progress =
              fakeAsync.waitFuture(handleInit(dependencies)).result;
          expect(progress, [
            'dep1 (1/10)',
            'concurrent1/dep2 (2/10)',
            'concurrent1/sequential1/dep3 (3/10)',
            'concurrent1/dep4 (4/10)',
            'concurrent1/sequential1/concurrent2/dep5: Exception: dep5 failed',
          ]);
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep5',
            '  "dep1" initialized',
            '  [concurrent1] failed: sequential1/concurrent2/dep5',
            '    "dep4" initialized',
            '    [sequential1] failed: concurrent2/dep5',
            '      "dep3" initialized',
            '      [concurrent2] failed: dep5',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] cancelled',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled with error: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" initialized',
            '  "dep10" not initialized',
          ]);
          expect(failedDependencies(dependencies), [
            'concurrent1/sequential1/concurrent2/dep5 failed: Exception: dep5 failed',
            'concurrent1/sequential1/concurrent2/sequential2/dep7 cancelled with error: Exception: dep7 failed',
            'concurrent1/sequential1/concurrent2/dep6 cancelled with error: Exception: dep6 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);

          expectDisposed(fakeAsync, dependencies.dispose());
          expect(states(dependencies), [
            '[group] failed: concurrent1/sequential1/concurrent2/dep5',
            '  "dep1" disposed',
            '  [concurrent1] failed: sequential1/concurrent2/dep5',
            '    "dep4" disposed',
            '    [sequential1] failed: concurrent2/dep5',
            '      "dep3" no disposal required',
            '      [concurrent2] failed: dep5',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled with error: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyFailed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, true);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, false);
        });
      });
    });
  });

  group('anonymous nested group paths', () {
    test('no leading or double slashes', () {
      final dependencies = TestDependenciesAnonNested(failed: {'depB'});
      myFakeAsync((async) {
        final progress = handleInitFor(dependencies, async);
        expect(progress, ['depA (1/2)', 'depB: Exception: depB failed']);
        expect(
          dependencies
              .flattenDependencies()
              .map((info) => '${info.path}${info.dependency.name}')
              .toList(),
          // Корень, лист depA, вложенная безымянная группа и лист depB —
          // ни один сегмент не даёт ведущий '/' или '//' на любом уровне
          // вложенности безымянных групп.
          ['', 'depA', '', 'depB'],
        );
      });
    });
  });

  group('ScopeAutoDependenciesProgress', () {
    test('carries the full path and the own name of the dependency', () {
      final dependencies = TestDependenciesNamedNested();
      final events = <ScopeAutoDependenciesProgress>[];

      myFakeAsync((async) {
        final completer = Completer<void>();
        final subscription = dependencies.init(null).listen(
          (state) {
            switch (state) {
              case ScopeProgress(:final progress?):
                events.add(progress);
              case ScopeProgress():
              case ScopeReady():
                break;
            }
          },
          onDone: completer.complete,
        );
        async.waitFuture(completer.future);
        unawaited(subscription.cancel());
      });

      expect(
        events.map((event) => event.path).toList(),
        ['dep1', 'group1/dep2'],
        reason: 'path is the whole path from the root of the tree',
      );
      expect(
        events.map((event) => event.name).toList(),
        ['dep1', 'dep2'],
        reason: 'name is the own name of the dependency, not its path',
      );
      expect(
        '${events.last}',
        'group1/dep2 (2/2)',
        reason: 'the readable form keeps naming the dependency in full',
      );
    });
  });

  group('concurrent group with empty stream set', () {
    test('dispose completes when no child requires disposal', () {
      final dependencies = TestDependenciesConcurrentNoDispose();
      myFakeAsync((async) {
        handleInitFor(dependencies, async);
        expect(dependencies.root.isInitialized, isTrue);

        // Ни depA, ни depB не назначили dep.dispose, поэтому у
        // concurrent-группы 'g' при dispose() список стримов для
        // объединения пуст. До фикса _mergeStreams() никогда не вызывает
        // controller.close() на пустом наборе, и dispose() зависает
        // навсегда — флаг disposed так и останется false.
        var disposed = false;
        unawaited(dependencies.dispose().then((_) => disposed = true));
        async.flushMicrotasks();

        expect(disposed, isTrue);
      });
    });

    test('init completes when no child requires initialization', () {
      final dependencies = TestDependenciesConcurrentEmptyInit();
      myFakeAsync((async) {
        // У concurrent-группы 'g' нет детей, поэтому набор стримов для
        // объединения пуст уже на инициализации. Guard в _mergeStreams()
        // один на оба направления, но проверен был только disposal: без
        // него controller.close() не вызывается, init() никогда не
        // завершается, и handleInitFor падает на «No more timers».
        final progress = handleInitFor(dependencies, async);

        expect(progress, ['$TestDependenciesConcurrentEmptyInit']);
        expect(dependencies.root.isInitialized, isTrue);
      });
    });
  });

  group('ScopeAutoDependencies re-initialization', () {
    // `_root` is built once and kept, and every dependency asserts that its
    // own initialization starts from `ScopeDependencyInitial`. A second
    // `init()` on the tree a disposal left behind therefore tripped that
    // assert instead of starting over.
    test(
      'control: a first init() builds the tree and initializes it',
      () {
        myFakeAsync((async) {
          final dependencies = TestAutoDisposeDependencies();
          final progress = handleInitFor(dependencies, async);

          expect(progress, [
            'depA (1/2)',
            'depB (2/2)',
            '$TestAutoDisposeDependencies',
          ]);
          expect(dependencies.buildCount, 1);
          expect(dependencies.root.isInitialized, isTrue);
        });
      },
    );

    test('a second init() rebuilds the tree the disposal left behind', () {
      myFakeAsync((async) {
        final dependencies = TestAutoDisposeDependencies();
        handleInitFor(dependencies, async);
        final firstRoot = dependencies.root;

        expectDisposed(async, dependencies.dispose());
        expect(dependencies.disposed, ['depB', 'depA']);
        expect(dependencies.root.isDisposed, isTrue);

        final progress = handleInitFor(dependencies, async);

        expect(
          dependencies.buildCount,
          2,
          reason: 'a tree that has been disposed of cannot be initialized '
              'again, so the second init() has to build a new one',
        );
        expect(
          identical(dependencies.root, firstRoot),
          isFalse,
          reason: 'the disposed tree must have been replaced, not reused',
        );
        expect(
          progress,
          [
            'depA (1/2)',
            'depB (2/2)',
            '$TestAutoDisposeDependencies',
          ],
          reason: 'the second run must initialize exactly like the first one',
        );
        expect(dependencies.root.isInitialized, isTrue);
        expect(
          dependencies.disposed,
          ['depB', 'depA'],
          reason: 'the second run has not been disposed of yet',
        );
      });
    });

    test('a second init() on a live tree fails with a clear error', () {
      myFakeAsync((async) {
        final dependencies = TestAutoDisposeDependencies();
        handleInitFor(dependencies, async);
        final firstRoot = dependencies.root;

        final progress = handleInitFor(dependencies, async);

        expect(
          progress.single,
          contains('has already been initialized'),
          reason: 'a tree that is still alive must not be silently thrown '
              'away by a second init(): whatever it holds would leak',
        );
        expect(dependencies.buildCount, 1);
        expect(identical(dependencies.root, firstRoot), isTrue);
      });
    });

    // The guard used to stand on "the tree still holds something" rather than
    // on "this container has already run", and the two part company for a
    // tree whose dependencies registered no disposer. There is nothing to
    // leak there, so the second `init()` went through -- and rebuilt the tree
    // over a container whose fields the first run had already assigned. What
    // came out was a `LateInitializationError` from the initializer of a
    // dependency, which reads as a mistake in the caller's own code.
    test('a second init() on a tree that holds nothing fails the same way', () {
      myFakeAsync((async) {
        final dependencies = TestHoldsNothingDependencies();
        handleInitFor(dependencies, async);
        final firstRoot = dependencies.root;

        final progress = handleInitFor(dependencies, async);

        expect(
          progress.single,
          contains('has already been initialized'),
          reason: 'holding nothing is not the same as having been disposed '
              'of, and the container is the same object either way',
        );
        expect(dependencies.buildCount, 1);
        expect(identical(dependencies.root, firstRoot), isTrue);
      });
    });

    // The `Scope` topic tells the reader that `late final` makes a container
    // single-use and that one meant to run more than once wants `late`. Both
    // halves of that promise were held by nothing until here: the suite could
    // go green over a package that had stopped keeping either.
    //
    // The first test holds one thing more -- what the failure says. The
    // container knows, at the moment a dependency throws, that this is a
    // second run over fields an earlier one assigned; the bare
    // `LateInitializationError` reads as a mistake in the caller's own code
    // and says none of it.
    test('a late final field refuses the second run, and says why', () {
      myFakeAsync((async) {
        final dependencies = TestLateFinalDependencies();
        handleInitFor(dependencies, async);

        expectDisposed(async, dependencies.dispose());

        final progress = handleInitFor(dependencies, async);

        expect(
          progress.single,
          allOf(
            contains('player: LateInitializationError'),
            contains('second `init()`'),
            contains('`late`'),
          ),
          reason: 'naming the dependency is not the answer: the reason is '
              'that this container has run before',
        );
        expect(
          dependencies.buildCount,
          2,
          reason: 'the tree was rebuilt -- the refusal is the field, not the '
              'guard',
        );
      });
    });

    test('a late field lets the container run again', () {
      myFakeAsync((async) {
        final dependencies = TestLateDependencies();
        handleInitFor(dependencies, async);

        expectDisposed(async, dependencies.dispose());

        final progress = handleInitFor(dependencies, async);

        expect(
          progress,
          ['player (1/1)', '$TestLateDependencies'],
          reason: 'this is what the topic promises for a container meant to '
              'be initialized more than once',
        );
        expect(dependencies.value, 'built');
      });
    });

    test('a failure of the second run is not blamed on late final', () {
      myFakeAsync((async) {
        final dependencies = TestSecondRunFailsDependencies();
        handleInitFor(dependencies, async);

        expectDisposed(async, dependencies.dispose());

        final progress = handleInitFor(dependencies, async);

        expect(
          progress.single,
          contains('the second run failed on its own'),
        );
        expect(
          progress.single,
          isNot(contains('`late`')),
          reason: 'the hint explains one failure, and a hint that shows up '
              'beside the others is one nobody believes',
        );
      });
    });

    // The wording of the failure is the same one the hint is matched on, and
    // everything the hint would say about it is false: no run of this
    // container has finished, and the field was not assigned by one. Without
    // the container asking whether it has run before, the text alone would be
    // enough to print it.
    test('a first run tripping the same refusal is not given the hint', () {
      myFakeAsync((async) {
        final dependencies = TestPreassignedDependencies()..value = 'by hand';

        final progress = handleInitFor(dependencies, async);

        expect(
          progress.single,
          contains('player: LateInitializationError'),
          reason: 'the failure is the one the hint is matched on',
        );
        expect(
          progress.single,
          isNot(contains('second `init()`')),
          reason: 'there was no earlier run to blame it on',
        );
      });
    });
  });

  // `ScopeDependencyDisposalCancelled` was read as unreachable: nothing in the
  // package stops a teardown walk halfway. The walk is public, though --
  // `dispose()` is a stream -- so a caller who drives one and cancels the
  // subscription reaches the state, and this is what it looks like.
  test('a disposal cancelled by whoever drove it says so', () {
    myFakeAsync((async) {
      final dependencies = TestDependencies();
      handleInitFor(dependencies, async);

      final subscription = dependencies.root.dispose().listen((_) {});
      async
        ..elapse(TestDependencies.step)
        ..waitFuture(subscription.cancel());

      expect(dependencies.root.state, isA<ScopeDependencyDisposalCancelled>());
      expect(dependencies.root.stateToString(), 'disposal cancelled');
      expect(
        dependencies.root.isDisposed,
        isFalse,
        reason: 'a walk that stopped halfway did not dispose of the tree',
      );
    });
  });

  // The `Scope` topic used to promise that sibling errors are all kept in the
  // state, and the group renders them with a `join(', ')` that reads the same
  // way. Neither is true: the stream a group runs its children in is guarded,
  // and a guarded stream closes on the first error -- so the state keeps one
  // failed child however many fail in the same instant.
  test('a group keeps one failed child, not every sibling that fell over', () {
    myFakeAsync((async) {
      final dependencies = TestDependenciesTwinFailures();
      handleInitFor(dependencies, async);

      final state = dependencies.root.state;
      expect(state, isA<ScopeDependencyFailed>());
      expect(
        (state as ScopeDependencyFailed).errors(),
        hasLength(1),
        reason: 'two children failed at once, and the group closed on the '
            'first of them',
      );
      expect(
        dependencies.root.stateToString(),
        anyOf('failed: depA', 'failed: depB'),
        reason: 'so the rendered state names one child, never a pair',
      );
    });
  });

  group('ScopeAutoDependencies failure after the automatic disposal', () {
    // A group is disposed of *because* something under it failed
    // (`ScopeDependencyGroup.disposalRequired` covers
    // `ScopeDependencyFailed`), and `dispose` used to overwrite that state
    // with `ScopeDependencyDisposed` — so with the default
    // `autoDisposeOnError` the caller was left with a tree that said nothing
    // about what had gone wrong. A failed *leaf* keeps its errors by the same
    // rule -- a state that carries them is not overwritten -- and it is disposed
    // of all the same, whenever its initializer took something before it failed.
    // The groups now behave the same way.
    test('control: a tree that succeeded ends up disposed', () {
      myFakeAsync((async) {
        final dependencies = TestAutoDisposeDependencies();
        handleInitFor(dependencies, async);
        expectDisposed(async, dependencies.dispose());

        expect(dependencies.root.stateToString(), 'disposed');
        expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
        expect(dependencies.root.isDisposed, isTrue);
        expect(dependencies.root.isFailed, isFalse);
      });
    });

    test('keeps the group-level error list readable', () {
      myFakeAsync((async) {
        final dependencies = TestAutoDisposeDependencies(failed: {'depB'});
        final progress = handleInitFor(dependencies, async);

        expect(progress, ['depA (1/2)', 'depB: Exception: depB failed']);
        expect(
          dependencies.disposed,
          ['depA'],
          reason: 'autoDisposeOnError must already have released depA',
        );

        expect(
          dependencies.root.stateToString(),
          'failed: depB',
          reason: 'the disposal must not erase which child failed',
        );
        expect(dependencies.root.state, isA<ScopeDependencyFailed>());
        expect(
          (dependencies.root.state as ScopeDependencyAnyFailed).errors(),
          hasLength(1),
          reason: 'the error list is the only record of the failure',
        );
        expect(dependencies.root.isFailed, isTrue);
        expect(
          dependencies.root.disposalRequired,
          isFalse,
          reason: 'a group that has been disposed of does not need disposing '
              'again, whatever its state says about the initialization',
        );
      });
    });

    test('a second dispose() does not release anything twice', () {
      myFakeAsync((async) {
        final dependencies = TestAutoDisposeDependencies(failed: {'depB'});
        handleInitFor(dependencies, async);
        expect(dependencies.disposed, ['depA']);

        expectDisposed(async, dependencies.dispose());

        expect(dependencies.disposed, ['depA']);
        expect(dependencies.root.stateToString(), 'failed: depB');
      });
    });
  });

  group('ScopeAutoDependencies failed initialization that cannot let go', () {
    // The `finally` of the generator runs while the failure is on its way out
    // of it, and nothing downstream sees that failure until the generator
    // finishes. An `await dispose()` with no limit therefore does not merely
    // leak a disposer: it holds the failure itself, and the scope above shows
    // its loading branch for good -- nothing on screen and nothing in the
    // console. The neighbouring family bounds the same wait for the same
    // reason, in `AsyncControllerScopeElementBase`.
    test(
      'a disposer that never finishes does not hold the failure back',
      () async {
        ScopeConfig.defaultDisposeScopeTimeout =
            const Duration(milliseconds: 50);
        addTearDown(ScopeConfig.reset);

        final dependencies = HangingDisposeDependencies();

        await expectLater(
          dependencies.init(null).drain<void>(),
          throwsA(
            isA<Exception>().having(
              (error) => error.toString(),
              'toString',
              contains('the second one failed'),
            ),
          ),
          reason: 'the failure of the initialization is what the scope above '
              'is waiting for, and giving up on the disposer is what lets it '
              'through',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    // The sixth bounded wait of the package, and the one that used to read the
    // default straight out of `ScopeConfig` instead of resolving it. The other
    // five turn a `ScopeTimeout.none` into the `null` that means "no limit at
    // all"; here the marker went on to a timer as the negative length it is
    // made of, and the wait gave up on the very first tick -- one value of one
    // switch meaning opposite things in neighbouring places.
    test(
      'ScopeTimeout.none as the global default removes the limit',
      () async {
        ScopeConfig.defaultDisposeScopeTimeout = ScopeTimeout.none;
        addTearDown(ScopeConfig.reset);

        final dependencies = HangingDisposeDependencies();
        addTearDown(() {
          if (!dependencies.hang.isCompleted) {
            dependencies.hang.complete();
          }
        });

        var settled = false;
        unawaited(
          dependencies
              .init(null)
              .drain<void>()
              .catchError((Object _) {})
              .whenComplete(() => settled = true),
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          settled,
          isFalse,
          reason: 'with no limit the failure stays inside the generator for as '
              'long as the disposer holds it',
        );

        dependencies.hang.complete();
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(
          settled,
          isTrue,
          reason: 'and the wait was unbounded rather than stuck: releasing the '
              'disposer lets the failure out',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('ScopeAutoDependencies unmount that fails more than once', () {
    // A throw carries one failure, and the first hook to fail claims it. Every
    // one behind it used to be dropped where it happened -- not passed to the
    // caller, not sent to the observer, not reported. The walk itself was
    // right: every sibling is unmounted whatever any one of them makes of it.
    test('reports the failures behind the first instead of dropping them',
        () async {
      final observer = RecordingObserver();
      ScopeConfig.observer = observer;
      addTearDown(() => ScopeConfig.observer = null);

      final log = <String>[];
      final dependencies = TwoFailingUnmountsDependencies(log);
      await dependencies.init(null).drain<void>();

      expect(
        dependencies.onUnmount,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            // Reverse declaration order: the later dependency is built on top
            // of the earlier one, so it stops reaching the world first.
            'unmount b failed',
          ),
        ),
        reason: 'the first hook to fail is the one the caller hears',
      );

      expect(
        log,
        ['unmount b', 'unmount a'],
        reason: 'and both hooks ran: one that threw is no reason to leave the '
            'sibling below it holding what it holds',
      );
      expect(
        observer.events.where((event) => event.contains('unmount')),
        contains(contains('unmount a failed')),
        reason: 'and the one behind it is reported rather than dropped where '
            'it happened',
      );
    });
  });

  group('ScopeAutoDependencies concurrent init', () {
    // `_prepareDependencies` refuses a second `init()` on a live tree, and the
    // test above proves it. What it asked was whether the tree had left
    // `ScopeDependencyInitial` -- and a tree that is initializing right now has
    // not: that state is set at the very end of the run. So a second call
    // arriving while the first was parked on an `await` was handed the same
    // tree and started it again. The second run overwrote the one
    // `ScopeDependencyHandle` of each dependency, and with it the `unmount` and
    // `dispose` the first run had registered: what the first run took was left
    // with nothing to release it.
    test(
      'a second init() while the first is still running is refused',
      () async {
        final gate = Completer<void>();
        final log = <String>[];
        final dependencies = SlowInitDependencies(gate, log);
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });

        final first = dependencies.init(null).drain<void>();
        // One turn, so the initializer runs as far as its own `await`.
        await Future<void>.delayed(Duration.zero);

        // Not awaited before the gate is released: without the refusal the
        // second run parks on the very same gate, so awaiting it here would
        // hang the run rather than fail this test.
        Object? refused;
        final second = dependencies
            .init(null)
            .drain<void>()
            .catchError((Object error) => refused = error);

        gate.complete();
        await first;
        await second;

        expect(
          log,
          ['init slow'],
          reason: 'the initializer of a dependency runs once per tree',
        );
        expect(
          refused,
          isA<StateError>(),
          reason: 'and the caller is told, rather than left believing it '
              'started something',
        );

        await dependencies.dispose();

        expect(
          log,
          ['init slow', 'dispose slow'],
          reason: 'what the one run took is what the disposal gives back',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    // The last unguarded diagonal of the four. Second `init()` during the
    // first is refused, second `init()` on a tree not given back is refused,
    // a second `dispose()` joins the walk already running -- and `dispose()`
    // during an `init()` used to go ahead. It walked a tree whose parked
    // dependency had registered nothing yet, read it as one with nothing to
    // release, marked it disposed of and reported success -- before the
    // initialization had even reached `ScopeReady`. The disposer registered a
    // moment later was then attached to a dependency every future walk skips.
    //
    // Out of reach through a scope, which cancels the init subscription before
    // it disposes of anything. In reach for whoever drives a container by
    // hand, which is public, documented and tested -- and "the user left while
    // init was running, so I called dispose()" is the first thing such an
    // owner writes.
    test(
      'a dispose() while the first init() is still running is refused',
      () async {
        final gate = Completer<void>();
        final log = <String>[];
        final dependencies = LateRegisteringDependencies(gate, log);
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });

        final first = dependencies.init(null).drain<void>();
        // One turn, so the initializer runs as far as its own `await`. Its
        // handle is empty at this point: there is nothing to give back yet.
        await Future<void>.delayed(Duration.zero);

        Object? refused;
        await dependencies.dispose().catchError((Object error) {
          refused = error;
        });

        expect(
          refused,
          isA<StateError>(),
          reason: 'a walk started here cannot see what the parked initializer '
              'is about to register, so it must not start',
        );
        expect(
          log,
          ['init slow'],
          reason: 'and nothing was released, because nothing was taken yet',
        );

        gate.complete();
        await first;

        expect(
          dependencies.root.isDisposed,
          isFalse,
          reason: 'the refused walk left no mark: the tree is alive and the '
              'initialization it interrupted nothing of has finished',
        );

        await dependencies.dispose();

        expect(
          log,
          ['init slow', 'dispose slow'],
          reason: 'the disposer registered after the await is reached by the '
              'walk that comes later -- which is the whole point',
        );
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    // The same hole one layer down, and reachable without the container:
    // `ScopeDependency` is public and `init()` is on its interface, so a tree
    // driven by hand -- or a `ScopeDependencies` written against the interface
    // rather than built by `ScopeAutoDependencies` -- never passes the guard
    // above. The handle is the leaf's, so this is where the loss happens.
    test(
      'a dependency refuses a second init() while the first is running',
      () async {
        final gate = Completer<void>();
        final log = <String>[];
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });

        final dependency = ScopeDependency('slow', (dep) async {
          log.add('init slow');
          dep.dispose = () => log.add('dispose slow');
          await gate.future;
        });

        final first = dependency.init().drain<void>();
        await Future<void>.delayed(Duration.zero);

        Object? refused;
        final second = dependency
            .init()
            .drain<void>()
            .catchError((Object error) => refused = error);

        gate.complete();
        await first;
        await second;

        expect(log, ['init slow']);
        expect(refused, isA<StateError>());
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('ScopeAutoDependencies concurrent dispose', () {
    // The mirror of the concurrent `init()` above, and the same shape: the
    // handle is read at the top of the walk and cleared in the `finally`, so a
    // second `dispose()` arriving while the first is parked on the disposer
    // reads the same hook and runs it again. For a sink, a transaction, a file
    // or a network client that is an exception, a double rollback, or damage
    // outside the process.
    test(
      'a second dispose() while the first is still running releases once',
      () async {
        final gate = Completer<void>();
        final log = <String>[];
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });

        final dependency = ScopeDependency('slow', (dep) {
          dep.dispose = () async {
            log.add('dispose slow');
            await gate.future;
          };
        });

        await dependency.init().drain<void>();

        final first = dependency.dispose().drain<void>();
        await Future<void>.delayed(Duration.zero);
        final second = dependency.dispose().drain<void>();

        gate.complete();
        await first;
        await second;

        expect(log, ['dispose slow']);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'a container joins the disposal already running instead of starting one',
      () async {
        final gate = Completer<void>();
        final log = <String>[];
        addTearDown(() {
          if (!gate.isCompleted) {
            gate.complete();
          }
        });

        final dependencies = SlowDisposeDependencies(gate, log);
        await dependencies.init(null).drain<void>();

        final first = dependencies.dispose();
        await Future<void>.delayed(Duration.zero);
        final second = dependencies.dispose();

        expect(
          identical(first, second),
          isTrue,
          reason: 'the second caller observes the run already going rather '
              'than opening a second teardown of the same tree',
        );

        gate.complete();
        await first;

        expect(log, ['dispose slow']);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('ScopeAutoDependencies a disposal that was cancelled', () {
    // `dispose()` is a stream, and a caller who stops listening leaves what the
    // walk had not reached still holding what it took. Marked done all the
    // same, the tree stopped saying it needed disposing of -- so the next
    // `init()` replaced it, and everything the walk never reached became
    // unreachable.
    test('leaves the tree still asking to be disposed of', () async {
      final log = <String>[];
      final dependencies = TwoDisposersDependencies(log);

      await dependencies.init(null).drain<void>();

      // Stopped after the first path arrives, which is one child in.
      final subscription = dependencies.root.dispose().listen(null);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(
        dependencies.root.disposalRequired,
        isTrue,
        reason: 'the walk was stopped, and what it never reached is still '
            'holding what it took',
      );
      await expectLater(
        dependencies.init(null).drain<void>(),
        throwsA(isA<StateError>()),
        reason: 'so a second init() is refused rather than quietly replacing '
            'a tree nobody can reach any more',
      );
    });
  });

  group('ScopeAutoDependencies a leaf that registered only unmount', () {
    // `unmount` is a documented way to hold something -- a subscription is the
    // usual one -- and `disposalRequired` asked only about `dispose`. A bare
    // leaf as the root of a container therefore said it held nothing, and the
    // next `init()` replaced it in silence: the `unmount` of the first run was
    // never called at all.
    test('is not replaced by a second init()', () async {
      final log = <String>[];
      final dependencies = UnmountOnlyDependencies(log);

      await dependencies.init(null).drain<void>();

      expect(
        dependencies.root.disposalRequired,
        isTrue,
        reason: 'a hook that has to run is something to hold on to',
      );
      await expectLater(
        dependencies.init(null).drain<void>(),
        throwsA(isA<StateError>()),
      );

      dependencies.onUnmount();

      expect(log, ['unmount #1']);
    });
  });

  group('ScopeAutoDependencies type argument', () {
    // The first type argument is the container itself, and naming a different
    // container there compiles: the bound only asks for *a* container. It used
    // to be found out at the very end of a successful initialization, where
    // `ScopeReady` casts -- the whole tree built and running, a bare
    // `TypeError` out of a line nobody wrote, and no teardown, since the one
    // in `init` is for a tree that did not finish.
    test('naming another container is refused before anything is built',
        () async {
      final built = <String>[];
      final dependencies = WrongTypeArgumentDependencies(built);

      await expectLater(
        dependencies.init(null).drain<void>(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('$WrongTypeArgumentDependencies'),
              contains('$TestDependencies'),
            ),
          ),
        ),
      );

      expect(
        built,
        isEmpty,
        reason: 'nothing was built, so there is nothing left holding anything',
      );
    });
  });
}

/// A tree whose first dependency can never be released and whose second one
/// fails, so the teardown of the failure runs into a disposer that hangs.
final class HangingDisposeDependencies
    extends ScopeAutoDependencies<HangingDisposeDependencies, void> {
  final hang = Completer<void>();

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('holds', (dep) => dep.dispose = () => hang.future),
        dep('fails', (dep) => throw Exception('the second one failed')),
      ]);
}

/// A container whose two dependencies both fail to unmount.
final class TwoFailingUnmountsDependencies
    extends ScopeAutoDependencies<TwoFailingUnmountsDependencies, void> {
  final List<String> log;

  TwoFailingUnmountsDependencies(this.log);

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        for (final name in ['a', 'b'])
          dep(name, (dep) {
            dep.unmount = () {
              log.add('unmount $name');

              throw StateError('unmount $name failed');
            };
          }),
      ]);
}

/// A container whose one dependency parks its *disposer* on a gate.
final class SlowDisposeDependencies
    extends ScopeAutoDependencies<SlowDisposeDependencies, void> {
  final Completer<void> gate;
  final List<String> log;

  SlowDisposeDependencies(this.gate, this.log);

  @override
  ScopeDependency buildDependencies(void context) => dep('slow', (dep) {
        dep.dispose = () async {
          log.add('dispose slow');
          await gate.future;
        };
      });
}

/// A container of two dependencies, each with a disposer, so a walk can be
/// stopped between them.
final class TwoDisposersDependencies
    extends ScopeAutoDependencies<TwoDisposersDependencies, void> {
  final List<String> log;

  TwoDisposersDependencies(this.log);

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('a', (dep) => dep.dispose = () => log.add('dispose a')),
        dep('b', (dep) {
          dep.dispose = () async {
            log.add('dispose b');
            await Future<void>.delayed(const Duration(milliseconds: 20));
          };
        }),
      ]);
}

/// A bare leaf as the root of a container, holding a subscription through
/// `unmount` alone — the shape `disposalRequired` could not see.
final class UnmountOnlyDependencies
    extends ScopeAutoDependencies<UnmountOnlyDependencies, void> {
  final List<String> log;

  int _runs = 0;

  UnmountOnlyDependencies(this.log);

  @override
  ScopeDependency buildDependencies(void context) {
    final run = ++_runs;

    return dep('held', (dep) => dep.unmount = () => log.add('unmount #$run'));
  }
}

/// A container whose one dependency parks on a gate, so a second `init()` can
/// arrive while the first is still running.
final class SlowInitDependencies
    extends ScopeAutoDependencies<SlowInitDependencies, void> {
  final Completer<void> gate;
  final List<String> log;

  SlowInitDependencies(this.gate, this.log);

  @override
  ScopeDependency buildDependencies(void context) => dep('slow', (dep) async {
        log.add('init slow');
        dep.dispose = () => log.add('dispose slow');
        await gate.future;
      });
}

/// A container whose dependency parks *before* it has anything to give back.
///
/// The shape a hand-written initializer takes whenever the acquisition itself
/// is the slow part -- `final db = await open(); dep.dispose = db.close;`.
/// While it is parked the handle is empty, so the tree answers "nothing to
/// release" about a dependency that is about to hold something.
final class LateRegisteringDependencies
    extends ScopeAutoDependencies<LateRegisteringDependencies, void> {
  LateRegisteringDependencies(this.gate, this.log);

  final Completer<void> gate;
  final List<String> log;

  @override
  ScopeDependency buildDependencies(void context) => dep('slow', (dep) async {
        log.add('init slow');
        await gate.future;
        dep.dispose = () => log.add('dispose slow');
      });
}

/// A container that names another one where it should name itself -- the
/// copy-paste the compiler cannot catch.
final class WrongTypeArgumentDependencies
    extends ScopeAutoDependencies<TestDependencies, void> {
  final List<String> built;

  WrongTypeArgumentDependencies(this.built);

  @override
  ScopeDependency buildDependencies(void context) {
    built.add('built');

    return dep('held', (dep) {});
  }
}
