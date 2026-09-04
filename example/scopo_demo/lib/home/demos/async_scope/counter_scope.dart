import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../common/presentation/blinking_box.dart';
import '../../../utils/console/console.dart';

/// A notifier initialized and disposed explicitly by `CounterScopeElement`.
/// Its nullable count makes accidental reads before readiness fail loudly.
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

/// An `AsyncScopeCore` whose custom element owns the asynchronous model.
/// The widget carries configuration while the element implements lifecycle.
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

/// Maps model initialization and disposal onto the `AsyncScope` state
/// machine and publishes the ready model to descendants.
final class CounterScopeElement
    extends AsyncScopeElementBase<CounterScope, CounterScopeElement> {
  late final CounterModel _model;

  /// Taken once, on the way in.
  ///
  /// The examples number their scopes in `build`, so a rebuild that happens
  /// for a reason of its own — switching the theme — hands this element a
  /// widget with a new name. Read live, that printed the teardown of `1.2`
  /// with no initialization of `1.2` anywhere above it, in a demo that exists
  /// for the order of its lines. The other three families here cache the name
  /// for the same reason.
  late final Object _debugSource;
  late final String _debugName;

  CounterScopeElement(super.widget);

  // The coordinator serializes instances only when the widget supplies a key.
  @override
  Object? get scopeKey => widget.scopeKey;

  @override
  Duration? get pauseAfterInitialization => const Duration(milliseconds: 1000);

  @override
  void init() {
    super.init();
    _debugSource = widget.debugSource;
    _debugName = widget.debugName;
    _model = CounterModel(
      debugSource: _debugSource,
      debugName: _debugName,
    );
  }

  @override
  Future<void> initScopeAsync(ScopeInitContext ctx) async {
    console.log(_debugSource, '$_debugName: initialize');
    await ctx.wait(_model.init);
    // Before the return rather than after it, because after it there is
    // nothing: a generator had a statement that ran once the scope had taken
    // the event, and a body that returns does not.
    console.log(_debugSource, '$_debugName: initialized');
  }

  @override
  Future<void> disposeScope() async {
    console.log(_debugSource, '$_debugName: dispose');
    await _model.dispose();
    console.log(_debugSource, '$_debugName: disposed');
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
