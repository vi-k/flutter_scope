import 'dart:io';

import 'package:ansi_escape_codes/ansi_escape_codes.dart' as ansi;
import 'package:scopo/scopo.dart';

/// Sets up the logging of a test run.
///
/// Logging is **off by default**: a full run used to print around fifteen
/// debug lines per test, which buried the failures it was supposed to help
/// with. Turn it on for one run without touching the code:
///
/// ```sh
/// SCOPO_LOG=debug fvm flutter test test/scope_auto_dependencies_test.dart
/// ```
///
/// or ask for a level explicitly with `logInit(level: ScopeLogLevel.debug)`.
/// An explicit [level] wins over the environment.
void logInit({int? level}) {
  ScopeConfig.logger.level =
      level ?? _levelFromEnvironment() ?? ScopeLogLevel.off;

  void setPrinter(
    int level,
    ansi.Color foreground, {
    ansi.Color? background,
  }) {
    final printer = ansi.Printer(
      ansiCodesEnabled: !Platform.isIOS,
      defaultStyle: ansi.Style(
        foreground: foreground,
        background: background,
      ),
    );

    ScopeConfig.logger[level].publisher = ScopeLogFormatter(
      format: ScopeLogger.defaultFormat,
      output: printer.print,
    );
  }

  setPrinter(ScopeLogLevel.verbose, ansi.Color256.gray7);
  setPrinter(ScopeLogLevel.debug, ansi.Color256.gray12);
  setPrinter(ScopeLogLevel.info, ansi.Color256.rgb345);
  setPrinter(ScopeLogLevel.error, ansi.Color256.rgb400);
}

/// The level asked for through the `SCOPO_LOG` environment variable, or `null`
/// when it is unset or holds something else.
int? _levelFromEnvironment() =>
    switch (Platform.environment['SCOPO_LOG']?.toLowerCase()) {
      'off' => ScopeLogLevel.off,
      'verbose' => ScopeLogLevel.verbose,
      'debug' => ScopeLogLevel.debug,
      'info' => ScopeLogLevel.info,
      'error' => ScopeLogLevel.error,
      'all' => ScopeLogLevel.all,
      _ => null,
    };
