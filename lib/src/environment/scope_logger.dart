part of 'scope_config.dart';

/// The destination of the log events of a single level.
///
/// {@category debug}
typedef ScopeLogPublisher = CustomLogPublisher<ScopeLog>;

/// A [ScopeLogPublisher] that converts a [ScopeLog] into an [Out] and passes
/// the result to its output function.
///
/// {@category debug}
typedef ScopeLogFormatter<Out extends Object?>
    = CustomLogFormatter<ScopeLog, Out>;

/// Rewrites a [ScopeLog] before it reaches the publisher, or drops it by
/// returning `null`.
///
/// Assign one to [ScopeLogger.transformer].
///
/// {@category debug}
typedef ScopeLogTransformer = LogTransformer<ScopeLog>;

/// The logger the package writes through.
///
/// Not exported: an application configures [ScopeConfig.logger] instead.
final ScopeLogger log = ScopeConfig.logger;

/// The logging level thresholds used by the package.
///
/// {@category debug}
abstract final class ScopeLogLevel {
  /// The highest threshold: nothing is written.
  static const off = Levels.off;

  /// Registered, but unused by the package.
  static const verbose = Levels.verbose;

  /// The whole lifecycle, step by step.
  static const debug = Levels.debug;

  /// The milestones of an asynchronous scope.
  static const info = Levels.info;

  /// Failed initializations and failed disposals.
  static const error = Levels.error;

  /// The lowest threshold: everything is written.
  static const all = Levels.all;
}

/// The signature of the logging methods of a [ScopeLogger].
///
/// The message is evaluated lazily: a function passed as the `message` is only
/// called when the level is enabled.
///
/// {@category debug}
typedef ScopeLogFn = bool Function(
  Object? message, {
  Object? error,
  StackTrace? stackTrace,
});

/// A single log event produced by a [ScopeLogger].
///
/// {@category debug}
final class ScopeLog extends CustomLog {
  /// When the event was produced.
  final DateTime timestamp;
  final LazyString _lazyPath;
  final LazyString _lazyMessage;

  /// Creates a log event; the timestamp is taken here.
  ScopeLog(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required LazyString path,
    required Object? message,
  })  : timestamp = DateTime.now(),
        _lazyPath = path,
        _lazyMessage = LazyString(message);

  /// The path of the logger that produced it.
  String get path => _lazyPath.value;

  /// The message, resolved from a callback if one was passed.
  ///
  /// Never `null`: the message is held as a [LazyString], which renders a `null`
  /// -- and anything else that is not a [String] -- through `toString()`, so a
  /// log written with no message at all reads as `'null'`. A formatter of your
  /// own therefore has nothing to fall back to, and the declared type says so.
  String get message => _lazyMessage.value;
}

/// The logger of one level of a [ScopeLogger], available as
/// `ScopeConfig.logger[level]`.
///
/// Holds that level's name and its [publisher].
///
/// {@category debug}
final class ScopeLevelLogger extends CustomLevelLogger<ScopeLogger,
    ScopeLevelLogger, ScopeLogFn, ScopeLog> {
  /// Creates the logger of one level.
  ScopeLevelLogger({required super.level, required super.name, super.shortName})
      : super(
          noLog: (_, {error, stackTrace}) => true,
          publisher: const CustomLogFormatter(
            format: ScopeLogger.defaultFormat,
            output: print,
          ),
        );

  @override
  ScopeLogFn get processLog => (message, {error, stackTrace}) {
        publishLog(
          ScopeLog(
            this,
            path: logger._lazyPath,
            message: message,
            error: error,
            stackTrace: stackTrace,
          ),
        );

        return true;
      };
}

/// The logger of the package, rooted at `ScopeConfig.logger`.
///
/// Logging is off until a threshold is assigned to `level`. Sub-loggers created
/// with [withAddedName] extend the [path] that every [ScopeLog] carries.
///
/// {@category debug}
final class ScopeLogger
    extends CustomLogger<ScopeLogger, ScopeLevelLogger, ScopeLogFn, ScopeLog> {
  final LazyString _lazyPath;

  /// Joins the segments of [path]; inherited by sub-loggers created after it.
  String pathSeparator = ' | ';

  /// Creates a root logger called [name].
  ScopeLogger(Object name) : _lazyPath = LazyString(name);

  ScopeLogger._(super.parent, Object name)
      : _lazyPath = LazyString(
          () => '${parent.path}'
              '${parent.pathSeparator}'
              '${LazyString(name).value}',
        ),
        pathSeparator = parent.pathSeparator,
        super.sub();

  /// The name of this logger, with the names of its parents in front.
  String get path => _lazyPath.value;

  /// A sub-logger whose [path] is this one plus [name].
  ScopeLogger withAddedName(Object name) => ScopeLogger._(this, name);

  final ScopeLevelLogger _v = ScopeLevelLogger(
    level: Levels.verbose,
    name: 'verbose',
  );
  final ScopeLevelLogger _d = ScopeLevelLogger(
    level: Levels.debug,
    name: 'debug',
  );
  final ScopeLevelLogger _i = ScopeLevelLogger(
    level: Levels.info,
    name: 'info',
  );
  final ScopeLevelLogger _e = ScopeLevelLogger(
    level: Levels.error,
    name: 'error',
  );

  /// Writes at the `verbose` level.
  ScopeLogFn get v => _v.log;

  /// Writes at the `debug` level.
  ScopeLogFn get d => _d.log;

  /// Writes at the `info` level.
  ScopeLogFn get i => _i.log;

  /// Writes at the `error` level.
  ScopeLogFn get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_v);
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  /// The default one-line format: level, path, message, error.
  static String defaultFormat(ScopeLog entry) => '[${entry.shortLevelName}]'
      ' ${entry.path}'
      ' | ${entry.message}'
      '${entry.error == null ? '' : ': ${entry.error}'}'
      '${entry.stackTrace == null || entry.stackTrace == StackTrace.empty //
          ? '' : '\n${entry.stackTrace}'}';
}
