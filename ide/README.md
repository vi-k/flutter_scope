# Editor templates

Nine templates for the boilerplate a scope needs: the class skeletons of every
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
cp "$(find ~/.pub-cache/hosted/pub.dev -maxdepth 1 -name 'scopo-*' | sort | tail -1)"/ide/scopo.code-snippets .vscode/
```

For all your projects at once, run **Snippets: Configure Snippets** from the
command palette, pick Dart, and paste the contents in.

## IntelliJ IDEA and Android Studio

**Settings → Editor → Live Templates → the gear icon → Import Live Templates**,
and pick `scopo-live-templates.xml`. The templates arrive in a group named
`scopo`.

## The templates

| type this | and get |
| --- | --- |
| `scopo-scope` | a full `Scope`: widget, state and the five statics |
| `scopo-deps` | a `ScopeDependencies` container with async initialization |
| `scopo-lite` | a `LiteScope` and its state |
| `scopo-widget` | a `ScopeWidgetBase` |
| `scopo-model` | a `ScopeModelBase` over a plain object |
| `scopo-notifier` | a `ScopeNotifierBase` over a `Listenable` |
| `scopo-async` | an `AsyncScopeBase` |
| `scopo-data` | an `AsyncDataScopeBase` |
| `scopo-access` | the accessor line, for a scope that prefers `ScopeAccess` |

## What is checked, and what is not

Every skeleton these templates insert is compiled: they are expanded with their
default names into `test/ide/snippet_skeletons.dart`, which `flutter analyze`
covers like any other file of the package. A template that stops being valid
Dart fails the gate.

**The live templates themselves are not verified by a run.** The XML is well
formed and follows the format of the Dart plugin's own templates — two
contexts exist, `DART` and `DART_STATEMENT`, and these use `DART` because they
declare classes and members rather than statements — but whether IntelliJ
accepts the file is something only an import shows. If it refuses one, that is a
bug worth reporting.
