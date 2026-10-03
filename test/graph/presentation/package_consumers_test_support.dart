import 'dart:async';

import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_view_model.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_state.dart';
import 'package:doable/src/daily_choice/presentation/path/choice_path_suggestions_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_details.dart';
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
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

/// Номер объекта фикстуры по его UUID.
int _label(String uuid) => int.parse(uuid.split('-').last, radix: 16);

/// Число успешных чтений каждого вида с события [from]; события команд
/// тегов и намерений чтениями не считаются.
Map<Type, int> successfulReadCounts(
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
final class PackageConsumerProbe {
  PackageConsumerProbe(this.name, {required this.observes});

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

/// Потребители подтверждённых пакетов вне поиска на настоящем хранилище:
/// наблюдения прикладной границы и модели открытых представлений.
final class PackageConsumerProbes {
  PackageConsumerProbes(this._container, this._repository, this._coordinator);

  final ProviderContainer _container;
  final DriftPersonalGraphRepository _repository;
  final GraphCommandCoordinator _coordinator;
  final all = <PackageConsumerProbe>[];
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _providerSubscriptions = <ProviderSubscription<Object?>>[];
  final _notifiers = <ChangeNotifier>[];

  PackageConsumerProbe _add(String name, {required bool observes}) {
    final probe = PackageConsumerProbe(name, observes: observes);
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

Future<void> quiescePackageConsumers() async {
  for (var attempt = 0; attempt < 5; attempt++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<void> settlePackageConsumersUntil(
  bool Function() condition, {
  String Function()? diagnostics,
}) async {
  for (var attempt = 0; attempt < 200 && !condition(); attempt++) {
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(condition(), isTrue, reason: diagnostics?.call());
}
