import 'dart:async';

import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import 'counter_view.dart';

final class ChildScreen extends LiteScope<ChildScreen, ChildScreenState> {
  final bool withNode;

  const ChildScreen({super.key, required this.withNode});

  @override
  ChildScreenState createState() => ChildScreenState();

  @override
  Widget? buildOnWaiting(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text('Waiting…'),
      ),
    );
  }

  static ChildScreenState of(BuildContext context) {
    return LiteScope.of<ChildScreen, ChildScreenState>(context);
  }
}

final class ChildScreenState
    extends LiteScopeState<ChildScreen, ChildScreenState> {
  @override
  Future<void> disposeAsync() async {
    await Future<void>.delayed(const Duration(milliseconds: 1000));
  }

  @override
  Widget build(BuildContext context) {
    final child = Scaffold(
      appBar: AppBar(
        title: Text(
          '$ChildScreen ${params.withNode ? 'with own node' : 'without own node'}',
        ),
      ),
      body: const Padding(
        padding: EdgeInsets.all(8),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CounterView(),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );

    return params.withNode
        ? NavigationNode(
            onPop: (context, result) async {
              await ChildScreen.of(context).close();
              return true;
            },
            child: child,
          )
        : child;
  }
}
