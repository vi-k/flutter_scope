## 0.10.0

* Fix `ScopeModel.create(context)` running before the element was mounted: the
  context can now read ancestor scopes with `listen: false`, while the model
  and notifier subscriptions are still ready before the first subtree build.
  The same mounted-before-build timing now applies to custom
  `ScopeWidgetElementBase.init()` overrides. Synchronous initialization
  failures stay inside Flutter's build error boundary. Such a failure is
  terminal: the hook is not attempted again, so nothing it already took is
  taken a second time, and every later build reports the same failure.
  Cleanup is symmetrical with it — the element disposer runs for a failed
  initialization too, so whatever it took before it failed is given back, and
  family disposers now expect a partially initialized scope. `AsyncScope`
  starts its async phase only after a successful synchronous initialization,
  and only once; a scope that never got that far registers with no parent
  scope and its `close()` completes instead of waiting for an initialization
  that will never begin.
* Subscribing to another scope from an initialization hook — `listen: true`
  inside `init()` or `ScopeModel.create()` — is now caught by an assertion.
  The hook runs once, before the first build, so such a subscription could
  never be honoured; look the scope up with `listen: false` instead.
* Fix a dependency keeping what it had already taken. A dependency whose
  initializer acquired a resource and registered its disposer, and only then
  failed or was cancelled, was skipped by the disposal entirely: the criterion
  was the state it ended in rather than what it was holding. Whatever was taken
  is now released either way, once. A dependency in that position therefore
  reports `disposed` rather than `cancelled` when it carried no errors of its
  own.
* Fix one failing disposer taking the rest of a sequential group with it. The
  walk stopped at the first dependency that could not let go, leaving everything
  below it — already initialized, still holding resources — untouched. Each
  release is now guarded on its own, the walk finishes, and the first failure is
  passed upwards afterwards; every failure is recorded on the dependency it
  belongs to, as before.
* Fix an asynchronous `NavigationNode.onPop` being asked twice and answering
  too late. Two quick back presses started two questions, and two answers of
  `true` took two outer routes; an answer arriving after the route the node
  sits on had been closed by something else — or buried under a newer one —
  popped whatever was on top instead. The hook is now asked one press at a
  time, and an answer is acted on only while it still applies.
* A `NavigationNode` refuses a `navigatorKey` that changes. It is the key the
  nested navigator is built with, so another one would mean another navigator
  and an empty stack — which is why the node kept the first one and the new key
  simply never resolved. An assertion says so, and points at `Widget.key` and
  at the `GlobalKey()` written inside `build` that usually causes it.
* Fix a teardown held forever by an initialization that cannot be cancelled.
  Cancelling an `async*` means resuming its body and letting it run out, so a
  body parked on a future that never completes is never cancelled at all — and
  the teardown waited for that with no limit, never reaching the release behind
  it. The scope stayed registered with its parent and never gave its `scopeKey`
  back, so every later scope on that key queued behind an entry nobody would
  ever complete. The wait is now bounded by `initCancellationTimeout`, three
  seconds by default (`ScopeConfig.defaultInitCancellationTimeout`, `null` to
  wait indefinitely), with an `onInitCancellationTimeout` callback beside the
  two expiry callbacks the families already had. On expiry the initialization
  is left where it stands, the expiry is reported through
  `FlutterError.reportError`, and the teardown goes on to give back what the
  scope was holding. What the generator itself holds stays held: it waits on
  somebody else's future, and no scope can complete that one for it.
* `ScopeNotifier.value` takes a `tag`. It was the one constructor in the family
  without one, so a scope over a listenable somebody else owns had no name in
  the log — and that is exactly where two scopes of the same type stand side by
  side over two different models.
* [breaking changes] `State.dispose` is sealed on `LiteScopeState` and
  `ScopeState`. It belongs to Flutter and lands on either side of a scope's
  teardown depending on how the scope went, so nothing a scope has to let go of
  can be released on that schedule. Overriding it is now an analyzer warning
  that says so; the teardown goes in `onUnmount()` and `disposeAsync()`.
