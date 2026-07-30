import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../utils/console/console.dart';

final class ScreenDependencies
    extends ScopeAutoDependencies<ScreenDependencies, BuildContext> {
  ScreenDependencies();

  @override
  ScopeDependency buildDependencies(BuildContext context) => sequential('', [
        dep('1', (dep) async {
          console.log(ScreenScope, 'initialize 1');
          await Future<void>.delayed(const Duration(milliseconds: 200));
          dep.dispose = () async {
            console.log(ScreenScope, 'dispose 1');
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          };
        }),
        dep('2', (dep) async {
          console.log(ScreenScope, 'initialize 2');
          await Future<void>.delayed(const Duration(milliseconds: 200));
          dep.dispose = () async {
            console.log(ScreenScope, 'dispose 2');
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          };
        }),
        dep('3', (dep) async {
          console.log(ScreenScope, 'initialize 3');
          await Future<void>.delayed(const Duration(milliseconds: 200));
          dep.dispose = () async {
            console.log(ScreenScope, 'dispose 3');
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          };
        }),
        dep('4', (dep) async {
          console.log(ScreenScope, 'initialize 4');
          await Future<void>.delayed(const Duration(milliseconds: 200));
          dep.dispose = () async {
            console.log(ScreenScope, 'dispose 4');
            await Future<void>.delayed(const Duration(milliseconds: 1000));
          };
        }),
      ]);
}

final class ScreenScope
    extends Scope<ScreenScope, ScreenDependencies, ScreenState> {
  const ScreenScope({
    super.key,
    super.scopeKey,
  }) : super(pauseAfterInitialization: const Duration(milliseconds: 200));

  static ScreenState of(BuildContext context) =>
      Scope.of<ScreenScope, ScreenDependencies, ScreenState>(context);

  @override
  Stream<ScopeInitState<ScopeAutoDependenciesProgress, ScreenDependencies>>
      initDependencies(
    BuildContext context,
  ) =>
          ScreenDependencies().init(context);

  Widget _wrap({required Widget child}) {
    return Scaffold(
      appBar: AppBar(title: const Text('screen scope')),
      body: child,
    );
  }

  @override
  Widget buildOnInitializing(
    BuildContext context,
    covariant ScopeAutoDependenciesProgress? progress,
  ) {
    return _wrap(
      child: Center(
        child: Text(
          'Initializing'
          '${progress == null ? '' : ' ${progress.number}/${progress.total}'}',
        ),
      ),
    );
  }

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant ScopeAutoDependenciesProgress? progress,
  ) {
    return _wrap(
      child: Center(
        child: Text(
          'Error${progress == null ? '' : ' on step $progress'}: $error',
        ),
      ),
    );
  }

  @override
  Widget wrapState(
    BuildContext context,
    ScreenDependencies dependencies,
    Widget child,
  ) =>
      NavigationNode(
        onPop: (context, result) async {
          console.log(ScreenScope, 'close');
          await ScreenScope.of(context).close();
          console.log(ScreenScope, 'closed');
          return true;
        },
        child: _wrap(
          child: child,
        ),
      );

  @override
  ScreenState createState() => ScreenState();

  @override
  Widget buildOnClosing(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.5),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(0, 0.9),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiary,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(blurRadius: 2),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                'This is a screenshot'
                '\nThe actual widget has been removed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onTertiary,
                ),
              ),
            ),
          ),
          const Center(
            child: CircularProgressIndicator.adaptive(),
          ),
        ],
      ),
    );
  }
}

final class ScreenState
    extends ScopeState<ScreenScope, ScreenDependencies, ScreenState> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox.square(
        dimension: 200,
        child: Stack(
          children: [
            Positioned.fill(
              child: Transform.flip(
                flipX: true,
                child: const CircularProgressIndicator(),
              ),
            ),
            const Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(),
              ),
            ),
            Center(
              child: FilledButton(
                onPressed: Navigator.of(context).maybePop,
                child: const Text('close'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
