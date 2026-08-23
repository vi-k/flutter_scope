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

final class PlayerScope
    extends AsyncControllerScopeBase<PlayerScope, PlayerController> {
  const PlayerScope({super.key, required super.child});

  /// The controller itself, for calling methods on it. Throws until there
  /// is one — read it from below [buildOnReady], where there always is.
  static PlayerController of(
    BuildContext context, {
    required bool listen,
  }) =>
      AsyncControllerScopeBase.of<PlayerScope, PlayerController>(
        context,
        listen: listen,
      ).controller;

  static V select<V>(
    BuildContext context,
    V Function(PlayerController controller) selector,
  ) =>
      AsyncControllerScopeBase.select<PlayerScope, PlayerController, V>(
        context,
        (scope) => selector(scope.controller),
      );

  /// One value of the controller, subscribed to on its own.
  static bool isPlayingOf(BuildContext context) =>
      select(context, (controller) => controller.isPlaying);

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

final class PlayerController extends ScopeController {
  Timer? _ticker;

  bool isPlaying = false;

  @override
  Future<void> init() async {
    // `mounted` after every await: the scope may have gone while this was
    // suspended, and what is taken afterwards has nobody to release it.
    if (!mounted) return;
  }

  /// Drops what must stop reaching the controller at once. Synchronous, and
  /// always runs before [dispose].
  @override
  void onUnmount() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  FutureOr<void> dispose() {}
}
