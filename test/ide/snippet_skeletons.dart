// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// Every skeleton the snippets insert, with the tab stops replaced by their
// defaults, so that `flutter analyze` compiles what an editor would actually
// paste. `ide_snippets_test.dart` regenerates this file and fails if it has
// drifted from the snippets.
//
// ignore_for_file: unreachable_from_main, prefer_const_constructors
// ignore_for_file: avoid_unused_constructor_parameters

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

final class UserModel {
  void dispose() {}
}

final class Counter extends ChangeNotifier {}

final class Database {
  static Future<Database> open() async => Database();
  Future<void> close() async {}
}

// --- scopo-scope ---
final class App extends Scope<App, AppDependencies, AppState> {
  const App({super.key, required super.child});

  static AppState of(BuildContext context) =>
      Scope.of<App, AppDependencies, AppState>(context);

  static AppState? maybeOf(BuildContext context) =>
      Scope.maybeOf<App, AppDependencies, AppState>(context);

  static V select<V>(
    BuildContext context,
    V Function(AppState state) selector,
  ) =>
      Scope.select<App, AppDependencies, AppState, V>(
        context,
        selector,
      );

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

  @override
  Stream<ScopeInitState<Object, AppDependencies>> initDependencies(
    BuildContext context,
  ) =>
      AppDependencies.init(context);

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

final class AppState extends ScopeState<App, AppDependencies, AppState> {
  @override
  Widget build(BuildContext context) => params.child;
}

// --- scopo-deps ---
final class AppDependencies implements ScopeDependencies {
  static Stream<ScopeInitState<Object, AppDependencies>> init(
    BuildContext context,
  ) async* {
    yield ScopeProgress('initializing');

    yield ScopeReady(AppDependencies());
  }

  /// Runs once, always before [dispose].
  @override
  void onUnmount() {}

  @override
  Future<void> dispose() async {}
}

// --- scopo-lite ---
final class ScreenScope extends LiteScope<ScreenScope, ScreenScopeState> {
  const ScreenScope({super.key, required super.child});

  static ScreenScopeState of(BuildContext context) =>
      LiteScope.of<ScreenScope, ScreenScopeState>(context);

  static ScreenScopeState? maybeOf(BuildContext context) =>
      LiteScope.maybeOf<ScreenScope, ScreenScopeState>(context);

  static V select<V>(
    BuildContext context,
    V Function(ScreenScopeState state) selector,
  ) =>
      LiteScope.select<ScreenScope, ScreenScopeState, V>(
        context,
        selector,
      );

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

  @override
  Widget? buildOnWaiting(BuildContext context) => const SizedBox.shrink();

  @override
  ScreenScopeState createState() => ScreenScopeState();
}

final class ScreenScopeState
    extends LiteScopeState<ScreenScope, ScreenScopeState> {
  @override
  Widget build(BuildContext context) => params.child;
}

// --- scopo-widget ---
final class ApiConfig extends ScopeWidgetBase<ApiConfig> {
  final String apiKey;

  const ApiConfig({super.key, required this.apiKey, required super.child});

  static ApiConfig of(BuildContext context, {required bool listen}) =>
      ScopeWidgetBase.of<ApiConfig>(context, listen: listen);

  static V select<V>(
    BuildContext context,
    V Function(ApiConfig widget) selector,
  ) =>
      ScopeWidgetBase.select<ApiConfig, V>(context, selector);

  @override
  Widget build(BuildContext context) => child;
}

// --- scopo-model ---
final class UserScope extends ScopeModelBase<UserScope, UserModel> {
  final Widget Function(BuildContext context) builder;

  UserScope({super.key, required this.builder})
      : super(
          create: (context) => UserModel(),
          dispose: (model) => model.dispose(),
        );

  /// Over a model somebody else owns: `super.value(value: model)`.
  static ScopeModelContext<UserScope, UserModel> of(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeModelBase.of<UserScope, UserModel>(
        context,
        listen: listen,
      );

  static V select<V>(
    BuildContext context,
    V Function(ScopeModelContext<UserScope, UserModel> context) selector,
  ) =>
      ScopeModelBase.select<UserScope, UserModel, V>(
        context,
        selector,
      );

  @override
  Widget build(BuildContext context) => builder(context);
}

// --- scopo-notifier ---
final class CounterScope extends ScopeNotifierBase<CounterScope, Counter> {
  final Widget Function(BuildContext context) builder;

  CounterScope({super.key, required this.builder})
      : super(
          create: (context) => Counter(),
          dispose: (model) => model.dispose(),
        );

  /// Over a notifier somebody else owns: `super.value(value: model)`.
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

  @override
  Widget build(BuildContext context) => builder(context);
}

// --- scopo-async ---
final class ConnectionScope extends AsyncScopeBase<ConnectionScope> {
  const ConnectionScope({super.key, required super.child});

  static AsyncScopeContext<ConnectionScope> of(
    BuildContext context, {
    required bool listen,
  }) =>
      AsyncScopeBase.of<ConnectionScope>(context, listen: listen);

  static V select<V>(
    BuildContext context,
    V Function(AsyncScopeContext<ConnectionScope> context) selector,
  ) =>
      AsyncScopeBase.select<ConnectionScope, V>(context, selector);

  @override
  Stream<AsyncScopeInitState> initScope(BuildContext context) async* {
    yield AsyncScopeProgress('connecting');

    yield AsyncScopeReady();
  }

  @override
  Future<void> disposeScope() async {}

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

  @override
  Widget buildOnReady(BuildContext context) => child;
}

// --- scopo-data ---
final class DbScope extends AsyncDataScopeBase<DbScope, Database> {
  const DbScope({super.key, required super.child});

  static AsyncDataScopeContext<DbScope, Database> of(
    BuildContext context, {
    required bool listen,
  }) =>
      AsyncDataScopeBase.of<DbScope, Database>(
        context,
        listen: listen,
      );

  static V select<V>(
    BuildContext context,
    V Function(AsyncDataScopeContext<DbScope, Database> context) selector,
  ) =>
      AsyncDataScopeBase.select<DbScope, Database, V>(
        context,
        selector,
      );

  @override
  Stream<AsyncDataScopeInitState<Object, Database>> initData(
    BuildContext context,
  ) async* {
    yield AsyncDataScopeReady(await Database.open());
  }

  @override
  FutureOr<void> disposeData(Database data) => data.close();

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

  @override
  Widget buildOnReady(BuildContext context, Database data) => child;
}
