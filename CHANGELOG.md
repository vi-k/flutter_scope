## 0.9.6

* Upgrade logger_builder to 0.4.0.

## 0.9.5

* Replace ellipsis characters in log messages.

## 0.9.4

* Minor logging changes.

## 0.9.3

* Fix some bug on dispose `AsyncScopeElementBase`.

## 0.9.2

* Minor changes to `LiteScope.buildOnWaiting`.
* Add docs.

## 0.9.1

* Minor changes to the logging.

## 0.9.0

* Upgrade ansi_escape_codes to 3.0.2.
* [breaking changes] Upgrade logger_builder to 0.3.1.

## 0.8.1

* Upgrade ansi_escape_codes to 2.2.1.
* Upgrade logger_builder to 0.2.0.

## 0.8.0

* [breaking changes] change `pkglog` to `logger_builder`.
* change license to MIT.

## 0.7.5

* fix bug: `data` in `AsyncDataScope` may be `null`.
* fix bug: `unmount` in `AsyncDataScope` can be called before `data`
  initialization.

## 0.7.3-0.7.4

* add `onMount`/`onUnmount` calls to `AsyncScope` and `AsyncDataScope`.
* add `unmount` to `ScopeDependencies`, `ScopeDependency` and `DepHelper`.

## 0.7.1-0.7.2

* update logging
* minor changes

## 0.7.0

* [breaking changes] rename `ScopeQueueMixin` to `ScopeAutoDependencies` and
  refactor.
* [breaking changes] rename `waitBuilder` to `waitingBuilder`.
* minor: add package `pkglog` for logging.

## 0.6.3

* add timeouts for waiting for access (`scopeKey`) and waiting for children to
  complete (`AsyncScopeParent`, `waitForChildren`)
* set default timeouts to 3 seconds.
* add info logging (`ScopeLog.logInfo`) for important messages.

## 0.6.2

* add `AsyncScopeCoordinator` for coordination of scopes with the same key.
* minor fixes.

## 0.6.1

* add `asyncScopeRoot` to register scopes that do not have a parent, so that
  you can wait for them to complete.

## 0.6.0

* fix some bugs.
* add `buildOnClosing` for `Scope`.
* add more examples.
* add `AsyncScope`, `AsyncDataScope`, `LiteScope` with `LiteScopeState`.

## 0.5.0

* [breaking changes] refactor, rename.
* [breaking changes] `exclusiveCoordinator` transformed to `scopeKey`.
* parent scopes now depend on their children (`asyncInit`, `asyncDispose`).
* scope states can now also be initialized and disposed asynchronously
  (`asyncInit`, `asyncDispose`).

## 0.4.1

* update example's README.md.

## 0.4.0

* [breaking changes] add context to init.
* add `AsyncInitializer` and `AsyncState`.

## 0.3.3

* return `child` back. by default, it is not used, but you can use it yourself.

## 0.3.2

* add `ScopeDependenciesQueue` for sequiential async initialization and
  disposal from list of dependencies.

## 0.3.1

* fix a serious bug: the code is built using a Flutter fork. transfer to the
  official version.

## 0.3.0

* add `ScopeModel`, `ScopeNotifier`, `ScopeAsyncInitializer`,
  `ScopeStreamInitializer`.
* new `Scope`.
* remake scopo_demo
* add `LifyceycleCoordinator` for sequiential async initialization and
  disposal.

## 0.2.2+1

* breaking changes: rename `ListenableAspectBuilder` to `ListenableSelector`.
* breaking changes: rename `listenTo` to `select`.
* update docs.
* fix: `pauseAfterInitialization` to zero by default.

## 0.2.0-0.2.1

* breaking changes: remove context from `init`.

## 0.1.3

* implement `ScopeContent` from `Listenable`
* add utils for `Listenable`
* add minimal example.

## 0.1.2

* `yield ScopeReady` closes `init`
* add `ScopeConsumer`
* remove type for progress from `Scope` definition

## 0.1.1

* remove `wrap`
* add `wrapContent`

## 0.1.0

* scopo is ready for production
