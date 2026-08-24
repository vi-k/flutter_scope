// GENERATED from `ide/scopo.code-snippets` — do not edit by hand.
//
// The skeleton `scopo-widget` inserts, with its tab stops replaced by their
// defaults, so `flutter analyze` compiles what an editor would actually paste.
// One file per skeleton: several of them declare a class of the same default
// name, which is right in an editor and a conflict in one library.
//
// The stubs stand for the types a skeleton only names. A skeleton reads a field
// of one of them in its `…Of` example, so the stub declares that field: what is
// compiled is the shape of the call, and the name is the user's to change.
//
// ignore_for_file: unreachable_from_main, prefer_const_constructors
// ignore_for_file: avoid_unused_constructor_parameters, unused_field
// ignore_for_file: unused_import

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

final class ApiConfig extends ScopeWidgetBase<ApiConfig> {
  final String apiKey;

  /// The subtree of this scope.
  final Widget Function(BuildContext context) builder;

  const ApiConfig({
    super.key,
    required this.apiKey,
    required this.builder,
  });

  static ApiConfig of(BuildContext context, {required bool listen}) =>
      ScopeWidgetBase.of<ApiConfig>(context, listen: listen);

  static V select<V>(
    BuildContext context,
    V Function(ApiConfig widget) selector,
  ) =>
      ScopeWidgetBase.select<ApiConfig, V>(context, selector);

  /// One parameter, subscribed to on its own.
  static String apiKeyOf(BuildContext context) =>
      select(context, (widget) => widget.apiKey);

  @override
  Widget build(BuildContext context) => builder(context);
}
