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

final ScopeLogger log = ScopeConfig.logger;

/// The logging level thresholds used by the package.
///
/// {@category debug}
abstract final class ScopeLogLevel {
  static const off = Levels.off;
  static const verbose = Levels.verbose;
  static const debug = Levels.debug;
  static const info = Levels.info;
  static const error = Levels.error;
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
  final DateTime timestamp;
  final LazyString _lazyPath;
  final LazyString _lazyMessage;

  ScopeLog(
    super.levelLogger, {
    super.error,
    super.stackTrace,
    required LazyString path,
    required Object? message,
  })  : timestamp = DateTime.now(),
        _lazyPath = path,
        _lazyMessage = LazyString(message);

  String get path => _lazyPath.value;
  String? get message => _lazyMessage.value;
}

/// The logger of one level of a [ScopeLogger], available as
/// `ScopeConfig.logger[level]`.
///
/// Holds that level's name and its [publisher].
///
/// {@category debug}
final class ScopeLevelLogger extends CustomLevelLogger<ScopeLogger,
    ScopeLevelLogger, ScopeLogFn, ScopeLog> {
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
        publisher.publish(
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
  String pathSeparator = ' | ';

  ScopeLogger(Object name) : _lazyPath = LazyString(name);

  ScopeLogger._(super.parent, Object name)
      : _lazyPath = LazyString(
          () => '${parent.path}'
              '${parent.pathSeparator}'
              '${LazyString(name).value}',
        ),
        pathSeparator = parent.pathSeparator,
        super.sub();

  String get path => _lazyPath.value;

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

  ScopeLogFn get v => _v.log;
  ScopeLogFn get d => _d.log;
  ScopeLogFn get i => _i.log;
  ScopeLogFn get e => _e.log;

  @override
  void registerLevels() {
    registerLevel(_v);
    registerLevel(_d);
    registerLevel(_i);
    registerLevel(_e);
  }

  static String defaultFormat(ScopeLog entry) => '[${entry.shortLevelName}]'
      ' ${entry.path}'
      ' | ${entry.message}'
      '${entry.error == null ? '' : ': ${entry.error}'}'
      '${entry.stackTrace == null || entry.stackTrace == StackTrace.empty //
          ? '' : '\n${entry.stackTrace}'}';
}
