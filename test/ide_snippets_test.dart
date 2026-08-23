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

  // The copy in `.vscode/` is what this repository's own editor picks up, so it
  // exists to be tried out on the spot rather than copied from pub-cache first.
  // Two files with one content drift the moment one of them is edited, and
  // nothing but a check keeps them together — `.vscode/` is not in the package
  // archive, so no consumer ever sees the difference and no one else notices.
  test('the copy in .vscode matches the one that ships', () {
    final shipped = File('ide/scopo.code-snippets');
    final local = File('.vscode/scopo.code-snippets');

    expect(
      local.existsSync(),
      isTrue,
      reason: 'the working copy of the snippets is missing; restore it with '
          '`cp ide/scopo.code-snippets .vscode/`',
    );
    expect(
      local.readAsStringSync(),
      shipped.readAsStringSync(),
      reason: 'the snippets were edited on one side only — copy '
          '`ide/scopo.code-snippets` over `.vscode/scopo.code-snippets`',
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
    // One file per skeleton, named after the prefix: several skeletons declare
    // a class of the same default name, which is right in an editor and a
    // conflict in one library.
    //
    // Compared with the whitespace squeezed out of both sides. The generated
    // files are formatted by `dart format` like everything else in the suite,
    // and the formatter is entitled to move a line break or drop the trailing
    // space a `$0` leaves behind — neither of which changes what the editor
    // pastes.
    for (final entry in snippets.values) {
      final snippet = entry as Map;
      final prefix = snippet['prefix'] as String;
      if (prefix == 'scopo-access') continue;

      final file = File('test/ide/${prefix.replaceAll('-', '_')}.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'a snippet was added without a skeleton to compile it: '
            'expected ${file.path}',
      );
      expect(
        _squeezed(file.readAsStringSync()),
        contains(_squeezed(_skeletonOf(snippet))),
        reason: 'the snippet `$prefix` was changed without regenerating '
            '${file.path}, so nothing compiles what the editor now pastes',
      );
    }
  });
}

/// What an editor pastes: tab stops replaced by their defaults and the VS Code
/// escape of `$` undone.
String _skeletonOf(Map<dynamic, dynamic> snippet) {
  var body = (snippet['body'] as List).cast<String>().join('\n');
  body = body.replaceAllMapped(
    RegExp(r'\$\{\d+:([^}]*)\}'),
    (m) => m.group(1)!,
  );
  body = body.replaceAllMapped(
    RegExp(r'\$\{\d+\|([^,|]*)[^}]*\}'),
    (m) => m.group(1)!,
  );

  return body.replaceAll(r'$0', '').replaceAll(r'\$', r'$');
}

/// The text with every run of whitespace removed, so that formatting cannot
/// make two equal skeletons look different.
String _squeezed(String text) => text.replaceAll(RegExp(r'\s+'), '');
