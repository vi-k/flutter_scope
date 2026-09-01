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
  ///
  /// The samples are in here as well, and they were the omission that made
  /// this list a hand-written one again: `example/**` goes into the archive
  /// and its README is the Example tab on pub.dev, so a stale fragment there
  /// is read by as many people as one in a topic. `CHANGELOG.md` ships too.
  /// What is skipped under `example` is what is not published from it --
  /// build output and the tool's own cache.
  Iterable<File> publishedMarkdown() => <FileSystemEntity>[
        File('README.md'),
        File('CHANGELOG.md'),
        File('ide/README.md'),
        ...Directory('doc').listSync(),
        ...Directory('example').listSync(recursive: true),
        ...Directory('docs/ru').listSync(recursive: true),
      ].whereType<File>().where((file) => file.path.endsWith('.md')).where(
            (file) =>
                !file.path.contains('/build/') &&
                !file.path.contains('/.dart_tool/'),
          );

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

  // The other half of the same renaming, and the half the check above cannot
  // see. `dispose:` is a real parameter -- of `ScopeModel` and
  // `ScopeNotifier` -- so it cannot be asked about everywhere, which is why
  // the check above asks only about `init:`. In the two asynchronous topics it
  // is the name the parameter lost in 2026-08-18, and a fragment that drifts
  // back to it there compiles nowhere.
  test('the asynchronous topics call their teardown by its own name', () {
    final topics = [
      for (final file in publishedMarkdown())
        if (RegExp(r'async_(data_)?scope\.md$').hasMatch(file.path)) file,
    ];

    expect(
      topics,
      hasLength(4),
      reason: 'a check over nothing passes for nothing: two topics and the '
          'Russian mirror of each',
    );

    final stale = [
      for (final file in topics)
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (RegExp(r'(^|[\s(,])dispose:').hasMatch(line))
            '${file.path}:${index + 1}: ${line.trim()}',
    ];

    expect(
      stale,
      isEmpty,
      reason: 'these two take `disposeScope:` and `disposeData:`; a reader who '
          "copies `dispose:` gets \"The named parameter 'dispose' isn't "
          'defined"',
    );

    final text = topics.map((file) => file.readAsStringSync()).join();
    expect(
      RegExp('disposeScope:').hasMatch(text) &&
          RegExp('disposeData:').hasMatch(text),
      isTrue,
      reason: 'and both names they should be using are in these files',
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
