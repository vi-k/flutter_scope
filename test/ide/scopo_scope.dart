// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-scope` inserts, with its tab stops replaced by their
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

final class Database {
  static Future<Database> open() async => Database();
  Future<void> close() async {}
}

final class App extends Scope<App, AppDependencies, AppState> {
  final String title;

  const App({super.key, required this.title, required super.child});

  static App paramsOf(BuildContext context, {required bool listen}) =>
      Scope.paramsOf<App, AppDependencies, AppState>(
        context,
        listen: listen,
      );

  static V selectParam<V>(
    BuildContext context,
    V Function(App widget) selector,
  ) =>
      Scope.selectParam<App, AppDependencies, AppState, V>(
        context,
        selector,
      );

  /// One parameter, subscribed to on its own.
  static String titleOf(BuildContext context) =>
      selectParam(context, (widget) => widget.title);

  static AppState of(BuildContext context) =>
      Scope.of<App, AppDependencies, AppState>(context);

  static V select<V>(
    BuildContext context,
    V Function(AppState state) selector,
  ) =>
      Scope.select<App, AppDependencies, AppState, V>(
        context,
        selector,
      );

  /// One value of the state, subscribed to on its own.
  static int counterOf(BuildContext context) =>
      select(context, (state) => state.counter);

  @override
  Stream<ScopeInitState<Object, AppDependencies>> initDependencies(
    BuildContext context,
  ) =>
      AppDependencies().init(context);

  @override
  AppState createState() => AppState();

  @override
  Widget buildOnProgress(BuildContext context, Object? progress) =>
      const Center(child: CircularProgressIndicator());

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    Object? progress,
  ) =>
      Center(child: Text('$error'));
}

final class AppDependencies
    extends ScopeAutoDependencies<AppDependencies, BuildContext> {
  late final Database database;

  @override
  ScopeDependency buildDependencies(BuildContext context) => sequential('', [
        dep('database', (dep) async {
          database = await Database.open();
          dep.dispose = database.close;
        }),
      ]);
}

final class AppState extends ScopeState<App, AppDependencies, AppState> {
  int counter = 0;

  @override
  FutureOr<void> initStateAsync() {}

  @override
  FutureOr<void> disposeStateAsync() {}

  @override
  Widget build(BuildContext context) => params.child;
}
