import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_state.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation, TagAssignment;
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_state.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/relation_neighborhood_view_model.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

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
  late _Probes probes;

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
    probes = _Probes(container, repository, coordinator)
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
    await _settleUntil(() => probes.allLoaded, diagnostics: probes.describe);
    // Незавершённая форма и выбор фильтра не должны пострадать от пакета.
    container.read(intentionDetailsViewModelProvider(observed).notifier)
      ..beginEditing()
      ..changeTitle('Черновик названия');
    container
        .read(dailyChoiceCatalogViewModelProvider.notifier)
        .selectCompletion(true);
    await _settleUntil(
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
      await _settleUntil(
        () => probes.observingSettledAt(revision),
        diagnostics: probes.describe,
      );
      await _quiesce();

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
        _readCounts(diagnostics, from: firstEvent),
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
    await _settleUntil(
      () => probes.observingSettledAt(updateRevision),
      diagnostics: probes.describe,
    );
    await _quiesce();
    final ordinaryReads = _readCounts(diagnostics, from: firstEvent);
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
      await _quiesce();

      expect(_readCounts(diagnostics, from: firstEvent), isEmpty);
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
}

/// Номер объекта фикстуры по его UUID.
int _label(String uuid) => int.parse(uuid.split('-').last, radix: 16);

