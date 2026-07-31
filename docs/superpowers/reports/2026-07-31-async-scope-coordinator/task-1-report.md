# Task 1 Report: Ядро — очереди по ключам

## What was done

Followed the brief's TDD process exactly, in `/Users/user/development/my/scopo/.claude/worktrees/coordinator`:

1. Read the existing `_AsyncScopeCoordinatorQueue` / `AsyncScopeCoordinatorEntry` in
   `lib/src/scope/e_async_scope/async_scope_coordinator.dart:109-208` to confirm the
   semantics being extracted (FIFO mutex per key, `Future.any` race of previous
   entries / self-completion / cancellation, optional timeout that lets the entry in
   anyway, queue removed from the map once empty).
2. Confirmed baseline: `flutter test` → 35 tests passed; `flutter analyze` → `No issues
   found!`.
3. **Step 1** — created `test/scope_coordination_test.dart` with the first three tests
   from the brief verbatim (first entry gets in immediately / second waits for first to
   exit / queue removed once last entry exits).
4. **Step 2** — ran `flutter test test/scope_coordination_test.dart`; got the expected
   compile failure (library doesn't exist).
5. **Step 3** — created `lib/src/scope/e_async_scope/scope_coordination.dart` with
   `KeyedAccessQueues`, `AccessEntry`, and the private `_AccessQueue`, transcribed from
   the brief (which is itself transcribed from the old private class), with the one
   deliberate semantic change: on timeout the new code calls
   `onTimeout?.call(TimeoutException(...), stackTrace)` instead of
   `FlutterError.reportError(...)` — no Flutter reporting happens in this core.
6. **Step 4** — ran `dart format` on both files (no changes needed), then re-ran the
   3 tests — all passed.
7. **Step 5** — appended the remaining 5 tests to the same `group` block, verbatim from
   the brief (ordering, cancellation, fake-async timeout, key reuse after release,
   independent keys).
8. **Step 6** — ran the full 8-test file (all passed), the Flutter-free grep, and
   `flutter analyze`. The analyzer flagged one lint (`avoid_escaping_inner_quotes`) on
   the timeout message string, which used `'...couldn\'t...'`; fixed by switching that
   literal to double quotes (`"...couldn't..."`) — see Deviations below. Re-ran
   `flutter analyze` → clean. Re-ran the full suite (`flutter test`) → 43 tests passed
   (35 baseline + 8 new).
9. **Step 7** — committed exactly the two new files with the specified message.

## Commands and output

### Baseline (before any changes)

```
$ flutter test
...
00:00 +35: All tests passed!

$ flutter analyze
Analyzing coordinator...
No issues found! (ran in 0.9s)
```

### Step 2 — failing run (library doesn't exist)

```
$ flutter test test/scope_coordination_test.dart
test/scope_coordination_test.dart:4:8: Error: Error when reading
'lib/src/scope/e_async_scope/scope_coordination.dart': No such file or directory
  import 'package:scopo/src/scope/e_async_scope/scope_coordination.dart';
         ^
test/scope_coordination_test.dart:13:22: Error: Method not found: 'KeyedAccessQueues'.
...
00:00 +0 -1: Some tests failed.
```

This matches the brief's expected failure (`Target of URI doesn't exist`) — the Dart
frontend reports it as "Error when reading ... No such file or directory" plus
downstream "Method not found" errors for the missing symbols, which is the same
root cause (the library doesn't exist yet).

### Step 4 — first three tests passing

```
$ flutter test test/scope_coordination_test.dart
00:00 +0: KeyedAccessQueues the first entry gets in immediately
00:00 +1: KeyedAccessQueues the second entry waits for the first to exit
00:00 +2: KeyedAccessQueues the queue is removed once the last entry exits
00:00 +3: All tests passed!
```

### Step 6 — all 8 tests passing

```
$ flutter test test/scope_coordination_test.dart
00:00 +0: KeyedAccessQueues the first entry gets in immediately
00:00 +1: KeyedAccessQueues the second entry waits for the first to exit
00:00 +2: KeyedAccessQueues the queue is removed once the last entry exits
00:00 +3: KeyedAccessQueues entries are let in in the order they arrived
00:00 +4: KeyedAccessQueues cancelling stops the wait but keeps the place in the queue
00:00 +5: KeyedAccessQueues a timeout reports and lets the entry in anyway
00:00 +6: KeyedAccessQueues a key can be taken again after it was released
00:00 +7: KeyedAccessQueues different keys do not block each other
00:00 +8: All tests passed!
```

Flutter-free grep:

```
$ grep -c "package:flutter" lib/src/scope/e_async_scope/scope_coordination.dart
0
```

Analyze, before and after the quoting fix:

```
$ flutter analyze
Analyzing coordinator...
   info • Unnecessary escape of '''. Try changing the outer quotes to '"' •
     lib/src/scope/e_async_scope/scope_coordination.dart:121:11 • avoid_escaping_inner_quotes
1 issue found. (ran in 1.0s)

# after switching that string literal to double quotes + dart format:
$ flutter analyze
Analyzing coordinator...
No issues found! (ran in 1.0s)
```

Full suite after the fix:

```
$ flutter test
...
00:00 +43: All tests passed!
```

(43 = 35 baseline + 8 new.)

## Deviations from the brief's code

1. **Quoting of the timeout message** (`_AccessQueue.enter`, inside the
   `on TimeoutException catch` block). The brief's code block used:

   ```dart
   '${entry._debugName} couldn\'t wait to get access to [$key]:'
   ' $previous',
   ```

   This trips the repo's `avoid_escaping_inner_quotes` lint (part of the ~150-rule
   strict set), which flags the escaped `'` inside a single-quoted string. Changed the
   outer quotes of that one literal to double quotes:

   ```dart
   "${entry._debugName} couldn't wait to get access to [$key]:"
   ' $previous',
   ```

   No semantic change — same message text, same behavior. This is exactly the kind of
   "may need formatting" adjustment the task context flagged as expected against the
   strict lint set.

2. No other deviations. `dart format` made no changes to either file beyond this fix
   (ran it before and after; 0 changed each time post-fix). The rest of the core and
   both test blocks were transcribed verbatim from the brief.

## Files touched

- Created: `lib/src/scope/e_async_scope/scope_coordination.dart`
- Created: `test/scope_coordination_test.dart`
- Not touched: `lib/src/scope/e_async_scope/async_scope_coordinator.dart` (confirmed via
  `git status --short` / `git diff --stat` showing it absent from the diff — only the
  two new files are untracked/added).

## Commit

```
efb9e6f feat: add a Flutter-free keyed access queue for scope coordination
 2 files changed, 312 insertions(+)
```
