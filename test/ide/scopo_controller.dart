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

final class PlayerScope
    extends AsyncControllerScopeBase<PlayerScope, PlayerController> {
  const PlayerScope({super.key, required super.child});

  /// The controller itself, for calling methods on it. Throws until there
  /// is one — read it from below [buildOnReady], where there always is.
  ///
  /// `listen: false`, and not as a default worth revisiting: subscribing
  /// here follows the *state* of the scope — waiting, ready, error — and
  /// this family does not make the controller observable. A controller
  /// whose values the widgets have to follow should be a `Listenable`
  /// with a `ScopeNotifier` under this scope, or should expose a stream.
  static PlayerController of(BuildContext context) =>
      AsyncControllerScopeBase.of<PlayerScope, PlayerController>(
        context,
        listen: false,
      ).controller;

  // No `select` here on purpose. It would subscribe to the state of the
  // scope — `hasController`, `isInitialized` — and a widget under the
  // ready branch is past all of those. To follow something *inside* the
  // controller, make it a `Listenable` and wrap the widget in a
  // `ListenableSelector`, or put a `ScopeNotifier` under this scope.
  // `AsyncControllerScopeBase.select` is there if the state is what you
  // need.

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
