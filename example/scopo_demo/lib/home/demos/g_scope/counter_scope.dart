import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';
import '../../../utils/console/console.dart';

final class CounterController with ChangeNotifier {
  final Object debugSource;
  final String debugName;

  CounterController({
    required this.debugSource,
    required this.debugName,
  });

  int? _count;
  int get count => _count ?? (throw StateError('Not initialized'));

  void increment() {
    _count = count + 1;
    notifyListeners();
  }

  Future<void> init() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));
    _count = 0;
  }

  @override
  Future<void> dispose() async {
    super.dispose();

    await Future<void>.delayed(const Duration(milliseconds: 500));
    _count = null;
  }
}

final class CounterDependencies
    extends ScopeAutoDependencies<CounterDependencies, BuildContext> {
  final Object debugSource;
  final String debugName;

  late final CounterController counterController;

  CounterDependencies({
    required this.debugSource,
    required this.debugName,
  });

  @override
  Future<void> dispose() async {
    console.log(debugSource, '$debugName: dispose dependencies');
    await super.dispose();
    console.log(debugSource, '$debugName: disposed');
  }

  @override
  ScopeDependency buildDependencies(BuildContext context) {
    return concurrent('', [
      dep('counterController', (dep) async {
        counterController = CounterController(
          debugSource: debugSource,
          debugName: debugName,
        );
        await counterController.init();
        dep.dispose = counterController.dispose;
      }),
      dep('test1', (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }),
      dep('test2', (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }),
    ]);
  }
}

final class CounterScope
    extends Scope<CounterScope, CounterDependencies, CounterState> {
  final String? title;
  final Widget? childScope;
  final Object debugSource;
  final String debugName;

  const CounterScope({
    super.key,
    super.scopeKey,
    this.title,
    this.childScope,
    required this.debugSource,
    required this.debugName,
  }) : super(
          tag: debugName,
          pauseAfterInitialization: const Duration(milliseconds: 1000),
        );

  static CounterScope paramsOf(BuildContext context) =>
      Scope.paramsOf<CounterScope, CounterDependencies, CounterState>(
        context,
        listen: false,
      );

  static V selectParam<V>(
    BuildContext context,
    V Function(CounterScope widget) selector,
  ) =>
      Scope.selectParam<CounterScope, CounterDependencies, CounterState, V>(
        context,
        selector,
      );

  static String? titleOf(BuildContext context) => Scope.selectParam<
          CounterScope, CounterDependencies, CounterState, String?>(
        context,
        (widget) => widget.title,
      );

  static Widget? childOf(BuildContext context) => Scope.selectParam<
          CounterScope, CounterDependencies, CounterState, Widget?>(
        context,
        (widget) => widget.childScope,
      );

  static CounterState of(BuildContext context) =>
      Scope.of<CounterScope, CounterDependencies, CounterState>(context);

  static V select<V>(
    BuildContext context,
    V Function(CounterState state) selector,
  ) =>
      Scope.select<CounterScope, CounterDependencies, CounterState, V>(
        context,
        selector,
      );

  static bool isInitializedOf(BuildContext context) =>
      Scope.select<CounterScope, CounterDependencies, CounterState, bool>(
        context,
        (state) => state.isInitialized,
      );

  @override
  Stream<ScopeInitState<ScopeAutoDependenciesProgress, CounterDependencies>>
      initDependencies(
    BuildContext context,
  ) {
    console.log(debugSource, '$debugName: initialize dependencies');

    return CounterDependencies(
      debugSource: debugSource,
      debugName: debugName,
    ).init(context);
  }

  @override
  Widget buildOnWaiting(BuildContext context) {
    return const Text('Waiting…');
  }

  @override
  Widget buildOnInitializing(
    BuildContext context,
    covariant ScopeAutoDependenciesProgress? progress,
  ) {
    return Text(
      'Initializing'
      '${progress == null ? '' : ' ${progress.number}/${progress.total}'}',
    );
  }

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant ScopeAutoDependenciesProgress? progress,
  ) {
    return Text(
      'Error${progress == null ? '' : ' on step $progress'}: $error',
    );
  }

  @override
  CounterState createState() => CounterState();
}

final class CounterState
    extends ScopeState<CounterScope, CounterDependencies, CounterState> {
  late final Object _debugSource;
  late final String _debugName;

  @override
  Future<void> initAsync() async {
    _debugSource = CounterScope.paramsOf(context).debugSource;
    _debugName = CounterScope.paramsOf(context).debugName;

    console.log(_debugSource, '$_debugName: initialize state');

    await Future<void>.delayed(const Duration(milliseconds: 1000));

    console.log(_debugSource, '$_debugName: initialized');
  }

  @override
  Future<void> disposeAsync() async {
    console.log(_debugSource, '$_debugName: dispose state');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    Widget body = Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [_CounterView(), _IncrementAction()],
            ),
          ],
        ),
      ),
    );

    if (CounterScope.childOf(context) case final child?) {
      body = Row(
        children: [
          Expanded(child: body),
          const VerticalDivider(),
          Expanded(child: child),
        ],
      );
    }

    if (CounterScope.titleOf(context) case final title?) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          body,
        ],
      );
    }

    return body;
  }
}

class _CounterView extends StatelessWidget {
  const _CounterView();

  @override
  Widget build(BuildContext context) {
    return ListenableSelector<CounterController, int>(
      listenable: CounterScope.of(context).dependencies.counterController,
      selector: (controller) => controller.count,
      builder: (context, controller, count, _) {
        return Center(
          child: BlinkingBox(
            blinkingColor:
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            child: Text('$count'),
          ),
        );
      },
    );
  }
}

class _IncrementAction extends StatelessWidget {
  const _IncrementAction();

  @override
  Widget build(BuildContext context) {
    final isInitialized =
        CounterScope.select(context, (state) => state.isInitialized);
    return IconButton(
      color: Theme.of(context).colorScheme.primary,
      onPressed: !isInitialized
          ? null
          : CounterScope.of(context).dependencies.counterController.increment,
      icon: const Icon(Icons.add_circle),
    );
  }
}
