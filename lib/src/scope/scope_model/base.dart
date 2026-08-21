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

  /// Refuses a rebuild that changes which constructor the scope was built
  /// with.
  ///
  /// The model, its disposer and -- for a notifier -- its listener all belong
  /// to the mode the scope came into being in, and it is fixed for the
  /// lifetime of the element. Switching in place has no honest answer:
  /// arriving at the owning constructor there is nothing to own, since
  /// `create` runs once and has already not run; leaving it, the model this
  /// scope made is still its to release, and the widget that says who releases
  /// it is gone.
  ///
  /// Both were silent before. `.value` to owning dereferenced a `value` that
  /// is no longer there; owning to `.value` kept the model the scope had made,
  /// ignored the one it was handed, and left nothing to ever release the
  /// first.
  ///
  /// **"Refuses" here means an assertion, and an assertion is debug-only.** In
  /// a release build the switch still happens, and it still ends the two ways
  /// above: a leaked model with a listener pointing at it, or a null check on
  /// a `value` that is gone. Nothing repairs it at runtime, because there is
  /// nothing honest to repair it with — see the paragraph above — so what a
  /// release build is left with is what the assertion is there to keep out of
  /// it. Test in debug, where it is loud.
  ///
  /// To change the mode, give the widget a different [Widget.key]: the
  /// framework then builds a new element, which reads the mode afresh and
  /// releases what the old one owned.
  @override
  void update(W newWidget) {
    assert(
      widget.hasValue == newWidget.hasValue,
      'A scope cannot change between the constructor that owns its model and '
      '`.value`. The model, its disposer and its listener belong to the mode '
      'the scope was built in, and that mode is fixed for the lifetime of the '
      'element. Give the widget a different `Widget.key` instead, so the '
      'framework builds a new element for the new mode and releases what the '
      'old one owned.',
    );
    super.update(newWidget);
  }

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
    // A `create` that threw leaves no model behind, and the disposal runs for
    // that scope too -- so a missing model here is a legitimate answer, not a
    // broken invariant.
    if ((widget.dispose, _model) case (final dispose?, final model?)) {
      dispose(model);
    }
  }

  @override
  Widget buildChild() => widget.build(this);
}