* [breaking changes] `ScopeDependencies.unmount` and `ScopeDependency.unmount`
  are now `onUnmount`, so that every hook a scope calls to drop what must stop
  reaching it goes by one name. The assignable callbacks keep the short verb
  they always had: `dep.unmount`, and `AsyncScope(unmount:)`.
* [breaking changes] The synchronous half of a teardown is now a step of the
  teardown rather than a tail of `Element.unmount`, and `LiteScopeState` /
  `ScopeState` gained `onUnmount()` to put it in. A scope leaves in one of two
  ways, and only one of them went through the framework: `close()`, which keeps
  the element mounted on purpose, skipped the synchronous half altogether — a
  dependency's `unmount` never ran, and by the time the element did leave the
  tree the asynchronous half had already released it, so nothing was left to
  drop the subscription from. `onUnmount` now runs exactly once, always before
  `disposeAsync`, whichever way the scope goes.

  `State.dispose` is not part of that order and cannot be: it belongs to
  Flutter, which calls it before the scope's teardown begins on removal, and
  not until the tree comes down after a `close()`. The synchronous half of a
  scope's teardown therefore belongs in `onUnmount()`. Scopes that only ever
  leave by removal are unaffected.
* [breaking changes] `AsyncScopeBase.onMount` and `AsyncDataScopeBase.onMount`
  now run before the initialization they are documented to precede. They ran
  from `Element.mount`, which is after the first build — so after the
  synchronous `init()` and after the asynchronous phase had started. They run
  from `init()` now, which is also where the rules of that hook apply: a
  failure is terminal, and subscribing to an ancestor scope with `listen: true`
  is rejected by an assertion.
* A scope now refuses to change between the constructor that owns its model and
  `.value`. Switching in place had no honest answer and both directions were
  silent: `.value` to owning dereferenced a `value` that is no longer there,
  and owning to `.value` kept the model the scope had made, ignored the one it
  was handed, and left nothing to ever release the first. An assertion refuses
  the rebuild and points at `Widget.key`.
* Fix `ScopeNotifier.value` keeping its listener on the model it was given
  before. The swap was decided by `==`, so two models that compare equal were
  taken for one: the listener stayed on the model the scope had let go of, and
  every notification of the new one was lost. Ownership of a subscription is
  now decided by identity.
* Fix `ListenableSelector` ignoring a new `selector` or `compare`. They were
  replaced only together with the `listenable`, so a parent that passed a new
  closure over the same source kept getting the previous one. Any of the three
  changing now re-subscribes.
* Fix `Listenable.select` leaving a listener behind when the selector fails on
  its first read. The first value was read after the listener was registered,
  so a failure there left the listener in place with no subscription handed
  back to take it away, and the next notification reached an unassigned `late`
  field. The first read now happens before the registration.
* `CompareUtils.identical` no longer recommends itself for `compare:`. A
  `compare:` answers "did it change?", so the one to pass for a value that is
  replaced rather than mutated is `notIdentical`; `identical` reports the
  opposite of what it is asked. The same correction lands in the dartdoc of
  `Listenable.select` and `ListenableSelector.compare`, and in `doc/j_utils.md`.
* Fix `AsyncDataScopeContext.data` handing out a `null` the scope never
  produced. For a nullable `T` the getter read the value itself as the answer to
  "is there one yet?", so before the initialization finished it returned `null`
  instead of throwing `StateError`. Readiness is now tracked apart from the
  value, and a legitimate `null` result still reads as `null`.
