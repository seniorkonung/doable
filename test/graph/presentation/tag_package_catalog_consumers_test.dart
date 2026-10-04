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
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import 'package_consumers_test_support.dart';

/// Пакеты команд тегов на настоящем хранилище: каталожная мутация команды
/// назначения — изменение кратких данных существующего намерения для всех
/// потребителей вне поиска.
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
  late TagId tagId;
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
    final created = await repository.execute(
      CreateTag(TagName.fromInput('Здоровье')),
    );
    tagId = ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;

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
    // Незавершённая форма и выбор фильтра не должны пострадать от пакета.
    container.read(intentionDetailsViewModelProvider(observed).notifier)
      ..beginEditing()
      ..changeTitle('Черновик названия');
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

  Future<GraphRevision> run(TagCommand command) async {
    final start = switch (command) {
      final AssignTag assign => coordinator.acceptTagAssign(assign),
      final RemoveTagAssignment remove => coordinator.acceptTagRemoveAssignment(
        remove,
      ),
      _ => throw ArgumentError.value(command, 'command'),
    };
    final completion = await (start as TagCommandAccepted).future;
    final confirmed = completion.confirmedResult;
    expect(confirmed, isA<TagCommandSucceeded>());
    expect(
      (confirmed as TagCommandSucceeded).value.value,
      isA<TagAssignmentChanged>(),
    );
    return confirmed.value.revision;
  }

  test('назначение и снятие тега обновляют наблюдающих потребителей один раз '
      'без смены формы, выбора и содержимого', () async {
    final contentBefore = probes.visibleContent();
    final formBefore = probes.intentionDetailsEdit(observed);
    expect(formBefore?.$1, 'Черновик названия');
    final selectionBefore = probes.dailyCatalogSelection;
    final neighborhoodSelectionBefore = probes.neighborhoodSelection(observed);

    final packages = <List<Object>>[];
    for (final command in <TagCommand>[
      AssignTag(tagId: tagId, intentionId: observed),
      RemoveTagAssignment(tagId: tagId, intentionId: observed),
    ]) {
      probes.reset();
      final firstEvent = diagnostics.events.length;
      final revision = await run(command);
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
      expect(probes.intentionDetailsEdit(observed), formBefore);
      expect(probes.dailyCatalogSelection, selectionBefore);
      expect(
        probes.neighborhoodSelection(observed),
        neighborhoodSelectionBefore,
      );
      packages.add([
        successfulReadCounts(diagnostics, from: firstEvent),
        probes.emissions,
      ]);
    }

    // Действующий контракт: обычное изменение кратких данных того же
    // намерения. Пакет команды тега вызывает у потребителей те же чтения
    // и публикации состояния.
    probes.reset();
    final firstEvent = diagnostics.events.length;
    final updated = await (coordinator.acceptExisting(
      UpdateIntention(
        id: observed,
        title: 'Намерение 3',
        description: 'Уточнение',
      ),
      presentationTitle: 'Намерение 3',
    ) as IntentionCommandAccepted).future;
    final updateRevision = updated.revision!;
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

  test(
    'пакет тега ненаблюдаемого намерения не затрагивает потребителей',
    () async {
      final contentBefore = probes.visibleContent();
      final formBefore = probes.intentionDetailsEdit(observed);

      probes.reset();
      final firstEvent = diagnostics.events.length;
      await run(AssignTag(tagId: tagId, intentionId: isolated));
      await quiescePackageConsumers();

      expect(successfulReadCounts(diagnostics, from: firstEvent), isEmpty);
      for (final probe in probes.all) {
        expect(probe.updates, 0, reason: probe.name);
        expect(probe.forbiddenStates, isEmpty, reason: probe.name);
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.intentionDetailsEdit(observed), formBefore);
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

  test('факты начальных назначений в пакете создания действуют на '
      'потребителей так же, как минимальное создание', () async {
    final contentBefore = probes.visibleContent();
    final formBefore = probes.intentionDetailsEdit(observed);

    Future<List<Object>> create(CreateIntention command) async {
      probes.reset();
      final firstEvent = diagnostics.events.length;
      final completion = await (coordinator.acceptCreation(
        IntentionCreationFormKey(),
        command,
      ) as IntentionCommandAccepted).future;
      expect(completion.isFailure, isFalse);
      await quiescePackageConsumers();
      for (final probe in probes.all) {
        expect(probe.updates, 0, reason: probe.name);
        expect(probe.forbiddenStates, isEmpty, reason: probe.name);
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.intentionDetailsEdit(observed), formBefore);
      return [
        successfulReadCounts(diagnostics, from: firstEvent),
        probes.emissions,
      ];
    }

    final minimal = await create(
      const CreateIntention(title: 'Ходить пешком', description: null),
    );
    final full = await create(
      CreateIntention.withInitialState(
        title: 'Ходить пешком',
        description: 'Каждый день',
        readiness: IntentionReadiness.ready,
        favoriteMark: FavoriteMark.favorite,
        tagIds: [tagId],
      ),
    );
    expect(full, minimal);
  });
}
