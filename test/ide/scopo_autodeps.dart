// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-autodeps` inserts, with its tab stops replaced by their
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

final class AppDependencies
    extends ScopeAutoDependencies<AppDependencies, BuildContext> {
  late final Database database;

  @override
  ScopeDependency buildDependencies(BuildContext context) => sequential('', [
        dep('database', (dep) async {
          database = await Database.open();
          // Registered before the next await: whatever this step took is
          // given back even if a later one fails or is cancelled.
          dep.dispose = database.close;
        }),
      ]);
}