* Fix a selector staying registered after the widget stopped reading it. What a
  dependent selected was added to what it had selected in earlier builds, and
  the pile was only cleared once a change had already been found: a widget that
  moved from one value to another was still rebuilt by the one it had left.
  What a dependent selects now belongs to the build it selected in. The build
  boundary is the frame, so a dependent rebuilt twice within a single frame
  keeps both sets and pays at most one extra rebuild — the scope's own
  notification is not that case.
* Fix a failing cleanup hook taking the mandatory teardown with it. A scope
  hands control to code you wrote on its way out — `onUnmount`,
  `onWaitForChildrenTimeout`, the state's `disposeAsync`, a dependency's
  `unmount` — and a failure there used to abandon everything behind it: the
  scope stayed registered with its parent, its `scopeKey` was never released,
  its model was never disposed of, and its dependencies kept whatever they had
  taken. Every mandatory stage now runs whatever the hooks make of it, and the
  first failure is reported once the teardown is over. Two consequences worth
  knowing: an `unmount` that fails on one dependency no longer leaves its
  siblings mounted, and a scope whose disposal failed before the mandatory
  block now reports that failure after the block rather than instead of it.
* Fix `NavigationNode` system back handling: a pushed route or dialog in its
  nested navigator now closes before the enclosing route can pop. Once the node
  has nothing of its own left to close, `onPop` is asked exactly once and its
  refusal keeps the route; a back inside nested nodes reaches the innermost one
  and leaves every route above it alone. `Navigator.canPop` inside a node no
  longer counts the node's own forwarding bookkeeping as a route it can close.
* Fix a `NavigationNode` emptying itself. `Navigator.pop()` on the node's first
  page used to take that page away and leave the node with nothing to show: at
  once in a node marked `isRoot`, and from the second pop on in any other node,
  whose way outwards was a one-shot. A root node now keeps such a pop, and an
  ordinary node forwards it every time it is asked.
* [breaking changes] Raise the Flutter floor to 3.29.0. The declared `>=3.27.0`
  never resolved: `logger_builder` requires `meta ^1.16.0` while the
  `flutter_test` of 3.27 pins `meta` to 1.15.0, so `pub get` failed for anyone
  who took the constraint at its word. The suite is now run on 3.29.0 itself
  before a release. The Dart constraint stays `^3.6.0` — the code needs nothing
  newer, and raising it would switch `dart format` to the tall style and
  reformat the package for no gain.
* `meta` is no longer a dependency: nothing under `lib/` imports it. A single
  test utility does, so it is a dev dependency now.
* [breaking changes] An expired `waitForChildren` now drops the children it
  was awaiting, so `hasChildren` and `childrenCount` fall to zero for them.
  Children registered while the wait was already running are kept.
* The dartdoc of `ScopeConfig.defaultScopeKeysTimeout` and
  `defaultWaitForChildrenTimeout` was wrong: a zero duration expires
  immediately, it does not disable the timeout. Only `null` removes the limit.
  The behaviour is unchanged — anyone who set `Duration.zero` expecting the
  documented meaning has been running with instantly-expiring waits.
* [breaking changes] `AsyncScopeCoordinator` now owns the `scopeKey` queues of
  its own subtree instead of a process-wide map, and is what scopes without a
  parent scope register with. The global `asyncScopeRoot`, `AsyncScopeRoot`,
  `AsyncScopeCoordinatorEntry` and `ScopeChildEntry` are gone, and
  `AsyncScopeParent.waitForChildren` takes `timeout` and `onTimeout`.
  * Migration: `asyncScopeRoot.waitForChildren()` becomes
    `AsyncScopeCoordinator.waitForChildren(context, {timeout, onTimeout})`,
    which awaits the scopes registered with the nearest coordinator above
    `context`. `timeout` defaults to
    `ScopeConfig.defaultWaitForChildrenTimeout` and an expiry is reported
    through `FlutterError.reportError` unless `onTimeout` is given.
  * `AsyncScopeCoordinator.enter` is no longer public: the queues are entered
    by the scopes themselves and the entry types are internal.
  * `AsyncScopeParent.registerChild` is no longer public. It was a public
    member of a public mixin, so code that mixed `AsyncScopeParent` in and
    called or overrode `registerChild` no longer compiles; `hasChildren`,
    `childrenCount` and `waitForChildren` stay public.
  * **Silent behaviour change:** a scope with neither a parent scope nor an
    `AsyncScopeCoordinator` above it now registers nowhere, so nothing awaits
    its disposal — previously every such scope landed in the global
    `asyncScopeRoot`. Such code keeps compiling unchanged and behaves
    differently: if anything used to await those scopes, put an
    `AsyncScopeCoordinator` above them (the usual place is above
    `MaterialApp`) and await
    `AsyncScopeCoordinator.waitForChildren(context)`.
