import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

final class CounterModel with ChangeNotifier {
  int _count = 0;
  int get count => _count;

  void increment() {
    _count++;
    notifyListeners();
  }
}

/// Supplies a tagged local counter so routes can reveal which inherited
/// scope remains visible from their navigator.
final class CounterScope extends ScopeNotifierBase<CounterScope, CounterModel> {
  final String title;

  CounterScope({
    super.key,
    super.tag,
    required this.title,
    super.child,
  }) : super(
          create: (_) => CounterModel(),
          dispose: (model) => model.dispose(),
        );

  static String titleOf(BuildContext context, {bool listen = true}) => listen
      ? ScopeNotifierBase.select<CounterScope, CounterModel, String>(
          context,
          (context) => context.widget.title,
        )
      : ScopeNotifierBase.of<CounterScope, CounterModel>(
          context,
          listen: false,
        ).widget.title;

  static CounterModel of(BuildContext context) =>
      ScopeNotifierBase.of<CounterScope, CounterModel>(
        context,
        listen: false,
      ).model;

  static int countOf(BuildContext context) =>
      ScopeNotifierBase.select<CounterScope, CounterModel, int>(
        context,
        (context) => context.model.count,
      );

  @override
  Widget build(BuildContext context) => child;
}
