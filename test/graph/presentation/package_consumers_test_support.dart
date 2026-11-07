import 'dart:async';

import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/presentation/day/action_day_instance.dart';
import 'package:doable/src/action/presentation/day/action_day_state.dart';
import 'package:doable/src/action/presentation/day/action_day_view_model.dart';
import 'package:doable/src/action/presentation/panel/action_panel_state.dart';
import 'package:doable/src/action/presentation/panel/action_panel_view_model.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_state.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/intention/presentation/edit/intention_edit_view_model.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_state.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/intention_relations/intention_relations_state.dart';
import 'package:doable/src/long_term_relation/presentation/intention_relations/intention_relations_view_model.dart';
import 'package:doable/src/long_term_relation/presentation/relation_list_reconciliation.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// День действия потребителей пакетов и начальная дата экрана дня.
final packageConsumersActionDate = CalendarDate.fromParts(2026, 9, 23);

/// Номер объекта фикстуры по его UUID.
int _label(String uuid) => int.parse(uuid.split('-').last, radix: 16);

/// Наблюдение одного потребителя с момента последнего сброса: число
/// опубликованных новых ревизий и запрещённых состояний.
final class PackageConsumerProbe {
  PackageConsumerProbe(this.name, {required this.observes});

  final String name;
  final bool observes;
  var updates = 0;
  final forbiddenStates = <Object>[];
  GraphRevision? revision;
  bool loaded = false;
  Object? Function() content = () => null;

  void reset() {
    updates = 0;
    forbiddenStates.clear();
  }
}

/// Потребители подтверждённых пакетов вне поиска на настоящем хранилище:
/// наблюдения прикладной границы и модели открытых представлений.
final class PackageConsumerProbes {
  PackageConsumerProbes(this._container, this._repository);

  final actionDayProvider = actionDayViewModelProvider(
    ActionDayInstance(initialDate: packageConsumersActionDate),
  );

  final ProviderContainer _container;
  final DriftPersonalGraphRepository _repository;
  final all = <PackageConsumerProbe>[];
  final _subscriptions = <StreamSubscription<Object?>>[];
  final _providerSubscriptions = <ProviderSubscription<Object?>>[];
  final _notifiers = <ChangeNotifier>[];
  final _intentionEdits = <IntentionId, IntentionEditViewModelProvider>{};
  final _relationPages = <IntentionId, IntentionPageInstance>{};

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

