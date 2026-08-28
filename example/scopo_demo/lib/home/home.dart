import 'package:flutter/material.dart';
import 'package:navigation_node/navigation_node.dart';
import 'package:scopo/scopo.dart';

import '../app/app_error.dart';
import '../app/theme_manager/theme_manager.dart';
import '../common/data/fake_services/fake_bloc.dart';
import '../common/data/fake_services/fake_controller.dart';
import '../common/presentation/animated_progress_indicator.dart';
import '../common/presentation/sized_tab_bar.dart';
import 'demos/async_controller/async_controller_demo.dart';
import 'demos/async_data_scope/async_data_scope_demo.dart';
import 'demos/async_scope/async_scope_demo.dart';
import 'demos/deferred_closing/deferred_closing_demo.dart';
import 'demos/full_scope/scope_demo.dart';
import 'demos/lite_scope/lite_scope_demo.dart';
import 'demos/navigation_node/navigation_node_demo.dart';
import 'demos/scope_model/scope_model_demo.dart';
import 'demos/scope_notifier/scope_notifier_demo.dart';
import 'demos/scope_widget/scope_widget_demo.dart';
import 'home_dependencies.dart';

const _tabs = <(String, Widget)>[
  ('ScopeWidget', ScopeWidgetDemo()),
  ('ScopeModel', ScopeModelDemo()),
  ('ScopeNotifier', ScopeNotifierDemo()),
  ('AsyncScope', AsyncScopeDemo()),
  ('AsyncDataScope', AsyncDataScopeDemo()),
  ('AsyncControllerScope', AsyncControllerDemo()),
  ('LiteScope', LiteScopeDemo()),
  ('Scope', ScopeDemo()),
  ('Deferred closing', DeferredClosingDemo()),
  ('NavigationNode', NavigationNodeDemo()),
];

/// A child scope.
///
/// Initializes feature-specific dependencies like [FakeBloc] and
/// [FakeController].
final class Home extends Scope<Home, HomeDependencies, HomeState> {
  final ScopeInitCallback<ScopeAutoDependenciesProgress, HomeDependencies> init;
  final bool isRoot;

  const Home({
    super.key,
    super.tag,
    required this.init,
    this.isRoot = true,
  }) : super(pauseAfterInitialization: const Duration(milliseconds: 500));

  @override
  ScopeAutoDependenciesStream<HomeDependencies> initDependencies(
    BuildContext context,
  ) =>
      init(context);

  /// Provides access the scope params, i.e. to the widget [Home].
  static Home paramsOf(BuildContext context, {bool listen = true}) =>
      Scope.paramsOf<Home, HomeDependencies, HomeState>(
        context,
        listen: listen,
      );

  static V selectParam<V extends Object?>(
    BuildContext context,
    V Function(Home widget) selector,
  ) =>
      Scope.selectParam<Home, HomeDependencies, HomeState, V>(
        context,
        (widget) => selector(widget),
      );

  /// Provides access the [HomeState] and [HomeDependencies].
  static HomeState of(BuildContext context) =>
      Scope.of<Home, HomeDependencies, HomeState>(context);

  static V select<V extends Object?>(
    BuildContext context,
    V Function(HomeState state) selector,
  ) =>
      Scope.select<Home, HomeDependencies, HomeState, V>(
        context,
        (state) => selector(state),
      );

  @override
  Widget buildOnProgress(
    BuildContext context,
    covariant ScopeAutoDependenciesProgress? progress,
  ) =>
      _FakeContent(progress);

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant ScopeAutoDependenciesProgress? progress,
  ) =>
      AppError(error, stackTrace);

  @override
  Widget wrapState(
    BuildContext context,
    HomeDependencies dependencies,
    Widget child,
  ) =>
      NavigationNode(
        isRoot: isRoot,
        onPop: (context, result) async {
          await Home.of(context).close();
          return true;
        },
        child: child,
      );

  @override
  HomeState createState() => HomeState();
}

class HomeAppBar extends AppBar {
  HomeAppBar(BuildContext context, {super.key, bool withTabs = true})
      : super(
          title: const Text('scopo demo'),
          actions: [
            // The long press hangs on a `GestureDetector` rather than on
            // `IconButton.onLongPress`: that parameter arrived in Flutter 3.29
            // and the package floor is 3.27. The tooltip is a widget above the
            // detector rather than `IconButton.tooltip`, which would put a
            // `Tooltip` — a long press of its own — *below* it: the deeper
            // recognizer starts its timer first, takes the arena and the reset
            // never runs. `home_app_bar_test.dart` holds that order.
            Tooltip(
              message: 'Long tap for the system theme',
              child: GestureDetector(
                onLongPress: () {
                  ThemeManager.of(context, listen: false).resetBrightness();
                },
                child: IconButton(
                  onPressed: () {
                    ThemeManager.of(context, listen: false).toggleBrightness();
                  },
                  icon: Icon(
                    switch (ThemeManager.select(
                      context,
                      (m) => m.brightness,
                    )) {
                      Brightness.dark => Icons.light_mode,
                      Brightness.light => Icons.dark_mode,
                    },
                  ),
                ),
              ),
            ),
          ],
          bottom: withTabs
              ? SizedTabBar(
                  height: 32,
                  isScrollable: true,
                  labelStyle: Theme.of(context).textTheme.bodySmall,
                  labelColor: Theme.of(context).colorScheme.onPrimary,
                  unselectedLabelColor: Theme.of(
                    context,
                  ).colorScheme.onPrimary.withValues(alpha: 0.5),
                  tabs: _tabs.map((e) => Tab(text: e.$1)).toList(),
                )
              : null,
        );
}

/// The screen displays the progress of dependency initialization, mimicking
/// the [Home] screen.
class _FakeContent extends StatelessWidget {
  final ScopeAutoDependenciesProgress? progress;

  const _FakeContent(this.progress);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: HomeAppBar(context, withTabs: false),
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: Center(
          child: AnimatedProgressIndicator(
            value: progress?.value,
            builder: (value) {
              return CircularProgressIndicator(value: value);
            },
          ),
        ),
      ),
    );
  }
}

/// [HomeState] is used to manage UI state and logic for [Home] scope.
final class HomeState extends ScopeState<Home, HomeDependencies, HomeState> {
  var _counter = 0;
  int get counter => _counter;

  @override
  void initState() {
    super.initState();

    // What reading a dependency looks like.
    // ignore: unused_local_variable
    final controller = dependencies.fakeController;
  }

  void increment() {
    _counter++;
    notifyDependents();
  }

  void decrement() {
    _counter--;
    notifyDependents();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: HomeAppBar(context),
        body: TabBarView(
          children: _tabs.map((e) => e.$2).toList(),
        ),
      ),
    );
  }
}
