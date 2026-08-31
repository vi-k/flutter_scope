import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';
import '../../../utils/console/console.dart';

/// A notifier owned by `CounterState` after its asynchronous initialization.
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
    await Future<void>.delayed(const Duration(seconds: 1));
    _count = 0;
  }

  @override
  Future<void> dispose() async {
    console.log(debugSource, '$debugName: controller disposed');
    super.dispose();

    await Future<void>.delayed(const Duration(seconds: 1));
    _count = null;
  }
}

/// A `LiteScope` that exposes immutable widget parameters separately from
/// its lifecycle-aware `CounterState`.
final class CounterScope extends LiteScope<CounterScope, CounterState> {
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
  }) : super(tag: debugName);

  static CounterScope paramsOf(BuildContext context) =>
      LiteScope.paramsOf<CounterScope, CounterState>(
        context,
        listen: false,
      );

  static V selectParam<V>(
    BuildContext context,
    V Function(CounterScope widget) selector, {
    bool listen = true,
  }) =>
      listen
          ? LiteScope.selectParam<CounterScope, CounterState, V>(
              context,
              selector,
            )
          : selector(
              LiteScope.paramsOf<CounterScope, CounterState>(
                context,
                listen: false,
              ),
            );

  static String? titleOf(BuildContext context) =>
      LiteScope.selectParam<CounterScope, CounterState, String?>(
        context,
        (widget) => widget.title,
      );

  static Widget? childOf(BuildContext context) =>
      LiteScope.selectParam<CounterScope, CounterState, Widget?>(
        context,
        (widget) => widget.childScope,
      );

  static CounterState of(BuildContext context) =>
      LiteScope.of<CounterScope, CounterState>(context);

  static V select<V>(
    BuildContext context,
    V Function(CounterState state) selector,
  ) =>
      LiteScope.select<CounterScope, CounterState, V>(
        context,
        selector,
      );

  static bool isInitializedOf(BuildContext context) =>
      LiteScope.select<CounterScope, CounterState, bool>(
        context,
        (state) => state.isInitialized,
      );

  @override
  Widget buildOnWaiting(BuildContext context) {
    return const Text('Waiting…');
  }

  @override
  CounterState createState() => CounterState();
}

/// Owns asynchronous initialization, disposal, and the ready subtree for the
/// lightweight scope.
final class CounterState extends LiteScopeState<CounterScope, CounterState> {
  late final Object _debugSource;
  late final String _debugName;
  late final CounterController counterController;

  /// Whether [initStateAsync] got as far as building the controller.
  ///
  /// [disposeStateAsync] runs after an [initStateAsync] that threw as well as
  /// after one that finished, so what it releases is whatever had been taken
  /// by the time it did -- and a `late final` field the initializer never
  /// reached is not something to read.
  bool _controllerCreated = false;

  @override
  Future<void> initStateAsync() async {
    _debugSource = CounterScope.paramsOf(context).debugSource;
    _debugName = CounterScope.paramsOf(context).debugName;

    console.log(_debugSource, '$_debugName: initialize state');

    counterController = CounterController(
      debugSource: _debugSource,
      debugName: _debugName,
    );
    _controllerCreated = true;
    await counterController.init();

    console.log(_debugSource, '$_debugName: state initialized');
  }

  @override
  Future<void> disposeStateAsync() async {
    console.log(_debugSource, '$_debugName: dispose state');

    // The state built the controller, so the state gives it back: nobody else
    // holds one that the ready branch never handed over.
    if (_controllerCreated) {
      await counterController.dispose();
    }

    await Future<void>.delayed(const Duration(seconds: 1));

    console.log(_debugSource, '$_debugName: state disposed');
  }

  @override
  Widget build(BuildContext context) {
    // The state object exists before its asynchronous fields are ready.
    if (!CounterScope.isInitializedOf(context)) {
      return const Center(
        child: Text('State initializing…'),
      );
    }

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
      listenable: CounterScope.of(context).counterController,
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
    return IconButton(
      color: Theme.of(context).colorScheme.primary,
      onPressed: CounterScope.of(context).counterController.increment,
      icon: const Icon(Icons.add_circle),
    );
  }
}
