// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-data` inserts, with its tab stops replaced by their
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
  final bool isOpen = true;
  Future<void> close() async {}
}

final class DbScope extends AsyncDataScopeBase<DbScope, Database> {
  /// Built once the value is there, and receives it.
  final Widget Function(BuildContext context, Database data) builder;

  const DbScope({super.key, required this.builder});

  /// The value itself. Throws until there is one — read it from below
  /// [buildOnReady], where there always is.
  ///
  /// `listen: false`, and not as a default worth revisiting: subscribing
  /// here follows the *state* of the scope — waiting, progress, ready,
  /// error — and the value is read from a subtree the ready state built.
  /// Storing a value does not make it observable; a value the widgets have
  /// to follow should be a `Listenable` with a `ScopeNotifier` under this
  /// scope, or should expose a stream.
  static Database of(BuildContext context) =>
      AsyncDataScopeBase.of<DbScope, Database>(
        context,
        listen: false,
      ).data;

  // No `select` here on purpose. It would subscribe to the state of the
  // scope — `hasData`, `isInitialized` — and a widget under the ready
  // branch is past all of those. To follow something *inside* the value,
  // make the value a `Listenable` and wrap the widget in a
  // `ListenableSelector`, or put a `ScopeNotifier` under this scope.
  // `AsyncDataScopeBase.select` is there if the state is what you need.

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
  Widget buildOnReady(BuildContext context, Database data) =>
      builder(context, data);
}
