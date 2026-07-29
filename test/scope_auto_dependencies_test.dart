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

  FutureOr<void> Function(DepHelper) initDep(
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

  FutureOr<void> Function(DepHelper) initDep(Duration delay) => (dep) async {
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
          '      "dep3" initialized',
          '      [concurrent2] disposed',
          '        "dep5" disposed',
          '        [sequential2] disposed',
          '          "dep7" disposed',
          '          "dep8" disposed',
          '        "dep6" initialized',
          '      "dep9" initialized',
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
            '[group] disposed',
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
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" cancelled',
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
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" cancelled',
            '    [sequential1] disposed',
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
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" cancelled',
            '        [sequential2] disposed',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" failed: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" failed: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" initialized',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" failed: Exception: dep8 failed',
            '        "dep6" initialized',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" disposed',
            '        "dep6" initialized',
            '      "dep9" failed: Exception: dep9 failed',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" disposed',
            '        [sequential2] disposed',
            '          "dep7" disposed',
            '          "dep8" disposed',
            '        "dep6" initialized',
            '      "dep9" initialized',
            '    "dep2" disposed',
            '  "dep10" failed: Exception: dep10 failed',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" cancelled with error: Exception: dep4 failed',
            '    [sequential1] disposed',
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
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" cancelled',
            '        [sequential2] disposed',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" failed: Exception: dep4 failed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
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
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" cancelled',
            '          "dep8" not initialized',
            '        "dep6" cancelled with error: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
            '[group] disposed',
            '  "dep1" disposed',
            '  [concurrent1] disposed',
            '    "dep4" disposed',
            '    [sequential1] disposed',
            '      "dep3" initialized',
            '      [concurrent2] disposed',
            '        "dep5" failed: Exception: dep5 failed',
            '        [sequential2] disposed',
            '          "dep7" cancelled with error: Exception: dep7 failed',
            '          "dep8" not initialized',
            '        "dep6" cancelled with error: Exception: dep6 failed',
            '      "dep9" not initialized',
            '    "dep2" disposed',
            '  "dep10" not initialized',
          ]);
          expect(dependencies.root.state, isA<ScopeDependencyDisposed>());
          expect(dependencies.root.isInitialized, false);
          expect(dependencies.root.isFailed, false);
          expect(dependencies.root.isCancelled, false);
          expect(dependencies.root.isDisposed, true);
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
}
