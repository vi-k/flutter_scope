import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';
import '../../../utils/console/console.dart';

final class CounterModel with ChangeNotifier {
  static const int steps = 10;

  final Object debugSource;
  final String debugName;

  CounterModel._({
    required this.debugSource,
    required this.debugName,
  });

  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }

  static Stream<AsyncDataScopeInitState<Progress, CounterModel>> init({
    required Object debugSource,
    required String debugName,
  }) async* {
    console.log(debugSource, '$debugName: initialize');

    var isInitialized = false;
    final iterator = ProgressIterator(steps);

    try {
      yield AsyncDataScopeProgress(iterator.currentStep);
      for (var i = 0; i < steps; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        yield AsyncDataScopeProgress(iterator.nextStep());
      }

      yield AsyncDataScopeReady(
        CounterModel._(
          debugSource: debugSource,
          debugName: debugName,
        ),
      );

      isInitialized = true;
      console.log(debugSource, '$debugName: initialized');
    } finally {
      if (!isInitialized) {
        console.log(debugSource, '$debugName: cancelled');
      }
    }
  }

  @override
  Future<void> dispose() async {
    super.dispose();

    await null;
    console.log(debugSource, '$debugName: dispose');

    await Future<void>.delayed(const Duration(seconds: 2));

    console.log(debugSource, '$debugName: disposed');
  }
}

final class CounterScope
    extends AsyncDataScopeBase<CounterScope, CounterModel> {
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

  static CounterModel of(BuildContext context) =>
      AsyncDataScopeBase.of<CounterScope, CounterModel>(
        context,
        listen: false,
      ).data;

  static int countOf(BuildContext context) =>
      AsyncDataScopeBase.select<CounterScope, CounterModel, int>(
        context,
        (context) => context.data.count,
      );

  @override
  Stream<AsyncDataScopeInitState<Progress, CounterModel>> initData(
    BuildContext context,
  ) =>
      CounterModel.init(
        debugSource: debugSource,
        debugName: debugName,
      );

  @override
  Future<void> disposeData(CounterModel data) async {
    await data.dispose();
  }

  @override
  Widget? buildOnWaiting(BuildContext context) {
    return const Text('Waiting…');
  }

  @override
  Widget buildOnInitializing(
    BuildContext context,
    covariant Progress? progress,
  ) {
    return Text('Initializing${progress == null ? '' : ' $progress'}');
  }

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) {
    return Text('Error: $error');
  }

  @override
  Widget buildOnReady(BuildContext context, CounterModel value) {
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

    if (childScope case final child?) {
      body = Row(
        children: [
          Expanded(child: body),
          const VerticalDivider(),
          Expanded(child: child),
        ],
      );
    }

    if (title case final title?) {
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
    return ListenableSelector<CounterModel, int>(
      listenable: CounterScope.of(context),
      selector: (model) => model.count,
      builder: (context, model, count, _) {
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
      onPressed: CounterScope.of(context).increment,
      icon: const Icon(Icons.add_circle),
    );
  }
}
