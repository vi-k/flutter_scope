// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-notifier` inserts, with its tab stops replaced by their
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

final class Counter extends ChangeNotifier {
  final int value = 0;
}

final class CounterScope extends ScopeNotifierBase<CounterScope, Counter> {
  final Widget Function(BuildContext context) builder;

  CounterScope({super.key, required this.builder})
      : super(
          create: (context) => Counter(),
          dispose: (model) => model.dispose(),
        );

  /// Over a notifier somebody else owns. Delete whichever of the two this
  /// scope does not need.
  const CounterScope.value({
    super.key,
    required Counter model,
    required this.builder,
  }) : super.value(value: model);

  static ScopeModelContext<CounterScope, Counter> of(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeNotifierBase.of<CounterScope, Counter>(
        context,
        listen: listen,
      );

  static V select<V>(
    BuildContext context,
    V Function(ScopeModelContext<CounterScope, Counter> context) selector,
  ) =>
      ScopeNotifierBase.select<CounterScope, Counter, V>(
        context,
        selector,
      );

  /// One value of the model, subscribed to on its own.
  static int valueOf(BuildContext context) =>
      select(context, (scope) => scope.model.value);

  @override
  Widget build(BuildContext context) => builder(context);
}
