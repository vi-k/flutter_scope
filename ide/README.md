# Editor templates

Eleven templates for the boilerplate a scope needs: the class skeletons of every
family, the dependency container, and the accessor line.

The skeletons write out the accessors as **statics of the scope**, so a
descendant reads `App.select(context, …)`. That is what a template is for — the
cost of those wrappers was typing them, and a template has already paid it. The
`ScopeAccess` objects are the other answer to the same cost, for code written by
hand; `scopo-access` inserts one for a scope that prefers them.

Two files, one set. They are maintained side by side by hand, and a test
(`test/ide_snippets_test.dart`) fails if one of them gains a template the other
does not.

## VS Code

Also Cursor, Windsurf and Antigravity — they share the format.

The file ships with the package, so it is already on your machine. Find it and
copy it into the project:

```sh
mkdir -p .vscode
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort -V | tail -1)"/ide/scopo.code-snippets .vscode/
```

For all your projects at once, run **Snippets: Configure Snippets** from the
command palette, pick Dart, and paste the contents in.

## IntelliJ IDEA and Android Studio

Recent versions no longer offer an import button on the Live Templates page.
Copy the file into the configuration directory of the IDE instead, under
`templates/`, named after the group it declares:

```sh
# Android Studio on macOS; for IntelliJ IDEA the directory is
# ~/Library/Application Support/JetBrains/<product>/
DIR=~/Library/Application\ Support/Google/AndroidStudio<version>/templates
mkdir -p "$DIR"
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort -V | tail -1)"/ide/scopo-live-templates.xml "$DIR/scopo.xml"
```

The file name has to match the group: the XML declares `scopo`, so the file is
`scopo.xml`. Restart the IDE, and the templates appear under
**Settings → Editor → Live Templates** in a group named `scopo`.

## The templates

| type this | and get |
| --- | --- |
| `scopo-scope` | a full `Scope`: widget, automatic dependencies, state, statics |
| `scopo-autodeps` | a `ScopeAutoDependencies` tree that unwinds itself |
| `scopo-deps` | a hand-written container: immutable, with a teardown a cancellation reaches |
| `scopo-lite` | a `LiteScope` and its state |
| `scopo-widget` | a `ScopeWidgetBase` |
| `scopo-model` | a `ScopeModelBase` over a plain object |
| `scopo-notifier` | a `ScopeNotifierBase` over a `Listenable` |
| `scopo-async` | an `AsyncScopeBase` |
| `scopo-data` | an `AsyncDataScopeBase` |
| `scopo-controller` | an `AsyncControllerScopeBase` and the controller it owns |
| `scopo-access` | the accessor line, for a scope that prefers `ScopeAccess` |

## What is checked, and what is not

Every skeleton these templates insert is compiled: each is expanded with its
default names into its own file under `test/ide/`, which `flutter analyze`
covers like any other file of the package. One file each, because several
skeletons declare a class of the same default name — right in an editor,
a conflict in one library. A template that stops being valid
Dart fails the gate.

**The live templates are checked in part.** The suite holds them to the same set
as the snippets, to the two rules of XML a hand-edited file breaks, to the
IntelliJ way of escaping a literal dollar, to the list a tab stop offers, and to
the context each one belongs in — but what an editor makes of the file is
something only an import shows. Android Studio took it in August 2026; if a
version refuses one, that is a bug worth reporting.

A file an editor refuses is not a file with one broken template in it: the whole
group simply does not appear, and nothing says why.

Three contexts are in play, and only two of them belong to the Dart plugin.
`DART` is its generic one, offering a template everywhere in a Dart file;
`DART_STATEMENT` narrows that to statement positions, which means inside a
function. The third, `DART_TOPLEVEL`, is contributed by the **Flutter** plugin,
and it is what the ten class skeletons declare — the same context Flutter's own
`stless` and `stful` use. Without that plugin installed they are not offered at
all.

The accessor line takes `DART`, and the narrower context is the wrong one for
it: it goes into a class body, and a class body is not a statement position, so
`DART_STATEMENT` never offers it there. `DART` is too broad for a class
skeleton — that would turn up inside method bodies — and exactly right for a
member.

The skeletons are also inserted as written rather than reformatted by the IDE
(`toReformat="false"`): they are already shaped by `dart format`, which the gate
checks, and the IDE's own Dart formatter is not that one.
