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

  static const access = ScopeAccess<App, AppDependencies, AppState>();

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

  static const access = LiteScopeAccess<ScreenScope, ScreenScopeState>();

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

  static const access = ScopeWidgetAccess<ApiConfig>();

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
  static const access = ScopeModelAccess<UserScope, UserModel>();

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
  static const access = ScopeNotifierAccess<CounterScope, Counter>();

  @override
  Widget build(BuildContext context) => builder(context);
}

// --- scopo-async ---
final class ConnectionScope extends AsyncScopeBase<ConnectionScope> {
  const ConnectionScope({super.key, required super.child});

  static const access = AsyncScopeAccess<ConnectionScope>();

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

  static const access = AsyncDataScopeAccess<DbScope, Database>();

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
