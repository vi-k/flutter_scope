// ignore_for_file: discarded_futures

import 'dart:async';

import 'package:scopo/scopo.dart';
import 'package:scopo/src/environment/scope_config.dart';
import 'package:test/test.dart';

import 'utils/logging.dart';
import 'utils/my_fake_async.dart';

final _log = log.withAddedName('test');

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
        _log.v(() => 'init: ${dep.name} delay');
        await Future<void>.delayed(delay);
        _log.v(() => 'init: ${dep.name} after delay');
        if (failed.contains(dep.name)) {
          _log.d(() => 'init: ${dep.name} fail');
          throw Exception('${dep.name} failed');
        }
        if (dispose) {
          dep.dispose = () async {
            _log.v(() => 'dispose: ${dep.name}');
            await Future<void>.delayed(step);
            _log.v(() => 'dispose: ${dep.name} after delay');
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
        _log.v(() => 'init: ${dep.name} delay');
        await Future<void>.delayed(delay);
        _log.v(() => 'init: ${dep.name} after delay');
        if (failed.contains(dep.name)) {
          _log.d(() => 'init: ${dep.name} fail');
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
        _log.v(() => 'init: ${dep.name} delay');
        await Future<void>.delayed(delay);
        _log.v(() => 'init: ${dep.name} after delay');
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
    _log.withAddedName('handleInitFor').v(() => 'state=$state');
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
  logInit();

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
        _log.withAddedName('handleInit').v(() => 'state=$state');
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
        fakeAsync
          ..waitFuture(handleInit(dependencies))
          ..waitFuture(dependencies.dispose());

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

        fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

          fakeAsync.waitFuture(dependencies.dispose());
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

        async.waitFuture(dependencies.dispose());
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
        async.waitFuture(dependencies.dispose());

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

        async.waitFuture(dependencies.dispose());

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