* Upgrade logger_builder to 0.5.0: logs are now published through
  `publishLog`, so `ScopeConfig.logger.transformer` can now rewrite or drop
  them. scopo's own API is unaffected, since `ScopeLogPublisher` and
  `ScopeLogFormatter` are unchanged in 0.5.0. Add the `ScopeLogTransformer`
  typedef and document it on the `debug` page.
* [breaking changes] Unify dependency path format: no leading `/` in
  `ScopeDependencyException.name`, `ScopeDependencyInfo.path` and progress
  paths; anonymous groups add no separator.
* [breaking changes] `ScopeAutoDependenciesProgress.name` is renamed to `path`,
  which is what it always held. `name` stays, and is now the name the
  dependency was declared with — the last segment of `path`.
  * **Silent behaviour change:** `progress.name` keeps compiling and starts
    reporting the leaf name instead of the whole path. A caption that is meant
    to show the whole path becomes `progress.path`.
* [breaking changes] Remove dead API: `LiteScopeInitState`/`Waiting`/
  `Progress`/`Ready`; rename `ScopeDependencyNoDisposalRequred` to
  `ScopeDependencyNoDisposalRequired`.
* Remove the internal, never-exported `typeToShortString` and the unused
  `Notifier` mixin with its `TestNotifier`.
* Fix infinite recursion in `CompareUtils.identical`.
* Fix hang in `ScopeAutoDependencies.dispose()` when no dependency requires
  disposal.
* Fix an abandoned disposal when the initialization raises while it is being
  cancelled: a generator that fails in its `finally` hands that failure to the
  `cancel()` the disposal awaits, and it used to leave the disposal right
  there — the scope never unregistered from its parent, which then waited out
  its whole `waitForChildrenTimeout` on a scope that was already gone, and
  never released its `scopeKey`. The failure is now reported through
  `FlutterError.reportError` and the disposal runs to its end.
* Fix a deadlock when an asynchronous initialization fails before it starts:
  `initAsync()` raising on the spot, or the missing-`AsyncScopeCoordinator`
  error of a scope with a `scopeKey`, left the scope waiting for its own
  initialization forever. It never unregistered from its parent, so the parent
  burned its whole `waitForChildrenTimeout` on a scope that was already gone,
  and neither of them was ever disposed of. The failure is still reported the
  same way, and a scope whose initialization never happened is still not
  disposed of. The same failure in `LiteScopeCoreState.initAsync()` no longer
  keeps `close()` waiting forever either.
* Fix a failure raised after `initAsync()` had already reached
  `AsyncScopeReady` crashing with `Bad state: Future already completed`
  instead of being reported: the stream's error handler completed the
  initialization completer a second time, and that crash replaced the failure
  it was handling, so the real error reached nobody. Such a failure is now
  reported through `FlutterError.reportError` (library `scopo`) and the scope
  stays ready — it is no longer flipped into `AsyncScopeError`, which would
  have replaced the widgets already on screen with `buildOnError` while
  `disposeAsync()` still ran. The `already initialized` diagnostic now checks
  whether the initialization succeeded instead of the applied model state, so
  a second `AsyncScopeReady` arriving before the post-frame callback that
  applies the first one no longer re-runs the whole ready branch.
