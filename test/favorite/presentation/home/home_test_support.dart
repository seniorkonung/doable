import 'dart:async';

import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
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
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/in_memory_quick_creation_mode_store.dart';

/// Поднимает view model Главной над управляемым чтением избранного.
final class HomeHarness {
  /// [firstReadError] — исключение, которое граница бросает при запуске
  /// первоначального чтения.
  HomeHarness({Object? firstReadError}) {
    repository.nextReadError = firstReadError;
    container = ProviderContainer(
      overrides: [
        inMemoryQuickCreationModeOverride,
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
  GraphCommandCoordinator get coordinator =>
      container.read(graphCommandCoordinatorProvider.notifier);

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
      (coordinator) =>
          coordinator.acceptExisting(command, presentationTitle: 'Намерение'),
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
                  _intentionOf(after),
                  catalogMutation: mutation,
                  additionalChanges: counts,
                ),
        ),
      ),
    );
  }

  /// Проводит полное создание намерения [created] через координатор до
  /// опубликованного подтверждённого пакета ревизии [revision].
  ///
  /// Команда несёт готовность, отметку и теги окончательного снимка
  /// [created], а пакет повторяет настоящее создание: одна
  /// [IntentionCatalogCreated] с этим снимком и по одному факту назначения на
  /// каждый его тег, все на одной ревизии. Каждое создание принимается по
  /// собственному ключу формы, поэтому повтор вызова с тем же снимком и
  /// ревизией повторно доставляет тот же пакет.
  Future<void> create(IntentionSummary created, {required int revision}) {
    final graphRevision = HomeTestRevision(revision);
    return _run(
      (coordinator) => coordinator.acceptCreation(
        IntentionCreationFormKey(),
        CreateIntention.withInitialState(
          title: created.title,
          description: null,
          readiness: created.readiness,
          favoriteMark: created.favoriteMark,
          tagIds: [for (final tag in created.tags) tag.id],
        ),
      ),
      ResultSuccess(
        ConfirmedGraphResult<IntentionCommandSuccess>(
          revision: graphRevision,
          value: IntentionSaved(
            _intentionOf(created),
            catalogMutation: IntentionCatalogCreated(
              revision: graphRevision,
              entry: _HomeTestEntry(created),
            ),
            additionalChanges: [
              for (final tag in created.tags)
                TagAssignmentChangedChange(
                  revision: graphRevision,
                  assignment: TagAssignment(
                    tagId: tag.id,
                    intentionId: created.id,
                  ),
                  state: TagAssignmentState.assigned,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Проводит команду намерения до опубликованного отказа: подтверждённого
  /// пакета у такого завершения нет.
  Future<void> reject(ExistingIntentionCommand command) => _run(
    (coordinator) =>
        coordinator.acceptExisting(command, presentationTitle: 'Намерение'),
    const ResultFailure(IntentionUnavailableFailure()),
  );

  Future<void> _run(
    IntentionCommandStart Function(GraphCommandCoordinator coordinator) accept,
    Result<ConfirmedGraphResult<IntentionCommandSuccess>> result,
  ) async {
    repository.nextCommandResult = result;
    final start = accept(coordinator);
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

  /// Результат, которым граница завершает следующую команду намерения.
  Object? nextCommandResult;

  /// Исполненные команды, кроме перестановок, в порядке поступления.
  final commands = <Object>[];

  /// Полный порядок избранных, включая архивированные, над которым граница
  /// исполняет перестановку.
  FavoriteOrder favoriteOrder = FavoriteOrder(const []);

  /// Принятые перестановки; каждая завершается тестом явно.
  final moves = <HomeTestMove>[];

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command case final MoveFavoriteIntention moveCommand) {
      final move = HomeTestMove(moveCommand);
      moves.add(move);
      return await move._result.future
          as GraphCommandResult<TSuccess, TFailure>;
    }
    commands.add(command);
    final result = nextCommandResult;
    nextCommandResult = null;
    return result! as GraphCommandResult<TSuccess, TFailure>;
  }

  /// Исполняет перестановку [index] над [favoriteOrder] по контракту
  /// `MoveFavoriteIntention`: новый порядок вычисляет функция правила
  /// [moveInFavoriteOrder], а фактическая перестановка подтверждается на
  /// ревизии [revision]. Успех без изменения подтверждает прежний порядок на
  /// [revision] — текущей ревизии границы.
  void completeMove(int index, {required int revision}) {
    final command = moves[index].command;
    final graphRevision = HomeTestRevision(revision);
    final FavoriteOrderCommandResult result;
    switch (moveInFavoriteOrder(
      favoriteOrder,
      intentionId: command.intentionId,
      placement: command.placement,
    )) {
      case FavoriteOrderMoveApplied(:final order):
        favoriteOrder = order;
        result = FavoriteOrderCommandSucceeded(
          ConfirmedGraphResult(
            revision: graphRevision,
            value: FavoriteOrderMoved(
              FavoriteOrderChangedChange(revision: graphRevision),
            ),
          ),
        );
      case FavoriteOrderMoveWithoutChange():
        result = FavoriteOrderCommandSucceeded(
          ConfirmedGraphResult(
            revision: graphRevision,
            value: FavoriteOrderUnchanged(
              FavoriteOrderUnchangedChange(revision: graphRevision),
            ),
          ),
        );
      case final FavoriteOrderMoveRejected rejection:
        result = FavoriteOrderCommandFailed(
          FavoriteOrderCommandFailure.rejected(rejection),
        );
    }
    moves[index]._result.complete(result);
  }

  /// Завершает перестановку [index] отказом [failure] без записи.
  void failMove(int index, FavoriteOrderCommandFailure failure) =>
      moves[index]._result.complete(FavoriteOrderCommandFailed(failure));

  void throwFromMove(int index, Object error) =>
      moves[index]._result.completeError(error);

  void throwFromRead(int index, Object error) =>
      reads[index].completeError(error);
}

/// Перестановка, принятая тестовой границей и ожидающая завершения тестом.
final class HomeTestMove {
  HomeTestMove(this.command);

  final MoveFavoriteIntention command;
  final _result = Completer<FavoriteOrderCommandResult>();
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

/// Полный порядок избранных тестовой границы из номеров намерений: номера из
/// [archived] архивированы и на Главной скрыты.
FavoriteOrder homeTestOrder(
  List<int> numbers, {
  Set<int> archived = const {},
}) => FavoriteOrder([
  for (final number in numbers)
    FavoriteOrderEntry(
      intentionId: homeTestIntentionId(number),
      archiveState: archived.contains(number)
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
    ),
]);

/// Краткий снимок намерения для каталожной мутации подтверждённого пакета.
IntentionSummary homeTestSummary(
  int number,
  String title, {
  FavoriteMark favoriteMark = FavoriteMark.favorite,
  IntentionReadiness readiness = IntentionReadiness.notReady,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  int activeRelationCount = 0,
  List<Tag> tags = const [],
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
    tags: tags,
    favoriteMark: favoriteMark,
  );
}

Tag homeTestTag(int number, String name) => Tag(
  id: (TagId.decode(
    '018f0000-0000-7000-9000-${number.toRadixString(16).padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);

/// Намерение подтверждённой команды с полями снимка [summary].
Intention _intentionOf(IntentionSummary summary) => Intention(
  id: summary.id,
  title: summary.title,
  description: null,
  readiness: summary.readiness,
  archiveState: summary.archiveState,
  createdAt: summary.createdAt,
  updatedAt: summary.updatedAt,
);

final class _HomeTestEntry implements IntentionCatalogEntrySnapshot {
  const _HomeTestEntry(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}
