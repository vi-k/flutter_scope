// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-controller` inserts, with its tab stops replaced by their
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

final class PlayerController extends ScopeController {}

final class PlayerScope
    extends AsyncControllerScopeBase<PlayerScope, PlayerController> {
  const PlayerScope({super.key, required super.child});

  static AsyncControllerScopeContext<PlayerScope, PlayerController> of(
    BuildContext context, {
    required bool listen,
  }) =>
      AsyncControllerScopeBase.of<PlayerScope, PlayerController>(
        context,
        listen: listen,
      );

  static V select<V>(
    BuildContext context,
    V Function(
      AsyncControllerScopeContext<PlayerScope, PlayerController> context,
    ) selector,
  ) =>
      AsyncControllerScopeBase.select<PlayerScope, PlayerController, V>(
        context,
        selector,
      );

  /// The controller itself, for calling methods on it.
  static PlayerController controllerOf(BuildContext context) =>
      select(context, (scope) => scope.controller);

  @override
  PlayerController createController(BuildContext context) => PlayerController();

  /// No progress argument here, unlike the other async families: this
  /// scope's initialization is `createController()` plus the controller's
  /// own `init()`, and neither reports steps.
  @override
  Widget buildOnProgress(BuildContext context) =>
      const Center(child: CircularProgressIndicator());

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      Center(child: Text('$error'));

  @override
  Widget buildOnReady(BuildContext context, PlayerController controller) =>
      child;
}
