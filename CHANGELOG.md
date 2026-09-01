## 0.13.0

* **Breaking:** `ScopeState.disposeStateAsync` and `LiteScopeState.disposeStateAsync`
  now run after an `initStateAsync` that threw, in the same order as after one
  that succeeded. They used to be skipped, on the reasoning that a hook written
  about a finished thing does not run on one that never finished — but a failed
  initialization is not one that never happened. An initializer that opens a
  connection and throws on the next line has opened it, and nothing else is
  holding it: the scope never becomes ready, so its owner is never handed the
  state either, and this hook was the only release there was. **A disposer
  therefore has to expect a partially initialized state** — a field the `await`
  never reached is still unset when it runs. This is the rule
  `ScopeController.dispose` has always stated for the controller family. The
  `Scope` topic's table and its "what a failure of each leaves behind" section
  say the new answer; `disposeScope`, at the scope layer rather than the state
  one, is unchanged and still skipped, and deliberately so: what a scope whose
  `initScope` failed needs is a *partial* teardown, and which part that is can
  only be known inside the initializer that was doing the taking —
  `disposeScope` does the whole teardown of a finished scope and stays free of
  that question. The rule now stands on the page of every hook it governs: the
  three states that gather `initStateAsync` and `disposeStateAsync` into an
  overriding block each gave them a one-line doc of their own, and a doc comment
  on an override replaces the inherited text rather than adding to it — so the
  contract was on `LiteScopeCoreState`, the one class of the four nobody is told
  to extend. The `LiteScope` topic states it beside the teardown pair as well;
  the `Scope` topic already did.
* **Breaking:** `ScopeAutoDependencies.dispose()` and
  `ScopeDependency.dispose()` called while an `init()` of the same tree is
  still running are now refused with a `StateError` instead of going ahead.
  They used to walk a tree whose parked dependency had registered nothing yet,
  read it as one with nothing to release, mark it disposed of and report
  success — before the initialization had even reached `ScopeReady`. The
  disposer that dependency registered a moment later then hung on something
  every later walk skips, and the next `init()` — legal, because the tree now
  claimed its disposal had run to the end — built a new tree over one that was
  still holding. This was the last of the four
  concurrency diagonals left unguarded; the other three already refuse or join.
  A scope never reaches it, cancelling its subscription to `init()` first, so
  this is for whoever drives a container by hand — and the message says to do
  what the scope does. The guard stands on both doors because the tree has two:
  the container hands its tree out through `ScopeAutoDependencies.root`, and a
  walk started there — or on any node of a tree driven by hand — met nothing at
  all and lost the same dependency in the same way. Every node between that
  door and the parked leaf is initializing too, a group being one for as long
  as its children are, so the walk is refused wherever it was entered. The last
  way in is not a door but a side street: a group whose child was initialized
  *around* it carries no `_initializing` of its own, passes the guard, and used
  to write that child off as holding nothing for good. It no longer does — the
  walk still passes such a child by, because there is genuinely nothing to run
  for it, but the disposer it registers a moment later is reached by the walk
  that comes next. What the
  message says about the cancellation now depends on `autoDisposeOnError`: with
  the opt-out the cancellation unmounts and stops — keeping the half-built tree
  is the point of turning it off — so it sends the caller back for the
  `dispose()` afterwards instead of promising that cancelling is enough.
* Fixed: a change to an inherited widget the scope itself depends on — which is
  every `Theme.of(context)`, `MediaQuery.of(context)` or app-specific lookup
  made by the code that builds its subtree, the context there being the scope's
  own element — was lost when it landed in the same frame as a pending
  `notifyDependents()`. Such a change arrives as `didChangeDependencies()` and a
  bare `markNeedsBuild()` with no new widget, so the rebuild was taken for a
  notify-only one: the cached subtree was handed back and the change was gone
  for good, the framework having delivered it once. A page whose builder reads
  the theme could sit in the old one, indefinitely, while the rest of the app
  changed.
* **Breaking:** a dependency container no longer reports its disposal through
  `ScopeObserver.onProgress`. The release of each dependency arrives at the
  new `onDisposalProgress(target, path)` instead, so `onProgress` now means
  one thing — a step of an *initialization* is done — rather than two told
  apart by the type of a value. An existing `onProgress` override keeps
  compiling and simply stops hearing the disposal — which is the awkward part,
  since nothing points at the change. The three names added below are the one
  way this release can fail a build instead: a subclass that already has a
  member of its own called `onStepStarted`, `onDisposalStepStarted` or
  `onDisposalProgress` now declares an invalid override, Dart having no
  overloading. The `debug` topic has a "Coming from 0.12.x" section with the
  migration.
* Added `ScopeObserver.onStepStarted(target, path)`: a dependency container
  now announces each step of its initialization *before* running it, from
  inside the step and ahead of anything it awaits. Paired with the
  `onProgress` that follows, this makes a start that hung readable — the last
  path announced with nothing behind it is the step that never came back —
  including for a `concurrent` group, where the number of the last completed
  step says nothing about which of the steps in flight is stuck.
* Added `ScopeObserver.onDisposalStepStarted(target, path)`, the same mark for
  the teardown. Sent only for a dependency that has a release to run, so an
  entry with no `onDisposalProgress` behind it always means a release that did
  not come back — it hung, or it threw, and an `onError` beside it tells those
  two apart.
* `onDisposalProgress` is now sent by the container itself, when the disposer
  has returned, rather than from the stream of the disposal walk. The pair
  therefore holds however the walk was started — by the container, by a caller
  walking the tree by hand, or by a container that only joined a walk already
  running — and it survives a walk cancelled while a disposer was parked. It
  used to reach only whoever was reading the stream, so an observer watching a
  container whose tree someone else disposed of saw every step enter and none
  come back. A dependency of your own making is unaffected: its release is
  announced for it, by the group above it or by the container.
* `ScopeObserver.onError` for a failed release is now sent by the container the
  same way, and arrives right behind the entry it ends rather than at the end
  of the walk. A disposal driven by hand used to deliver the failure only to
  whoever was driving, so an observer that had already heard the entry — sent
  on the container's behalf whoever drives — was left with an unmatched entry
  and nothing to say it had failed, which is exactly what a hung release looks
  like. The error names the dependency as it always did.
* Fixed: a `ScopeDependency` of your own making whose `dispose()` or `init()`
  throws *before* it returns its stream — which the interface allows, and the
  package's own dependencies cannot do, both of their walks being `async*`
  bodies that do not run until they are listened to — no longer leaves the
  channel every other failure travels. As the root of a container, such a throw
  used to leave through the future `dispose()` hands its caller: the observer
  had heard the entry and then heard neither the failure nor `onDisposed`, and
  the promise that this walk never re-throws was not kept. As an arm of a
  `concurrent` group it was quieter and worse — the group asks its arms for
  their streams from inside the merge they are collected into, where a throw
  is told to nobody and closes nothing, so the walk stopped for good with no
  error, no exit and no end, on the way in as on the way out. Both now answer
  as a stream that fails after its first event does; a `sequential` group
  always did. The same holds for a throw from the dependency's `state` getter:
  a concurrent group filters its branches by `initializationRequired`, which
  reads `state`, and it does so inside that same merge — so the whole of what
  the group asks a foreign branch before running it is answered as an error
  now, rather than stopping the walk in silence.
* Fixed: a `close()` the framework refused used to stop the scope from ever
  being disposed of. `close()` asks for a rebuild before it releases anything,
  and `markNeedsBuild()` is refused outright while a build is running or while
  the tree is locked — which is where a `close()` from the build of a
  descendant, or from the `dispose()` of a neighbouring `State`, makes it. That
  refusal was sealed into the one future the scope hands every caller of its
  teardown, so the disposal on the way out of the tree joined it too and
  nothing ran: not `disposeScope`, not the cancellation of `initScope`, not
  `disposeStateAsync`, not the release of the `scopeKey` or of the place with
  the parent. The call is still refused and the caller still hears about it —
  it is a mistake, and in a release build it goes through, the assertion being
  a debug one — but the refusal is now answered once instead of for good.
* `ScopeObserver.onError` for the failed release of a root of your own making
  now names it — a `ScopeDependencyException` carrying the dependency's name,
  the shape the other two senders of that hook already used — instead of
  handing the error over bare. All three places a disposal failure is announced
  from therefore say which dependency failed.
* `ScopePrintObserver` writes the three new events as `initialize <path>…`,
  `dispose <path>…` and `disposed <path>`. The last of those replaces the
  `progress: <path>` line a release used to print, so anything that reads its
  output as text sees a changed format, not only added lines.
* Fixed: a disposal walk stopped halfway went on to mark itself finished
  unless the tree was in `ScopeDependencyInitialized`. A tree in
  `ScopeDependencyFailed` or `ScopeDependencyCancelled` — one led by hand
  after an initialization went wrong — and a second `dispose()` that was
  itself cancelled therefore stopped asking to be disposed of, and everything
  the walk had not reached was left holding what it took.
* **Breaking:** a second `ScopeAutoDependencies.init()` on a container that
  has been initialized and not disposed of is now refused whether or not its
  tree is holding anything. The guard used to ask whether anything was still
  held, and a tree whose dependencies registered no disposer answers no to
  that from the moment it is built — so such a container could be initialized
  again with no `dispose()` anywhere in sight, and the second run assigned its
  `late final` fields a second time. That came out as a
  `LateInitializationError` from inside a dependency's initializer, reading as
  a mistake in the caller's code rather than as the refusal it should have
  been. A container is still re-initializable after a disposal that ran to its
  end; the `Scope` topic now says what `late final` costs there.
* Added `ScopeDependencyException.hint`: something the package knows about a
  failure that the error itself does not say. A container sets one for exactly
  one case today — the second run over a `late final` field an earlier run
  assigned. What came out of that was a bare `LateInitializationError` from
  inside an initializer, naming the dependency and nothing else, and it read
  as a mistake in the caller's own code rather than as the consequence of
  running the container twice. The hint names the reason and the way out. It
  is printed by `toString()` on a line of its own, so anything that reads that
  text as a format sees one extra line in this one case.
* Fixed: a second `ScopeDependency.dispose()` arriving while the first was
  still running started a walk of its own, and in a `sequential` group that
  broke the reverse order the group promises. The child the running walk was
  parked in had already had its hook taken off, so the second walk read it as
  having nothing to do and moved on to the child below — the one the parked
  disposer is built on top of. It also reported itself finished while the
  first was still holding. A second call now joins the walk already running:
  it yields no paths of its own, closes when that walk closes, and raises what
  it raised. A walk stopped halfway is not a walk that finished, so a joiner
  over one of those is not told the disposal is over: it walks the tree
  itself, being a caller who asked for exactly that.
* Fixed: a tree built and then let go of without ever being initialized left
  its root saying `ScopeDependencyDisposed` while every child under it
  correctly said `ScopeDependencyInitial`, so a `flattenDependencies()` dump
  of it contradicted itself. Such a tree can be initialized afterwards, and
  `init()` now takes back the note the disposal walk left — without that, the
  tree came up already marked as disposed of and the next teardown walked
  past everything the initializer had taken.
* Fixed: a `ScopeNotifier` whose first value refused the listener — one already
  disposed of, or any `Listenable` of your own that says no — went on moving
  the subscription to every later value, while the teardown went on asking
  whether the initialization had ever subscribed. The listener was left behind
  on a live notifier with nothing able to remove it, and its next notification
  reached an element that no longer exists. Such an element shows the
  `ErrorWidget` from then on and for good, so it now subscribes to nothing.
* Fixed: `Listenable.select` counted a listener that threw as having received
  the value, so the next notification carrying that same value was filtered out
  as "no change" and the listener was never told at all. The listener most
  likely to throw is a `setState` from inside somebody else's build, which
  raises in debug and does nothing in release — the two builds disagreed about
  what the widget showed from then on. The value is taken back when the
  listener fails, and the next notification is a change again.
* Fixed: `Listenable.select` took the value back over a delivery that had
  already succeeded. A listener is free to notify again from inside its own
  call, and the nested delivery hands a newer value over before the outer one
  comes back — so an outer listener that then threw rolled in the value it had
  started from, over the top of one the listener had received. The subscription
  said one thing and the model another, and the next notification carrying the
  newer value was filtered out as already delivered. The value is now put back
  only when nothing got through while the failing listener was running.
