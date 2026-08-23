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
  Future<void> close() async {}
}

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

  /// The value itself, without subscribing to anything else.
  static Database dataOf(BuildContext context) =>
      select(context, (scope) => scope.data);

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
