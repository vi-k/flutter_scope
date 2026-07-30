import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  test('CompareUtils.identical does not recurse', () {
    final a = Object();
    expect(CompareUtils.identical(a, a), isTrue);
    expect(CompareUtils.identical(a, Object()), isFalse);
    expect(CompareUtils.notIdentical(a, Object()), isTrue);
  });
}
