part of '../scope.dart';

/// {@category AsyncDataScope}
abstract base class AsyncDataScopeCore<
    W extends AsyncDataScopeCore<W, E, T>,
    E extends AsyncDataScopeElementBase<W, E, T>,
    T extends Object?> extends AsyncScopeCore<W, E> {
  /// Creates the widget half of a scope producing a value.
  const AsyncDataScopeCore({
    super.key,
    super.tag,
    super.child, // Not used by default. You can use it at your own discretion.
  });

  /// The element of the nearest scope [W] above [context], or `null`.
  static E? maybeOf<W extends AsyncDataScopeCore<W, E, T>,
          E extends AsyncDataScopeElementBase<W, E, T>, T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<W, E>(
        context,
        listen: listen,
      );

  /// The element of the nearest scope [W] above [context].
  ///
  /// Throws when there is none.
  static E of<W extends AsyncDataScopeCore<W, E, T>,
          E extends AsyncDataScopeElementBase<W, E, T>, T extends Object?>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<W, E>(
        context,
        listen: listen,
      );

  /// Subscribes to one value of the scope and returns it.
  static V select<
          W extends AsyncDataScopeCore<W, E, T>,
          E extends AsyncDataScopeElementBase<W, E, T>,
          T extends Object?,
          V extends Object?>(
    BuildContext context,
    V Function(E element) selector,
  ) =>
      ScopeContext.select<W, E, V>(
        context,
        selector,
      );
}

/// {@category AsyncDataScope}
abstract base class AsyncDataScopeElementBase<
        W extends AsyncDataScopeCore<W, E, T>,
        E extends AsyncDataScopeElementBase<W, E, T>,
        T extends Object?> extends AsyncScopeElementBase<W, E>
    implements AsyncDataScopeContext<W, T> {
  //
  // Overriding block
  //

  @override
  Object? get scopeKey => null;

  @override
  Duration? get pauseAfterInitialization => null;

  /// The initialization, ending with the value.
  Stream<AsyncDataScopeInitState<Object, T>> initDataAsync();

  @override
  FutureOr<void> disposeAsync() {}

  @override
  Widget buildOnState(AsyncScopeState state);

  //
  // End of overriding block
  //

  @override
  T get data => _hasData ? _data as T : throw StateError('Not initialized');

  T? _data;

  /// Whether [_data] holds the value the initialization produced.
  ///
  /// Kept apart from the value, because for a nullable [T] the value cannot
  /// answer for itself: `null` is something the initialization may legitimately
  /// produce, and reading it as "nothing yet" made [data] hand out a value the
  /// scope had never been given.
  ///
  /// It is set the moment the value goes past, which is a little before the
  /// model says [AsyncScopeReady] — the model update waits for the end of the
  /// frame, or for the whole of `pauseAfterInitialization`. The teardown reads
  /// [data] in exactly that window, so this is the moment that matters and not
  /// the state of the model.
  bool _hasData = false;

  @override
  bool get hasData => _hasData;

  @override
  T? get dataOrNull => _data;

  /// Creates the element of a scope producing a value.
  AsyncDataScopeElementBase(super.widget);

  /// Sealed: this is where the value is caught on its way past, and the
  /// family has nothing to offer without it. The hook to write is
  /// [initDataAsync]; overriding this one instead would leave [data] empty
  /// for good, and the analyzer would say nothing about it.
  @nonVirtual
  @override
  Stream<AsyncScopeInitState> initAsync() => initDataAsync().map(
        (state) {
          switch (state) {
            case AsyncDataScopeProgress(:final progress):
              return AsyncScopeProgress(progress);
            case AsyncDataScopeReady(:final data):
              // Refused here rather than one layer up. This `map` runs as the
              // event goes past and `asyncMap` only after it, so the check for
              // a second initialization up there arrived to find the value
              // already replaced: the model stayed as it was, the dependents
              // heard nothing, `data` handed out the newcomer, and the value
              // the scope had been given was left with nobody to release it.
              if (_hasData) {
                throw StateError('$W already initialized');
              }

              _data = data;
              _hasData = true;
              return AsyncScopeReady();
          }
        },
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<T?>('data', _data));
  }
}
