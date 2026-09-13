@Deprecated('Используйте graph_command_coordinator.dart.')
library;

import '../../../graph/application/graph_command_coordinator.dart' as graph;

export '../../../graph/application/graph_command_coordinator.dart';

@Deprecated('Используйте GraphCommandCoordinator.')
typedef IntentionCommandCoordinator = graph.GraphCommandCoordinator;

@Deprecated('Используйте graphCommandCoordinatorProvider.')
final intentionCommandCoordinatorProvider =
    graph.graphCommandCoordinatorProvider;
