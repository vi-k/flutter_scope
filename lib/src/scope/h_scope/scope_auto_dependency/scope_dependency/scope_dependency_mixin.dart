part of '../../../scope.dart';

/// {@category Scope}
mixin ScopeDependencyMixin implements ScopeDependency {
  late final _log = log.withAddedName(
    () => '$ScopeDependencyMixin(#${shortHash(this)})',
  );

  @override
  ScopeDependencyState get state => _state;
  ScopeDependencyState _state = const ScopeDependencyInitial();

  /// Автоматизация процесса инициализации.
  ///
  /// Метод запускает [init], обрабатывает ошибки и устанавливает
  /// соответствующее состояние.
  ///
  /// Инициализация завершается успешно не в случае отсутствия ошибок, а только
  /// тогда, когда генератор НЕ БУДЕТ ОТМЕНЁН. Т.е. инициатор может НЕ ПРЕРВАТЬ
  /// стрим в случае ошибки, и тогда иницализация формально завершится
  /// состоянием [ScopeDependencyInitialized]. А может прервать стрим без
  /// какой-либо ошибки, и тогда иницализация завершится состоянием
  /// [ScopeDependencyCancelled].
  ///
  /// [init] может передать несколько ошибок, т.к. за ней может скрываться не
  /// одна зависимость, а группа зависимостей. Ранее обработанные ошибки, т.е.
  /// ошибки дочерних зависимостей игнорируются. Ошибки текущей зависимости
  /// приводят к состоянию [ScopeDependencyFailed] и оборачиваются в
  /// [ScopeDependencyException] для передачи в таком виде дальше. Но в этом
  /// случае сохраняется в состоянии только первая ошибка, т.к. предполагается,
  /// что конкретной зависимости нет необходимости генерировать несколько
  /// ошибок.
  @override
  Stream<String> runInit() async* {
    assert(_state is ScopeDependencyInitial);

    try {
      yield* runStreamGuarded(
        init,
        _handleInitializationPostCancelError,
        debugName: name,
      ).handleError(_handleInitializationError);
      if (_state is! ScopeDependencyFailed) {
        _state = const ScopeDependencyInitialized();
      }
    } finally {
      // Ловим отмену.
      if (_state is ScopeDependencyInitial) {
        _state = ScopeDependencyCancelled();
      }
    }
  }

  @override
  Stream<String> runDispose() async* {
    try {
      yield* runStreamGuarded(
        dispose,
        _handleDisposalPostCancelError,
        debugName: name,
      ).handleError(_handleDisposalError);
      if (_state is! ScopeDependencyDisposalFailed) {
        _state = const ScopeDependencyDisposed();
      }
    } finally {
      // Ловим отмену.
      if (_state is ScopeDependencyInitialized) {
        _state = ScopeDependencyDisposalCancelled();
      }
    }
  }

  void _addErrorToState(
    Object error,
    StackTrace stackTrace,
    _ScopeDependencyWithErrors Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    _state = switch (_state) {
      final _ScopeDependencyWithErrors state => state.addError(
          error,
          stackTrace,
        ),
      ScopeDependencySuccessStates() => defaultState(error, stackTrace),
    };
  }

  void _handleError(
    Object error,
    StackTrace stackTrace,
    ScopeDependencyFailedStates Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    _log.d(() => '[handleError] $wrappedName', error: error);

    // Добавляем ошибку в состояние.
    _addErrorToState(error, stackTrace, defaultState);

    // Отправляем ошибку дальше.
    if (error is ScopeDependencyException) {
      // Передаём ошибку, добавляя в путь к ней имя текущей зависимости.
      // Безымянная группа (name == '') не добавляет собственный сегмент и
      // разделитель, иначе путь получал бы ведущий или задвоенный '/'.
      Error.throwWithStackTrace(
        ScopeDependencyException(
          name.isEmpty ? error.name : '$name/${error.name}',
          error.error,
          error.stackTrace,
        ),
        stackTrace,
      );
    } else {
      // Свои ошибки оборачиваем, чтобы передать наверх имя.
      Error.throwWithStackTrace(
        ScopeDependencyException(name, error, stackTrace),
        StackTrace.empty,
      );
    }
  }

  void _handleInitializationError(Object error, StackTrace stackTrace) {
    _handleError(error, stackTrace, ScopeDependencyFailed.new);
  }

  void _handleDisposalError(Object error, StackTrace stackTrace) {
    _handleError(error, stackTrace, ScopeDependencyDisposalFailed.new);
  }

  void _handlePostCancelError(
    Object error,
    StackTrace stackTrace,
    ScopeDependencyCancelledStates Function(Object error, StackTrace stackTrace)
        defaultState,
  ) {
    _log.d(() => '[handlePostCancelError] $wrappedName', error: error);

    if (error is ParallelWaitError<void, List<AsyncError?>>) {
      for (final error in error.errors.nonNulls) {
        _handlePostCancelError(error.error, error.stackTrace, defaultState);
      }
      return;
    }

    // Добавляем ошибку в состояние.
    _addErrorToState(error, stackTrace, defaultState);
  }

  void _handleInitializationPostCancelError(
    Object error,
    StackTrace stackTrace,
  ) {
    _handlePostCancelError(
      error, //
      stackTrace,
      ScopeDependencyCancelled.new,
    );
  }

  void _handleDisposalPostCancelError(Object error, StackTrace stackTrace) {
    _handlePostCancelError(
      error, //
      stackTrace,
      ScopeDependencyDisposalCancelled.new,
    );
  }
}