* Fix a `scopeKey` held forever when `onScopeKeyTimeout()` throws: an expired
  wait lets the scope into the key anyway and then calls that hook, so by the
  time it ran the entry was already in the queue — and a failure there made
  the scope forget the entry, so its disposal never released the key. Every
  later scope on that key then waited for an entry nobody would ever
  complete, with no way out. The coordinator is now resolved before the entry
  is created, which is what the blanket handler existed for, and an attached
  entry is never dropped.
* Fix a scope running its whole initialization after its disposal had already
  begun: a scope with a `scopeKey` awaits the coordinator before it subscribes
  to `initAsync()`, and the disposal can only cancel an initialization through
  that subscription — so a disposal starting inside that window had nothing to
  cancel, and the `mounted` guard on the far side of the await says nothing
  about a `close()`, which keeps the element mounted on purpose. The scope
  went on to subscribe once the key was granted and to acquire resources it
  would never release, since a scope whose disposal has already passed the
  `disposeAsync()` decision does not run it. The initialization now also stops
  when the disposal has begun; the normal path is unchanged.
* Fix `close()` leaving an orphaned child entry behind: the post-frame
  callback that registers a scope with its parent was guarded by `mounted`
  alone, and `close()` keeps the element mounted on purpose. A disposal that
  finished before that callback fired handed the parent a fresh entry
  registered after the `finally` had unregistered the previous one, so the
  parent — or `AsyncScopeCoordinator.waitForChildren` — burned its whole
  timeout on a scope that was already gone. The callback is now guarded the
  same way its two siblings are.
* Fix moving a closed scope in the tree with a `GlobalKey` crashing: the
  disposal unregistered the entry it held with its parent but left the field
  pointing at it, and `activate()` re-registered unconditionally — so the move
  reached for an entry that was already gone. In debug that hit an assert; in
  release, where the assert is not there to stop it, it fell through to
  `Bad state: Future already completed`. The field is now cleared, a
  reactivation after disposal no longer registers at all, and
  `ChildEntry.unregister()` is idempotent.
* `scopeKey` is now documented and enforced as read exactly once, when the
  initialization starts: the answer it gives then — `null` included, which is
  an answer and not the absence of one — together with the
  `AsyncScopeCoordinator` above the scope, is binding until the scope has
  finished disposing of itself. A key that appears after a scope initialized
  without one, a key
  that is given up, a key that changes, and a scope moved with a `GlobalKey`
  under a different coordinator all used to be silent, and the mutual
  exclusion the key exists for quietly stopped working — an appearing key was
  never taken at all, so a second scope simply coexisted with the holder. All
  four are now reported in debug builds through an `assert`, each with a
  message that says what happened and what to do instead (give the widget a
  different `key`, so a new element reads the key afresh). Release builds are
  unaffected, and nothing is repaired: releasing a key and taking another one
  is asynchronous, and a rebuild is not. A scope that has finished disposing
  of itself holds nothing, so it is exempt: an element that outlives its own
  disposal — which is what `LiteScope.close()` leaves behind, still mounted so
  it can show a closing screen, and still movable with a `GlobalKey` — may be
  rebuilt and reparented freely. A key that changes while a `close()` is still
  in flight, with the entry still in its queue, is reported as before.
* Fix an expired `waitForChildren` forgetting the children registered after it
  started: the wait dropped the whole live registry instead of only the
  snapshot it was awaiting, so a scope that registered mid-wait — one the wait
  never awaited by design — was silently unregistered, and the next
  `waitForChildren()` returned at once while it was still disposing of itself.
  The children are now dropped even when the `onTimeout` reporter throws.
