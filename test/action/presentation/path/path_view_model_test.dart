import 'dart:async';

import 'package:doable/src/action/application/path_candidates.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/presentation/path/path_state.dart';
import 'package:doable/src/action/presentation/path/path_view_model.dart';
import 'package:doable/src/action/presentation/path_start/path_start_picker_page.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/action_seed.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';

final class _ControlledRepository implements PersonalGraphRepository {
  final requests = <Completer<PathCandidatesResult>>[];

  @override
  Future<PathCandidatesResult> getPathCandidates(PathCandidatesQuery query) {
    final request = Completer<PathCandidatesResult>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Первая порция пути из одного корня, у которого есть «Нужно» и «Можно».
Future<PathCandidatesResult> _firstPage(ActionPath path) async {
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (db) => raw = db),
  );
  await database.open();
  addTearDown(database.close);
  seedRawGraph(raw, () {
    seedIntention(raw, seedUuid(1), 'Причина');
    seedIntention(raw, seedUuid(2), 'Продолжение');
    seedIntention(raw, seedUuid(3), 'Возможность');
    seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
    seedRelation(raw, seedUuid(102), seedUuid(1), seedUuid(3));
    raw.execute('UPDATE long_term_relations SET type = ? WHERE id = ?', [
      LongTermRelationType.can.name,
      seedUuid(102),
    ]);
  });
  final graph = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    DateTime.now,
    InMemoryDiagnosticsSink(),
  );
  return graph.getPathCandidates(
    PathCandidatesQuery(draft: path, half: LongTermRelationType.need),
  );
}

void main() {
  test(
    'числа сохраняются при чтении и отказе и сбрасываются для нового намерения',
    () async {
      final path = ActionPath([seedIntentionId(1)]);
      final result = await _firstPage(path);
      final repository = _ControlledRepository();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final provider = pathViewModelProvider(
        PathSessionKey(),
        NewActionPathPurpose(path),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      await pumpEventQueue();
      repository.requests[0].complete(result);
      await pumpEventQueue();
      final model = container.read(provider.notifier);
      final first = container.read(provider).candidates!;
      expect(first.counts!.need, 1);
      expect(first.counts!.can, 1);
      model.selectRoot(PathStartSelected(seedIntentionId(1)));
      expect(container.read(provider).candidates!.counts, same(first.counts));
      repository.requests[1].complete(result);
      await pumpEventQueue();
      model.selectHalf(LongTermRelationType.can);
      expect(container.read(provider).candidates!.counts, same(first.counts));
      repository.requests[2].complete(
        const PathCandidatesError(PathCandidatesUnavailableFailure()),
      );
      await pumpEventQueue();
      expect(container.read(provider).candidates!.counts, same(first.counts));
      final retry = model.retry();
      expect(container.read(provider).candidates!.counts, same(first.counts));
      repository.requests[3].complete(
        const PathCandidatesError(PathCandidatesUnavailableFailure()),
      );
      await retry;
      model.selectHalf(LongTermRelationType.need);
      repository.requests[4].complete(result);
      await pumpEventQueue();
      model.selectCandidate(container.read(provider).candidates!.items.single);
      expect(container.read(provider).candidates!.counts, isNull);
    },
  );

  test('«Повторить» после отказа чтения пути сохраняет числа при загрузке и повторном отказе', () async {
    final path = ActionPath([seedIntentionId(1)]);
    final result = await _firstPage(path);
    final repository = _ControlledRepository();
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final provider = pathViewModelProvider(
      PathSessionKey(),
      NewActionPathPurpose(path),
    );
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await pumpEventQueue();
    repository.requests[0].complete(result);
    await pumpEventQueue();
    final model = container.read(provider.notifier);
    final counts = container.read(provider).candidates!.counts;
    expect(counts, isNotNull);
    model.selectRoot(PathStartSelected(seedIntentionId(1)));
    repository.requests[1].complete(
      const PathCandidatesError(PathCandidatesUnavailableFailure()),
    );
    await pumpEventQueue();
    expect(
      container.read(provider).draft,
      isA<FailedPathDraft>().having(
        (draft) => draft.candidates.counts,
        'counts',
        same(counts),
      ),
    );
    final retry = model.retry();
    expect(
      container.read(provider).draft,
      isA<LoadingPathDraft>().having(
        (draft) => draft.candidates.counts,
        'counts',
        same(counts),
      ),
    );
    repository.requests[2].complete(
      const PathCandidatesError(PathCandidatesUnavailableFailure()),
    );
    await retry;
    expect(
      container.read(provider).draft,
      isA<FailedPathDraft>().having(
        (draft) => draft.candidates.counts,
        'counts',
        same(counts),
      ),
    );
  });
}
