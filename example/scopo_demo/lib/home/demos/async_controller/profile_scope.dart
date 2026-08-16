import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../../../utils/console/console.dart';

/// A controller with a lifecycle of its own: it is what the scope exists to
/// run, and it produces nothing for the widgets to show.
///
/// Everything it does is written into the demo console, so the three examples
/// beside it make the order visible -- and make it visible that the teardown
/// happens even when the initialization never finished.
final class ProfileController extends ScopeController {
  final Object debugSource;
  final String debugName;

  /// How long the initialization takes. Long enough for the third example to
  /// walk away in the middle of it.
  final Duration initDuration;

  /// Makes the initialization fail, the way a network call does.
  final bool failOnInit;

  Timer? _ticker;

  ProfileController({
    required this.debugSource,
    required this.debugName,
    required this.initDuration,
    this.failOnInit = false,
  });

  @override
  Future<void> init() async {
    console.log(debugSource, '$debugName: init…');

    await Future<void>.delayed(initDuration);

    // The scope may have gone while this was suspended: `onUnmount` has then
    // already run, and nothing here should reach the outside world any more.
    if (!mounted) {
      console.log(debugSource, '$debugName: init returned to a scope that is '
          'gone; taking nothing');

      return;
    }

    if (failOnInit) {
      console.log(debugSource, '$debugName: init failed');

      throw StateError('could not load the profile');
    }

    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => console.log(debugSource, '$debugName: tick'),
    );
    console.log(debugSource, '$debugName: initialized');
  }

  @override
  void onUnmount() {
    _ticker?.cancel();
    console.log(debugSource, '$debugName: onUnmount');
  }

  @override
  Future<void> dispose() async {
    console.log(debugSource, '$debugName: dispose…');

    await Future<void>.delayed(const Duration(milliseconds: 500));

    console.log(debugSource, '$debugName: disposed');
  }
}

/// The whole adapter: what to create, and what to show on each branch.
final class ProfileScope
    extends AsyncControllerScopeBase<ProfileScope, ProfileController> {
  final Object debugSource;
  final String debugName;
  final Duration initDuration;
  final bool failOnInit;

  const ProfileScope({
    super.key,
    super.scopeKey,
    required this.debugSource,
    required this.debugName,
    this.initDuration = const Duration(seconds: 1),
    this.failOnInit = false,
  }) : super(tag: debugName);

  @override
  ProfileController createController(BuildContext context) => ProfileController(
        debugSource: debugSource,
        debugName: debugName,
        initDuration: initDuration,
        failOnInit: failOnInit,
      );

  @override
  Widget buildOnWaiting(BuildContext context) => const Text('Waiting…');

  @override
  Widget buildOnInitializing(BuildContext context) =>
      const Text('Initializing…');

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
  ) =>
      Text('Error: $error');

  @override
  Widget buildOnReady(BuildContext context, ProfileController controller) =>
      Text('Running: ${controller.debugName}');
}
