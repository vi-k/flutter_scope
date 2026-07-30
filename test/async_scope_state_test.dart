import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  group('AsyncScopeError.toString', () {
    test('balanced parens without progress', () {
      final s = AsyncScopeError(Exception('x'), StackTrace.empty).toString();
      expect('('.allMatches(s).length, ')'.allMatches(s).length);
    });

    test('balanced parens with progress', () {
      final s = AsyncScopeError(Exception('x'), StackTrace.empty, progress: 1)
          .toString();
      expect('('.allMatches(s).length, ')'.allMatches(s).length);
    });
  });
}