* Fixed: `StateAsNotifier.addListener` built a fresh notifier when it was
  called from the tail of its own `State.dispose()` — `mounted` stays true for
  the whole of that call, so the guard was open while the mixin had already
  let its notifier go. Nothing disposes of that one and nothing ever notifies
  it. The mixin now knows it is going.
* Fixed: `CompositeListenableSubscription.cancel()` stopped where a member
  refused to be cancelled, leaving every member behind it still listening —
  which is the leak the composite exists to prevent. It now cancels them all,
  raises the first failure and reports the rest. `removeListener` on a
  `ChangeNotifier` cannot throw, so this is for a `Listenable` of your own.
* Fixed: `notifyDependents()` arriving after the scope has left the tree threw
  the framework's bare assertion about a defunct element — from a subscription
  not taken off in `onUnmount`, or from a teardown of yours reporting as it
  goes. A report with nobody left to hear it is dropped, which is the rule the
  rest of the package already followed.
* Fixed: a `LiteScope` whose `buildOnWaiting()` returns `null` without a
  `buildOnProgress()` to fall back on used to be told that it "overrides
  `initScope()` but not `buildOnProgress()`" — two statements that may both be
  untrue of it, and neither of them the branch it is missing. The message now
  names both branches and what `null` there means.
* Fixed: a teardown that failed while a `close()` was waiting for its
  screenshot was announced twice — once to the caller of `close()`, and once
  more through the report that exists for a walk with nobody waiting for it.
* Added, in debug: `AsyncControllerScope` and `AsyncControllerScopeBase` refuse
  a `createController` that hands over a controller which has already been
  through the family. `performInit` on one of those is a documented no-op, so
  the ready branch used to go up over a controller that was not running, with
  nothing anywhere saying so. Cached and reused instances are what this
  catches; the assertion costs nothing in release.
* `Listenable.select` no longer calls a listener after its subscription has
  been cancelled, for a `Listenable` that dispatches over a copy of its list.
* The refusal `CompositeListenableSubscription` raises when something is added
  after `cancel()` now names `cancel()` — the call that ended the composite —
  rather than `add()`, the call being refused.
* `ScopeDependency.isDisposed` says in its dartdoc what it actually answers:
  which state the dependency stands in, not whether the teardown has run. A
  dependency that failed keeps `ScopeDependencyFailed` through its own
  disposal, because the error list lives in the state, so a tree released by
  `autoDisposeOnError` holds nothing and still answers `false`.
  `disposalRequired` is the one that says there is nothing left to release.
* `AsyncDataScopeBase.onUnmount` no longer promises a call "on the way out of a
  `close()`": that family has no `close()`.

## 0.12.0

* Added `controllerDep(name, create)`, a fourth `ScopeAutoDependencies`
  builder next to `dep`/`sequential`/`concurrent`: a single dependency backed
  by a `ScopeController`, wired to `performInit`/`performUnmount`/
  `performDispose`. The same controller class an `AsyncControllerScope` owns
  now fits, unchanged, as one branch of a dependency tree.

## 0.11.0

