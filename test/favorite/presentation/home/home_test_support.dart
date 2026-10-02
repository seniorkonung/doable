import 'dart:async';

import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/favorite/presentation/home/home_view_model.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Поднимает view model Главной над управляемым чтением избранного.
final class HomeHarness {
  /// [firstReadError] — исключение, которое граница бросает при запуске
  /// первоначального чтения.
  HomeHarness({Object? firstReadError}) {
    repository.nextReadError = firstReadError;
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(homeViewModelProvider, (_, _) {});
  }

  final repository = HomeTestRepository();
  late final ProviderContainer container;
  late final ProviderSubscription<HomeState> subscription;

  HomeViewModel get model => container.read(homeViewModelProvider.notifier);
  HomeState get state => container.read(homeViewModelProvider);

  /// Проводит команду намерения через координатор до опубликованного
  /// подтверждённого пакета ревизии [revision].
  ///
  /// Пакет несёт каталожную мутацию намерения команды со снимками [before] и
  /// [after]: отсутствие [after] означает физическое удаление.
  /// [activeRelationCounts] добавляет изменение счётчиков связей намерений
  /// по их номерам.
  Future<void> confirm(
    ExistingIntentionCommand command, {
    required int revision,
    required IntentionSummary before,
    required IntentionSummary? after,
    Map<int, int> activeRelationCounts = const {},
  }) async {
    final graphRevision = HomeTestRevision(revision);
    final mutation = after == null
        ? IntentionCatalogDeleted(
            revision: graphRevision,
            entry: _HomeTestEntry(before),
          )
        : IntentionCatalogUpdated(
            revision: graphRevision,
            before: _HomeTestEntry(before),
            after: _HomeTestEntry(after),
          );
    final counts = [
      for (final MapEntry(key: number, value: count)
          in activeRelationCounts.entries)
        IntentionRelationCountsChanged(
          revision: graphRevision,
          intentionId: homeTestIntentionId(number),
          counts: RelationCounts(
            activeNeedIncoming: 0,
            activeNeedOutgoing: count,
            activeCanIncoming: 0,
            activeCanOutgoing: 0,
            archivedNeedIncoming: 0,
            archivedNeedOutgoing: 0,
            archivedCanIncoming: 0,
            archivedCanOutgoing: 0,
          ),
        ),
    ];
    await _run(
      command,
      ResultSuccess(
        ConfirmedGraphResult<IntentionCommandSuccess>(
          revision: graphRevision,
          value: after == null
              ? IntentionDeleted(
                  before.id,
                  catalogMutation: mutation,
                  additionalChanges: counts,
                )
              : IntentionSaved(
                  Intention(
                    id: after.id,
                    title: after.title,
                    description: null,
                    readiness: after.readiness,
                    archiveState: after.archiveState,
                    createdAt: after.createdAt,
                    updatedAt: after.updatedAt,
                  ),
                  catalogMutation: mutation,
                  additionalChanges: counts,
                ),
        ),
      ),
    );
  }

  /// Проводит команду намерения до опубликованного отказа: подтверждённого
  /// пакета у такого завершения нет.
  Future<void> reject(ExistingIntentionCommand command) =>
      _run(command, const ResultFailure(IntentionUnavailableFailure()));

  Future<void> _run(
    ExistingIntentionCommand command,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
  ) async {
    repository.nextCommandResult = result;
    final start = container
        .read(graphCommandCoordinatorProvider.notifier)
        .acceptExisting(command, presentationTitle: 'Намерение');
    await (start as IntentionCommandAccepted).future;
    await pumpEventQueue();
  }

  void dispose() {
    subscription.close();
    container.dispose();
  }
}

/// Управляемая реализация контракта чтения избранного: каждое чтение
/// завершается тестом явно и в выбранном им порядке.
final class HomeTestRepository extends Fake implements PersonalGraphRepository {
  final reads = <Completer<FavoriteIntentionsResult>>[];

  /// Исключение, которое граница бросает вместо следующего чтения.
  Object? nextReadError;

  int get readCount => reads.length;

  @override
  Future<FavoriteIntentionsResult> getFavoriteIntentions() {
    final completer = Completer<FavoriteIntentionsResult>();
    reads.add(completer);
    final error = nextReadError;
    if (error != null) {
      nextReadError = null;
      throw error;
    }
    return completer.future;
  }

  void completeRead(
    int index, {
    List<FavoriteIntentionRow> items = const [],
    int archivedCount = 0,
    int revision = 1,
  }) => reads[index].complete(
    FavoriteIntentionsSuccess(
      FavoriteIntentionsSnapshot(
        items: items,
        archivedCount: archivedCount,
        revision: HomeTestRevision(revision),
      ),
    ),
  );

  void failRead(int index, FavoriteIntentionsReadFailure failure) =>
      reads[index].complete(FavoriteIntentionsError(failure));

  /// Результат, которым граница завершает следующую команду.
  Object? nextCommandResult;

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final result = nextCommandResult;
    nextCommandResult = null;
    return result! as GraphCommandResult<TSuccess, TFailure>;
  }

  void throwFromRead(int index, Object error) =>
      reads[index].completeError(error);
}

final class HomeTestRevision implements GraphRevision {
  const HomeTestRevision(this.number, [this.epoch = 0]);

  final int number;
  final int epoch;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    HomeTestRevision(epoch: final e) when e != epoch =>
      GraphRevisionOrder.differentEpoch,
    HomeTestRevision(number: final n) when number < n =>
      GraphRevisionOrder.older,
    HomeTestRevision(number: final n) when number > n =>
      GraphRevisionOrder.newer,
    HomeTestRevision() => GraphRevisionOrder.same,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

IntentionId homeTestIntentionId(int number) => (IntentionId.decode(
  '018f0000-0000-7000-8000-${number.toRadixString(16).padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

FavoriteIntentionRow homeTestRow(
  int number,
  String title, {
  IntentionReadiness readiness = IntentionReadiness.notReady,
  int activeRelationCount = 0,
}) => FavoriteIntentionRow(
  id: homeTestIntentionId(number),
  title: title,
  readiness: readiness,
  activeRelationCount: activeRelationCount,
);

/// Краткий снимок намерения для каталожной мутации подтверждённого пакета.
IntentionSummary homeTestSummary(
  int number,
  String title, {
  FavoriteMark favoriteMark = FavoriteMark.favorite,
  IntentionReadiness readiness = IntentionReadiness.notReady,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  int activeRelationCount = 0,
}) {
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 10, 2));
  return IntentionSummary(
    id: homeTestIntentionId(number),
    title: title,
    hasDescription: false,
    readiness: readiness,
    archiveState: archiveState,
    activeRelationCount: activeRelationCount,
    createdAt: timestamp,
    updatedAt: timestamp,
    favoriteMark: favoriteMark,
  );
}

final class _HomeTestEntry implements IntentionCatalogEntrySnapshot {
  const _HomeTestEntry(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}
