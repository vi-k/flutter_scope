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
  final bool isOpen = true;
  Future<void> close() async {}
}

final class Session {
  static Future<Session> connect() async => Session();
  Future<void> close() async {}
}

final class AppDependencies implements ScopeDependencies {
  // Final, and that is the reason to write a container by hand at all:
  // `ScopeAutoDependencies` fills its fields as it walks the tree, so they
  // cannot be. Here everything that changes lives inside [init], and what
  // leaves it is assembled once and never edited again.
  final Database database;
  final Session session;

  AppDependencies({required this.database, required this.session});

  static Stream<ScopeInitState<Object, AppDependencies>> init(
    BuildContext context,
  ) async* {
    // Locals, not fields: until the container is assembled, these belong
    // to this function, and it is this function that has to give them back
    // if it does not get that far. Nullable so that a step which never ran
    // can be skipped with `?.` below.
    Database? database;
    Session? session;

    // A cancellation raises nothing: it ends the generator at a yield, so a
    // `catch` never runs and only a `finally` sees it. The flag tells the
    // two endings apart — handed over, or abandoned half-built.
    var handedOver = false;

    try {
      yield ScopeProgress('opening the database');
      database = await Database.open();

      yield ScopeProgress('connecting');
      session = await Session.connect();

      yield ScopeReady(
        AppDependencies(database: database, session: session),
      );
      handedOver = true;
    } finally {
      // Only if the scope never got it. Once it did, releasing is the
      // scope's job — through [dispose] below — and doing it here would
      // release it twice.
      //
      // Reverse order of construction, and every step asks whether it was
      // reached at all.
      if (!handedOver) {
        await session?.close();
        await database?.close();
      }
    }
  }

  /// Drops what must stop reaching the dependencies at once. Runs once,
  /// always before [dispose].
  @override
  void onUnmount() {}

  /// Reached only for a container the scope took over, so both fields are
  /// there — no question of whether a step ran.
  @override
  Future<void> dispose() async {
    await session.close();
    await database.close();
  }
}

// `ScopeAutoDependencies` does the unwinding for you: register
// `dep.dispose` as each step succeeds and the tree comes apart in reverse,
// cancelled or not. Write the container by hand for an immutable one, or
// when the order or the conditions are yours rather than the tree's — see
// `scopo-autodeps`.
