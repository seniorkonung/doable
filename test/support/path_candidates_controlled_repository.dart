import 'dart:async';

import 'package:doable/src/action/application/path_candidates.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';

/// Управляет завершением чтения кандидатов, сохраняя реальные данные графа.
final class PathCandidatesControlledRepository
    implements PersonalGraphRepository {
  PathCandidatesControlledRepository(this.delegate);

  final PersonalGraphRepository delegate;
  Completer<void>? gate;
  bool fail = false;

  @override
  Future<PathCandidatesResult> getPathCandidates(
    PathCandidatesQuery query,
  ) async {
    final pending = gate;
    if (pending != null) await pending.future;
    if (fail) {
      return const PathCandidatesError(PathCandidatesUnavailableFailure());
    }
    return delegate.getPathCandidates(query);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
