part of '../scope.dart';

/// {@category ScopeModel}
abstract interface class ScopeModelContext<W extends ScopeInheritedWidget,
    M extends Object> implements ScopeContext<W> {
  @override
  W get widget;

  /// The model this scope owns.
  M get model;
}

/// {@category ScopeModel}
abstract interface class ScopeModelInheritedElement<
        W extends ScopeInheritedWidget, M extends Object>
    implements
        // ignore: avoid_implementing_value_types
        InheritedElement,
        ScopeInheritedElement<W>,
        ScopeModelContext<W, M> {
  @override
  W get widget;

  @override
  M get model;

  @override
  void init();

  @override
  void dispose();

  @override
  Widget buildChild();
}

base mixin _ScopeModelBaseMixin<M extends Object> on ScopeInheritedWidget {
  M? get value;
  bool get hasValue;
  M Function(BuildContext context)? get create;
  void Function(M model)? get dispose;

  Widget build(BuildContext context);
}

base mixin _ScopeModelMixin<M extends Object> on _ScopeModelBaseMixin<M> {
  Widget Function(BuildContext context) get builder;

  @override
  Widget build(BuildContext context) => builder(context);
}

base mixin _ScopeModelElementMixin<W extends _ScopeModelBaseMixin<M>,
    M extends Object> on InheritedElement, ScopeInheritedElement<W> {
  M? _model;

  M get model => _model ?? widget.value!;

  @override
  void init() {
    if (!widget.hasValue) {
      assert(widget.create != null);
      _model = widget.create!(this);
    }
    super.init();
  }

  @override
  void dispose() {
    super.dispose();
    assert(widget.dispose == null || _model != null);
    if ((widget.dispose, _model) case (final dispose?, final model?)) {
      dispose(model);
    }
  }

  @override
  Widget buildChild() => widget.build(this);
}
