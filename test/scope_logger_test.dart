import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  test('transformer rewrites and drops logs', () {
    final out = <String>[];
    ScopeConfig.logger.level = ScopeLogLevel.debug;
    ScopeConfig.logger[ScopeLogLevel.debug].publisher = ScopeLogFormatter(
      format: (log) => '${log.path}|${log.message}',
      output: out.add,
    );

    // Sub-logger must inherit the transformer.
    final sub = ScopeConfig.logger.withAddedName('child');

    ScopeLog? drop(ScopeLog log) =>
        (log.message ?? '').contains('noisy') ? null : log;

    expect(drop, isA<ScopeLogTransformer>());
    ScopeConfig.logger.transformer = drop;

    ScopeConfig.logger.d('kept');
    ScopeConfig.logger.d('noisy one');
    sub.d('kept from sub');
    sub.d('noisy from sub');

    expect(out, ['scopo|kept', 'scopo | child|kept from sub']);

    ScopeConfig.logger.transformer = null;
    ScopeConfig.logger.d('noisy again');
    expect(out.last, 'scopo|noisy again');

    ScopeConfig.logger.level = ScopeLogLevel.off;
  });
}
