/// A set of tools for creating and managing scopes on Flutter. Including
/// dependency injection, asynchronous initialization and disposal.
library;

// Listed rather than hidden. `hide` names what stays in, so the next internal
// helper added beside `notifyObserver` and the two resolvers would join the
// public API without anybody deciding that -- and a name is public from the
// moment it ships. The line below already says it the right way round.
export 'src/environment/scope_config.dart'
    show
        ScopeCompositeObserver,
        ScopeConfig,
        ScopeObservable,
        ScopeObserver,
        ScopePhase,
        ScopePrintObserver,
        ScopeTimeout;
export 'src/scope/scope.dart';
export 'src/utils/compare_utils.dart';
// The rebuild counter beside it is the package's own bookkeeping: written by
// `ScopeWidgetElementBase`, read by `isBuilding`, and no business of a
// consumer.
export 'src/utils/is_building.dart' show IsBuildingExtension;
export 'src/utils/listenable/listen.dart';
export 'src/utils/listenable/listenable_selector.dart';
export 'src/utils/listenable/listenable_view.dart';
export 'src/utils/listenable/state_as_notifier.dart';
export 'src/utils/progress_iterator/progress_iterator.dart';
export 'src/utils/screenshot_replacer.dart';
