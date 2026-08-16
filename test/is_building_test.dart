import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scopo/scopo.dart';

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
