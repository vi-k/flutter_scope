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
  late final FakeController controller;

  HomeDependencies();

  @override
  ScopeDependency buildDependencies(void context) => sequential('', [
        dep('httpClient', (dep) async {
          httpClient = FakeUserHttpClient();
          await httpClient.init();
          dep.dispose = httpClient.close;
        }),
        concurrent('', [
          dep('bloc', (dep) async {
            final completer = Completer<void>();
            bloc = FakeBloc()..add(FakeBlocLoad());
            bloc.stream.listen((state) {
              switch (state) {
                case FakeBlocInitial():
                case FakeBlocInProgress():
                  break;
                case FakeBlocSuccess():
                  completer.complete();
                case FakeBlocError(:final error, :final stackTrace):
                  bloc.close().whenComplete(() {
                    completer.completeError(error, stackTrace);
                  });
              }
            });
            await completer.future;
            dep.dispose = bloc.close;
          }),
          dep('controller', (dep) async {
            controller = FakeController();
            await controller.init();
            dep.dispose = controller.dispose;
          }),
        ]),
      ]);

  @override
  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(seconds: 1));
    await super.dispose();
  }
}
