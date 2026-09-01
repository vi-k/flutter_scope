import 'dart:io';

import 'package:test/test.dart';

/// The documents a reader is sent to, checked as the code they contain.
///
/// A topic on pub.dev is copied from, not read past — so a command that names
/// the wrong version and a fragment that calls a parameter by a name it lost
/// are defects of the same kind as one in `lib/`, and neither is caught by any
/// of the eight checks of the gate. Both checks below ask *every* published
/// document rather than the ones somebody listed: each of these two defects
/// had already been fixed once, in the places that were remembered, and each
/// survived in a place that was not.
void main() {
  /// Every Markdown file that ships or mirrors one that does.
  Iterable<File> publishedMarkdown() => <FileSystemEntity>[
        File('README.md'),
        File('ide/README.md'),
        ...Directory('doc').listSync(),
        ...Directory('docs/ru').listSync(recursive: true),
      ].whereType<File>().where((file) => file.path.endsWith('.md'));

// The command that copies the templates out of pub-cache takes the newest
// version it finds there, and it takes it with `sort`. A plain `sort` is
// lexicographic, so it puts `scopo-0.9.6` after `scopo-0.13.0` and the copy
// comes from a version that may have no `ide/` in it at all. Found once and
// fixed in the four places it was known to be in -- and the same two
// commands stood on in the `base` topic, which is the page the README sends
// the reader to for the details, until another review found them. A list
// written by hand is what let that happen twice, so this asks every file
// that carries the command instead.
  test('every copy of the install command sorts versions numerically', () {
    final markdown = publishedMarkdown();

    final commands = [
      for (final file in markdown)
        for (final line in file.readAsLinesSync())
          if (line.contains('find ~/.pub-cache')) '${file.path}: $line',
    ];

    expect(
      commands,
      hasLength(greaterThan(4)),
      reason: 'a check over nothing passes for nothing: the command is in the '
          'README, in the `base` topic, in `ide/README.md`, and in the Russian '
          'mirror of each',
    );
    expect(
      commands.where((command) => !command.contains('| sort -V |')),
      isEmpty,
      reason: 'a plain `sort` is lexicographic: it puts `scopo-0.9.6` after '
          '`scopo-0.13.0`, and the copy then comes from a version with no '
          '`ide/` in it',
    );
  });

  // A subclass that re-declares an inherited member and gives it a one-line
  // doc of its own does not add a line to the page: it replaces the whole
  // inherited text with that line. `LiteScopeState`, `ScopeCoreState` and
  // `ScopeState` each re-declare `initStateAsync` and `disposeStateAsync` to
  // gather them into their overriding block, and each carried "Initializes the
  // scope asynchronously." So the rule a disposer has to know -- that it runs
  // after an `initStateAsync` that threw and must therefore expect a partially
  // initialized state, the breaking change of 0.13.0 -- stood on the page of
  // `LiteScopeCoreState` alone, which is the one class of the four nobody is
  // told to extend. Left without a doc comment the override inherits the base
  // text, and `public_member_api_docs` does not ask for one on an override.
  test('the overriding blocks inherit their contract rather than shadow it',
      () {
    final declaration =
        RegExp(r'^\s*FutureOr<void> (initStateAsync|disposeStateAsync)\(\)');

    final overrides = <String>[];
    final shadowed = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final lines = entity.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        if (!declaration.hasMatch(line) ||
            index < 1 ||
            lines[index - 1].trim() != '@override') {
          continue;
        }

        final place = '${entity.path}:${index + 1}: ${line.trim()}';
        overrides.add(place);
        if (index >= 2 && lines[index - 2].trim().startsWith('///')) {
          shadowed.add(place);
        }
      }
    }

    expect(
      overrides,
      hasLength(6),
      reason: 'a check over nothing passes for nothing: three classes '
          're-declare both hooks, and the two base declarations carry no '
          '`@override`',
    );
    expect(
      shadowed,
      isEmpty,
      reason: 'a doc comment on an override replaces the inherited text on the '
          'page rather than adding to it, and the contract lives in the base',
    );
  });

  // `init:` is a parameter of nothing in this package. `AsyncScope` takes
  // `initScope:`, `AsyncDataScope` takes `initData:`, and both have since the
  // renaming of 2026-08-18; `ScopeModel` and `ScopeNotifier` take `create:`
  // and `dispose:`, which is why `dispose:` is not asked about here. The
  // renaming converted the complete examples of every topic and left the bare
  // fragments -- among them the Wrong/Right pair that teaches the one idiom
  // this package most wants copied -- calling the parameters by names that no
  // longer compile.
  test('the topics call the parameters by the names the package has', () {
    final stale = [
      for (final file in publishedMarkdown())
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (RegExp(r'(^|[\s(,])init:').hasMatch(line))
            '${file.path}:${index + 1}: ${line.trim()}',
    ];

    expect(
      stale,
      isEmpty,
      reason: 'a reader who copies this gets '
          "\"The named parameter 'init' isn't defined\"",
    );

    final text = publishedMarkdown().map((f) => f.readAsStringSync()).join();
    expect(
      RegExp('initScope:').hasMatch(text) && RegExp('initData:').hasMatch(text),
      isTrue,
      reason: 'a check over nothing passes for nothing: both names the '
          'fragments should be using are in these files',
    );
  });
}
