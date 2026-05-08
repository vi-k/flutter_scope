import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';
import '../../../utils/console/console.dart';

final class CounterModel with ChangeNotifier {
  final Object debugSource;
  final String debugName;

  CounterModel({
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
    super.dispose();

    await Future<void>.delayed(const Duration(seconds: 1));
    _count = null;
  }
}

final class CounterScope
    extends AsyncScopeCore<CounterScope, CounterScopeElement> {
  final Object? scopeKey;
  final String? title;
  final Widget? childScope;
  final Object debugSource;
  final String debugName;

  const CounterScope({
    super.key,
    this.scopeKey,
    this.title,
    this.childScope,
    required this.debugSource,
    required this.debugName,
  }) : super(tag: debugName);

  @override
  CounterScopeElement createScopeElement() => CounterScopeElement(this);

  static CounterModel of(BuildContext context) =>
      AsyncScopeCore.of<CounterScope, CounterScopeElement>(
        context,
        listen: false,
      )._model;

  static int countOf(BuildContext context) =>
      AsyncScopeCore.select<CounterScope, CounterScopeElement, int>(
        context,
        (context) => context._model.count,
      );
}

final class CounterScopeElement
    extends AsyncScopeElementBase<CounterScope, CounterScopeElement> {
  late final CounterModel _model;

  CounterScopeElement(super.widget);

  @override
  Object? get scopeKey => widget.scopeKey;

  @override
  Duration? get pauseAfterInitialization => const Duration(milliseconds: 1000);

  @override
  void init() {
    super.init();
    _model = CounterModel(
      debugSource: widget.debugSource,
      debugName: widget.debugName,
    );
  }

  @override
  Stream<AsyncScopeInitState> initAsync() async* {
    console.log(widget.debugSource, '${widget.debugName}: initialize');
    await _model.init();
    yield AsyncScopeReady();
    console.log(widget.debugSource, '${widget.debugName}: initialized');
  }

  @override
  Future<void> disposeAsync() async {
    console.log(widget.debugSource, '${widget.debugName}: dispose');
    await _model.dispose();
    console.log(widget.debugSource, '${widget.debugName}: disposed');
  }

  @override
  Widget buildOnState(AsyncScopeState state) {
    return switch (state) {
      AsyncScopeWaiting() => const Text('Waiting…'),
      AsyncScopeError(:final error) => Text('Error: $error'),
      AsyncScopeProgress() => const Text('Initializing…'),
      AsyncScopeReady() => buildOnReady(),
    };
  }

  Widget buildOnReady() {
    Widget body = Center(
      child: BlinkingBox(
        blinkingColor:
            Theme.of(this).colorScheme.primary.withValues(alpha: 0.2),
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

    if (widget.childScope case final child?) {
      body = Row(
        children: [
          Expanded(child: body),
          const VerticalDivider(),
          Expanded(child: child),
        ],
      );
    }

    if (widget.title case final title?) {
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
