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
/// `waitForChildrenTimeout`, on the scopes and on `waitForChildren`, and by
/// all four [ScopeConfig] defaults, where it says for the whole application
/// what `null` says there — and **not** by `initCancellationTimeout`, which
/// asserts against it. A cancellation waits for a generator to run out, and a
/// generator suspended on a future that never completes never does; waiting
/// for that with no limit is the hang the limit was put there to prevent.
/// That is a decision for the whole application, so
/// [ScopeConfig.defaultInitCancellationTimeout] does take it.
///
/// Anywhere else a [Duration] is asked for it is refused, with an assert:
/// `pauseAfterInitialization` is a stretch of time to hold the ready branch
/// back for rather than a limit on a wait, and "wait as long as it takes" has
/// nothing to say about one.
///
/// **It is recognised by its type, so it does not survive being computed
/// with.** `ScopeTimeout.none == const Duration(microseconds: -1)` is `true`
/// and `ScopeTimeout.none + Duration.zero` is an ordinary [Duration]: what
/// comes back from any arithmetic is the negative length behind the marker,
/// which a timer reads as "expire at once". The package asserts against a
/// negative limit everywhere it resolves one, so this is loud in debug rather
/// than silent — but a timeout is a value to pass on, not one to compute
/// with.
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
///
/// Every limit the package puts on a timer comes out of here, and nothing
/// negative does: see [_negativeLimit].
Duration? resolveTimeout(Duration? own, Duration? fallback) {
  final chosen = own ?? fallback;
  if (chosen is _NoTimeout) {
    return null;
  }

  assert(chosen == null || !chosen.isNegative, _negativeLimit(chosen));

  return chosen;
}

/// The limit for the wait on a cancelled initialization.
///
/// Separate from [resolveTimeout] because [ScopeTimeout.none] is refused as
/// [own]: see [ScopeTimeout]. In release, where the assert is gone, the value
/// is treated as if the scope had not given one, so a wait that cannot be
/// unbounded falls back to the default rather than running with a negative
/// limit.
///
/// [fallback] is not refused, and is resolved exactly as the other three
/// timeouts resolve theirs. The refusal above is what makes an unbounded
/// cancellation a decision for the whole application, and
/// [ScopeConfig.defaultInitCancellationTimeout] is where that decision is
/// written — as `null`, or as the [ScopeTimeout.none] that means the same
/// thing everywhere else it is accepted. Reading the marker back out of the
/// default was the one way to ask for no limit at all and be given a wait
/// that expires on its first tick.
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

  return resolveTimeout(own is _NoTimeout ? null : own, fallback);
}

/// What a refused negative limit says.
///
/// A limit is a length of time to wait, and there is no such thing as a
/// negative one: a timer given one fires on its first tick, which is
/// [Duration.zero] with extra steps. The reason the package refuses it rather
/// than rounding it up is [ScopeTimeout.none] — the one negative [Duration]
/// here means the opposite, and it is told apart by its type, so anything that
/// gives back a plain [Duration] loses it.
String _negativeLimit(Duration value) =>
    'A timeout of $value is negative, and a wait cannot be bounded by a '
    'length of time that has already passed. If this came from '
    'ScopeTimeout.none, something gave back a plain Duration on the way here '
    '-- `none + d`, `none * 2`, a `deadline.difference(now)` gone past due -- '
    'and all that is left of the marker is the negative length behind it, '
    'which a timer reads as "expire at once". Pass ScopeTimeout.none itself '
    'to remove the limit, Duration.zero to expire at once, or a Duration that '
    'is not negative to wait for it.';
