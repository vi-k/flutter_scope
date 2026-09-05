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

  static Future<AppDependencies> init(_, ScopeInitContext ctx) async {
    FakeAppHttpClient? httpClient;
    FakeService? service;
    FakeAnalytics? analytics;

    // An initialization that did not finish has to give back whatever it
    // already took, and both ways it can fail to finish arrive here as a
    // throw: a step of its own that fell over, and the cancellation, which
    // the next `ctx.progress` raises once the scope has given up. No flag is
    // needed to tell them apart from a successful run — that one leaves by
    // `return`.
    //
    // The steps themselves are called directly rather than through
    // `ctx.wait`: each of them is something this body will have to give back,
    // and `ctx.wait` ends the waiting rather than the work — a client whose
    // `init` is walked away from is a client the `catch` below would be
    // closing while it is still starting up. The pause is the one place
    // `ctx.wait` belongs: nobody needs it once the screen is gone.
    try {
      ctx.progress('init storage');
      final sharedPreferences = await SharedPreferences.getInstance();
      await ctx.wait(
        () => Future<void>.delayed(AppEnvironment.defaultInitPause),
      );

      ctx.progress('init analytics');
      analytics = FakeAnalytics();
      await analytics.init();

      ctx.progress('init http client');
      httpClient = FakeAppHttpClient();
      await httpClient.init();

      ctx.progress('init awesome service');
      service = FakeService();
      await service.init();

      return AppDependencies(
        sharedPreferences: sharedPreferences,
        httpClient: httpClient,
        service: service,
        analytics: analytics,
      );
      // ignore: avoid_catching_errors
    } on Object {
      await [
        httpClient?.close(),
        service?.dispose(),
        analytics?.dispose(),
      ].nonNulls.wait;
      rethrow;
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
