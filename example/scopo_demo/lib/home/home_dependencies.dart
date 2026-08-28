import 'dart:async';

import 'package:scopo/scopo.dart';

import '../common/data/fake_services/fake_bloc.dart';
import '../common/data/fake_services/fake_controller.dart';
import '../common/data/fake_services/fake_user_http_client.dart';
import 'home.dart';

/// Dependencies for [Home] scope.
final class HomeDependencies
    extends ScopeAutoDependencies<HomeDependencies, void> {
  late final FakeUserHttpClient httpClient;
  late final FakeBloc bloc;
  late final FakeController fakeController;

  HomeDependencies();

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        // Acquire, register, then carry on: the disposer goes on the handle
        // before the first `await`, so there is no window in which the client
        // exists and nothing knows how to close it. Registered after the
        // `await`, as this used to be, a failing `init()` left it created and
        // unreachable -- and `AppEnvironment.errorOnFakeUserHttpClientInit`
        // is a switch this demo ships, so that was the path it demonstrated.
        dep('httpClient', (dep) async {
          httpClient = FakeUserHttpClient();
          dep.dispose = httpClient.close;
          await httpClient.init();
        }),
        concurrent('', [
          dep('bloc', (dep) async {
            final completer = Completer<void>();
            bloc = FakeBloc()..add(FakeBlocLoad());
            dep.dispose = bloc.close;
            bloc.stream.listen((state) {
              switch (state) {
                case FakeBlocInitial():
                case FakeBlocInProgress():
                  break;
                case FakeBlocSuccess():
                  completer.complete();
                // Closing it here as well would be closing it twice: the
                // handle above already knows how, and a failed step is
                // disposed of like any other -- what decides that is whether
                // the initializer took anything, not how it ended.
                case FakeBlocError(:final error, :final stackTrace):
                  completer.completeError(error, stackTrace);
              }
            });
            await completer.future;
          }),
          dep('controller', (dep) async {
            fakeController = FakeController();
            dep.dispose = fakeController.dispose;
            await fakeController.init();
          }),
        ]),
      ]);

  @override
  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await super.dispose();
  }
}
