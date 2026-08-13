part of '../scope.dart';

/// {@category ScopeModel}
final class ScopeModel<M extends Object>
    extends ScopeModelBase<ScopeModel<M>, M> with _ScopeModelMixin<M> {
  @override
  final Widget Function(BuildContext context) builder;

  /// Creates a scope that owns the model [create] returns.
  ///
  /// The model is created when the scope is mounted and handed to
  /// [dispose] when it leaves the tree.
  const ScopeModel({
    super.key,
    super.tag,
    required super.create,
    required super.dispose,
    required this.builder,
  });

  /// Creates a scope over a model somebody else owns.
  ///
  /// Nothing is created and nothing is disposed of here.
  const ScopeModel.value({
    super.key,
    super.tag,
    required super.value,
    required this.builder,
  }) : super.value();

  /// The model of the nearest `ScopeModel<M>`, or `null` if there is none.
  static M? maybeOf<M extends Object>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.maybeOf<ScopeModel<M>, ScopeModelContext<ScopeModel<M>, M>>(
        context,
        listen: listen,
      )?.model;

  /// The model of the nearest `ScopeModel<M>`.
  ///
  /// Throws when there is no such scope above [context].
  static M of<M extends Object>(
    BuildContext context, {
    required bool listen,
  }) =>
      ScopeContext.of<ScopeModel<M>, ScopeModelContext<ScopeModel<M>, M>>(
        context,
        listen: listen,
      ).model;

  /// Subscribes to one value of the model and returns it.
  ///
  /// The caller is rebuilt only when that value changes.
  static V select<M extends Object, V extends Object?>(
    BuildContext context,
    V Function(M model) selector,
  ) =>
      ScopeContext.select<ScopeModel<M>, ScopeModelContext<ScopeModel<M>, M>,
          V>(
        context,
        (context) => selector(context.model),
      );
}
