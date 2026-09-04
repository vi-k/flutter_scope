import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';
import '../../../utils/console/console.dart';

/// Produces progress events followed by the notifier consumed as scope data.
/// Cancellation before readiness is visible in the demo console.
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

  static Future<CounterModel> init(
    ScopeInitContext ctx, {
    required Object debugSource,
    required String debugName,
  }) async {
    console.log(debugSource, '$debugName: initialize');

    final iterator = ProgressIterator(steps);

    try {
      ctx.progress(iterator.currentStep);
      for (var i = 0; i < steps; i++) {
        // Through the context rather than a bare `await`: the wait ends the
        // moment the scope gives up, instead of running the demo out to its
        // last step for a screen that is already gone.
        await ctx.wait(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        ctx.progress(iterator.nextStep());
      }

      final model = CounterModel._(
        debugSource: debugSource,
        debugName: debugName,
      );
      console.log(debugSource, '$debugName: initialized');

      return model;
    } on ScopeInitCancelled {
      // The cancellation arrives as a throw, so it can be told from a failure
      // by its type -- and the model was never built, so there is nothing to
      // dispose of, only something to say.
      console.log(debugSource, '$debugName: cancelled');
      rethrow;
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

/// An `AsyncDataScopeBase` that turns the initialization stream into a
/// ready `CounterModel` and owns its later disposal.
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

  @override
  Future<CounterModel> initData(BuildContext context, ScopeInitContext ctx) =>
      CounterModel.init(
        ctx,
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
  Widget buildOnProgress(
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
  Widget buildOnReady(BuildContext context, CounterModel data) {
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
