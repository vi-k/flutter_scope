import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

void main() {
  test('CompareUtils.identical does not recurse', () {
    final a = Object();
    expect(CompareUtils.identical(a, a), isTrue);
    expect(CompareUtils.identical(a, Object()), isFalse);
    expect(CompareUtils.notIdentical(a, Object()), isTrue);
  });

  // The four are passed as `compare:`, where the question is "did it change?"
  // — so a pair that answers it backwards turns a filter into its opposite
  // and nothing in the tree looks wrong until a value stops arriving. Cheap
  // to write down, and `notEquals` did read as `==` in a mutation the suite
  // never noticed.
  test('CompareUtils answers each question the way its name reads', () {
    expect(CompareUtils.equals('a', 'a'), isTrue);
    expect(CompareUtils.equals('a', 'b'), isFalse);
    expect(CompareUtils.notEquals('a', 'b'), isTrue);
    expect(CompareUtils.notEquals('a', 'a'), isFalse);

    // Equal but not the same object, which is where the two pairs part.
    final a = ['x'];
    final b = ['x'];
    expect(CompareUtils.identical(a, b), isFalse);
    expect(CompareUtils.notIdentical(a, b), isTrue);
    expect(CompareUtils.notIdentical(a, a), isFalse);
  });
}
