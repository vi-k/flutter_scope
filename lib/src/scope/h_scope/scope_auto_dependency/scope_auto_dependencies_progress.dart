part of '../../scope.dart';

/// {@category Scope}
final class ScopeAutoDependenciesProgress {
  /// The path of the dependency that has just been initialized: the names of
  /// the enclosing groups and its own name, joined with `/`.
  ///
  /// The format is the canonical one described in the `h_scope` topic — no
  /// leading slash, and an anonymous group contributes no segment.
  final String path;

  final Progress _progress;

  const ScopeAutoDependenciesProgress(this.path, this._progress);

  /// The name the dependency was declared with — the last segment of [path].
  ///
  /// This is what a caption under a progress bar usually wants; [path] tells
  /// the whole story instead.
  String get name {
    final separator = path.lastIndexOf('/');

    return separator < 0 ? path : path.substring(separator + 1);
  }

  int get number => _progress.number;
  int get total => _progress.total;
  double get progress => _progress.progress;

  @override
  String toString() => '$path ($_progress)';
}
