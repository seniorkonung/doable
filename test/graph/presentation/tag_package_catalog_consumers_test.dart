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
import '../../support/graph_seed.dart';
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
    await seedGraph(
      database,
      () => database.customStatement(
        '''INSERT INTO intentions
         (id, title, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, 'Намерение 6', 0, 0, 1, 1)''',
        [durabilityUuid(6)],
      ),
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
      CreateTag(name: TagName.fromInput('Здоровье'), color: null),
    );
    tagId = ((created as TagCommandSucceeded).value.value as TagCreated).tag.id;

    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        packageConsumersLocalDate(),
      ],
      retry: (retryCount, error) => null,
    );
    coordinator = container.read(graphCommandCoordinatorProvider.notifier);
    probes = PackageConsumerProbes(container, repository)
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
      ..dailyChoiceDetails(choice);
    await settlePackageConsumersUntil(
      () => probes.allLoaded,
      diagnostics: probes.describe,
    );
    // Незавершённая форма и выбор фильтров не должны пострадать от пакета.
    container.read(intentionDetailsViewModelProvider(observed).notifier)
      ..beginEditing()
      ..changeTitle('Черновик названия');
    container.read(probes.dailyCatalogProvider.notifier)
      ..selectDate(durabilityChoiceDate)
      ..toggleSection(false)
      ..toggleSection(true);
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

  test('назначение и снятие тега не меняют форму, выбор и содержимое '
      'потребителей', () async {
    final contentBefore = probes.visibleContent();
    final formBefore = probes.intentionDetailsEdit(observed);
    expect(formBefore?.$1, 'Черновик названия');
    final selectionBefore = probes.dailyCatalogSelection;
    final neighborhoodSelectionBefore = probes.neighborhoodSelection(observed);

    for (final command in <TagCommand>[
      AssignTag(tagId: tagId, intentionId: observed),
      RemoveTagAssignment(tagId: tagId, intentionId: observed),
    ]) {
      probes.reset();
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
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.intentionDetailsEdit(observed), formBefore);
      expect(probes.dailyCatalogSelection, selectionBefore);
      expect(
        probes.neighborhoodSelection(observed),
        neighborhoodSelectionBefore,
      );
    }
  });

  test(
    'пакет тега ненаблюдаемого намерения не затрагивает потребителей',
    () async {
      final contentBefore = probes.visibleContent();
      final formBefore = probes.intentionDetailsEdit(observed);

      probes.reset();
      await run(AssignTag(tagId: tagId, intentionId: isolated));
      await quiescePackageConsumers();

      for (final probe in probes.all) {
        expect(probe.forbiddenStates, isEmpty, reason: probe.name);
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.intentionDetailsEdit(observed), formBefore);
    },
  );

  test(
    'создание с начальными назначениями не затрагивает потребителей',
    () async {
      final contentBefore = probes.visibleContent();
      final formBefore = probes.intentionDetailsEdit(observed);

      probes.reset();
      final completion = await (coordinator.acceptCreation(
        IntentionCreationFormKey(),
        CreateIntention.withInitialState(
          title: 'Ходить пешком',
          description: 'Каждый день',
          readiness: IntentionReadiness.ready,
          tagIds: [tagId],
        ),
      ) as IntentionCommandAccepted).future;
      expect(completion.isFailure, isFalse);
      await quiescePackageConsumers();

      for (final probe in probes.all) {
        expect(probe.forbiddenStates, isEmpty, reason: probe.name);
      }
      expect(probes.visibleContent(), contentBefore);
      expect(probes.intentionDetailsEdit(observed), formBefore);
    },
  );
}
