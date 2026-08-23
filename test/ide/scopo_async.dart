// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-async` inserts, with its tab stops replaced by their
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

final class ConnectionScope extends AsyncScopeBase<ConnectionScope> {
  const ConnectionScope({super.key, required super.child});

  /// The state of the scope: `state`, `isInitialized`, `hasError`.
  ///
  /// `listen` is a real choice here, unlike in the data and controller
  /// families: what comes back is the state, and the state changes —
  /// waiting, progress, ready, error. Reading one field through [select]
  /// is the usual way in, since it subscribes to that field alone; take
  /// the whole context with `listen: false` when one read is enough.
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

  /// One value of the scope, subscribed to on its own.
  static bool isReadyOf(BuildContext context) =>
      select(context, (scope) => scope.isInitialized);

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
