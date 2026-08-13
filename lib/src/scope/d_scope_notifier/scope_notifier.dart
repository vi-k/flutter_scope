part of '../scope.dart';

/// {@category ScopeNotifier}
final class ScopeNotifier<M extends Listenable>
    extends ScopeNotifierBase<ScopeNotifier<M>, M> with _ScopeModelMixin<M> {
  @override
  final Widget Function(BuildContext context) builder;

  /// Creates a scope that owns the listenable [create] returns.
  const ScopeNotifier({
    super.key,
    super.tag,
    required super.create,
    required super.dispose,
    required this.builder,
  });

  /// Creates a scope over a listenable somebody else owns.
  ///
  /// A later build may hand it a different one; the subscription moves with
  /// it.
  const ScopeNotifier.value({
    super.key,
    required super.value,
    required this.builder,
  }) : super.value();

  /// The model of the nearest `ScopeNotifier<M>`, or `null` if there is none.
  static M? maybeOf<M extends Listenable>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<ScopeNotifier<M>,
          ScopeModelContext<ScopeNotifier<M>, M>>(
        context,
        listen: listen,
      )?.model;

  /// The model of the nearest `ScopeNotifier<M>`.
  ///
  /// Throws when there is no such scope above [context].
  static M of<M extends Listenable>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<ScopeNotifier<M>, ScopeModelContext<ScopeNotifier<M>, M>>(
        context,
        listen: listen,
      ).model;

  /// Subscribes to one value of the model and returns it.
  ///
  /// The caller is rebuilt on `notifyListeners`, and only when that value
  /// has changed.
  static V select<M extends Listenable, V extends Object?>(
    BuildContext context,
    V Function(M model) selector,
  ) =>
      ScopeContext.select<ScopeNotifier<M>,
          ScopeModelContext<ScopeNotifier<M>, M>, V>(
        context,
        (context) => selector(context.model),
      );
}
