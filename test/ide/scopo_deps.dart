// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-deps` inserts, with its tab stops replaced by their
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

final class AppDependencies implements ScopeDependencies {
  late final Database database;

  static Stream<ScopeInitState<Object, AppDependencies>> init(
    BuildContext context,
  ) async* {
    final deps = AppDependencies();
    // A cancellation raises nothing: it ends the generator at a yield, so a
    // `catch` never runs and only a `finally` sees it. The flag tells the two
    // endings apart — handed over, or abandoned half-built.
    var handedOver = false;

    try {
      yield ScopeProgress('opening the database');
      deps.database = await Database.open();

      yield ScopeReady(deps);
      handedOver = true;
    } finally {
      if (!handedOver) {
        await deps.database.close();
      }
    }
  }

  /// Runs once, always before [dispose].
  @override
  void onUnmount() {}

  @override
  Future<void> dispose() async {
    await database.close();
  }
}
