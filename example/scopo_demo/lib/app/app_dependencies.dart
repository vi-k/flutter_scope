import 'package:scopo/scopo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../common/data/fake_services/fake_analytics.dart';
import '../common/data/fake_services/fake_app_http_client.dart';
import '../common/data/fake_services/fake_service.dart';
import '../common/data/real_services/key_value_storage.dart';
import '../utils/app_environment.dart';
import 'app.dart';

/// Dependencies for [App] scope.
///
/// They are initialized asynchronously in the [init] stream.
final class AppDependencies implements ScopeDependencies {
  final SharedPreferences _sharedPreferences;
  final FakeAnalytics analytics;
  final FakeAppHttpClient httpClient;
  final FakeService service;

  AppDependencies({
    required SharedPreferences sharedPreferences,
    required this.httpClient,
    required this.service,
    required this.analytics,
  }) : _sharedPreferences = sharedPreferences;

  KeyValueStorage keyValueStorage(String prefix) =>
      KeyValueStorage(sharedPreferences: _sharedPreferences, prefix: prefix);

  static Stream<ScopeInitState<String, AppDependencies>> init(_) async* {
    SharedPreferences? sharedPreferences;
    FakeAppHttpClient? httpClient;
    FakeService? service;
    FakeAnalytics? analytics;

    // An initialization that did not finish has to give back whatever it
    // already took. A `try`/`catch` is not enough for that: the run can end
    // in a failure, but it can also be cancelled from outside — the scope
    // leaving the tree is enough — and only a `try`/`finally` sees both. The
    // flag is how the `finally` tells the two endings apart.
    var isInitialized = false;

    try {
      yield ScopeProgress('init storage');
      sharedPreferences = await SharedPreferences.getInstance();
      await Future<void>.delayed(AppEnvironment.defaultInitPause);

      yield ScopeProgress('init analytics');
      analytics = FakeAnalytics();
      await analytics.init();

      yield ScopeProgress('init http client');
      httpClient = FakeAppHttpClient();
      await httpClient.init();

      yield ScopeProgress('init awesome service');
      service = FakeService();
      await service.init();

      yield ScopeReady(
        AppDependencies(
          sharedPreferences: sharedPreferences,
          httpClient: httpClient,
          service: service,
          analytics: analytics,
        ),
      );

      isInitialized = true;
    } finally {
      if (!isInitialized) {
        await [
          httpClient?.close(),
          service?.dispose(),
          analytics?.dispose(),
        ].nonNulls.wait;
      }
    }
  }

  @override
  void onUnmount() {}

  @override
  Future<void> dispose() async {
    // Every dependency is released at once: none of them holds another.
    await [
      httpClient.close(),
      service.dispose(),
      analytics.dispose(),
    ].wait;
  }
}