* `AsyncScopeParent.waitForChildren` now defaults `onTimeout` to reporting the
  `TimeoutException` through `FlutterError.reportError` (library `scopo`),
  prefixed with the parent's short description — the same default
  `AsyncScopeCoordinator.waitForChildren` already applied. Calling the mixin
  method directly on a scope element used to drop the children and complete
  with nothing reported at all.
* [breaking changes] A `ScopeDependency` that carries errors keeps them
  through its disposal instead of being overwritten with
  `ScopeDependencyDisposed`. A group is disposed of *because* something under
  it failed — `disposalRequired` covers `ScopeDependencyFailed` — so the
  disposal threw away the one record of what had failed, and with the default
  `autoDisposeOnError` that happened before the caller ever saw it. A failed
  *leaf* was never disposed of and so always kept its errors; the groups now
  behave the same way. `disposalRequired` no longer reads the state alone, so
  a group that stays `ScopeDependencyFailed` is not disposed of twice.
  * Migration: after disposing of a tree that failed, the root reports
    `isFailed == true` and `isDisposed == false`, where it used to report the
    opposite; `stateToString()` still names the children that failed.
* `ScopeAutoDependencies.init()` can be called again once the previous run has
  been disposed of: it rebuilds the tree instead of reusing the one the
  disposal left behind, which tripped an opaque `assert` inside the first
  dependency it reached. The tree is replaced on the next `init()` rather than
  dropped by `dispose()`, so the outcome of the run that is over stays
  readable through `flattenDependencies()`. A second `init()` on a tree that
  is *still alive* now fails with a `StateError` that says so, instead of
  silently abandoning everything the first run is holding.
* Fix `ScopeNotifier.value` not subscribing to a new listenable on update.
* Fix `LiteScope.close()` hang outside the Ready state; fix
  `ScreenshotReplacer` completing early and leaking `ui.Image`.
* Fix `LiteScope.close()` waiting forever on a screenshot that could never be
  taken: a `notifyDependents()` left pending asks the next rebuild to skip the
  subtree, so the widget `buildOnReady()` built for the closing frame — the
  one carrying the `ScreenshotReplacer` that releases the barrier — was thrown
  away by `updateChild`. `mounted && state is AsyncScopeReady`, which is what
  `close()` checks before installing the barrier, is necessary but not
  sufficient, and a scope closed in place stays mounted, so the `dispose()`
  fallback never ran either. The closing frame now rebuilds the subtree
  anyway; the pending notification is still delivered.
* Fix a double close() race in LiteScope orphaning the screenshot barrier;
  cap ScreenshotReplacer retries (new public ScreenshotReplacer.maxRetries).
* Fix concurrent `LiteScope.close()` callers disagreeing about a failed
  disposal: only the caller that started the run saw the error, while every
  other one — a second `close()`, or the implicit disposal on unmount — was
  told the very same run had succeeded. All of them now receive the same
  value, or the same error and stack trace.
* Fix the closing screenshot never being taken in release and profile builds:
  the `debugNeedsPaint` pre-check is now assert-gated, so it no longer throws
  a `LateInitializationError` on every `close()`.
* Guard the Ready-state model update against running after disposal has
  started (an element closed via close() stays mounted while its model is
  being disposed of).
* Base the disposeAsync() decision on successful initialization instead of
  the applied model state (resources are now disposed of when the element
  is removed in the init-completion frame).
* Guard AsyncScope post-frame callbacks with `mounted`.
* Log dependency disposal errors instead of swallowing them.
* Fix unbalanced parenthesis in `AsyncScopeError.toString()`.
* Add `repository`, `issue_tracker` and `topics` to pubspec.
* [breaking changes] Tighten the SDK constraints to Flutter `>=3.27.0` (was
  `>=1.17.0`) and Dart `^3.6.0` (was `^3.2.0`) — the floor the package
  actually requires, since it calls `Color.withValues`.
* Switch analysis to flutter_lints in the package and demo.
* Rewrite README; sync the pub.dev example; real `debug`/`Scope` doc pages.

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
