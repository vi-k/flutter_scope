# debug

Logging and the global settings of the package. Everything on this page is
static and lives in `ScopeConfig`, so the usual place to set it up is `main()`,
before `runApp`.

## Levels

Logging is off by default: `ScopeConfig.logger.level` is `ScopeLogLevel.off`.
Assigning a lower threshold enables every level whose value is equal to or
greater than it.

```dart
void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  runApp(const App());
}
```

`ScopeLogLevel` collects the thresholds the package uses. They are plain `int`
constants (the `Levels` of `logger_builder`), so `level` also accepts an
intermediate value.

| Constant                | Value | What the package writes                   |
| ----------------------- | ----- | ----------------------------------------- |
| `ScopeLogLevel.all`     | 0     | the lowest possible threshold: everything |
| `ScopeLogLevel.verbose` | 400   | registered, but unused by the package     |
| `ScopeLogLevel.debug`   | 500   | the whole lifecycle, step by step         |
| `ScopeLogLevel.info`    | 800   | the milestones of an asynchronous scope   |
| `ScopeLogLevel.error`   | 1000  | failed initialization and failed disposal |
| `ScopeLogLevel.off`     | 2000  | the highest possible threshold: nothing   |

`info` is a reasonable default for an application: it reports
`initialize…`/`initialized`, the progress values, `dispose…`/`disposed`, and the
cancellation of an interrupted initialization.

`debug` is what to turn on when a scope hangs, initializes in an unexpected
order, or is disposed of too late. On top of the `info` messages it reports
preparation for initialization and disposal, waiting for a `scopeKey`, waiting
for child scopes, and every dependency of a `ScopeAutoDependencies` as it is
initialized or disposed of.

`error` reports `initialization failed`, `disposal failed`, and the errors
raised while disposing of dependencies — each with its `error` and
`stackTrace`. Note that a scope also reports its initialization errors through
`buildOnError` and its timeouts through `FlutterError.reportError`, so turning
logging off never hides an error completely.

## Output

Every level has its own publisher, so the format and the destination can be
replaced per level:

```dart
ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
  format: ScopeLogger.defaultFormat,
  output: debugPrint,
);
```

`ScopeLogFormatter` is the `ScopeLogPublisher` built from two functions:
`format` turns a `ScopeLog` into something (usually a `String`) and `output`
receives the result. Assigning `ScopeConfig.logger.publisher` instead of
`ScopeConfig.logger[level].publisher` replaces the publisher of all levels at
once. By default every level formats with `ScopeLogger.defaultFormat` and
prints with `print`.

A `ScopeLog` carries the `timestamp`, the `path` of the logger that produced it,
the `message`, the numeric `level` with its `levelName` and `shortLevelName`,
and the optional `error` and `stackTrace`. `ScopeLogger.defaultFormat` lays them
out like this:

```text
[d] scopo | TestDependencies(#25f53) | progress: dep1 (1/10)
[i] scopo | CounterScope(#4e0b7) | initialized
[e] scopo | CounterScope(#4e0b7) | initialization failed: Exception: no network
```

The path starts with the name of the root logger (`scopo`) and gains a segment
per nested logger — for a scope, the widget type with its short hash, or with
its `tag` when one is given. The segments are joined with
`ScopeLogger.pathSeparator` (` | ` by default; assign it on `ScopeConfig.logger`
and the sub-loggers created afterwards inherit it). The message is followed by
`: <error>` when the event carries one, and by the stack trace on a line of its
own when it carries a non-empty one.

`ScopeLogFn` is the signature of the four logging methods of `ScopeLogger` (`v`,
`d`, `i`, `e`): a message plus an optional `error` and `stackTrace`. The message
is an `Object?`, and a callback passed as the message is only invoked when the
level is enabled — which is why the calls inside the package look like
`_log.d(() => 'progress: $path')`.

`ScopeLevelLogger` is the object behind `ScopeConfig.logger[level]`: it holds
that level's `name`, `shortName`, and `publisher`.

### Filtering and rewriting

A transformer runs on every log of every level just before it is published.
Returning `null` drops the log, which is how noisy paths are filtered out
without turning the level off:

```dart
ScopeConfig.logger.transformer = (log) =>
    log.path.contains('AnimationScope') ? null : log;
```

Its signature is `ScopeLogTransformer`. Sub-loggers inherit the transformer the
same way they inherit `level` and publishers, so assigning one on
`ScopeConfig.logger` covers the whole package. A transformer that throws drops
the log rather than publishing it untransformed, and reports the error to the
current zone.

### Per-level colors

The pattern used by both example applications — one ANSI printer per level:

