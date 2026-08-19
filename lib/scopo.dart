/// A set of tools for creating and managing scopes on Flutter. Including
/// dependency injection, asynchronous initialization and disposal.
library;

export 'src/environment/scope_config.dart' hide log, notifyObserver;
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
export 'src/utils/navigation_node/navigation_node.dart';
export 'src/utils/progress_iterator/progress_iterator.dart';
export 'src/utils/screenshot_replacer.dart';
