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
  // Nullable rather than `late final`, and that is the whole trick: a step
  // that never ran leaves `null`, so the teardown below can skip it with
  // `?.`. Reading an unset `late final` throws — from inside a teardown,
  // where the failure has nowhere to go.
  Database? _database;
  Session? _session;

  /// Read from below the ready branch, where both are there.
  Database get database => _database!;

  Session get session => _session!;

  static Stream<ScopeInitState<Object, AppDependencies>> init(
    BuildContext context,
  ) async* {
    final deps = AppDependencies();
    // A cancellation raises nothing: it ends the generator at a yield, so a
    // `catch` never runs and only a `finally` sees it. The flag tells the
    // two endings apart — handed over, or abandoned half-built.
    var handedOver = false;

    try {
      yield ScopeProgress('opening the database');
      deps._database = await Database.open();

      yield ScopeProgress('connecting');
      deps._session = await Session.connect();

      yield ScopeReady(deps);
      handedOver = true;
    } finally {
      // Only if the scope never got it. Once it did, releasing is the
      // scope's job and doing it here would release it twice.
      if (!handedOver) {
        await deps._release();
      }
    }
  }

  /// The one teardown, used by both endings — the cancellation above and
  /// the ordinary [dispose] below.
  ///
  /// Reverse order of construction, and every step asks whether it was
  /// reached at all. Clearing each field as it goes makes a second call
  /// harmless.
  Future<void> _release() async {
    await _session?.close();
    _session = null;

    await _database?.close();
    _database = null;
  }

  /// Drops what must stop reaching the dependencies at once. Runs once,
  /// always before [dispose].
  @override
  void onUnmount() {}

  @override
  Future<void> dispose() => _release();
}

// `ScopeAutoDependencies` does all of the above for you: register
// `dep.dispose` as each step succeeds and the container unwinds itself in
// reverse, cancelled or not. Write the container by hand when the order or
// the conditions are yours rather than the tree's — see `scopo-autodeps`.
