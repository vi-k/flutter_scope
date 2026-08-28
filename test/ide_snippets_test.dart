import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

/// The snippets are code, and code that ships has to compile.
///
/// `ide/scopo.code-snippets` and `ide/scopo-live-templates.xml` are two formats
/// of one thing, kept side by side by hand — so the first thing worth checking
/// is that they still describe the same set. The second is that the skeletons
/// they insert are valid Dart, and that is checked by `flutter analyze` rather
/// than here: `test/ide/` holds one file per snippet prefix — several
/// skeletons declare a class of the same default name, which is right in an
/// editor and a conflict in one library — each with its tab stops resolved,
/// and the test below fails when a file no longer matches the snippet it was
/// generated from.
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

  // A file an editor refuses is not a file with a broken template in it: the
  // whole group simply does not appear, without a word. It happened here — a
  // rewritten header comment carried `--`, which XML does not allow inside one,
  // and the gate had nothing that would notice, because everything else reads
  // this file as text. These are the two rules a hand-edited XML actually
  // breaks; a full parse would want a package, and this is not one.
  test('the live templates file is XML a parser will accept', () {
    final xml = templatesFile.readAsStringSync();

    for (final comment in RegExp(r'<!--([\s\S]*?)-->').allMatches(xml)) {
      expect(
        comment.group(1),
        isNot(contains('--')),
        reason: 'XML forbids `--` inside a comment, and an editor that meets '
            'one drops the whole file',
      );
    }

    final ampersands = RegExp('&').allMatches(xml).length;
    final entities =
        RegExp(r'&(#\d+|#x[0-9a-fA-F]+|amp|lt|gt|quot|apos);').allMatches(xml);
    expect(
      ampersands - entities.length,
      0,
      reason: 'a bare `&` is not XML either; every one of them has to open an '
          'entity',
    );
  });

  // A live template is offered where its context says. The ten that declare
  // classes take `DART_TOPLEVEL`, contributed by the *Flutter* plugin rather
  // than the Dart one — which is why reading the Dart plugin's `plugin.xml`
  // alone showed only two contexts — and it is what Flutter's own `stless` and
  // `stful` declare.
  //
  // The accessor line goes into a class body, and that is neither of the two
  // narrow contexts: `DART_STATEMENT` covers statement positions, which means
  // inside a function, and a class body is not one. `DART`, the generic
  // context, is the only one that reaches it. Too broad for a class skeleton —
  // it offers one inside a method body, where it pastes as broken code — and
  // exactly right here. Both halves were settled by an import, not by reading.
  test('every live template declares the context it belongs in', () {
    final xml = templatesFile.readAsStringSync();

    const genericTemplates = {'scopo-access'};

    final blocks =
        RegExp(r'<template name="([^"]+)"[\s\S]*?</template>').allMatches(xml);

    expect(blocks.length, 11, reason: 'eleven templates, one context each');

    for (final block in blocks) {
      final name = block.group(1)!;
      final contexts = RegExp('<option name="(DART[A-Z_]*)"')
          .allMatches(block.group(0)!)
          .map((m) => m.group(1)!)
          .toList();

      final expected =
          genericTemplates.contains(name) ? 'DART' : 'DART_TOPLEVEL';

      expect(
        contexts,
        [expected],
        reason: '`$name` is offered in the wrong place: a class skeleton on '
            '`DART` turns up inside method bodies, and the accessor line on '
            'anything narrower does not turn up in a class body at all',
      );
    }
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

  // A tab stop that offers a list is the one place where the two formats say
  // the same thing differently: VS Code writes `${1|A,B,C|}` inline, IntelliJ
  // writes `expression="enum(&quot;A&quot;,…)"` on the variable. Nothing but a
  // check keeps them together, and the one that went missing left the stop
  // empty — the reader had to know the eight names by heart.
  test('a choice in the snippets is a choice in the live templates too', () {
    final xml = templatesFile.readAsStringSync();
    final choice = RegExp(r'\$\{\d+\|([^|]*)\|\}');

    var checked = 0;
    for (final entry in snippets.values) {
      final snippet = entry as Map;
      final prefix = snippet['prefix'] as String;
      final body = (snippet['body'] as List).cast<String>().join('\n');

      for (final match in choice.allMatches(body)) {
        final options = match.group(1)!.split(',');
        final wanted =
            'enum(${options.map((o) => '&quot;$o&quot;').join(',')})';
        final block = RegExp('<template name="$prefix"[\\s\\S]*?</template>')
            .firstMatch(xml)!
            .group(0)!;

        expect(
          block,
          contains(wanted),
          reason: '`$prefix` offers a list in VS Code and nothing in IntelliJ; '
              'the same list belongs there as $wanted',
        );
        checked++;
      }
    }

    expect(
      checked,
      1,
      reason: 'one stop offers a list today — the accessor class of '
          '`scopo-access`; a test that found none would pass for the wrong '
          'reason',
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
      // `scopo-access` has no skeleton to compile, and cannot have one: its
      // first tab stop is a choice of eight accessor types, and they do not
      // share a shape -- `ScopeAccess` takes three type arguments where
      // `ScopeWidgetAccess` takes one, so the `<Widget>` the snippet offers
      // is a placeholder the writer replaces rather than code that compiles.
      // Checked below instead, by the one thing that could go wrong silently:
      // a name in that list no longer being a class in the package.
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

  // The one snippet with no skeleton to compile, and the one way it can go
  // wrong without a word: `scopo-access` offers a choice of eight accessor
  // types, and nothing tied that list to the library. Renaming one of them
  // left the snippet offering a name that no longer exists, and every other
  // check here passed -- the set of prefixes was unchanged, the XML was
  // valid, and this snippet is skipped by the skeleton comparison above.
  test('every type the access snippet offers is a class in the package', () {
    final snippet = snippets.values
        .cast<Map<dynamic, dynamic>>()
        .firstWhere((s) => s['prefix'] == 'scopo-access');
    final body = (snippet['body'] as List).cast<String>().join('\n');
    final choice = RegExp(r'\$\{\d+\|([^}|]*)\|\}').firstMatch(body);

    expect(
      choice,
      isNotNull,
      reason: 'the snippet no longer offers a choice of types; if that is '
          'deliberate, this test is what has to change with it',
    );

    final offered = choice!.group(1)!.split(',');
    expect(offered, hasLength(8));

    final sources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    for (final name in offered) {
      expect(
        sources,
        contains(RegExp('class $name<')),
        reason: 'the access snippet offers `$name`, and the package has no '
            'such class any more',
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
