// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-lite` inserts, with its tab stops replaced by their
// defaults, so `flutter analyze` compiles what an editor would actually paste.
// One file per skeleton: several of them declare a class of the same default
// name, which is right in an editor and a conflict in one library.
//
// The stubs stand for the types a skeleton only names. A skeleton reads a field
// of one of them in its `…Of` example, so the stub declares that field: what is
// compiled is the shape of the call, and the name is the user's to change.
//
// ignore_for_file: unreachable_from_main, prefer_const_constructors
// ignore_for_file: avoid_unused_constructor_parameters, unused_field
// ignore_for_file: unused_import

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  final String title;

  /// The subtree of this scope.
  final Widget Function(BuildContext context) builder;

  const ScreenScope({
    super.key,
    required this.title,
    required this.builder,
  });

  static ScreenScope paramsOf(
    BuildContext context, {
    required bool listen,
  }) =>
      LiteScope.paramsOf<ScreenScope, ScreenScopeState>(
        context,
        listen: listen,
      );

  static V selectParam<V>(
    BuildContext context,
    V Function(ScreenScope widget) selector,
  ) =>
      LiteScope.selectParam<ScreenScope, ScreenScopeState, V>(
        context,
        selector,
      );

  /// One parameter, subscribed to on its own.
  static String titleOf(BuildContext context) =>
      selectParam(context, (widget) => widget.title);

  static ScreenScopeState of(BuildContext context) =>
      LiteScope.of<ScreenScope, ScreenScopeState>(context);

  static V select<V>(
    BuildContext context,
    V Function(ScreenScopeState state) selector,
  ) =>
      LiteScope.select<ScreenScope, ScreenScopeState, V>(
        context,
        selector,
      );

  /// One value of the state, subscribed to on its own.
  static int counterOf(BuildContext context) =>
      select(context, (state) => state.counter);

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  ScreenScopeState createState() => ScreenScopeState();
}

final class ScreenScopeState
    extends LiteScopeState<ScreenScope, ScreenScopeState> {
  int counter = 0;

  void incrementCounter() {
    counter++;
    // Wakes the descendants subscribed through `select`. It does not run
    // this state's own `build` — that is what `setState` is for, and both
    // are needed when both have to see the change.
    notifyDependents();
  }

  @override
  Future<void> initStateAsync() async {}

  /// The synchronous half of the teardown: drop what must stop reaching
  /// this state at once. The context is gone by now on a removed scope.
  @override
  void onUnmount() {}

  /// The asynchronous half, after it.
  @override
  Future<void> disposeStateAsync() async {}

  @override
  Widget build(BuildContext context) => params.builder(context);
}
