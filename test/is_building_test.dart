import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';
// Not exported: the counter is the package's own bookkeeping. It is read here
// directly because it is the half of the answer a release build keeps, and in
// debug `isBuilding` covers for it whether it works or not.
import 'package:scopo/src/utils/is_building.dart';

void main() {
  group('IsBuildingExtension', () {
    testWidgets('says nothing is being built while the tree is idle', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox.shrink());

      expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
      expect(SchedulerBinding.instance.isBuilding, isFalse);
    });

    testWidgets('sees a build that runs inside a frame', (tester) async {
      bool? seen;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            seen = SchedulerBinding.instance.isBuilding;

            return const SizedBox.shrink();
          },
        ),
      );

      seen = null;
      rebuild(() {});
      await tester.pump();

      expect(seen, isTrue);
    });

    // `runApp` builds the first tree exactly like this: `attachRootWidget`
    // runs from a timer, so `buildScope` walks the dirty list with no frame in
    // progress and the phase still `idle`. It is a build all the same, and
    // `markNeedsBuild` from inside it is what Flutter answers with "setState()
    // or markNeedsBuild() called during build".
    testWidgets('sees a build driven outside a frame', (tester) async {
      bool? seen;
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            seen = SchedulerBinding.instance.isBuilding;

            return const SizedBox.shrink();
          },
        ),
      );

      seen = null;
      rebuild(() {});

      expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
      tester.binding.buildOwner!.buildScope(
        tester.element(find.byType(StatefulBuilder)),
      );

      expect(seen, isTrue, reason: 'the phase alone cannot answer this one');
    });

    // The build owner keeps its flag inside an `assert`, so in release the
    // frame phase is the whole of what the framework can be asked — and a
    // build driven with no frame in progress looks there like no build at all.
    // Whatever this package builds itself it can answer for, and it does, with
    // a plain field. Read directly, since `isBuilding` would say `true` from
    // the assert-only flag whether the field was ever written or not.
    testWidgets('sees a scope of its own being rebuilt outside a frame',
        (tester) async {
      final seen = <bool>[];

      await tester.pumpWidget(
        AsyncScope(
          initScope: (context) async* {
            yield AsyncScopeReady();
          },
          disposeScope: () {},
          progressBuilder: (context, progress) => const SizedBox.shrink(),
          errorBuilder: (context, error, stackTrace, progress) =>
              const SizedBox.shrink(),
          builder: (context) {
            seen.add(scopeIsRebuilding);

            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(seen, isNotEmpty, reason: 'the ready branch was built at all');
      expect(
        seen,
        everyElement(isTrue),
        reason: 'a build of the scope is a build, and saying so must not '
            'depend on an assertion',
      );

      seen.clear();
      expect(SchedulerBinding.instance.schedulerPhase, SchedulerPhase.idle);
      final element = tester.element(find.byType(AsyncScope))..markNeedsBuild();
      tester.binding.buildOwner!.buildScope(element);

      expect(
        seen,
        [isTrue],
        reason: 'the phase says nothing about this one -- it is the build '
            '`runApp` drives, and the case the finding is about',
      );
      expect(
        scopeIsRebuilding,
        isFalse,
        reason: 'and the count is put down once the build is over',
      );
    });

    testWidgets('runOutsideFrame holds an action back until the build is over',
        (tester) async {
      final order = <String>[];
      late StateSetter rebuild;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            SchedulerBinding.instance.runOutsideFrame(() => order.add('after'));
            order.add('build');

            return const SizedBox.shrink();
          },
        ),
      );

      order.clear();
      rebuild(() {});
      tester.binding.buildOwner!.buildScope(
        tester.element(find.byType(StatefulBuilder)),
      );

      expect(order, ['build'], reason: 'not while the build is running');

      await tester.pumpAndSettle();

      expect(order, ['build', 'after']);
    });
  });
}
