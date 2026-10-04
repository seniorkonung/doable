import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation, TagAssignment;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import 'package_consumers_test_support.dart';

/// Пакеты отметки избранного и её снятия на настоящем хранилище: открытые
/// представления без поиска отметку не показывают и после изменения только
/// отметки сохраняют состав, параметры и позицию.
///
/// Граф фикстуры: связи 101 (1→2), 102 (2→3), 103 (1→4), 104 (1→5),
/// дневной выбор 201 от 1 к 3 по пути 101, 102 и отдельное намерение 6.
/// Намерение 3 наблюдают потребители выбора 201, связи 102 и самого
/// намерения; намерение 6 не наблюдает никто.
void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late ProviderContainer container;
  late GraphCommandCoordinator coordinator;
  late PackageConsumerProbes probes;

  final observed = durabilityIntention(3);
  final isolated = durabilityIntention(6);
  final observedRelation = durabilityRelation(102);
  final unobservedRelation = durabilityRelation(104);
  final choice = durabilityChoice(201);

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase());
    await database.open();
    await seedDurabilityGraph(database);
    await database.customStatement(
      '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, 'Намерение 6', 0, 0, 1, 1)''',
      [durabilityUuid(6)],
    );
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 30),
      diagnostics,
      dailyChoiceIdGenerator: FixedChoiceIds(choice),
      choicePathStepIdGenerator: SequentialStepIds(301),
    );
    expect(
      await repository.execute(durabilityCreate()),
      isA<GraphCommandSucceeded>(),
    );

    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (retryCount, error) => null,
    );
    coordinator = container.read(graphCommandCoordinatorProvider.notifier);
    probes = PackageConsumerProbes(container, repository, coordinator)
      ..watchIntention(observed, observes: true)
      ..watchIntention(durabilityIntention(5), observes: false)
      ..watchDailyChoice(choice, observes: true)
      ..watchRelation(observedRelation, observes: true)
      ..watchRelation(unobservedRelation, observes: false)
      ..watchSelectedRelations(
        SelectedRelationsQuery(
          intentionId: durabilityIntention(2),
          relationIds: [observedRelation],
        ),
        observes: true,
      )
      ..watchSelectedRelations(
        SelectedRelationsQuery(
          intentionId: durabilityIntention(1),
          relationIds: [unobservedRelation],
        ),
        observes: false,
      )
      ..intentionDetails(observed, observes: true)
      ..intentionDetails(durabilityIntention(5), observes: false)
      ..neighborhood(observed, observes: true)
      ..neighborhood(durabilityIntention(5), observes: false)
      ..relationDetails(observedRelation, observes: true)
      ..relationDetails(unobservedRelation, observes: false)
      ..dailyChoiceCatalog()
      ..dailyChoiceDetails(choice)
      ..choicePathSuggestions(ChoicePathSuggestionsForAction(observed));
    await settlePackageConsumersUntil(
      () => probes.allLoaded,
      diagnostics: probes.describe,
    );
    // Выбор фильтра каталога дневных выборов не должен пострадать от пакета.
    container
        .read(dailyChoiceCatalogViewModelProvider.notifier)
        .selectCompletion(true);
    await settlePackageConsumersUntil(
      () => probes.allLoaded && probes.dailyCatalogSelected,
      diagnostics: probes.describe,
    );
  });

  tearDown(() async {
    await probes.dispose();
    await coordinator.shutdown();
    container.dispose();
    await database.close();
  });

  Future<IntentionCommandCompletion> run(ExistingIntentionCommand command) =>
      (coordinator.acceptExisting(
        command,
        presentationTitle: 'Намерение',
      ) as IntentionCommandAccepted).future;

  /// Подтверждённое изменение только отметки: новая ревизия с каталожной
  /// мутацией существующего намерения.
  Future<GraphRevision> runChanging(ExistingIntentionCommand command) async {
    final completion = await run(command);
    expect(
      completion.result,
      isA<ResultSuccess<IntentionCommandSuccess>>().having(
        (success) => success.value.catalogMutation,
        'каталожная мутация',
        isA<IntentionCatalogUpdated>(),
      ),
    );
    return completion.revision!;
  }

  FavoriteMark detailsMark(IntentionId id) => (container.read(
    intentionDetailsViewModelProvider(id),
  ) as IntentionDetailsLoaded).details.favoriteMark;

  test('отметка и её снятие обновляют наблюдающих потребителей один раз без '
      'смены состава, параметров и позиции', () async {
    final contentBefore = probes.visibleContent();
    final selectionBefore = probes.dailyCatalogSelection;
    final neighborhoodSelectionBefore = probes.neighborhoodSelection(observed);
    expect(detailsMark(observed), FavoriteMark.notFavorite);

    final packages = <List<Object>>[];
    for (final (command, mark) in <(ExistingIntentionCommand, FavoriteMark)>[
      (MarkIntentionFavorite(observed), FavoriteMark.favorite),
      (UnmarkIntentionFavorite(observed), FavoriteMark.notFavorite),
    ]) {
      probes.reset();
      final firstEvent = diagnostics.events.length;
      final revision = await runChanging(command);
      await settlePackageConsumersUntil(
        () => probes.observingSettledAt(revision),
        diagnostics: probes.describe,
      );
      await quiescePackageConsumers();

      for (final probe in probes.all) {
        expect(
          probe.forbiddenStates,
          isEmpty,
          reason: '${probe.name}: удаление, отказ или сброс загрузки',
        );
        if (probe.observes) {
          expect(
            probe.updates,
            1,
            reason: '${probe.name}: ровно одно обновление на пакет',
          );
          expect(
            probe.revision?.compareTo(revision),
            GraphRevisionOrder.same,
            reason: probe.name,
          );
        } else {
          expect(probe.updates, 0, reason: '${probe.name}: пакет не наблюдает');
          expect(probe.emissions, 0, reason: probe.name);
        }
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.dailyCatalogSelection, selectionBefore);
      expect(
        probes.neighborhoodSelection(observed),
        neighborhoodSelectionBefore,
      );
      // Пакет дошёл до потребителей: страница намерения показывает
      // подтверждённую отметку.
      expect(detailsMark(observed), mark);
      expect(detailsMark(durabilityIntention(5)), FavoriteMark.notFavorite);
      packages.add([
        successfulReadCounts(diagnostics, from: firstEvent),
        probes.emissions,
      ]);
    }

    // Действующий контракт: обычное изменение кратких данных того же
    // намерения. Пакет отметки вызывает у потребителей те же чтения и
    // публикации состояния.
    probes.reset();
    final firstEvent = diagnostics.events.length;
    final updateRevision = await runChanging(
      UpdateIntention(
        id: observed,
        title: 'Намерение 3',
        description: 'Уточнение',
      ),
    );
    await settlePackageConsumersUntil(
      () => probes.observingSettledAt(updateRevision),
      diagnostics: probes.describe,
    );
    await quiescePackageConsumers();
    final ordinaryReads = successfulReadCounts(diagnostics, from: firstEvent);
    expect(ordinaryReads, isNotEmpty);
    final ordinary = [ordinaryReads, probes.emissions];
    expect(packages, [ordinary, ordinary]);
  });

  test('повтор отметки без изменения не затрагивает потребителей', () async {
    final marked = await runChanging(MarkIntentionFavorite(observed));
    await settlePackageConsumersUntil(
      () => probes.observingSettledAt(marked),
      diagnostics: probes.describe,
    );
    await quiescePackageConsumers();
    final contentBefore = probes.visibleContent();
    final selectionBefore = probes.dailyCatalogSelection;

    probes.reset();
    final repeated = await run(MarkIntentionFavorite(observed));
    await quiescePackageConsumers();

    expect(
      repeated.result,
      isA<ResultSuccess<IntentionCommandSuccess>>().having(
        (success) => success.value.catalogMutation,
        'каталожная мутация',
        isA<IntentionCatalogUnchanged>(),
      ),
    );
    for (final probe in probes.all) {
      expect(probe.updates, 0, reason: probe.name);
      expect(probe.forbiddenStates, isEmpty, reason: probe.name);
    }
    expect(probes.visibleContent(), contentBefore);
    expect(probes.dailyCatalogSelection, selectionBefore);
    expect(detailsMark(observed), FavoriteMark.favorite);
    // Повтор не продвигает ревизию: состояние публикует только страница
    // самого намерения, которая отражает завершение его операции.
    expect(
      [
        for (final probe in probes.all)
          if (probe.emissions > 0) probe.name,
      ],
      ['подробности намерения 3'],
    );
  });

  test(
    'отметка ненаблюдаемого намерения не затрагивает потребителей',
    () async {
      final contentBefore = probes.visibleContent();
      final selectionBefore = probes.dailyCatalogSelection;

      probes.reset();
      final firstEvent = diagnostics.events.length;
      await runChanging(MarkIntentionFavorite(isolated));
      await quiescePackageConsumers();

      expect(successfulReadCounts(diagnostics, from: firstEvent), isEmpty);
      for (final probe in probes.all) {
        expect(probe.updates, 0, reason: probe.name);
        expect(probe.forbiddenStates, isEmpty, reason: probe.name);
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.dailyCatalogSelection, selectionBefore);
      expect(detailsMark(observed), FavoriteMark.notFavorite);
      // Реакция на пакет ненаблюдаемого намерения: только отметка ревизии
      // каталога дневных выборов, без чтений и смены содержимого.
      expect(
        [
          for (final probe in probes.all)
            if (probe.emissions > 0) probe.name,
        ],
        ['каталог дневных выборов'],
      );
    },
  );
}