* **Breaking:** `NavigationNode`, `NodeNavigatorState` and
  `PreviousNavigatorExtension` have left this package. They are the
  [navigation_node](https://pub.dev/packages/navigation_node) package now — the
  same code, the same behaviour, the same six lessons of an example. Add the
  dependency and change one import:

  ```dart
  import 'package:navigation_node/navigation_node.dart';
  ```

  Nothing in scopo used the widget, and the widget used nothing in scopo — it
  imports nothing but Flutter — so a package about scopes was carrying a nested
  navigator that nobody looking for one would think to find there. The two
  still go together: a scope over a screen is exactly what a pushed route
  loses, and a node is what keeps it.
* Added an accessor object per family — `ScopeAccess`, `LiteScopeAccess`,
  `ScopeWidgetAccess`, `ScopeModelAccess`, `ScopeNotifierAccess`,
  `AsyncScopeAccess`, `AsyncDataScopeAccess`, `AsyncControllerScopeAccess`.
  Each takes the type arguments of its family once and forwards to the statics
  of the same names, so the five wrappers a scope used to declare become one
  line: `static const access = ScopeAccess<App, AppDependencies, AppState>();`.
  Nothing is deprecated by it — the statics stay, and a scope that wants
  accessors under its own names still writes them. New section in `README.md`
  and in the topic `base`.
* `@mustCallSuper` removed from `onUnmount` of a scope state. It was empty
  there and in every class between it and the one an application extends, so
  `super.onUnmount()` did nothing and never had — while `disposeStateAsync`
  beside it, the other half of the same teardown and just as empty, asked for
  nothing. The two halves now read alike. On an *element* the hook does carry
  work — `ScopeElementBase.onUnmount` disposes of the dependency container —
  and there the annotation stays. Nothing to change on the consuming side: a
  `super` call that is no longer required is still allowed.

* Editor templates now ship with the package: `ide/scopo.code-snippets` for VS
  Code (and Cursor, Windsurf, Antigravity) and `ide/scopo-live-templates.xml`
  for IntelliJ and Android Studio. Eleven templates — a class skeleton per
  family, two containers, and the accessor line; each writes every class its
  shape needs in one paste. The skeletons write
  the accessors out as statics of the scope, which is the shape to prefer when
  something else is doing the typing; `ScopeAccess` is the shape to prefer when
  you are. Installation is in
  `ide/README.md`. The skeletons they insert are expanded into
  `test/ide/`, a file each, and compiled by the gate, so a template that stops
  being valid Dart fails the build.

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
* Fix a scope left with no subtree when its own build notified its dependents.
  A `builder` that touches the model synchronously — a lazy load, a default
  filled in on first read — notifies while the scope is building, and the flag
  that notification raises was read by the rebuild already in progress: the
  subtree was treated as one to keep rather than one to mount, and there was
  none to keep. In debug this surfaced as two framework assertions naming
  neither the scope nor the cause; in release the subtree was simply absent.
  The flag a notification raises and the flag the current rebuild reads are
  now separate, so a notification can no longer reach into the rebuild that is
  running. Such a notification is also no longer lost: marking an element that
  is already building as needing a build does nothing, so the rebuild is asked
  for once the frame is over, and the dependents hear about the change a frame
  later instead of never.
* **Behaviour change:** `dep.unmount` now runs in reverse declaration order
  within a group, the way `dep.dispose` already did. The two are halves of one
  teardown, and reverse order exists because a later dependency is built on top
  of an earlier one — so having the synchronous half walk forward released the
  foundation first. In `sequential('', [dep('bus'), dep('repo')])`, where
  `repo` listens to `bus`, the bus was unmounted first and the repository was
  left listening to a source that had already been told to stop. The order was
  not documented before and is now, in the dartdoc of `sequential`,
  `concurrent` and `ScopeDependencyHandle.unmount`, and in the `Scope` topic.
* Fix `unmount` being skipped for a dependency whose scope failed to
  initialize, while `dispose` ran. The hook is documented to run exactly once
  and always before `dispose`, whichever way the scope goes, but the container
  reached the element only once initialization had succeeded — so on the
  failing path nothing unmounted, and a dependency that had registered
  `unmount = subscription.cancel` alongside `dispose = sink.close` closed the
  sink and kept writing into it. The container now unmounts itself from inside
  its own initialization when that initialization did not finish, whether or
  not `autoDisposeOnError` is set: a container kept for inspection still holds
  the subscriptions it took. A hook that throws there is reported rather than
  re-thrown, so it cannot replace the failure the initialization is already
  carrying. `unmount` is also exactly-once by construction now — each hook is
  taken off as it runs — so the passes that can reach a container cannot
  double up on it.
* Fix one failing disposer taking the rest of a sequential group with it. The
  walk stopped at the first dependency that could not let go, leaving everything
  below it — already initialized, still holding resources — untouched. Each
  release is now guarded on its own, the walk finishes, and the first failure is
  passed upwards afterwards; every failure is recorded on the dependency it
  belongs to, as before.
* Fix an initialization that fails synchronously leaving the scope on its
  loading branch for good. `AsyncScopeError` was reached only from the
  stream's own failures, so a throw raised while the stream was still being
  built — the `AsyncScopeCoordinator` lookup of a scope that asks for a
  `scopeKey` and has no coordinator above it, or an `initScope` that is not a
  generator and throws — never reached the model: the scope stayed in
  `AsyncScopeWaiting` and went on showing `buildOnProgress`, which for a
  missing coordinator is the commonest mistake in the tree. It now shows
  `buildOnError`, as the state table always said it would, and the failure is
  still reported as before. The state is applied outside the frame, because
  such a failure is raised before the first `await` and therefore inside the
  build that started the initialization.
* Subscribing to a scope from anywhere but a build — `select` or
  `of(listen: true)` in `didChangeDependencies`, say — is caught by an
  assertion. What a dependent asked for is remembered per build, and the
  boundary between builds is taken from the frame, so a registration made
  outside a build belonged to whichever build shared its frame and was dropped
  by the first one that did not: it looked like it worked, and then stopped,
  on the first rebuild that came from the parent rather than from a change.
  Keep the subscription in `build`, and read with `listen: false` from
  `didChangeDependencies` when the point is to react rather than to show.
* `Progress.value` is a fraction between 0 and 1 whatever it was built
  from, which is what a progress indicator is handed. A task of no steps at all
  used to give the `NaN` of `0 / 0`, and a release build that stepped past the
  total gave `4/3`; the first is now 1 and the second is clamped. `Progress`
  also refuses a negative `number` or `total` by assertion, and the assertion
  in `ProgressIterator.addSteps` says `total` where it used to say `count`. The
  dartdoc example of `ProgressIterator` compiles again: it showed a named
  `count:` argument the constructor never had, and a `ProgressValue` type that
  does not exist.
* `StateAsNotifier` lets go of its notifier in `dispose` instead of merely
  disposing of it, and takes no listener after the state is gone. A callback
  that outlived the state — a stream event, a timer — used to reach a disposed
  `ChangeNotifier`, which answers with "A ChangeNotifier was used after being
  disposed" in debug; a late `addListener` was worse, since in release the
  listener was then held for good by a notifier nobody would ever notify.
* `SchedulerBinding.isBuilding` also sees a build that runs with no frame in
  progress — which is how `runApp` builds the first tree. `markNeedsBuild` from
  inside one of those is refused just as it is inside a frame, so
  `runOutsideFrame` now holds the action back there too. The build owner keeps
  that flag behind an assertion, so in a release build the scheduler phase is
  still all there is to go by.
* Fix `SchedulerBinding.isBuilding` answering differently in release, and
  `runOutsideFrame` running an action inside the build it was keeping it out
  of. The build owner's flag exists only inside an `assert`, so a release build
  had the frame phase alone to go by, and a build driven with no frame in
  progress — the way `runApp` builds the first tree — looked there like no
  build at all. Marking an element dirty from inside a build is refused in
  silence, so an `AsyncScope` whose initialization failed before its first
  `await` showed an empty subtree in release where debug showed `buildOnError`.
  The scopes of this package now count their own rebuilds in a plain field,
  which release builds keep, and `isBuilding` reads it. What remains beyond
  reach is a build that belongs neither to a frame nor to this package; the
  `utils` topic says so.
* A `NavigationNode.onPop` that returns a failing `Future` — a confirmation
  dialog that raised, usually — is reported through `FlutterError.reportError`
  instead of surfacing as an unhandled zone error far from the widget that
  caused it. The press is simply not acted on, and the next one is asked as
  usual. **What the answer sets off is now held the same way.** Acting on a
  `true` means asking the route what a pop there would do and then popping, and
  both read user code — a guard of the application's own, a callback the route
  makes as it goes. A failure in either was left in a chain nobody holds,
  because the previous fix answered for the question and not for what followed
  it. A node also no longer stays stood aside when that reading falls over: it
  steps aside for the length of one read, and a raise in the middle of it used
  to leave it aside for good, after which every later press took the whole route
  without the node being asked at all.
* `NavigationNode` hands its nested navigator the same page list across a
  rebuild that changes nothing. `NavigatorState` compares the list it is given
  by identity, so a fresh one on every build had it diff its stack and report it
  again — twice per rebuild, to every listener above the node — for a page that
  had not changed. While `child` and `isRoot` are the same objects, nothing is
  handed over anew.
* [breaking changes] The Flutter floor is `>=3.27.0`, down from the `>=3.29.0`
  raised earlier in this same release. Nothing here ever needed 3.29 — the floor
  went up because `logger_builder`, then a dependency, asked for `meta ^1.16.0`
  while the `flutter_test` of 3.27 pins `meta` to 1.15.0. Its 0.6.1 relaxed that
  to `^1.15.0`, which is what let the floor back down; later in this same
  release the dependency goes away altogether, so nothing external is left to
  push the floor up again. `fake_async` and `leak_tracker_flutter_testing` are
  asked for a patch lower, `^1.3.1` and `^3.0.8`, the versions 3.27 pins; both
  are dev dependencies, so nothing a consumer resolves changed except the floor
  itself. `sdk: ^3.6.0` is untouched and now reaches something real:
  3.27.0 carries exactly Dart 3.6.0, so the language version the formatter reads
  is the floor's own and not one above it. Tests, formatter, dartdoc, publish dry
  run, translations and both example suites are run on 3.27.0, and CI pins the
  same number.
* [breaking changes] Renames, the first of several waves. Nothing here changes
  behaviour: each is a name that said the wrong thing or said it differently
  from its neighbour. `ScopeConfig.defaultScopeKeysTimeout` is
  `defaultScopeKeyTimeout`, singular like the `scopeKey` and `scopeKeyTimeout`
  it answers for and like the three settings beside it. The three sealed bases
  of the dependency states drop a plural that described the hierarchy rather
  than the object: `ScopeDependencySuccessStates`, `ScopeDependencyFailedStates`
  and `ScopeDependencyCancelledStates` are `ScopeDependencyAnySuccess`,
  `ScopeDependencyAnyFailed` and `ScopeDependencyAnyCancelled`, which is how
  they read at a call site — `state is ScopeDependencyAnyFailed`. `DepHelper` is
  `ScopeDependencyHandle` and has a file of its own: everything else in that
  family spells `Dependency` out, and "Helper" said nothing about the handle it
  is. `ScopeInitFunction` is `ScopeInitCallback`, `Callback` being the one
  suffix this package uses for the idea, and `ScopeInitBuilder` is
  `ScopeProgressBuilder` after the state it builds for.
  `Progress.progress` is `Progress.value` — a fraction inside a class already
  called `Progress` explained itself worse than the pair `number`/`total` beside
  it — and `ScopeAutoDependenciesProgress.progress` follows it.
  `ProgressIterator.add` is `addSteps`, the word `nextStep` and `currentStep`
  already use.
* [breaking changes] The branch built while a scope initializes is named after
  the state it belongs to, in both halves of the API: the parameter
  `initBuilder` is `progressBuilder` and the method `buildOnInitializing` is
  `buildOnProgress`, in every family. `init` and `initBuilder` sat in one
  constructor and read as a pair -- the work and its builder -- while the second
  is the screen shown *while* the first runs; the state it answers is
  `AsyncScopeProgress`, and so now is its name. `buildOnWaiting` and
  `buildOnReady` already worked that way. The entries above that named the old
  spelling were rewritten to the new one: 0.10.0 has not shipped, so the section
  speaks the vocabulary the release will have. Released sections are untouched.
* [breaking changes] The lifecycle hooks say what they initialize and what they
  release, on both levels, because one name meant two things: `initAsync` was
  the scope's own initialization on `AsyncScopeBase` and the state's own on
  `LiteScopeState`, and `disposeAsync` was both teardowns at once. The scope's
  half is `initScope` and `disposeScope` — `LiteScope.init()` joins them under
  the first name — and the state's half is `initStateAsync` and
  `disposeStateAsync`, where `Async` still earns its place beside Flutter's
  synchronous `initState`. `onUnmount` keeps its prefix on both: it is called
  when the scope goes, and it is not what takes it away. `initData`,
  `disposeData`, `initDependencies` and `createController` are unchanged — they
  already named what they prepare. The timeout that bounds the scope's teardown
  follows the method: `disposeAsyncTimeout` is `disposeScopeTimeout`,
  `onDisposeAsyncTimeout` is `onDisposeScopeTimeout`, and
  `ScopeConfig.defaultDisposeAsyncTimeout` is `defaultDisposeScopeTimeout`.
  `initCancellationTimeout` is untouched: it is named after an event rather than
  after a method.
* [breaking changes] A parameter of `AsyncScope`, `AsyncDataScope` or
  `AsyncControllerScope` now carries the name of the method it stands in for:
  `onMount`, `initScope`/`initData`, `onUnmount`, `disposeScope`/`disposeData`,
  `createController`. The builders keep the shape they had — `waitingBuilder`,
  `progressBuilder`, `errorBuilder`, `builder` — beside `buildOnWaiting`,
  `buildOnProgress`, `buildOnError` and `buildOnReady`. **The callbacks are
  constructor parameters only now**: a field cannot share a name with the method
  it implements, so each is held in a private field. Nothing in this package,
  its tests or its examples read them from outside, and the analyzer says so at
  once for anyone who did.
* [breaking changes] `ScopeDependency` stops offering two ways to run one step.
  The interface had `init()` beside `runInit()` and `dispose()` beside
  `runDispose()`, the second of each wrapping the first and keeping `state` in
  step; the bare pair was an implementation detail with the shorter, more
  inviting name. The wrappers are `init()` and `dispose()` now — the names a
  caller expects — and the step itself is private to the library. Nothing
  outside called the bare pair, here or in the tests.
* A scope owning a controller has a context of its own. `of`, `maybeOf` and
  `select` of `AsyncControllerScope` and `AsyncControllerScopeBase` return an
  `AsyncControllerScopeContext`, which answers `controller`, `controllerOrNull`
  and `hasController` — the controller used to be read as `data` off an
  `AsyncDataScopeContext`, a type named after another family and a member named
  after a payload. This is an addition: the new interface implements the old
  one, so `data`, `dataOrNull` and `hasData` still answer the same object.
* [breaking changes] `ScopeStateNotifier.equals` is `shouldNotify`, **and its
  sense is inverted**: it returns `true` by default, where `equals` returned
  `false`, and `update` notifies when it says so rather than when it does not.
  The old name promised a comparison and denied every equality — including an
  object with itself — while what it decides is whether the listeners hear
  about a change; `CompareUtils.equals` beside it is the honest one. An
  override written with `@override` stops compiling, which is the point; one
  written without it does not, so check for it before upgrading.
* The dartdoc of `AsyncControllerScopeBase` says why its `buildOnProgress` and
  `buildOnError` take no progress where the other three families do: this
  scope's initialization is `createController()` and the controller's own
  `init()`, and neither reports steps. The reason was a comment in the
  implementation, where the person reading the signature never sees it.
* Add `ScopeConfig.observer`: an application assigns a typed `ScopeObserver` to
  hear about a scope's lifecycle. Nine hooks, every one of them empty by
  default — `onInit`, `onProgress`, `onReady`, `onCancelled`, `onDispose`,
  `onDisposed`, `onError`, `onTimeout` and `onTrace` — so a subclass overrides
  only what it needs; the first argument of each is a `ScopeObservable`,
  carrying the `debugLabel` its source names itself by. The field is `null` by
  default, so the package says nothing until one is assigned. The structural
  pair `onInit`/`onDisposed` lives on `ScopeWidgetElementBase` — the ancestor of
  every scope family — so a family that never reported anything of its own
  now reports through the observer the same as the rest. A hook that throws is
  reported through `FlutterError.reportError` rather than reaching the scope,
  and a nested notification — an observer producing a scope event of its own
  from inside a hook — is refused rather than left to recurse.
* `AsyncScope`'s own lifecycle now reports through `ScopeConfig.observer` too
  — and with it every family built on the same element: `AsyncDataScope`,
  `AsyncControllerScope`, `LiteScope` and `Scope`. `onProgress`, `onReady`,
  `onCancelled`, `onDispose`, `onTimeout` for an expired wait, and `onError`
  for each phase that can fail (initialization, its cancellation, preparation
  for disposal, `onUnmount`, disposal, a wait nobody was left to hear the end
  of). A family that runs its own initialization reports it in place of the
  structural pair `ScopeWidgetElementBase` fires for the rest, rather than
  alongside it — `ScopeWidgetElementBase.reportsOwnLifecycle`, `false` by
  default, `true` on `AsyncScopeElementBase` — so `onInit`/`onDisposed` are not
  doubled for `LiteScope` and `Scope`, whose default `initScope()` runs the
  exact stream `AsyncScope`'s does. The coordination below the lifecycle — the
  `scopeKey` queue, cancelling an initialization, waiting for children —
  reports through `onTrace`.
* The dependency container and a single dependency now report through
  `ScopeConfig.observer` too, the same eleven points that used to log:
  `ScopeAutoDependencies` reports `onInit`, `onProgress` (a
  `ScopeAutoDependenciesProgress` while it initializes, the bare path of each
  step while it disposes), `onReady` or `onCancelled`, `onDispose`,
  `onDisposed`, and `onError` for each phase that can fail here — `onUnmount`,
  an abandoned wait for its own disposal, and disposal itself — plus
  `onTimeout` for that same abandoned wait giving up. Its `debugLabel` is
  `T(#hash)`, the shape its `logger` name already had; a single dependency's is
  its own `name`. The two diagnostic lines inside `ScopeDependencyMixin` —
  handling an error, handling one after a cancellation — report through
  `onTrace` instead, the error folded into the message rather than kept as a
  separate field. `runStreamGuarded`, which every dependency's `init()` and
  `dispose()` run through, is internal and not exported — it has no
  `ScopeObservable` of its own either, being a function rather than an object
  — so it gained an optional `observable` parameter: its two callers inside
  the package pass their own, and its seven internal steps report through
  `onTrace` under that label.
* **Breaking:** `logger_builder` is no longer a dependency. Nine public names
  built on it are gone: `ScopeConfig.logger`, `ScopeLogger`, `ScopeLevelLogger`,
  `ScopeLog`, `ScopeLogPublisher`, `ScopeLogFormatter`, `ScopeLogTransformer`,
  `ScopeLogLevel` and `ScopeLogCallback`. In their place, a ready-made
  `ScopePrintObserver`: `ScopeConfig.observer = const ScopePrintObserver();`
  prints one line per event — `scopo | <label> | <what happened>`, a failure's
  error and stack trace included — the same shape `ScopeLogger.defaultFormat`
  wrote, minus the level and the logger path. A failure line spells out its
  phase as English instead of the bare `ScopePhase` name — `preparation for
  disposal failed`, not `preparationForDisposal failed` — the same wording
  `ScopeLogger.defaultFormat` used for the same six phases; the one phrase
  that does not end in "failed", `an abandoned wait ended in a failure`, is
  the old logger's `an abandoned wait for $what ended in a failure` with the
  `$what` left out, since the observer has none to put there. `trace: true`
  also prints what `onTrace` carries, off by default: that is where the
  coordination below the lifecycle reports, and a scope produces a dozen such
  lines where it produces one of the rest.
* Fix a failure that outlives its scope reaching `ScopeConfig.observer` as a
  failure of the observer. A bounded wait that expired is abandoned rather
  than forgotten, and the work behind it reports through `onError` with
  `ScopePhase.abandonedWait` if it falls over later — by which time the scope
  has given its widget back, so reading `target.debugLabel` raised a
  `TypeError` inside the hook and the guard reported *that* instead. The
  teardown now keeps the label it had while it still had a widget, so the
  three calls that can reach a consumer after it is over — the scope's own
  `disposeScope`, the cancellation of its initialization, and an
  `AsyncControllerScope` giving back a controller — deliver the failure they
  were written to deliver.
* **Behaviour change:** `ScopeObserver.onDispose` and
  `ScopeObserver.onDisposed` now always come as a pair. `onDispose` is sent by
  every teardown, not only by one that follows a successful initialization, so
  a scope taken down while it was still loading no longer reports the end of a
  teardown nobody was told had begun; and `onDisposed` is sent even when the
  teardown failed, after the `onError` that says so rather than instead of it.
  Separately each half was defensible; together they made the pair unreliable
  in both directions, and a consumer that counts with it — a leak counter, a
  span tracker — got it wrong either way. `onCancelled` is documented as what
  it is: a scope cancelled while still queued for its `scopeKey` sends it
  without any `onInit` before it, because it never started an initialization
  of its own. The structural pair joins the same guarantee: a family with no
  initialization phase of its own — `ScopeWidget`, `ScopeModel`,
  `ScopeNotifier`, `AsyncScopeCoordinator` — used to send `onDisposed` alone,
  with no `onDispose` before it. It now sends both, and only for an element
  whose `init()` actually succeeded: one that threw, or never ran, reports
  neither half — the opposite of the phase-reporting families above, where the
  pair can still close a teardown that opened with no `onInit` at all.
* Fix a synchronous initialization failure being invisible to
  `ScopeConfig.observer`. `ScopeWidgetElementBase.build()` catches what
  `init()` threw, records it and raises it again into Flutter's build error
  boundary — which puts an `ErrorWidget` in the subtree but tells the observer
  nothing. A structural family therefore reported no event at all for such a
  scope: no `onInit`, and by the rule above no teardown pair either. A family
  with a phase of its own fared no better, since that phase is started only
  for an `init()` that returned. The hook now sends `onError` with
  `ScopePhase.initialization` before it raises the failure again — the one
  point both kinds of family pass through; for a structural scope that single
  event is its whole recording.
* **Breaking:** add `ScopePhase.build`, and report a failing build through
  `ScopeConfig.observer`. `buildOnReady`, `buildOnProgress`, `buildOnError`,
  `buildOnWaiting`, `buildOnClosing`, `ScopeWidgetBase.build` and
  `ScopeModel.build` all run from `ScopeWidgetElementBase.build()`, whose
  failure Flutter's build error boundary answers with an `ErrorWidget` — what
  the subtree shows, not what the observer hears, the same split a failing
  `init()` used to fall into. This was the last family of user code the
  observer could not hear; every other lifecycle hook already reported. The
  report is added to the raise rather than put in its place: unlike a teardown
  with nobody left to hand a failure to, a build has a caller, and the
  `ErrorWidget` it draws is unchanged. A widget that is not a scope —
  `NavigationNode`, `ListenableSelector`, the views of `ScopeNotifier` — has no
  `debugLabel` to be named as the target, so its build is not covered.
  `ScopePhase` already asked a `switch` over it in your own code to carry a
  `default` branch; one written without it stops compiling.
* Fix an `AsyncControllerScope` failing to give back a controller its own
  initialization never handed over, and telling `ScopeConfig.observer` nothing
  about it. That release runs from the `finally` of the initialization, where
  a raise would replace the failure that actually broke the scope, so its own
  failure was reported through `FlutterError.reportError` alone — while the
  expiry of the very same wait already arrived as `onTimeout` with `its
  controller to be released`. An observer therefore heard about a release that
  ran too long and nothing at all about one that failed. It now also sends
  `onError` with `ScopePhase.disposal`, the phase the ordinary teardown uses
  for the same kind of failure; the `FlutterError` report is unchanged.
* Fix a failing `onUnmount` reaching `ScopeConfig.observer` on one of the two
  paths out of a scope but not the other. The hook runs from `unmountScope()`,
  and both `ScopeWidgetElementBase.unmount()` and the asynchronous teardown
  call it — whichever gets there first does the work, and the other finds it
  already done. The asynchronous one guards it and sends `onError` with
  `ScopePhase.unmount`; the element's did neither, so a scope the tree took
  away reported nothing while a scope that closed itself reported the failure.
  The framework still showed it, as an error of the widget tree rather than an
  event of the scope. Both paths now report it — and the element's path no
  longer raises it afterwards; see the entry about a batch of scopes below.
* Fix the second of two simultaneous teardown failures of a `Scope` reaching
  `ScopeConfig.observer` through neither channel. The state is torn down
  before the dependencies and each half is guarded on its own, so both can
  fail; only the first can leave through the throw, and the second went to
  `FlutterError.reportError` alone. It now also sends `onError` — with
  `ScopePhase.unmount` or `ScopePhase.disposal`, whichever half it came from.
  This is reachable with a dependency container written by hand against
  `ScopeDependencies`: the built-in `ScopeAutoDependencies` reports what its
  own children throw and never hands a failure to the scope above it.
* Fix a `ScopeModel` whose `dispose` callback throws telling
  `ScopeConfig.observer` nothing about it. The callback runs from the element's
  own disposer, which `unmount()` calls from a `finally` — outside the guard
  around the `unmountScope()` beside it — so the failure went to the framework
  and no further, and the `onDispose`/`onDisposed` pair closed around it as if
  the teardown had gone through. It now sends `onError` with
  `ScopePhase.disposal` before the failure is raised at the caller as before.
  With this, every point where a scope hands control to your code on its way
  in or out reports through the observer; a `buildOnReady` and its siblings
  still do not, because a build belongs to Flutter's own error boundary, which
  answers it with an `ErrorWidget`.
* All six bounded waits now report an expiry through `ScopeConfig.observer`.
  Four already did; the wait for a `scopeKey` and the wait for child scopes
  reported only through `FlutterError.reportError` and the scope's own
  `onScopeKeyTimeout` / `onWaitForChildrenTimeout`, which is where they were
  before the observer existed. `onTimeout` names them `access to its scopeKey`
  and `its child scopes`. The wait for the children reports from
  `AsyncScopeParent.waitForChildren`, the one point all three ways of asking
  for it pass through — a scope's own teardown, a parent asked directly, and
  `AsyncScopeCoordinator.waitForChildren` — and it reports even when you pass
  an `onTimeout` of your own: a callback replaces the `FlutterError` report,
  not what the package says about itself.
* **Breaking:** the `AsyncScopeParent` mixin now implements `ScopeObservable`,
  so a parent of your own has to answer `debugLabel`. That is what lets an
  expired wait for the children reach the observer from the mixin, under the
  same label the rest of the scope's events carry. Every element of the
  package already answered to it.
* Add `ScopeTimeout.none`: the one value a single scope has for "wait as long
  as it takes". Every timeout parameter is a `Duration?` and all three of its
  values were taken — absent or `null` means "take the default from
  `ScopeConfig`", `Duration.zero` means "expire at once", and any other
  `Duration` is the limit — so removing a limit was possible only for every
  scope at once. Accepted by `scopeKeyTimeout`, `disposeScopeTimeout` and
  `waitForChildrenTimeout`, on the scopes and on both `waitForChildren`
  helpers, and by all four `ScopeConfig` defaults, where it says for the whole
  application what `null` says there — including the release of a dependency
  container after a failed initialization, which reads
  `ScopeConfig.defaultDisposeScopeTimeout` and takes no per-scope override. It
  is a subtype of `Duration` rather than a magic value, so the parameters keep
  their type and no existing call site changes; the package tells it apart by
  its type rather than by `==`, so a `Duration` some arithmetic happened to
  make negative is not mistaken for it. Such a `Duration` is refused instead,
  with an assert, everywhere a limit is resolved: a wait cannot be bounded by a
  length of time that has already passed, and a timer given one expires on its
  first tick.
* `initCancellationTimeout` and `pauseAfterInitialization` refuse
  `ScopeTimeout.none`, each with an assert, and for opposite reasons. A
  cancellation waits for the initialization generator to run out, and one
  suspended on a future that never completes never does — an unbounded wait
  there is the hang the limit exists to prevent; removing that limit stays a
  decision for the whole application, through
  `ScopeConfig.defaultInitCancellationTimeout`, which takes `null` or
  `ScopeTimeout.none` for it. A pause refuses the marker because it is not a
  limit on a wait at all but a stretch of time to hold the ready branch back
  for, and "wait as long as it takes" has nothing to say about one.
* Fix an anonymous dependency group — the common shape for the root of a tree,
  `sequential('', […])` or `concurrent('', […])` — reporting through
  `ScopeConfig.observer` under an empty label instead of `[group]`.
  `ScopeDependencyMixin.debugLabel` fell back to `name`, empty by design for
  such a group, so a line about it printed with a doubled space where the
  label should have been; `[group]` is the same fallback `wrappedName` already
  used for the same case, and a named group still reports under its own name,
  unwrapped.
* The bookkeeping that decides which build a dependent's selectors belong to asks
  for a frame when nothing else will bring one. The reset runs in a post-frame
  callback, and a build is not always inside a frame — `runApp` builds the first
  tree outside any — so with no frame to come the flag would stay raised and
  every dependent from then on would add its selectors to a pass that never ends.
  Asked for only when the scheduler is idle: from inside a frame it would order
  one more, empty, after every frame that built anything.
* `AsyncControllerScopeCore` has `maybeOf`, `of` and `select` of its own, like
  the two `Core` layers below it. Statics are not inherited in Dart, so a family
  built on this layer had to reach for `AsyncDataScopeCore.maybeOf` with its own
  type arguments — which works, and is not something to have to find out.
* The placeholder `child` every `ScopeInheritedWidget` carries says which mistake
  it is instead of raising a bare `UnimplementedError` from inside the framework.
  A scope builds what it shows through `buildChild()`; that placeholder is only
  reached when a family returns a `child` nobody passed.
* Dartdoc corrections, all of them about promises rather than behaviour:
  `AsyncDataScope` and `AsyncControllerScope` now say what their twin
  `AsyncScope` says about `scopeKey`, about each expiry callback, about
  `pauseAfterInitialization` and about what the builders receive;
  `ScopeDependency.count` no longer claims to include the group itself (it counts
  the steps a subtree reports, and a group reports none); `AsyncScopeModel` is
  the third type argument of `ScopeModelCore`, not of the two-parameter
  `AsyncScopeCore`; and the `dispose` comment no longer justifies itself with
  "a failed leaf is never disposed of at all", which stopped being true when a
  failed leaf started giving back what it had taken.
* An expired `AsyncScopeParent.waitForChildren` names the scope after its widget,
  which is the name carrying `tag`, instead of after its element, which is a type
  and a hash. The two neighbouring waits —
  `AsyncScopeCoordinator.waitForChildren` and a scope's own teardown — already
  did. A parent of your own can say what it is called by overriding the new
  `AsyncScopeParent.reportName`.
* The log line about giving up a place in a `scopeKey` queue names the key the
  initialization took rather than reading the `scopeKey` getter again. The getter
  is your code, and a message resolved lazily would have run it from a teardown
  that has already begun.
* The diagnostic about a `scopeKey` that changed no longer describes a queue that
  does not exist. A scope reads its key before it looks for a coordinator, and
  that lookup is the one step which can fail with the key already read — such a
  scope entered nothing, and the message said it was "holding [k] in the queue of
  no AsyncScopeCoordinator".
* A `ScreenshotReplacer.onCompleted` that raises is reported through
  `FlutterError.reportError` instead of being left where nobody is waiting. The
  callback is called from the capture, which runs as an unawaited future in a
  post-frame callback, so a raise there surfaced as an unhandled zone error far
  from the widget; called from `dispose` — the last resort, when no capture ever
  succeeded — it came out of `State.dispose` and took the unmount with it. The
  report stays one-shot either way. `dispose` also releases the captured
  `ui.Image` before telling the application anything, so what the state holds no
  longer depends on what the callback does.
* **Breaking change:** `NodeNavigatorState` can no longer be constructed. The
  type stays public — it is what a `GlobalKey<NodeNavigatorState>()` is made of
  and what it resolves to — but one built by hand and installed under an
  ordinary `Navigator` would fail on its first pop rather than at the line where
  the mistake was made: it reads the node from the widget a `NavigationNode`
  builds. Only that widget can make one now.
* `NodeNavigatorState` is documented rather than hidden with `@nodoc`. It is
  the type a `GlobalKey<NodeNavigatorState>()` is made of, so
  `NavigationNode.navigatorKey` could not be written without naming it.
* `ScopeController.performInit` keeps the promise the family makes about it. It
  ran `init()` every time it was called and paid no attention to whether the
  controller had already been let go of, so a second call — or one after
  `performDispose()` — re-mounted a disposed controller and initialized it
  against fields its `dispose()` had already released. The three `perform`
  methods are a one-way sequence now, as the documentation always said.
* `ScopeController.performDispose` no longer tells a second caller that a
  teardown still running is over. It marked the controller disposed of before
  awaiting `dispose()`, so a concurrent second call returned at once and
  reported success — including when the run it was reporting on went on to
  fail. Every caller now joins the one run and receives its outcome, the way
  `LiteScope.close()` already did.
* `ScopeConfig.reset()` puts the pause switch and the four timeout defaults
  back where they started. They are global and outlive the code that changed
  them, and until now every suite saved and restored them by hand — a
  convention, and one a test that forgot it could break for its neighbours.
  `ScopeConfig.observer` is left alone: it is an object rather than a switch,
  and it is usually the whole point of the run it was assigned for. The dartdoc
  of `pauseAfterInitializationEnabled` described what setting it to `false` does
  while documenting a field whose value is `true`; it now says what the field
  is.
* `AsyncDataScopeContext.hasData` says whether the initialization has produced
  its value. For a nullable `T` nothing else could: `dataOrNull` is `null` on
  both sides of the moment the value arrives, since `null` is a value the
  initialization may legitimately produce, and the flag the family kept for
  exactly this was consulted only by `data`. The dartdoc of `data` and of
  `unmount`/`onUnmount` now also says when the value starts being there — a
  shade before the scope shows its ready branch, and deliberately much earlier
  than that when `pauseAfterInitialization` is set.
* A second `AsyncDataScopeReady` no longer replaces the value behind the
  model's back. The value is caught in the `map` the family wraps the
  initialization in, which runs as the event goes past, while the check for a
  second initialization sits one layer up in an `asyncMap`, which runs after
  it: by the time the diagnostic was raised the new value had already been
  stored, the model stayed as it was, the dependents heard nothing, `data`
  handed out the newcomer — and the value the scope had been given was left
  with nobody to release it. The second `ready` is refused where the value is
  caught.
* `AsyncScopeModel` is documented rather than hidden with `@nodoc`. It is what
  `AsyncScopeElementBase.model` returns, and the model type the family fixes on
  the layer below — `ScopeModelCore<W, E, AsyncScopeModel>` — so a scope written
  on the `Core` layer has to name it.
* `AsyncScopeElementBase.model` is one object instead of a fresh wrapper on
  every read. `state`, `isInitialized`, `hasError`, `error`, `stackTrace`,
  `buildChild()` and every run of every selector go through it.
* `ScopeDependencyNoDisposalRequired` is a state a dependency can actually
  reach. A dependency that set no `dep.dispose` has nothing to give back, so
  its group passes it by — rightly — but it was passed by in silence and went
  on saying `initialized` after the whole tree had been torn down, which made
  the dump of a fully disposed scope read as though half of it were still
  alive. The state that exists for exactly this was created nowhere.
* A lookup with `listen: true` that finds no scope is remembered as an
  unsatisfied dependency, the way Flutter's own
  `dependOnInheritedWidgetOfExactType` remembers one. A widget that asked when
  there was no scope above it and is later carried under one by a `GlobalKey`
  is now told its dependencies changed, instead of going on showing what it
  read when there was nothing to read.
* `State.widget` on a scope state throws an `UnsupportedError` that says why,
  and is no longer marked `@visibleForTesting` — an annotation that read as
  "use this from tests" where the meaning is "there is nothing here to use".
  A scope state has no widget of its own; `params` is the scope widget.
* Fix `LiteScope.wrapState` doing nothing. The hook is documented as the way
  to put a widget around the ready branch alone, and `Scope` has always
  honoured it, but the element behind `LiteScope` never called it: whatever it
  returned was thrown away, and the ready branch was built unwrapped.
* Fix a root `NavigationNode` forwarding a pop after all. `isRoot` says the
  node keeps a pop to itself, and `NodeNavigatorState.pop` honoured it, but the
  system back reaches the navigator above by another path — and there the
  promise held only for as long as nobody wrote an `onPop`. A root node whose
  hook allowed the pop took the route below it; a root node placed as `home`
  took the last route of the application's own navigator and left a blank
  screen. The hook is still asked, since that is where an application decides
  what its own outermost back means, but a `true` no longer leaves the node.
* Fix an ordinary `NavigationNode` on the first route emptying the application's
  own navigator. The fix above was made for `isRoot` and stopped there, while
  the line it left in place — a plain `pop` on the navigator above — takes the
  last route that navigator holds without asking whether it is the last. A node
  placed as `home` with an `onPop` that allowed the pop therefore left a blank
  screen, and an assertion of the framework on the frame after it.
* Fix that same forwarding walking past a `PopScope` the application put around
  the node: a route the application guarded, and refused a pop for, was taken
  anyway. Both defects are one line, and the node now asks the route it stands
  on what a pop there would do instead of telling it. It asks with its own
  answer stood aside for the length of the question — the node's own entry is
  registered on that very route and has already had its say — so what is left is
  what the node has no business answering for itself: the application's guard,
  and whether there is a route to give up at all. Asking rather than telling is
  also why an application still hears one press as one: a `maybePop` of the
  node's own would report a second refusal to every `PopScope` on that route.
* Fix system back taking the whole route instead of closing a `Drawer`, a
  `showBottomSheet` or anything else a `NavigationNode`'s page opened with
  `addLocalHistoryEntry`. None of those change a navigator's stack, and nothing
  announces them — `addLocalHistoryEntry` ends in `changedInternalState`, which
  marks the route dirty and dispatches no notification — so the node was
  deciding from an answer worked out before the drawer opened, and the answer
  said the press was none of its business. The node was taking away what works
  without it. It now works the answer out when the framework asks for it, by
  registering a `PopEntry` of its own instead of building a `PopScope`.
* **Behaviour change:** the node's first page no longer carries a
  `LocalHistoryEntry` of the node's own. It was there to draw the back arrow of
  an `AppBar` on that page and to route a `maybePop` out of the node, and it
  cost the node the ability to tell it from a drawer's entry — a route reports
  only whether its local history is empty. The page says
  `impliesAppBarDismissal` for itself now, and `NodeNavigatorState.maybePop`
  leaves the node when the node has nothing of its own to close, which is what
  the arrow presses. `NodeNavigatorState.canPop()` therefore stopped
  overriding `NavigatorState.canPop()`: with no marker of the node's own in the
  way, the base answer is the true one, and it used to answer `false` while a
  drawer was open.
* Fix a `pauseAfterInitialization` outliving the tree. The delay was a timer
  nobody held, so a scope taken off the tree mid-pause left it running: in a
  widget test that is `A Timer is still pending even after the widget tree was
  disposed`, which fails a test of yours for no reason of yours, and in
  production it is an unmounted element held for the rest of the pause. The
  scope keeps the timer now and puts it out first thing in the teardown. It is
  still a timer of the current zone, unlike the bounded waits below — this delay
  is one the user sees, so a widget test must be able to drive it with
  `pump(duration)`.
* Fix the wait for a `scopeKey` and the wait for the child scopes taking their
  timers from the current zone. Both used `Future.timeout`, which does, and both
  are waits on a hang that outlives frames — a scope is usually taken down
  between them, so the timer was still pending once the tree was gone, and that
  is what `flutter_test` ends a test on. The other two bounded waits of the
  teardown had already been moved to the root zone for this reason; these two
  are the same kind of wait and had been missed. A consequence for tests: a wait
  of any of the four is now waited out in real time, and `pump(duration)`
  reaches none of them. The `debug` topic says so.
* Fix an initialization stream that ends without `AsyncScopeReady` leaving the
  scope on its loading branch for good, and silently. The model stayed
  `AsyncScopeWaiting`, `disposeScope` was never called, and the only trace was
  an `info` line in a logger that is off by default — nothing on screen and
  nothing in the console, which is the hardest kind of failure to look for. The
  scope now moves to `AsyncScopeError` with a `StateError` saying what a stream
  is expected to end with, so `buildOnError` builds and the report is loud. This
  reaches every family: `AsyncDataScope`, `AsyncControllerScope` and the `Scope`
  container all initialize through the same subscription.
* Fix the same silence coming from the other side: `ScopeAutoDependencies`
  awaited the disposal of its half-built tree with no limit, from the `finally`
  of its own generator. Nothing downstream sees the failure of an initialization
  until the generator finishes, so a `dep.dispose` that never completed held not
  only the resources but the failure itself, and the scope showed its loading
  branch for ever. The wait is now bounded by
  `ScopeConfig.defaultDisposeScopeTimeout`, the way every other wait in the
  teardown is, and giving up is reported rather than passed over; a release that
  fails after it was abandoned is reported too. The `AsyncScope` topic now says
  what an `await` in a hand-written guard costs when it cannot finish.
* Fix a controller left unreleased when its `init()` woke up after the
  teardown was over. An initialization parked on a future cannot be cancelled
  — cancelling an `async*` means resuming its body, and a body suspended for
  good is never resumed — so the teardown gives up on it after
  `initCancellationTimeout` and runs to the end. If that future ever
  completes, the generator is resumed with its `finally` still holding the
  controller to release; by then the element has given back everything it
  held, the widget among it. Reading `disposeScopeTimeout` there went through
  that widget and raised a `_TypeError` where a release belonged, so the
  console got a report about a null instead of the release the family
  promises on every path. An abandoned release now runs unbounded, which is
  what it deserves: nobody is waiting for it and it can hold nothing up.
* `LiteScope.buildOnWaiting` is documented as the required builder it is, and
  the two optional ones say what happens when they are left out. The dartdoc
  read like that of an optional method — "may return `null`" — while the
  method is abstract, which is the wrong half of the story to tell first. The
  rule across the families is one: exactly one branch before the ready one has
  to be written, and it is the one that family is certain to reach. A `Scope`
  always initializes a container, so `buildOnProgress` is its required
  one; a `LiteScope` initializes nothing of its own, so the branch it always
  has is the wait. The `LiteScope` topic now says so, and says what moving a
  screen from `Scope` to `LiteScope` trades for what.
* A `LiteScope` that overrides `init()` and forgets `buildOnProgress` or
  `buildOnError` gets an `UnimplementedError` that names the scope and the
  method instead of a bare one that names nothing. The error branch carries
  the failure it was called for as well: without it that failure was replaced
  on screen by the missing-builder error, and the reason the initialization
  failed at all went with it.
* The `AsyncScope` topic showed `hasChildren`, `childrenCount` and
  `waitForChildren` on a `scope` a reader has no way of getting hold of: the
  mixin that carries them sits on the element, and the elements of the five
  built-in families are private, while `AsyncScope.of` hands back an
  `AsyncScopeContext` that has none of them. The topic and the dartdoc of
  `AsyncScopeParent` now say who those three are for — a family of your own,
  reading them on `this` — and what a subtree asks instead:
  `AsyncScopeCoordinator.waitForChildren`, which awaits the scopes registered
  with the nearest coordinator rather than the children of one scope.
* **Behaviour change:** `ScopeStateWithErrorNotifier.update` now puts down a
  failure the model was holding. `_error` used to be set once and never
  cleared, while the inherited `update` went through as usual: it replaced the
  state and notified everybody, and `state` went on throwing the old failure at
  every listener that came to read it. Under a scope that is one attempt at
  recovery turning a whole subtree into `ErrorWidget`s — the selector throws,
  the dependent is rebuilt, its `build` reads `state`, and so on. A state
  handed over is a state that can be read, so the failure goes with the same
  call; the listeners hear about it even when the value is the one from before
  the failure, since `shouldNotify` weighs one value against another and this
  change is between a
  state that throws and one that does not. The `ScopeNotifier` topic says so.
* The dartdoc of `of`, `maybeOf` and `select` on `Scope` and `LiteScope`
  promised one condition where there are two. Both read the state, and the
  state exists only in the ready branch — so a scope that is waiting for its
  `scopeKey`, initializing, failed or closed makes `of` throw and `maybeOf`
  answer `null` just as an absent scope does. A caller reading the promise as
  written looked for a scope that was there all along. The two conditions are
  now spelled out, together with the one difference between the two lookups:
  `of` says which of them it was, `maybeOf` cannot.
* Fix every failure of a teardown but the first being lost. The disposal of an
  asynchronous scope runs in four stages, each guarded on its own so that a
  failure in one never skips the ones behind it, and only the first of them can
  be passed on — a throw carries one failure. The rest went to an `info`-level
  logger that is off by default, which is the same as losing them: a scope
  whose wait for its children expired and whose own `disposeScope` then fell
  over said nothing at all about the second failure. Every failure behind the
  first is now reported through `FlutterError.reportError`, which is the trade
  the rest of the teardown already makes for failures it cannot hand to a
  caller.
* Fix the *first* failure being lost in the two halves of a `Scope` teardown.
  `ScopeState.onUnmount` runs before `ScopeDependencies.onUnmount`, and
  `ScopeState.disposeStateAsync` before `ScopeDependencies.dispose`; in both pairs
  the state's failure was kept in a local while the container's was left to
  throw over the top of it, so the first — the one that explains what the
  second made of the same teardown — vanished without a trace. Both halves are
  now guarded apart: the first failure leaves through the throw, the second
  through a report. This shows only with a hand-written `ScopeDependencies`:
  `ScopeAutoDependencies` reports what its own children throw and never hands a
  failure up. The `Scope` and `AsyncScope` topics say what the order costs.
* The dartdoc of the twelve timeout parameters said the opposite of what they
  do. `scopeKeyTimeout`, `initCancellationTimeout`, `disposeScopeTimeout` and
  `waitForChildrenTimeout`, in all three asynchronous families, each promised
  that `null` "waits indefinitely" — and each is read as
  `value ?? ScopeConfig.defaultX`, which is three seconds. A teardown that was
  meant to wait as long as it took gave up after three seconds and went on
  without its children, and the report of the expiry sent the reader looking
  somewhere else. They now say what the element layer had always said, that
  `null` takes the default, and that a limit is removed through `ScopeConfig`,
  which is the only place a limit can be removed at all. The `debug` topic says
  the same.
* **Breaking:** the first type argument of `ScopeAutoDependencies` is now bound
  to the container itself — `ScopeAutoDependencies<T extends
  ScopeAutoDependencies<T, C>, C>`. It had been bound to `ScopeDependencies`
  only, so anything at all could stand there, and what stands there is what the
  container hands the scope when the tree is up. A container naming another
  container — a copy-paste with the argument left behind — compiled, built its
  whole tree, initialized it, and then failed on the cast at the very end of a
  successful initialization: a bare `TypeError` from a line the caller never
  wrote, with everything still running and nothing left holding a reference to
  release it. The bound alone does not close it, since another container
  satisfies the bound too, so the container also refuses a type argument that is
  not itself before it builds anything, and says which two types it is looking
  at. A container that already named itself, which is what every example and
  every test did, is unaffected.
* **Behaviour change:** `NavigationNode.onPop` is given a context from inside
  the node. It used to get one from above the nested navigator, so
  `Navigator.of(context)` there was the application's navigator — and the
  confirmation dialog the documentation recommends asking from that hook, with
  `useRootNavigator: false`, was pushed outside the node, above everything the
  node exists to stay below. A scope the node stood under was unreachable from
  the dialog asking whether to leave it. The context the route the node stands
  on is found from is unchanged, so an answer arriving after that route has been
  closed or buried still takes nothing.
* A notification no longer rebuilds the widgets of the subtree it is not
  rebuilding. "Skips rebuilding the whole subtree" was true of the elements and
  not of the widgets: `ComponentElement.performRebuild` calls `build()`
  whatever else happens, and only `updateChild` was skipped — so `buildChild()`
  ran on every `notifyDependents`, and everything it returned was thrown away
  unlooked at. For a scope notified once a frame that is the whole widget graph
  of its subtree, built and dropped, once a frame. The widget of the last real
  build is handed back instead.
* [breaking changes] `ScopeDependenciesExtension.asStream` takes one type
  argument instead of two: the container type is the type of the receiver and
  is inferred, so `AppDependencies().asStream<String>()` replaces
  `AppDependencies().asStream<String, AppDependencies>()`. Written out, it was
  a downcast the compiler could not check — a container renamed in a refactor
  left the old name in the call, which still compiled and failed on the first
  frame. The shortest way to build an initialization stream was the one that
  moved a type error from compilation to run time.
* `of` and `select` on `LiteScope` and `Scope` say which scope they found and
  what state it is in when there is no state to answer with. The state is
  created in the ready branch, so any other state — waiting for a `scopeKey`,
  initializing, failed, or closed in place — used to answer `Null check
  operator used on a null value`, naming neither. `maybeOf` still answers
  `null` there, the same as when there is no such scope at all, and the
  message says so.
* The methods that carry a family's promise are sealed. `initScope` on
  `AsyncDataScopeElementBase` catches the value on its way past, and
  `initDataAsync` on `AsyncControllerScopeElementBase` is the whole of what the
  controller family guarantees; both are `@nonVirtual` now, and the controller
  layer's `disposeScope` is `@mustCallSuper`. They sat in the same class as the
  hooks a subclass is meant to write, so overriding one silently turned the
  guarantee off — `data` left empty for good, or a controller never released —
  with nothing from the compiler or the analyzer to say so.
* Fix a controller whose `dispose()` fails taking the failure of its `init()`
  with it. The release runs from a `finally`, and an exception raised there
  replaces the one the `finally` was entered for — so `buildOnError` was handed
  the secondary failure and the reason the scope actually broke disappeared.
  It is reported now, and the original is what the scope shows. `dispose()` is
  documented to run on the path where `init()` failed halfway, which makes
  that the path it is most likely to fail on.
* The same release is bounded by `disposeScopeTimeout`, which the
  `AsyncControllerScope` topic already promised for it. Nothing bounded it on
  the path where `init()` threw: a teardown that never finished never let the
  generator finish either, so the failure never reached the model and the
  scope showed its loading branch for ever, with no report of any kind.
* [breaking changes] The `value` of `ScopeModel.value` and
  `ScopeNotifier.value` is a non-nullable `M`. The field behind it stays
  nullable — the owning constructor leaves it empty — and `required` therefore
  said nothing about what a `.value` scope was handed: `null` compiled and
  then failed on a bare null check, naming neither the scope nor the
  parameter, and for a notifier from inside `init()`. A nullable expression
  now needs a `!` at the call, where the decision belongs.
* `CompositeListenableSubscription.cancel()` skips a member that was already
  cancelled on its own instead of cancelling it again. Cancelling a
  subscription twice is a mistake in the caller and still says so, but a
  composite holding one is not that caller: raising there left every member
  after it in the list still listening — the very leak the composite exists to
  prevent, and in debug builds only, since release has no assert to raise.
* A failure of a dependency reaches `buildOnError` with the stack trace of
  what actually failed. The wrapper was raised with `StackTrace.empty`, so the
  trace that travelled up the tree — and into whatever the application does
  with it — pointed nowhere. The original was inside
  `ScopeDependencyException.stackTrace` all along, but nothing said so.
* A failure of the dependency teardown is reported through
  `FlutterError.reportError`, not only logged. `ScopeAutoDependencies.dispose`
  never re-throws, by design, so the log was the single way out — and the
  package logger is off by default, which made a disposer that could not close
  its resource completely silent.
* `LiteScopeState.close()` and `ScopeState.close()` use the element the state
  belongs to instead of looking one up through `context`. The lookup answered
  the *nearest* scope of that type, which a `wrapState` putting another scope
  of the same type around the state is enough to shadow, and it answered
  nothing at all once the state had been unmounted — where closing a scope
  that is already gone should cost nothing.
* Fix a teardown passing on its last failure instead of its first. Its four
  stages are guarded apart so that a failure in one never skips the ones after
  it, and the first of them is what the caller was meant to hear — but two of
  the three handlers assigned to the record instead of keeping what was
  already there, so the last one won and the first was left in a log that is
  off by default. Only a scope closed with `close()` could show it: on a scope
  taken off the tree the framework has already run the synchronous half before
  the teardown reaches it, so that stage cannot fail there at all.
* `AsyncScopeParent.waitForChildren` defaults its `timeout` to
  `ScopeConfig.defaultWaitForChildrenTimeout`, the same default the identically
  named helper on `AsyncScopeCoordinator` has always applied. It passed `null`
  straight to the registry, where `null` means no limit at all — so the most
  natural call of a public method, without arguments, was the one wait in the
  package that could hang for ever. Waiting with no limit is now what setting
  that default to `null` means, which is a decision for the application rather
  than for one call.
* Fix a selector that throws taking the whole notification with it. The walk
  over the dependents runs user code with no boundary of its own around it, so
  one selector that could not answer stopped the walk: every dependent it had
  not reached yet never heard about the change, and which ones those were came
  down to the iteration order of a hash map. A scope's own subscription is
  walked first, so a failure there swallowed the notification whole. The
  failure is now reported through `FlutterError.reportError` and its dependent
  is treated as changed, so it is rebuilt and asks the selector again from
  inside its own build — where a second failure becomes an `ErrorWidget` for
  that one widget, instead of a second, derived error for the frame.
* Fix one failing disposer taking the rest of a *concurrent* group with it —
  the same defect as the sequential one above, in the class beside it. An
  error reaching the merged stream cancelled every arm still running, and an
  arm suspended mid-walk resumes only as far as its next `yield`: a nested
  branch stopped wherever the cancellation found it, everything below that
  point stayed held, and nothing came back for it, since the walk marks itself
  done whichever way it ended. Each arm now keeps its failure to itself, the
  merge finishes, and the first failure is passed upwards afterwards. The
  initialization of a concurrent group is unchanged: there the first error is
  meant to cancel the rest, and what the losing arms took is picked up by the
  disposal that follows.
* Fix a failing `ScopeState.onUnmount` taking the synchronous teardown of the
  dependencies with it. The state let go of its own first and the dependencies
  after it, unguarded, so a hook that threw meant no dependency ever heard
  `unmount` at all — and none ever would: the pass runs once and nothing comes
  back for a second attempt, so whatever a dependency drops only there lived on
  until the tree died with it. The two halves are now guarded apart, as they
  already were in `disposeScope`, and the first failure is passed on once both
  have run.
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
* A new family, `AsyncControllerScope`, for a scope whose whole content is a
  controller with a lifecycle of its own — something that has to run while a
  part of the tree is on screen, rather than something to show. A
  `ScopeController` writes three hooks — `init`, `onUnmount`, `dispose` — and
  chains to no `super`: the three methods the scope calls (`performInit`,
  `performUnmount`, `performDispose`) are sealed, keep `mounted`, keep the
  order, and run each hook at most once. The scope releases the controller it
  created on every path, including the two a hand-written version over
  `AsyncDataScope` loses it on: an `init` that threw, and an `init` interrupted
  before it handed the controller over. Three layers as everywhere:
  `AsyncControllerScopeCore`, `AsyncControllerScopeBase`, and
  `AsyncControllerScope<C>` with a `create` callback.
* [breaking changes] The type arguments of `AsyncDataScope.select` are in the
  order every other `select` in the package uses — the scope's own type first,
  the selected type last: `select<Profile, String>` rather than
  `select<String, Profile>`. It was the only one the other way round, against
  `ScopeModel`, `ScopeNotifier`, `Scope`, `LiteScope` and its own
  `AsyncDataScopeBase.select`. A call written for the old order stops
  compiling rather than changing meaning.
* [breaking changes] `AsyncScope` hands the progress to the branches built
  before the scope is ready: `progressBuilder` is now
  `(context, progress)` and `errorBuilder` is
  `(context, error, stackTrace, progress)`, matching `Scope`, `LiteScope` and
  `AsyncDataScope`. It was the only family that computed the progress, kept it
  in the model, and then left the builder to fish it back out of
  `AsyncScope.of`. Subclasses of `AsyncScopeBase` take the same two arguments
  in `buildOnProgress` and `buildOnError`.
* Fix a teardown held forever by a `disposeScope` that never completes — the
  same hole one step further down, and user code on both sides of it. The
  release that follows it, and with it the `scopeKey` of a scope that had
  already left the tree, waited for it with no limit. Bounded now by
  `disposeScopeTimeout`, three seconds by default
  (`ScopeConfig.defaultDisposeScopeTimeout`, `null` to wait indefinitely), with
  an `onDisposeScopeTimeout` callback. On expiry the teardown is left to finish
  whenever it does, the expiry is reported, and the scope gives back what it
  was holding. A release that legitimately takes longer than the limit is
  therefore no longer waited out — raise the limit for such a scope, or drop it
  with `null`.
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
* `AsyncScope` and `AsyncDataScope` take the nine settings their base classes
  declare: `scopeKeyTimeout`, `initCancellationTimeout`, `disposeScopeTimeout`
  and `waitForChildrenTimeout` with the callback beside each, and
  `pauseAfterInitialization`. The elements behind both widgets had always read
  them; only the constructors never passed them on, so the two closure forms
  were the only ones in the package whose user could not set a limit for one
  scope — the process-wide `ScopeConfig` default was the whole choice.
  `AsyncControllerScope` took all nine from the start.
* [breaking changes] `State.dispose` is sealed on `LiteScopeState` and
  `ScopeState`. It belongs to Flutter and lands on either side of a scope's
  teardown depending on how the scope went, so nothing a scope has to let go of
  can be released on that schedule. Overriding it is now an analyzer warning
  that says so; the teardown goes in `onUnmount()` and `disposeStateAsync()`.
* [breaking changes] `ScopeDependencies.unmount` and `ScopeDependency.unmount`
  are now `onUnmount`, so that every hook a scope calls to drop what must stop
  reaching it goes by one name. The assignable callbacks keep the short verb
  they always had: `dep.unmount`, and `AsyncScope(onUnmount:)`.
* [breaking changes] The synchronous half of a teardown is now a step of the
  teardown rather than a tail of `Element.unmount`, and `LiteScopeState` /
  `ScopeState` gained `onUnmount()` to put it in. A scope leaves in one of two
  ways, and only one of them went through the framework: `close()`, which keeps
  the element mounted on purpose, skipped the synchronous half altogether — a
  dependency's `unmount` never ran, and by the time the element did leave the
  tree the asynchronous half had already released it, so nothing was left to
  drop the subscription from. `onUnmount` now runs exactly once, always before
  `disposeStateAsync`, whichever way the scope goes.

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
  `Listenable.select` and `ListenableSelector.compare`, and in `doc/utils.md`.
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
  `onWaitForChildrenTimeout`, the state's `disposeStateAsync`, a dependency's
  `unmount` — and a failure there used to abandon everything behind it: the
  scope stayed registered with its parent, its `scopeKey` was never released,
  its model was never disposed of, and its dependencies kept whatever they had
  taken. Every mandatory stage now runs whatever the hooks make of it, and the
  first failure is reported once the teardown is over. Two consequences worth
  knowing: an `unmount` that fails on one dependency no longer leaves its
  siblings mounted, and a scope whose disposal failed before the mandatory
  block now reports that failure after the block rather than instead of it.
* Fix a failing `onUnmount` costing every *other* scope of the same batch the
  teardown it is owed. The failure was raised at the caller of
  `ScopeWidgetElementBase.unmount()` once it had been reported — and that
  caller is `BuildOwner._inactiveElements._unmountAll()`, a loop with no
  boundary around any one element, over a list it has already cleared. Three
  sibling scopes with a throwing `onUnmount` in the middle left the third one
  mounted for good: no `unmountScope`, no `dispose`, no asynchronous teardown,
  its `scopeKey` never given back and its registration with the parent never
  dropped. Such a failure now goes to `ScopeConfig.observer` and
  `FlutterError.reportError` and no further, which is the trade the rest of the
  teardown already makes. The `close()` path is unchanged: there a caller
  exists, and it still hears it.
* `Progress.value` drops a branch that said the same thing twice. `num.clamp`
  compares with `compareTo`, which treats `NaN` as the maximal double, so
  `0 / 0` already came back as the upper limit and the explicit `total == 0`
  test in front of it could not change any answer. Nothing about the value
  changes; what does is that the promise now has one implementation and a test
  that holds it.
* Fix the first failure of an asynchronous teardown leaving as an unhandled
  error of the zone while every failure behind it was reported through
  `FlutterError.reportError`. The teardown runs on a future `dispose()`
  discards, so on the ordinary way off the tree there is nobody to raise at —
  an application with ordinary crash reporting therefore saw the failures that
  had no caller and missed the one that did. It is reported now, by the same
  channel as the rest. `close()` is untouched: there a caller exists and still
  hears it.
* `onDispose` opens before the four stages of the teardown rather than between
  the second and the third. `onError` for the unmount and for the preparation,
  `onCancelled` and two `onTimeout` all used to arrive before the teardown they
  belong to had been announced at all, so an observer pairing `onDispose` with
  `onDisposed` counted them against whatever came before.
* A scope lets go of the `scopeKey` object and of the coordinator element once
  the key has been released. A scope closed with `close()` stays mounted for as
  long as its owner likes — a closing screen can be on show for minutes — and
  both were held for all of it, long after the only thing that reads them had
  stopped.
* `ScopeStateNotifier.update` replaces the state whether or not `shouldNotify`
  says anybody has to hear about it. That hook answers whether the change is
  worth waking a listener for, not whether it happened; skipping the assignment
  with the notification left the model holding the *older* of two objects its
  own comparison called the same. `ScopeStateWithErrorNotifier.update` keeps
  the value it was handed when it recovers from a failure — the one call that
  puts a failure down was the one call whose value was thrown away — and asks
  `shouldNotify` once instead of twice.
* Every `unmount` failure of a dependency group is reported. The first is
  passed on as it always was; the ones behind it used to be dropped where they
  happened, reaching neither the caller, nor the observer, nor `FlutterError`.
* `runStreamGuarded` cancels a source that reported an error from inside
  `listen()` itself, before the subscription had been handed back. Nothing in
  the package produces such a stream; the helper stands up to one that does.
* Add `ScopeCompositeObserver`, which hands every event to each of the
  observers it is given. `ScopeConfig.observer` holds one, and wanting two is
  ordinary — `ScopePrintObserver` while developing and a reporter of your own
  beside it. It belongs to the package rather than to the application, and that
  is the point: `ScopeObserver` is a `base class` with empty hooks so that an
  ordinary observer keeps compiling when a tenth hook is added, and a delegate
  is the one subclass that gains nothing from that — the new hook would arrive
  with the base implementation and every observer behind the delegate would go
  quiet without a word. An observer that throws does not stop the ones after
  it; the failure is reported and the rest are asked.
* **Breaking:** `CompositeListenableSubscription.add` no longer throws a
  `StateError` outright after the composite has been cancelled. It still says
  the call is a mistake, with an assertion, the way `cancel` beside it does —
  but the subscription it was handed is cancelled first. Raising left exactly
  what the composite exists to prevent: the subscription was made on the line
  before, and the throw was what kept it attached to its listenable with nobody
  holding it.
* The suite is no longer part of the published archive. 756 KB against the
  540 KB of `lib/`, downloaded by everyone who depends on the package and of no
  use to any of them — the topics in `doc/` are the documentation and they
  ship. 364 KB compressed becomes 234 KB.
* The dartdoc of `ListenableSelector.selector` says what comparing it by
  identity costs: the inline closure the examples show is a new object on every
  build of the parent, so each of those rebuilds cancels the subscription and
  takes a new one. Hold the selector in a field where the parent rebuilds often
  and the listenable does not.
* `ScreenshotReplacer` no longer reports a failed capture through
  `FlutterError.reportError` when it gives up. The case it reported is the one
  the widget documents as ordinary — a subtree that is never painted cannot be
  captured — and in debug the pre-check catches it before `toImage` is reached,
  so the report only ever happened in release: a line in a crash reporter for
  something the developer could not see happening, and not a failure of the
  application at all. `onCompleted` and the absence of a picture say what
  happened.
* The dartdoc of the four timeout parameters of `Scope` and `LiteScope` says
  what the three asynchronous families' already did: which `ScopeConfig`
  default each takes, that `ScopeTimeout.none` removes the limit for one scope,
  that `initCancellationTimeout` is the one that refuses it, and what happens
  when a wait expires. On `Scope`, `disposeScopeTimeout` also says that it
  bounds two steps rather than one.
* The dartdoc of the constructor-mode check on `ScopeModel` and `ScopeNotifier`
  says that "refuses" means an assertion, and an assertion is debug-only: in
  release the switch still happens and still ends in a leaked model or a null
  check on a `value` that is gone. There is nothing honest to repair it with at
  runtime, which is the reason the check is where it is.
* The error a `LiteScope` throws for a missing branch names `initScope()`, the
  method that exists, rather than `init()`, which is a different hook. The
  `LiteScope` topic said the same thing in the same place.
* The `debug` topic counts the bounded waits the same way in both places it
  mentions them, and lists all of them: the two a `Scope` reports for the two
  steps behind `disposeScope` were missing from the table.
* Fix `PreviousNavigatorExtension.previous` throwing for a `NavigatorState`
  whose tree is gone. The guard was written the wrong way round — `State.context`
  asserts on an unmounted state, so asking the *context* whether it is mounted
  read it first and raised. It asks the state now, and answers `null`.
* Fix a root `NavigationNode` letting a `maybePop` out of itself. "A root node
  keeps a pop to itself" was honoured by `pop` and not by `maybePop`, which is
  the path the back arrow of an `AppBar` takes and the one a caller holding the
  `navigatorKey` takes: it would have pushed the pop out of the node and taken
  the route the node stands on with it.
* `NavigationNode.onPop` is asked wherever the press reaches the node, a node
  with no navigator above it included. It used to be skipped when there was
  nothing outside to hand a pop to, which made the promise wider than the code:
  the hook is where an application decides what its own outermost back means,
  and a root node's `true` was already documented as taking nothing.
* `PopEntry.onPopInvoked` is a no-op rather than an `UnimplementedError`. It is
  the deprecated half of the pair and the framework's own is empty; raising
  from it made the node refuse to be a `PopEntry` at all in any version that
  still calls it.
* The dartdoc of `onPop` and the `utils` topic say what the hook actually
  answers: every pop the route is *asked* about — the system back,
  `Navigator.maybePop()`, and the back arrow of an `AppBar` above the node as
  much as one inside it — and not `Navigator.pop()`, which takes the route
  rather than asking and consults no `PopEntry`.
* Fix a notification made from the build of a *descendant* being refused. The
  guard that defers such a notification asked whether *this* element was
  rebuilding, and a model touched from a descendant's build — a lazy load, a
  default filled in on first read, the ordinary user code the guard exists for
  — arrives while it is not. The bare `markNeedsBuild()` was then called on an
  element that is not the one building, which the framework refuses outright;
  in release the check lives in an assert and the same code worked, so this was
  a difference between debug and release rather than a rule. Any build defers
  it now, and a second notification arriving before the frame is over joins the
  callback already waiting instead of adding one of its own.
* An `aspect` the scope does not recognise subscribes the dependent to every
  change instead of to nothing. It can only come from a
  `dependOnInheritedElement` written by hand, and the assert that says so is
  debug-only: subscribed to everything a dependent is rebuilt more often than
  it needs, subscribed to nothing it is never rebuilt and nothing says why.
* The post-frame callback that registers a scope with its parent asks for the
  frame it needs, as the package's three other deferred callbacks already did.
  A build `runApp` drives outside a frame leaves nothing to ask for it.
* Fix a disposer running twice when two disposals of one dependency overlap.
  The hook was read at the top of the walk and cleared in the `finally` — that
  is, after the `await` — so a second `dispose()` arriving while the first was
  parked on the disposer read the same hook and ran it again: a second
  rollback, a second close, a second write. It is taken off before it is
  called now, the way `unmount` beside it always was, so "exactly once" holds
  by construction rather than by which caller arrives first.
  `ScopeAutoDependencies.dispose()` likewise hands a second caller the run
  already going rather than opening a second teardown of the same tree; once it
  is over a later call runs again, since a walk that was stopped halfway leaves
  the tree still asking to be disposed of.
* Fix a disposal that was cancelled halfway being recorded as one that
  finished. `dispose()` marked the tree done either way, so it stopped saying
  it needed disposing of — and the next `init()` replaced it, leaving
  everything the walk had never reached holding what it took with nobody able
  to reach it. Only a walk that reaches its end is done now, and a group whose
  disposal was cancelled still answers `disposalRequired`, so a second `init()`
  is refused rather than quietly losing a tree.
* Fix a dependency that registered only `unmount` saying it held nothing.
  `disposalRequired` asked about `dispose` alone, while `unmount` is the other
  documented way of holding something — a subscription, usually. A bare leaf
  standing as the root of a container therefore looked disposable, and a second
  `init()` replaced it in silence: the `unmount` of the first run was never
  called at all.
* **Breaking:** `ScreenshotReplacer` and `ListenableSelector` are `final`, the
  way the other sixty-odd public classes of the package already were. They were
  the two left as a bare `class` by oversight rather than by decision, and
  sealing them after 1.0 would be a breaking change; now it is one word.
* **Breaking:** the barrel lists what `ScopeConfig` and its parts export with
  `show` instead of naming the internals with `hide`. `hide` says what stays
  in, so the next internal helper written beside `notifyObserver` would have
  joined the public API without anybody deciding it — and a name is public from
  the moment it ships. Nothing a consumer could reach changes.
* `Progress` compares by value. It arrives in `buildOnProgress` and inside
  `AsyncScopeProgress`, both of which are compared — a selector holding one, and
  the model of a scope — and by identity two readings of the same step answered
  "changed", so a subtree rebuilt for a step that had not moved.
* `NavigationNode` gains `enabled`, for the one shape where a node cannot work
  out whether the press is its own: **several nodes on one route**, of which
  one is on screen — a node per tab of an `IndexedStack`, which builds every
  branch and shows one. A route asks each of its `PopEntry`s and calls each of
  them back, so a single back press unwound the stack of every tab at once, the
  hidden ones included. Which node is the one on screen cannot be found out
  from inside: a hidden branch answers `TickerMode.of(context)` and
  `ModalRoute.of(context)` exactly as a shown one does, and the order sibling
  nodes register in says nothing. The application knows, and writes
  `NavigationNode(enabled: i == tab, …)`. A disabled node takes no place on the
  route — not asked, not called back — while its nested navigator keeps its
  stack and goes on answering `Navigator.of(context)` from inside. Nodes nested
  one inside another never need it: an inner node registers on the page of the
  navigator above it rather than on the route both stand on. The ambiguity is
  Flutter's own — two `PopScope`s on one route are both consulted — and this is
  the same answer an application gives there. `README.md`, the `utils` topic
  and the dartdoc all carry the reasoning.
* Fix a `NavigationNode` with an `onPop` taking a system back that belonged to
  the route it stands on. A route asks its `PopEntry`s before it looks at its
  own local history, so an entry that says "do not pop" ends the matter — and
  `onPop != null` said that unconditionally. A `Scaffold` with a `drawer:`
  above the node therefore could not be closed with back at all when `onPop`
  refused, and when it agreed the user was asked "leave this screen?" about a
  press whose whole job was to close a drawer. The node now stands aside
  whenever the route will handle the press internally, which is what a drawer,
  a bottom sheet and an application's own `LocalHistoryEntry` all look like.
* Fix `disposeScopeTimeout` expiring on a `Scope` skipping the disposal of its
  dependency container entirely. The teardown put one limit around
  `disposeScope()`, and for a `Scope` that method is two steps — the state's own
  asynchronous teardown and then the container's. A state that never finished
  therefore spent the whole limit, the wait was given up on, and what it gave up
  on was both steps: the `scopeKey` came back on time and every dependency
  stayed held with nothing left to release it. The `Scope` topic described the
  two as separate steps and promised that "a failure in one is never a reason to
  skip what comes behind it" — which was true of a failure and not of a hang.
  The two are now bounded one each. A teardown where both hang reports two
  expiries, and the topic says so.
* Fix `close()` over a subtree that can never be painted — inside an `Offstage`,
  or the unselected branch of an `IndexedStack` — leaving that subtree standing.
  `ScreenshotReplacer` gives up after `maxRetries` frames and reports that the
  screenshot is no longer pending, which releases the barrier `close()` waits
  on; it used to keep the child in place all the same. The scope then tore
  itself down under a ready subtree that was still mounted: the scopes below it
  stayed registered, this one waited out its whole `waitForChildrenTimeout` for
  a child nobody had taken away, and released what that child was still reading.
  Giving up now takes the child away too, which is what the report is for —
  with no image to put there, what takes its place is nothing.
* The `LiteScope` topic no longer promises that the ready branch waits for
  `initStateAsync()`. It cannot: the state is created by the ready branch, so
  by the time its asynchronous initialization can begin, that branch has
  already built. The topic said the opposite in two places, and the package's
  own demo was already working around it with an `isInitialized` check. Both
  are corrected, the dartdoc of `initStateAsync` now says what does and does
  not wait for it, and both places name `isInitialized` and `onInitialized` as
  the two halves of the answer. No behaviour changed — the promise did.
* `select` and `listen: true` are allowed from the builder of a `LayoutBuilder`,
  an `OrientationBuilder` or a `SliverLayoutBuilder`. Those run from
  `performLayout`, inside a build of their own element, and what they return is
  that element's subtree — but a `RenderObjectElement` raises `debugDoingBuild`
  for `performRebuild` alone, so the assertion behind the "only from a build"
  rule refused a working and common pattern, and refused it in debug only. The
  assertion now also accepts a layout callback. It still refuses
  `didChangeDependencies`, except for a dependent that is itself under a layout
  callback, which is the one case the two cannot be told apart in.
* Fix a second `ScopeReady` from a `Scope`'s own `initDependencies` replacing
  the container before anything could refuse it. The field was assigned inside
  the `map` the family wraps the initialization in, one step ahead of the
  "already initialized" check in the layer above — `map` runs as the event goes
  past, `asyncMap` only after it. The model stayed as it was and the dependents
  heard nothing, but the container the scope had been using was gone from the
  field: the teardown unmounted and disposed of the newcomer, and what the
  scope had actually been running on was left with nobody to release it. The
  second `ready` is now refused where the assignment is, which is where the
  neighbouring `AsyncDataScope` has always refused it.
* Fix two `ScopeAutoDependencies.init()` runs overlapping. A second `init()` on
  a live tree was already refused, but the question asked was whether the tree
  had left `ScopeDependencyInitial` — and a tree that is initializing right now
  has not: that state is set at the very end of the run. A call arriving while
  the first was parked on an `await` was therefore handed the same tree and
  started it again. Each dependency has one `ScopeDependencyHandle`, so the
  second run replaced it along with the `unmount` and `dispose` the first had
  registered, and whatever that run had already acquired was left with nothing
  to release it; worse, the second run's own teardown then tore the tree down
  under the first. Both `ScopeAutoDependencies.init()` and
  `ScopeDependency.init()` now refuse a call that arrives while one is running,
  the second because a dependency tree driven by hand never passes the first.
* Fix a scope frozen on an `ErrorWidget` for the rest of its life after one
  failed build. A rebuild made for a notification alone hands back what the
  last real build produced and leaves the child element as it is — which needs
  there to have been a real build. When the first one threw, the boundary above
  put an `ErrorWidget` in the subtree's place and the cache stayed empty: every
  notification after that built a fresh subtree, handed it to an `updateChild`
  that kept the `ErrorWidget` instead, and filled the cache with what it had
  just thrown away, so the next notification did not even build. Only a rebuild
  from the parent could bring the scope back. A rebuild with nothing cached is
  no longer treated as notify-only. This is the layer every family is built on,
  so it applies to all nine.
* Fix `close()` never completing when the build that starts it failed. The
  barrier `close()` waits on is released by the `ScreenshotReplacer` that the
  closing build mounts, so anything that stops that build from finishing was a
  teardown that never began at all — not four stages skipped, but the whole of
  it, the `scopeKey` and the registration with the parent included, while
  Flutter's own `State.dispose` had already run under the `ErrorWidget`. The
  closing build is now guarded and releases the barrier before the failure goes
  on to the boundary above.
  The reachable trigger was the package's own: the ready branch was wrapped in
  a bare `Stack`, which resolves its alignment through a `Directionality`
  *above* itself, and a scope at the root of the application builds the
  `MaterialApp` inside its own branches — so every `Directionality` in the tree
  is below that point and the first rebuild after `close()` threw while the
  `Stack` was being mounted. That `Stack` now aligns with `Alignment.topLeft`,
  which needs none; nothing is aligned by it either way. The `LiteScope` topic
  says both, and says that the default closing overlay reads the theme above
  the scope, which for such a root scope is `ThemeData.fallback()`.
* `ScopeController.performDispose()` runs `dispose` even when `onUnmount`
  threw. The two stages were chained, so a synchronous half that failed left
  everything the controller had taken held — and `_disposeCompleter` was
  installed by then, so a second `performDispose()` handed back the failed run
  instead of picking the teardown up. They are now guarded apart, the way the
  four-stage teardown of a scope guards its own, and the first failure is
  passed on once both are over. The path this is reached on is the one where
  `init` failed: everywhere else the scope has run `onUnmount` itself already,
  and `performDispose` found it done.
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
  reformat the package for no gain. Superseded later in this same release: once
  `logger_builder` 0.6.1 and `ansi_escape_codes` 4.0.1 let `meta` back down to
  `^1.15.0`, nothing external held 3.29 any more and the floor returned to
  `>=3.27.0`.
* `meta` is no longer a dependency: nothing under `lib/` imports it. A single
  test utility does, so it is a dev dependency now.
* [breaking changes] An expired `waitForChildren` now drops the children it
  was awaiting, so `hasChildren` and `childrenCount` fall to zero for them.
  Children registered while the wait was already running are kept.
* The dartdoc of `ScopeConfig.defaultScopeKeyTimeout` and
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
  `initScope()` raising on the spot, or the missing-`AsyncScopeCoordinator`
  error of a scope with a `scopeKey`, left the scope waiting for its own
  initialization forever. It never unregistered from its parent, so the parent
  burned its whole `waitForChildrenTimeout` on a scope that was already gone,
  and neither of them was ever disposed of. The failure is still reported the
  same way, and a scope whose initialization never happened is still not
  disposed of. The same failure in `LiteScopeCoreState.initStateAsync()` no longer
  keeps `close()` waiting forever either.
* Fix a failure raised after `initScope()` had already reached
  `AsyncScopeReady` crashing with `Bad state: Future already completed`
  instead of being reported: the stream's error handler completed the
  initialization completer a second time, and that crash replaced the failure
  it was handling, so the real error reached nobody. Such a failure is now
  reported through `FlutterError.reportError` (library `scopo`) and the scope
  stays ready — it is no longer flipped into `AsyncScopeError`, which would
  have replaced the widgets already on screen with `buildOnError` while
  `disposeScope()` still ran. The `already initialized` diagnostic now checks
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
  to `initScope()`, and the disposal can only cancel an initialization through
  that subscription — so a disposal starting inside that window had nothing to
  cancel, and the `mounted` guard on the far side of the await says nothing
  about a `close()`, which keeps the element mounted on purpose. The scope
  went on to subscribe once the key was granted and to acquire resources it
  would never release, since a scope whose disposal has already passed the
  `disposeScope()` decision does not run it. The initialization now also stops
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
* Base the disposeScope() decision on successful initialization instead of
  the applied model state (resources are now disposed of when the element
  is removed in the init-completion frame).
* Guard AsyncScope post-frame callbacks with `mounted`.
* Log dependency disposal errors instead of swallowing them.
* Fix unbalanced parenthesis in `AsyncScopeError.toString()`.
* Add `repository`, `issue_tracker` and `topics` to pubspec.
* [breaking changes] Tighten the SDK constraints to Flutter `>=3.27.0` (was
  `>=1.17.0`) and Dart `^3.6.0` (was `^3.2.0`) — the floor the package
  actually requires, since it calls `Color.withValues`. This is where 0.10.0
  ends up after a detour: the floor went to `>=3.29.0` in the middle of the
  release because `>=3.27.0` would not resolve, and came back once the
  dependency that stopped it gave up the constraint. The two entries above say
  why it moved and what moving it back cost.
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