  void watchAction(ActionId id, {required bool observes}) {
    final probe = _add('чтение действия', observes: observes);
    _subscriptions.add(
      _repository.watchAction(id).listen((result) {
        probe
          ..updates += 1
          ..loaded = true;
        switch (result) {
          case GraphResultSuccess(:final value) when value.value != null:
            probe
              ..revision = value.revision
              ..content = () => _actionContent(value.value!);
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
          observe(next);
        },
        fireImmediately: true,
      ),
    );
  }

  /// Открывает вкладку «Связи» на группе [group] над полученными подробными
  /// данными намерения.
  void intentionRelations(
    IntentionId id, {
    required IntentionRelationGroup group,
    required bool observes,
  }) {
    final probe = _add(
      'связи намерения ${_label(id.toCanonicalString())}',
      observes: observes,
    );
    final page = _relationPages[id] = IntentionPageInstance(
      target: RelationsTarget(group),
    );
    void observe(IntentionRelationsState state) {
      switch (state) {
        case IntentionRelationsConfirmed():
          probe
            ..loaded = true
            ..content = () => _relationsContent(state);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
          if (state.summaryStatus is RelationListSummaryRefreshFailure) {
            probe.forbiddenStates.add(state);
          }
        case IntentionRelationsInitialLoad():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case IntentionRelationsInitialFailure() ||
            IntentionRelationsIntentionNotFound():
          probe.forbiddenStates.add(state);
      }
    }

    _providerSubscriptions.add(
      _container.listen<IntentionRelationsState>(
        intentionRelationsViewModelProvider(id, page),
        (_, next) {
          observe(next);
        },
        fireImmediately: true,
      ),
    );
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
            RelationDetailsOwnDeletionConfirmed() ||
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
          observe(next);
        },
        fireImmediately: true,
      ),
    );
  }

  /// Экран дня действий. Его строки зависят от самих действий дня и от
  /// корневых намерений путей, поэтому пакеты остальных намерений новую
  /// ревизию на экране дня не публикуют, и такой экран нужно регистрировать
  /// с `observes: false`.
  void actionDay({required bool observes}) {
    final probe = _add('экран дня действий', observes: observes);
    void observe(ActionDayState state) {
      switch (state) {
        case ActionDayLoaded():
          probe
            ..loaded = true
            ..content = () => _actionDayContent(state);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
          if (state.refreshFailure != null ||
              state.incomplete.pageStatus is ActionDayContinuationFailure ||
              state.completed.pageStatus is ActionDayContinuationFailure) {
            probe.forbiddenStates.add(state);
          }
        case ActionDayInitialLoad():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case ActionDayInitialFailure():
          probe.forbiddenStates.add(state);
      }
    }

    _providerSubscriptions.add(
      _container.listen<ActionDayState>(actionDayProvider, (_, next) {
        observe(next);
      }, fireImmediately: true),
    );
  }

  void actionPanel(ActionId id, {required bool observes}) {
    final probe = _add('панель действия', observes: observes);
    final model = ActionPanelViewModel(
      _repository,
      _container.read(graphCommandCoordinatorProvider.notifier),
      id,
    );
    _notifiers.add(model);
    model.addListener(() {
      final state = model.state;
      switch (state) {
        case ActionPanelLoaded():
          probe
            ..loaded = true
            ..content = () => _actionContent(state.details);
          final order = probe.revision == null
              ? null
              : state.revision.compareTo(probe.revision!);
          if (order != null && order != GraphRevisionOrder.same) {
            probe.updates += 1;
          }
          probe.revision = state.revision;
        case ActionPanelLoading():
          if (probe.loaded) probe.forbiddenStates.add(state);
        case ActionPanelNotFound() ||
            ActionPanelDeleted() ||
            ActionPanelUnavailable() ||
            ActionPanelCorruption() ||
            ActionPanelUnexpected():
          probe.forbiddenStates.add(state);
      }
    });
  }

  bool get allLoaded => all.every((probe) => probe.loaded);

  /// Экран дня загружен для дня действия потребителей со свёрнутой секцией
  /// невыполненных и раскрытой секцией выполненных.
  bool get actionDaySelected =>
      actionDaySelection == (packageConsumersActionDate, false, true) &&
      _container.read(actionDayProvider) is ActionDayLoaded;

  (Object?, bool, bool) get actionDaySelection {
    final selection = _container.read(actionDayProvider).selection;
    return (
      selection.date,
      selection.incompleteExpanded,
      selection.completedExpanded,
    );
  }

  /// Выбранная группа вкладки «Связи» и раскрытие её архива.
  (IntentionRelationGroup, bool) relationsSelection(IntentionId id) {
    final settings = _relationPages[id]!.relations!;
    return (settings.group, settings.expandedArchives.contains(settings.group));
  }

  /// Открывает над полученными подробными данными сессию экрана изменения
  /// намерения и удерживает её до [dispose].
  IntentionEditViewModel openIntentionEdit(IntentionId id) {
    final provider = intentionEditViewModelProvider(IntentionEditFormKey(), id);
    _intentionEdits[id] = provider;
    _providerSubscriptions.add(_container.listen(provider, (_, _) {}));
    return _container.read(provider.notifier);
  }

  /// Черновик и состояние операции сессии, открытой [openIntentionEdit].
  (String, String, Object) intentionEditDraft(IntentionId id) {
    final state = _container.read(_intentionEdits[id]!);
    return (state.title, state.description, state.operation.runtimeType);
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

Object _participant(RelationParticipantSummary participant) =>
    (participant.id, participant.title, participant.archiveState);

Object _relationContent(LongTermRelationDetails details) => (
  details.relation.id,
  details.relation.type,
  details.relation.priority,
  details.relation.scope,
  _participant(details.source),
  _participant(details.related),
  details.description,
);

Object _pathIntention(ActionPathIntention intention) => switch (intention) {
  ExistingActionPathIntention(:final intention) => _intention(intention),
  DeletedActionPathIntention(:final id, :final title) => (id, title),
};

Object _pathLink(ActionPathLink link) => switch (link) {
  ExistingActionPathLink(:final relation) => (
    relation.id,
    relation.type,
    relation.priority,
    relation.scope,
  ),
  DeletedActionPathLink(:final type) => type,
};

Object _pathContent(ActionSavedPath path) => [
  _pathIntention(path.root),
  for (final step in path.steps)
    (_pathLink(step.link), _pathIntention(step.intention)),
];

Object _actionContent(ActionDetails details) => [
  details.action.id,
  details.action.title,
  details.action.description,
  details.action.date,
  details.action.schedule,
  details.action.priority,
  details.action.isCompleted,
  _pathContent(details.path),
];

Object _actionListItem(ActionListItem item) => (
  item.id,
  item.title,
  item.description,
  item.date,
  item.schedule,
  item.priority,
  item.isCompleted,
  item.rootIntentionId,
  item.rootTitle,
  item.pathIntentionCount,
);

Object _actionDayContent(ActionDayLoaded state) => [
  [for (final item in state.items) _actionListItem(item)],
  state.incomplete.totalCount,
  state.completed.totalCount,
  state.hasTimedActions,
  state.incomplete.nextCursor == null && state.completed.nextCursor == null,
];

Object _relationEntry(RelationGroupEntry item) => (
  item.relation.id,
  item.neighbor.id,
  item.neighbor.title,
  item.neighbor.archiveState,
  item.descriptionPreview?.text,
);

Object _relationsContent(IntentionRelationsConfirmed state) => [
  state.group,
  state.counts,
  switch (state) {
    IntentionRelationsLoaded(:final items) => [
      for (final item in items) _relationEntry(item),
    ],
    IntentionRelationsEmpty() => const [],
  },
  switch (state.archive) {
    IntentionRelationsArchiveExpanded(:final items) => [
      for (final item in items) _relationEntry(item),
    ],
    IntentionRelationsArchiveFolded() ||
    IntentionRelationsArchivePending() => const [],
  },
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