```dart
import 'dart:io';

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;
import 'package:scopo/scopo.dart';

void setLogPrinter(int level, ansi.Color foreground) {
  final printer = ansi.Printer(
    ansiCodesEnabled: !Platform.isIOS,
    defaultStyle: ansi.Style(foreground: foreground),
  );

  ScopeConfig.logger[level].publisher = ScopeLogFormatter(
    format: ScopeLogger.defaultFormat,
    output: printer.print,
  );
}

void main() {
  ScopeConfig.logger.level = ScopeLogLevel.info;

  setLogPrinter(ScopeLogLevel.verbose, ansi.Color256.gray7);
  setLogPrinter(ScopeLogLevel.debug, ansi.Color256.gray12);
  setLogPrinter(ScopeLogLevel.info, ansi.Color256.rgb345);
  setLogPrinter(ScopeLogLevel.error, ansi.Color256.rgb400);

  runApp(const App());
}
```

A publisher does not have to format anything: any `ScopeLogPublisher` will do,
which is the way to collect the events into a list and assert on them.

## Timeouts

Four waits in the scope lifecycle are bounded by a timeout, and all four
defaults live in `ScopeConfig`:

- `ScopeConfig.defaultScopeKeysTimeout` — how long a scope waits for its
  `scopeKey` to be released by the previous owner;
- `ScopeConfig.defaultInitCancellationTimeout` — how long a teardown waits for
  the initialization to be cancelled;
- `ScopeConfig.defaultDisposeAsyncTimeout` — how long a teardown waits for
  `disposeAsync`, the scope's own release;
- `ScopeConfig.defaultWaitForChildrenTimeout` — how long a scope waits for its
  child scopes to be disposed of before disposing of itself.

All four are three seconds by default. `null` removes the limit and the scope
waits indefinitely. An expired timeout is not fatal: it is reported through
`FlutterError.reportError`, and the scope then proceeds as if the wait had
succeeded — so a dependency that never completes its disposal degrades into a
delay plus an error report instead of a deadlock.

The two middle ones are measured on real time rather than on the clock of the
zone the teardown runs in, which is what a widget test replaces with a fake
one. A hang like the ones they exist for outlives frames, and a scope is
usually taken down between them: a timer belonging to that zone would still be
pending when the tree is gone, and `flutter_test` ends a test on exactly that.

Every scope can override all four defaults for itself with the
`scopeKeyTimeout`, `initCancellationTimeout`, `disposeAsyncTimeout` and
`waitForChildrenTimeout` parameters, and observe an expiry through the
`onScopeKeyTimeout`, `onInitCancellationTimeout`, `onDisposeAsyncTimeout` and
`onWaitForChildrenTimeout` callbacks. What a scope cannot do for itself is
remove the limit: `null` there means "take the default", not "wait as long as it
takes". Removing a limit is what the `ScopeConfig` values above are for, and it
applies to every scope at once.

## pauseAfterInitializationEnabled

`pauseAfterInitialization` is an artificial delay between the moment a scope
becomes ready and the moment its subtree is shown; it exists to keep a loading
indicator visible long enough to be read instead of blinking.

`ScopeConfig.pauseAfterInitializationEnabled = false` switches every such pause
off globally, without touching the widgets that declare it. Set it in the setup
of a widget test, or while stepping through an initialization in the debugger.

## reset()

The switches above — the pause and the four timeouts — are global and outlive
the code that changed them, so a test that raises a timeout and forgets to put
it back hands the next test a different package. `ScopeConfig.reset()` puts all
five back to their defaults:

```dart
void main() {
  tearDown(ScopeConfig.reset);
  …
}
```

`setUp` works as well, and covers a test that failed before its own teardown
ran. The logger is left alone: it is an object with publishers and a
transformer of its own rather than a switch, and the level it was given is
usually the whole point of the run it was given for.

## In tests

The whole setup for a test suite is the threshold plus a publisher pointing at
wherever the test output goes:

```dart
void logInit() {
  ScopeConfig.logger.level = ScopeLogLevel.debug;
  ScopeConfig.logger.publisher = const ScopeLogFormatter(
    format: ScopeLogger.defaultFormat,
    output: print,
  );
}
```

Keep it opt-in: at `debug` a single scope produces a dozen lines, which buries
the reason a test failed. `ScopeLogLevel.off` between investigations, and
`ScopeConfig.pauseAfterInitializationEnabled = false` so that the pauses do not
have to be pumped through.

See
[example/minimal](https://github.com/vi-k/scopo/blob/main/example/minimal/lib/main.dart)
for the setup of a real application, and
[example/scopo_demo](https://github.com/vi-k/scopo/tree/main/example/scopo_demo)
for a demo that logs every lifecycle call of every scope family side by side.
