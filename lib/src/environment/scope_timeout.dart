part of 'scope_config.dart';

/// The one value a single scope has for "wait as long as it takes".
///
/// Every timeout parameter of a scope is a `Duration?`, and all three of its
/// values were spoken for: absent or `null` means "take the default from
/// [ScopeConfig]", [Duration.zero] means "expire at once", and any other
/// [Duration] is the limit itself. [none] is the fourth, and it removes the
/// limit for that one scope — which was possible only for every scope at
/// once, by setting the matching `ScopeConfig.default…` to `null`.
///
/// ```dart
/// AsyncScope(
///   waitForChildrenTimeout: ScopeTimeout.none,
///   disposeScopeTimeout: const Duration(seconds: 5),
///   …
/// )
/// ```
///
/// It is accepted by `scopeKeyTimeout`, `disposeScopeTimeout` and
/// `waitForChildrenTimeout`, on the scopes and on `waitForChildren` — and
/// **not** by `initCancellationTimeout`, which asserts against it. A
/// cancellation waits for a generator to run out, and a generator suspended
/// on a future that never completes never does; waiting for that with no
/// limit is the hang the limit was put there to prevent.
///
/// {@category debug}
abstract final class ScopeTimeout {
  /// Wait with no limit at all, for this scope only.
  static const Duration none = _NoTimeout();
}

/// The type behind [ScopeTimeout.none].
///
/// A subtype of [Duration] rather than a magic value, so every timeout
/// parameter stays a `Duration?` and no call site has to change. The package
/// recognises it with `is`, never with `==`: [Duration] compares by value, so
/// `==` would also match a `Duration(microseconds: -1)` that some arithmetic
/// happened to produce — `deadline.difference(now)` gone negative, say — and
/// a wait meant to expire at once would silently become one that never does.
final class _NoTimeout extends Duration {
  const _NoTimeout() : super(microseconds: -1);

  /// What a report about this limit says.
  ///
  /// Without it a diagnostic would carry `-0:00:00.000001`, which names the
  /// trick rather than the meaning.
  @override
  String toString() => 'no timeout';
}

/// The limit a wait actually gets: [own] if it is one, the global [fallback]
/// if the scope did not say, and `null` — no limit at all — when either of
/// them is [ScopeTimeout.none].
///
/// `null` from a scope means "take the default"; `null` from [ScopeConfig]
/// means "no limit". The two `null`s meeting here is why a scope needed a
/// value of its own to say the second thing.
Duration? resolveTimeout(Duration? own, Duration? fallback) {
  final chosen = own ?? fallback;

  return chosen is _NoTimeout ? null : chosen;
}

/// The limit for the wait on a cancelled initialization.
///
/// Separate from [resolveTimeout] because [ScopeTimeout.none] is refused here: see
/// [ScopeTimeout]. In release, where the assert is gone, the value is treated
/// as if the scope had not given one, so a wait that cannot be unbounded
/// falls back to the default rather than running with a negative limit.
Duration? resolveCancellationTimeout(Duration? own, Duration? fallback) {
  assert(
    own is! _NoTimeout,
    'ScopeTimeout.none is not accepted by initCancellationTimeout. A '
    'cancellation waits for the initialization generator to run out, and a '
    'generator suspended on a future that never completes never does -- so '
    'an unbounded wait here is the hang the limit exists to prevent. Give a '
    'longer Duration instead, or remove the limit for every scope at once '
    'with ScopeConfig.defaultInitCancellationTimeout.',
  );

  return own is _NoTimeout ? fallback : (own ?? fallback);
}
