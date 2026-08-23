import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The snippets are code, and code that ships has to compile.
///
/// `ide/scopo.code-snippets` and `ide/scopo-live-templates.xml` are two formats
/// of one thing, kept side by side by hand — so the first thing worth checking
/// is that they still describe the same set. The second is that the skeletons
/// they insert are valid Dart, and that is checked by `flutter analyze` rather
/// than here: `test/ide/snippet_skeletons.dart` holds every skeleton with its
/// tab stops resolved, and the test below fails when it no longer matches the
/// snippets it was generated from.
void main() {
  final snippetsFile = File('ide/scopo.code-snippets');
  final templatesFile = File('ide/scopo-live-templates.xml');
  final skeletonsFile = File('test/ide/snippet_skeletons.dart');

  late Map<String, dynamic> snippets;

  setUpAll(() {
    snippets = (jsonDecode(snippetsFile.readAsStringSync()) as Map)
        .cast<String, dynamic>();
  });

  test('both formats describe the same set of templates', () {
    final xml = templatesFile.readAsStringSync();

    final prefixes =
        snippets.values.map((s) => (s as Map)['prefix'] as String).toSet();
    final names = RegExp('<template name="([^"]+)"')
        .allMatches(xml)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      names,
      prefixes,
      reason: 'a template added to one format and forgotten in the other is '
          'exactly what this pair of files is at risk of',
    );
  });

  test('the live templates escape a literal dollar the IntelliJ way', () {
    final xml = templatesFile.readAsStringSync();

    expect(
      xml,
      isNot(contains(r'\$')),
      reason: r'`\$` is the VS Code escape; IntelliJ takes it literally and '
          'would paste a backslash into the code',
    );
    expect(
      xml,
      contains(r'$$error'),
      reason: 'the interpolation of the error branch survives as a literal '
          'dollar rather than becoming a template variable',
    );
  });

  test('the analyzed skeletons match the snippets they came from', () {
    // Compared with the whitespace squeezed out of both sides. The generated
    // file is formatted by `dart format` like every other file of the suite,
    // and the formatter is entitled to move a line break or drop the trailing
    // space a `$0` leaves behind — neither of which changes what the editor
    // pastes. Comparing verbatim made the test fail on the format run rather
    // than on a snippet that had actually drifted.
    final actual = _squeezed(skeletonsFile.readAsStringSync());

    for (final skeleton in _skeletonsOf(snippets)) {
      expect(
        actual,
        contains(_squeezed(skeleton)),
        reason: 'a snippet was changed without regenerating '
            '`test/ide/snippet_skeletons.dart`, so nothing compiles what the '
            'editor now pastes',
      );
    }
  });
}

/// What an editor pastes, for every snippet but the one-liner: tab stops
/// replaced by their defaults and the VS Code escape of `$` undone.
List<String> _skeletonsOf(Map<String, dynamic> snippets) {
  final out = <String>[];
  for (final entry in snippets.values) {
    final snippet = entry as Map;
    if (snippet['prefix'] == 'scopo-access') continue;

    var body = (snippet['body'] as List).cast<String>().join('\n');
    body = body.replaceAllMapped(
      RegExp(r'\$\{\d+:([^}]*)\}'),
      (m) => m.group(1)!,
    );
    body = body.replaceAllMapped(
      RegExp(r'\$\{\d+\|([^,|]*)[^}]*\}'),
      (m) => m.group(1)!,
    );
    out.add(body.replaceAll(r'$0', '').replaceAll(r'\$', r'$'));
  }

  return out;
}

/// The text with every run of whitespace removed, so that formatting cannot
/// make two equal skeletons look different.
String _squeezed(String text) => text.replaceAll(RegExp(r'\s+'), '');
