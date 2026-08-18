/// Throws an exception when the [object] is disposed of.
///
/// [disposeMethod] is a disposal method that can only be called once for
/// a given [object].
///
/// Usage:
///
/// ```dart
/// throwIfDisposed(object, object.isDisposed, 'dispose');
/// ```
void throwIfDisposed(
  Object object,
  bool isDisposed,
  String disposeMethod,
) {
  if (isDisposed) {
    final runtimeTypeStr = '${object.runtimeType}';
    throw StateError(
      'A $runtimeTypeStr was used after being disposed.'
      ' Once you have called `$disposeMethod()` on a $runtimeTypeStr,'
      ' it can no longer be used.',
    );
  }
}

/// Assert that the [object] has not yet been disposed.
///
/// See [throwIfDisposed] for details.
///
/// Usage:
///
/// ```dart
/// assert(debugAssertNotDisposed(object, object.isDisposed, 'dispose'));
/// ```
bool debugAssertNotDisposed(
  Object object,
  bool isDisposed,
  String disposeMethod,
) {
  assert(() {
    throwIfDisposed(object, isDisposed, disposeMethod);
    return true;
  }());

  return true;
}