Map<Type, int> _readCounts(
  InMemoryDiagnosticsSink diagnostics, {
  required int from,
}) {
  final counts = <Type, int>{};
  for (final event in diagnostics.events.skip(from)) {
    if (event
        case TagCommandDiagnosticsEvent() ||
            IntentionCommandDiagnosticsEvent()) {
      continue;
    }
    if (event.status is! DiagnosticsSucceeded) continue;
    counts.update(event.runtimeType, (count) => count + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// Наблюдение одного потребителя с момента последнего сброса: число
/// опубликованных новых ревизий, всех публикаций и запрещённых состояний.
final class _Probe {
  _Probe(this.name, {required this.observes});

  final String name;
  final bool observes;
  var updates = 0;
  var emissions = 0;
  final forbiddenStates = <Object>[];
  GraphRevision? revision;
  bool loaded = false;
  Object? Function() content = () => null;

  void reset() {
    updates = 0;
    emissions = 0;
    forbiddenStates.clear();
  }
}

final class _Probes {
  _Probes(this._container, this._repository, this._coordinator);

  final ProviderContainer _container;
  final DriftPersonalGraphRepository _repository;
  final GraphCommandCoordinator _coordinator;
  final all = <_Probe>[];
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _providerSubscriptions = <ProviderSubscription<Object?>>[];
  final _notifiers = <ChangeNotifier>[];

  _Probe _add(String name, {required bool observes}) {
    final probe = _Probe(name, observes: observes);
    all.add(probe);
    return probe;
  }

  void watchIntention(IntentionId id, {required bool observes}) {
    final probe = _add(
      'наблюдатель намерения ${_label(id.toCanonicalString())}',
      observes: observes,
    );
    _subscriptions.add(
      _repository.watchIntention(id).listen((result) {
        probe
          ..updates += 1
          ..emissions += 1
          ..loaded = true;
        switch (result) {
          case ResultSuccess(:final value):
            probe
              ..revision = value.revision
              ..content = () => _intentionContent(value.value);
            if (value.value == null) probe.forbiddenStates.add(result);
          case ResultFailure():
            probe.forbiddenStates.add(result);
        }
      }),
    );
  }

  void watchDailyChoice(DailyChoiceId id, {required bool observes}) {
    final probe = _add('чтение дневного выбора', observes: observes);
    _subscriptions.add(
      _repository.watchDailyChoice(id).listen((result) {
        probe
          ..updates += 1
          ..emissions += 1
          ..loaded = true;
        switch (result) {
          case GraphResultSuccess(:final value) when value.value != null:
            probe
              ..revision = value.revision
              ..content = () => _dailyChoiceContent(value.value!);
          case GraphResultSuccess() || GraphResultFailure():
            probe.forbiddenStates.add(result);
        }
      }),
    );
  }

  void watchRelation(LongTermRelationId id, {required bool observes}) {
    final probe = _add(
      'подробности связи ${_label(id.toCanonicalString())}',
      observes: observes,
    );
    _subscriptions.add(
      _repository.watchRelation(id).listen((result) {
        probe
          ..updates += 1
          ..emissions += 1
          ..loaded = true;
        switch (result) {
          case GraphResultSuccess(:final value) when value.value != null:
            probe
              ..revision = value.revision
              ..content = () => _relationContent(value.value!);
          case GraphResultSuccess() || GraphResultFailure():
            probe.forbiddenStates.add(result);
        }
      }),
    );
  }

  void watchSelectedRelations(
    SelectedRelationsQuery query, {
    required bool observes,
  }) {
    final probe = _add(
      'выбранные связи ${_label(query.intentionId.toCanonicalString())}',
      observes: observes,
    );
    _subscriptions.add(
      _repository.watchSelectedRelations(query).listen((result) {
        probe
          ..updates += 1
          ..emissions += 1
          ..loaded = true;
        switch (result) {
          case SelectedRelationsReadSuccess(:final value):
            probe
              ..revision = value.revision
              ..content = () => _selectedContent(value.value);
          default:
            probe.forbiddenStates.add(result);
        }
      }),
    );
  }

  void intentionDetails(IntentionId id, {required bool observes}) {
    final probe = _add(
      'подробности намерения ${_label(id.toCanonicalString())}',
      observes: observes,
    );
    void observe(IntentionDetailsState state) {
      switch (state) {
        case IntentionDetailsLoaded():
          probe
            ..loaded = true
            ..content = () => _intentionContent(state.details);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
        case IntentionDetailsLoading():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case IntentionDetailsNotFound() ||
            IntentionDetailsUnavailable() ||
            IntentionDetailsCorruption() ||
            IntentionDetailsUnexpected() ||
            IntentionDetailsDeleted():
          probe.forbiddenStates.add(state);
      }
    }

    _providerSubscriptions.add(
      _container.listen<IntentionDetailsState>(
        intentionDetailsViewModelProvider(id),
        (_, next) {
          probe.emissions += 1;
          observe(next);
        },
        fireImmediately: true,
      ),
    );
    probe.emissions = 0;
  }

  void neighborhood(IntentionId id, {required bool observes}) {
    final probe = _add(
      'окрестность намерения ${_label(id.toCanonicalString())}',
      observes: observes,
    );
    void observe(RelationNeighborhoodState state) {
      switch (state) {
        case RelationGroupConfirmedState():
          probe
            ..loaded = true
            ..content = () => _neighborhoodContent(state);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
          if (state.summaryStatus is RelationSummaryRefreshFailure) {
            probe.forbiddenStates.add(state);
          }
        case RelationGroupInitialLoad():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case RelationGroupInitialFailure() ||
            RelationNeighborhoodIntentionNotFound():
          probe.forbiddenStates.add(state);
      }
    }

    _providerSubscriptions.add(
      _container.listen<RelationNeighborhoodState>(
        relationNeighborhoodViewModelProvider(id),
        (_, next) {
          probe.emissions += 1;
          observe(next);
        },
        fireImmediately: true,
      ),
    );
    probe.emissions = 0;
  }

  void relationDetails(LongTermRelationId id, {required bool observes}) {
    final probe = _add(
      'модель подробностей связи ${_label(id.toCanonicalString())}',
      observes: observes,
    );
    void observe(RelationDetailsState state) {
      switch (state) {
        case RelationDetailsLoaded():
          probe
            ..loaded = true
            ..content = () => _relationContent(state.details);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
          if (state.refreshStatus
              case RelationDetailsRefreshUnavailable() ||
                  RelationDetailsRefreshCorruption() ||
                  RelationDetailsRefreshUnexpected()) {
            probe.forbiddenStates.add(state);
          }
        case RelationDetailsLoading():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case RelationDetailsNotFound() ||
            RelationDetailsDeleted() ||
            RelationDetailsUnavailable() ||
            RelationDetailsCorruption() ||
            RelationDetailsUnexpected():
          probe.forbiddenStates.add(state);
      }
    }

    _providerSubscriptions.add(
      _container.listen<RelationDetailsState>(
        relationDetailsViewModelProvider(id),
        (_, next) {
          probe.emissions += 1;
          observe(next);
        },
        fireImmediately: true,
      ),
    );
    probe.emissions = 0;
  }

  void dailyChoiceCatalog() {
    final probe = _add('каталог дневных выборов', observes: true);
    void observe(DailyChoiceCatalogState state) {
      switch (state) {
        case DailyChoiceCatalogLoaded():
          probe
            ..loaded = true
            ..content = () => _dailyCatalogContent(state);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
          if (state.refreshFailure != null ||
              state.pageStatus is DailyChoiceCatalogPageFailure) {
            probe.forbiddenStates.add(state);
          }
        case DailyChoiceCatalogInitialLoad():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case DailyChoiceCatalogInitialFailure():
          probe.forbiddenStates.add(state);
      }
    }

    _providerSubscriptions.add(
      _container.listen<DailyChoiceCatalogState>(
        dailyChoiceCatalogViewModelProvider,
        (_, next) {
          probe.emissions += 1;
          observe(next);
        },
        fireImmediately: true,
      ),
    );
    probe.emissions = 0;
  }

  void dailyChoiceDetails(DailyChoiceId id) {
    final probe = _add('модель подробностей дневного выбора', observes: true);
    final model = DailyChoiceDetailsViewModel(_repository, id);
    _notifiers.add(model);
    model.addListener(() {
      probe.emissions += 1;
      final state = model.state;
      switch (state) {
        case DailyChoiceDetailsLoaded():
          probe
            ..loaded = true
            ..content = () => _dailyChoiceContent(state.details);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
        case DailyChoiceDetailsLoading():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case DailyChoiceDetailsNotFound() ||
            DailyChoiceDetailsUnavailable() ||
            DailyChoiceDetailsCorruption() ||
            DailyChoiceDetailsUnexpected():
          probe.forbiddenStates.add(state);
      }
    });
  }

  void choicePathSuggestions(ChoicePathSuggestionsQuery query) {
    final probe = _add('предложения пути', observes: true);
    final model = ChoicePathSuggestionsViewModel.fromCoordinator(
      _repository,
      _coordinator,
      query,
    );
    _notifiers.add(model);
    model.addListener(() {
      probe.emissions += 1;
      final state = model.state;
      switch (state) {
        case ChoicePathSuggestionsCurrent():
          probe
            ..loaded = true
            ..content = () => _suggestionsContent(state.items);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
        case ChoicePathSuggestionsUpdating():
          break;
        case ChoicePathSuggestionsLoading():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case ChoicePathSuggestionsRefreshFailure() ||
            ChoicePathSuggestionsNotFound() ||
            ChoicePathSuggestionsLoadFailure():
          probe.forbiddenStates.add(state);
      }
    });
  }

  bool get allLoaded => all.every((probe) => probe.loaded);

  bool get dailyCatalogSelected =>
      dailyCatalogSelection == (null, true) &&
      _container.read(dailyChoiceCatalogViewModelProvider)
          is DailyChoiceCatalogLoaded;

  (Object?, bool?) get dailyCatalogSelection {
    final selection = _container
        .read(dailyChoiceCatalogViewModelProvider)
        .selection;
    return (selection.date, selection.isCompleted);
  }

  Object? neighborhoodSelection(IntentionId id) {
    final state = _container.read(relationNeighborhoodViewModelProvider(id));
    return (state.selection, state.group);
  }

  (String, String, Object)? intentionDetailsEdit(IntentionId id) {
    final state = _container.read(intentionDetailsViewModelProvider(id));
    if (state is! IntentionDetailsLoaded) return null;
    final edit = state.edit;
    if (edit == null) return null;
    return (edit.title, edit.description, edit.operation.runtimeType);
  }

  bool observingSettledAt(GraphRevision revision) => all
      .where((probe) => probe.observes)
      .every(
        (probe) =>
            probe.revision?.compareTo(revision) == GraphRevisionOrder.same &&
            probe.content() != null,
      );

  List<Object?> visibleContent() => [
    for (final probe in all) [probe.name, probe.content()],
  ];

  void reset() {
    for (final probe in all) {
      probe.reset();
    }
  }

  List<(String, int)> get emissions => [
    for (final probe in all) (probe.name, probe.emissions),
  ];

  String describe() => [
    for (final probe in all)
      '${probe.name}: loaded=${probe.loaded}, updates=${probe.updates}, '
          'forbidden=${probe.forbiddenStates.length}',
  ].join('; ');

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    for (final subscription in _providerSubscriptions) {
      subscription.close();
    }
    for (final notifier in _notifiers) {
      notifier.dispose();
    }
  }
}

Object _intention(Intention intention) => (
  intention.id,
  intention.title,
  intention.description,
  intention.readiness,
  intention.archiveState,
  intention.createdAt,
  intention.updatedAt,
);

Object _intentionContent(IntentionDetails? details) => switch (details) {
  null => 'нет',
  IntentionDetails(:final intention, :final relationCounts) => (
    _intention(intention),
    relationCounts,
  ),
};

Object _participant(RelationParticipantSummary participant) => (
  participant.id,
  participant.title,
  participant.archiveState,
  participant.activeRelationCount,
);

Object _relationContent(LongTermRelationDetails details) => (
  details.relation.id,
  details.relation.type,
  details.relation.priority,
  details.relation.scope,
  _participant(details.source),
  _participant(details.related),
  details.description,
);

Object _pathContent(List<DailyChoicePathStepDetails> path) => [
  for (final step in path)
    (
      step.step.id,
      step.relation.id,
      step.description,
      _intention(step.source),
      _intention(step.related),
    ),
];

Object _dailyChoiceContent(DailyChoiceDetails details) => [
  details.choice.id,
  details.choice.date,
  details.choice.description,
  details.choice.isCompleted,
  _intention(details.source),
  _intention(details.selected),
  _pathContent(details.path),
];

Object _catalogParticipant(DailyChoiceCatalogParticipant participant) => (
  participant.id,
  participant.title,
  participant.archiveState,
  participant.readiness,
);

Object _dailyItem(DailyChoiceCatalogItem item) => (
  item.id,
  _catalogParticipant(item.source),
  _catalogParticipant(item.selected),
  item.date,
  item.isCompleted,
);

Object _dailyCatalogContent(DailyChoiceCatalogLoaded state) => [
  [for (final item in state.items) _dailyItem(item)],
  state.totalCount,
  state.nextCursor == null,
];

Object _selectedContent(SelectedRelationsSnapshot snapshot) => [
  for (final MapEntry(:key, :value) in snapshot.entriesByReference.entries)
    (
      key,
      switch (value) {
        SelectedRelationPresent(:final details) => _relationContent(details),
        SelectedDailyChoicePresent(:final item) => _dailyItem(item),
        SelectedRelationMissing() ||
        SelectedRelationNoLongerBlocking() ||
        SelectedDailyChoiceMissing() ||
        SelectedDailyChoiceNoLongerBlocking() => value.runtimeType,
      },
    ),
];

Object _neighborhoodContent(RelationGroupConfirmedState state) => [
  state.counts,
  switch (state) {
    RelationGroupLoaded(:final items) => [
      for (final item in items)
        (
          item.relation.id,
          _participant(item.source),
          _participant(item.related),
        ),
    ],
    DailyChoiceGroupLoaded(:final items) => [
      for (final item in items) _dailyItem(item),
    ],
    RelationGroupEmpty() => const [],
  },
];

Object _suggestionsContent(List<AvailableChoicePathSuggestion> items) => [
  for (final item in items)
    [
      item.originChoiceId,
      _intention(item.source),
      _intention(item.action),
      _pathContent(item.path),
    ],
];

Future<void> _quiesce() async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> _settleUntil(
  bool Function() condition, {
  String Function()? diagnostics,
}) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: diagnostics?.call());
}
