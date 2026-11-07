/// Действие с сохранённым путём и репозиторий, который отдаёт его панели.
library;

import 'dart:async';
import 'dart:math';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_day_statuses.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/application/action_result.dart';
import 'package:doable/src/action/domain/action.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';

import 'action_read_contract_test_fallback.dart';
import 'tag_read_contract_test_fallback.dart';

String _uuid(int n) =>
    '018f0b5d-6b2e-7c80-8000-${n.toRadixString(16).padLeft(12, '0')}';

ActionId actionIdOf(int number) =>
    (ActionId.decode(_uuid(number)) as ActionIdDecodingSuccess).id;

IntentionId intentionIdOf(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId relationIdOf(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;

/// Действие [actionIdOf] 1 с путём из [pathLength] существующих активных
/// намерений; корневое называется [rootTitle].
ActionDetails actionDetailsFixture({
  String title = 'Пробежка',
  String? description,
  CalendarDate? date,
  ActionSchedule schedule = const ActionAllDay(),
  ActionPriority priority = ActionPriority.p4,
  bool isCompleted = false,
  int pathLength = 2,
  String rootTitle = 'Быть здоровым',
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 10, 6, 9);
  Intention intention(int position) => Intention(
    id: intentionIdOf(10 + position),
    title: position == 0 ? rootTitle : 'Намерение ${position + 1}',
    description: null,
    readiness: IntentionReadiness.ready,
    archiveState: IntentionArchiveState.active,
    createdAt: IntentionTimestamp(created),
    updatedAt: IntentionTimestamp(created),
  );
  final intentions = [for (var i = 0; i < pathLength; i++) intention(i)];
  return ActionDetails(
    action: Action(
      id: actionIdOf(1),
      title: ActionTitle(title),
      description: description == null
          ? null
          : ActionDescription.fromInput(description),
      path: ActionPath(intentions.map((intention) => intention.id)),
      date: date ?? CalendarDate.fromParts(2026, 10, 8),
      schedule: schedule,
      priority: priority,
      isCompleted: isCompleted,
      creationSequence: ActionCreationSequence(1),
      createdAt: ActionTimestamp(created),
      updatedAt: ActionTimestamp(updatedAt ?? created),
    ),
    path: ActionSavedPath(
      root: ExistingActionPathIntention(intentions.first),
      steps: [
        for (var i = 1; i < pathLength; i++)
          ActionPathStep(
            link: ExistingActionPathLink(
              LongTermRelation(
                id: relationIdOf(100 + i),
                sourceIntentionId: intentions[i - 1].id,
                relatedIntentionId: intentions[i].id,
                type: LongTermRelationType.need,
                priority: RelationPriority.p1,
                scope: RelationScope.active,
                creationSequence: RelationCreationSequence(i),
                createdAt: RelationTimestamp(created),
                updatedAt: RelationTimestamp(created),
              ),
            ),
            intention: ExistingActionPathIntention(intentions[i]),
          ),
      ],
    ),
  );
}

final class FixtureRevision implements GraphRevision {
  const FixtureRevision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    final difference = value.compareTo((other as FixtureRevision).value);
    return difference < 0
        ? GraphRevisionOrder.older
        : difference > 0
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

final class _Change implements GraphChange {
  const _Change(this.revision);

  @override
  final GraphRevision revision;
}

/// Репозиторий панели действия: подписка управляется тестом, а команда
/// остаётся незавершённой, пока тест не подтвердит или не отклонит её.
final class ActionPanelRepository
    with TagReadContractTestFallback, ActionReadContractTestFallback
    implements PersonalGraphRepository {
  final controller = StreamController<ActionReadResult>.broadcast(sync: true);
  final commands = <UpdateActionFields>[];
  final deletions = <DeleteAction>[];

  /// Связи, подробный просмотр которых открыла панель.
  final watchedRelations = <LongTermRelationId>[];
  final _requests = <Completer<ActionCommandResult>>[];
  var _revision = 0;
  ActionId? observedId;
  var watchCount = 0;
  Action? _shown;

  bool get hasListener => controller.hasListener;

  /// Изменения полей из отправленных команд.
  List<ActionFieldsPatch> get sentPatches => [
    for (final command in commands) command.patch,
  ];

  @override
  Stream<ActionReadResult> watchAction(ActionId id) {
    observedId = id;
    watchCount++;
    return controller.stream;
  }

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) {
    watchedRelations.add(id);
    return const Stream.empty();
  }

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is UpdateActionFields) {
      commands.add(command as UpdateActionFields);
    } else {
      deletions.add(command as DeleteAction);
    }
    final request = Completer<ActionCommandResult>();
    _requests.add(request);
    return await request.future as GraphCommandResult<TSuccess, TFailure>;
  }

  /// Листу даты отметки дней не нужны: ни у одного дня нет действий.
  @override
  Future<ActionDayStatusesReadResult> getActionDayStatuses(
    ActionDayStatusQuery query,
  ) async => ActionDayStatusesReadSuccess(
    GraphSnapshot(
      revision: FixtureRevision(_revision),
      value: ActionDayStatuses(query: query, statuses: const {}),
    ),
  );

  /// Показывает действие на ревизии [revision] или на следующей по порядку;
  /// следующая подтверждённая запись получает ревизию старше показанной.
  void emit(ActionDetails details, {int? revision}) {
    _shown = details.action;
    _revision = revision == null ? _revision + 1 : max(_revision, revision);
    controller.add(
      ActionReadSuccess(
        GraphSnapshot(
          value: details,
          revision: FixtureRevision(revision ?? _revision),
        ),
      ),
    );
  }

  void emitMissing() => controller.add(
    ActionReadSuccess(
      GraphSnapshot<ActionDetails?>(
        value: null,
        revision: FixtureRevision(++_revision),
      ),
    ),
  );

  void failRead(ActionReadFailure failure) =>
      controller.add(ActionReadError(failure));

  void failCommand(ActionCommandFailure failure) =>
      _requests.last.complete(GraphCommandFailed(failure));

  /// Подтверждает запись последней команды поверх показанного действия; новое
  /// значение приходит отдельно через [emit]. Без [written] подтверждается
  /// состояние, которое получилось бы из изменения команды.
  void succeedUpdate({Action? written}) {
    final before = _shown!;
    final patch = commands.last.patch;
    _requests.last.complete(
      GraphCommandSucceeded(
        ConfirmedGraphResult(
          revision: FixtureRevision(++_revision),
          value: ActionFieldsUpdated(
            action:
                written ??
                Action(
                  id: before.id,
                  title: patch.title.resolve(before.title),
                  description: patch.description.resolve(before.description),
                  path: before.path,
                  date: patch.date.resolve(before.date),
                  schedule: patch.schedule.resolve(before.schedule),
                  priority: patch.priority.resolve(before.priority),
                  isCompleted: patch.isCompleted.resolve(before.isCompleted),
                  creationSequence: before.creationSequence,
                  createdAt: before.createdAt,
                  updatedAt: before.updatedAt,
                ),
            changes: [_Change(FixtureRevision(_revision))],
          ),
        ),
      ),
    );
  }

  /// Подтверждает удаление показанного действия; снимок без действия приходит
  /// отдельно через [emitMissing].
  void succeedDelete() => _requests.last.complete(
    GraphCommandSucceeded(
      ConfirmedGraphResult(
        revision: FixtureRevision(++_revision),
        value: ActionDeleted(
          action: _shown!,
          changes: [_Change(FixtureRevision(_revision))],
        ),
      ),
    ),
  );

  Future<void> dispose() => controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
