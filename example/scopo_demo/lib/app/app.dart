import 'package:flutter/material.dart';
import 'package:scopo/scopo.dart';

import '../common/data/fake_services/fake_analytics.dart';
import '../common/data/fake_services/fake_app_http_client.dart';
import '../common/data/fake_services/fake_service.dart';
import '../home/demos/navigation_node/counter_scope.dart';
import '../home/demos/navigation_node/navigation_node_demo.dart';
import 'app_dependencies.dart';
import 'app_error.dart';
import 'theme_manager/theme_manager.dart';

/// The root scope.
///
/// Initializes global dependencies like [FakeAppHttpClient], [FakeService], and
/// [FakeAnalytics].
final class App extends Scope<App, AppDependencies, AppState> {
  final ScopeInitCallback<String, AppDependencies> init;
  final ScopeProgressBuilder<String> progressBuilder;
  final Widget Function(BuildContext context) builder;

  const App({
    super.key,
    required this.init,
    required this.progressBuilder,
    required this.builder,
  }) : super(pauseAfterInitialization: const Duration(milliseconds: 500));

  @override
  Stream<ScopeInitState<String, AppDependencies>> initDependencies(
    BuildContext context,
  ) =>
      init(context);

  /// Provides access the scope params, i.e. to the widget [App].
  static App paramsOf(BuildContext context, {bool listen = true}) =>
      Scope.paramsOf<App, AppDependencies, AppState>(context, listen: listen);

  static V selectParam<V extends Object?>(
    BuildContext context,
    V Function(App widget) selector,
  ) =>
      Scope.selectParam<App, AppDependencies, AppState, V>(
        context,
        (widget) => selector(widget),
      );

  static AppState? maybeOf(BuildContext context) =>
      Scope.maybeOf<App, AppDependencies, AppState>(context);

  /// Provides access the scope state.
  static AppState of(BuildContext context) =>
      Scope.of<App, AppDependencies, AppState>(context);

  static V select<V extends Object?>(
    BuildContext context,
    V Function(AppState state) selector,
  ) =>
      Scope.select<App, AppDependencies, AppState, V>(
        context,
        (state) => selector(state),
      );

  Widget _wrap({
    ThemeMode mode = ThemeMode.system,
    ThemeData? light,
    ThemeData? dark,
    required Widget child,
  }) {
    return AsyncScopeCoordinator(
      child: MaterialApp(
        title: 'Scope demo',
        themeMode: mode,
        theme: light ?? StaticThemes.lightTheme,
        darkTheme: dark ?? StaticThemes.darkTheme,
        debugShowCheckedModeBanner: false,
        home: child,
      ),
    );
  }

  @override
  Widget buildOnProgress(
    BuildContext context,
    covariant String? progress,
  ) =>
      _wrap(child: progressBuilder(context, progress));

  @override
  Widget buildOnError(
    BuildContext context,
    Object error,
    StackTrace stackTrace,
    covariant String? progress,
  ) =>
      _wrap(child: AppError(error, stackTrace));

  @override
  Widget wrapState(
    BuildContext context,
    AppDependencies dependencies,
    Widget child,
  ) =>
      ThemeManager(
        keyValueService: dependencies.keyValueStorage('theme.'),
        builder: (context) {
          final themeModel = ThemeManager.of(context);

          return Directionality(
            textDirection: TextDirection.ltr,
            child: CounterScope(
              tag: 'global counter for $NavigationNodeDemo',
              title: 'Global counter above $MaterialApp',
              child: _wrap(
                mode: themeModel.mode,
                light: themeModel.lightTheme,
                dark: themeModel.darkTheme,
                child: child,
              ),
            ),
          );
        },
      );

  @override
  AppState createState() => AppState();
}

/// [AppState] is used to manage UI state and logic for [App] scope.
final class AppState extends ScopeState<App, AppDependencies, AppState> {
  @override
  Widget build(BuildContext context) {
    return App.paramsOf(context).builder(context);
  }
}
