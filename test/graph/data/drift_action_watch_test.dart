import 'dart:async';
import 'dart:convert';

import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Action, Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/encoded_diagnostics_log.dart';
import '../../support/graph_seed.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;
IntentionId _intention(int number) =>
    (IntentionId.decode(seedUuid(number)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  seedUuid(number),
) as LongTermRelationIdDecodingSuccess).id;

/// Отказывает чтению пути действия, пока включён.
final class _ActionPathReadFailure extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    final error = failure;
    if (error != null &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM action_path_items p')) {
      throw error;
    }
  }
}

GraphSnapshot<ActionDetails?> _snapshot(ActionReadResult result) =>
    (result as ActionReadSuccess).value;

Intention _existing(ActionPathIntention intention) =>
    (intention as ExistingActionPathIntention).intention;

LongTermRelation _relationOf(ActionPathLink link) =>
    (link as ExistingActionPathLink).relation;

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late EncodedDiagnosticsLog diagnostics;
  late _ActionPathReadFailure readFailure;

  setUp(() async {
    readFailure = _ActionPathReadFailure();
    diagnostics = EncodedDiagnosticsLog();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        readFailure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7, 12),
      diagnostics,
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
      seedAction(
        raw,
        id: seedUuid(11),
        path: [seedUuid(1), seedUuid(2), seedUuid(3)],
        description: 'Утром',
        hour: 18,
        priority: 2,
        isCompleted: true,
      );
    });
  });

  tearDown(() => database.close());

  /// Подписывается на действие [number] и отдаёт итератор событий.
  StreamIterator<ActionReadResult> watch(int number) {
    final events = StreamIterator(repository.watchAction(_action(number)));
    addTearDown(events.cancel);
    return events;
  }

  Future<ActionDetails> next(StreamIterator<ActionReadResult> events) async {
    expect(await events.moveNext(), isTrue);
    return _snapshot(events.current).value!;
  }

  Future<void> confirm(Object command) async {
    final result = await switch (command) {
      final ActionCommand action => repository.execute(action),
      final IntentionCommand intention => repository.execute(intention),
      final LongTermRelationCommand relation => repository.execute(relation),
      _ => throw ArgumentError.value(command),
    };
    expect(result, isA<GraphCommandSucceeded>());
  }

  test('отдаёт поля действия и весь путь с текущими данными намерений и '
      'связей, включая архивные', () async {
    seedRawGraph(raw, () {
      raw.execute(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [seedUuid(102)],
      );
      raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
        seedUuid(3),
      ]);
    });

    final details = await next(watch(11));

    final action = details.action;
    expect(action.id, _action(11));
    expect(action.title, ActionTitle('Пробежка'));
    expect(action.description, ActionDescription.fromInput('Утром'));
    expect(action.date, CalendarDate.fromParts(2026, 10, 8));
    expect(action.schedule, ActionAtHour(18));
    expect(action.priority, ActionPriority.p2);
    expect(action.isCompleted, isTrue);
    final path = details.path;
    expect(path.intentionCount, 3);
    expect(_existing(path.root).title, 'Намерение 1');
    expect(_existing(path.root).archiveState, IntentionArchiveState.active);
    final [toSecond, toThird] = path.steps;
    expect(_relationOf(toSecond.link).id, _relation(101));
    expect(_relationOf(toSecond.link).type, LongTermRelationType.need);
    expect(_relationOf(toSecond.link).priority, RelationPriority.p1);
    expect(_relationOf(toSecond.link).scope, RelationScope.active);
    expect(_existing(toSecond.intention).title, 'Намерение 2');
    expect(_relationOf(toThird.link).id, _relation(102));
    expect(_relationOf(toThird.link).scope, RelationScope.archived);
    expect(_existing(toThird.intention).title, 'Намерение 3');
    expect(
      _existing(toThird.intention).archiveState,
      IntentionArchiveState.archived,
    );
  });

  test('путь из одного намерения не имеет звеньев', () async {
    seedRawGraph(
      raw,
      () => seedAction(raw, id: seedUuid(12), path: [seedUuid(2)]),
    );

    final path = (await next(watch(12))).path;

    expect(path.intentionCount, 1);
    expect(path.root.id, _intention(2));
    expect(path.steps, isEmpty);
  });

  test('отсутствующее действие — успех без значения, а изменение и удаление '
      'действия наблюдаются своими ревизиями', () async {
    final absent = watch(99);
    expect(await absent.moveNext(), isTrue);
    expect(_snapshot(absent.current).value, isNull);

    final events = watch(11);
    expect(await events.moveNext(), isTrue);
    final initial = _snapshot(events.current);

    final updated = await repository.execute(
      UpdateActionFields(
        actionId: _action(11),
        patch: ActionFieldsPatch(
          date: ActionFieldSet(CalendarDate.fromParts(2026, 10, 12)),
          isCompleted: const ActionFieldSet(false),
        ),
      ),
    );
    expect(await events.moveNext(), isTrue);
    final afterUpdate = _snapshot(events.current);
    expect(
      afterUpdate.value!.action.date,
      CalendarDate.fromParts(2026, 10, 12),
    );
    expect(afterUpdate.value!.action.isCompleted, isFalse);
    expect(afterUpdate.value!.path.intentionCount, 3);
    expect(
      afterUpdate.revision.compareTo(
        (updated as GraphCommandSucceeded).value.revision,
      ),
      GraphRevisionOrder.same,
    );
    expect(
      afterUpdate.revision.compareTo(initial.revision),
      GraphRevisionOrder.newer,
    );

    await confirm(DeleteAction(_action(11)));
    expect(await events.moveNext(), isTrue);
    final deleted = _snapshot(events.current);
    expect(deleted.value, isNull);
    expect(
      deleted.revision.compareTo(afterUpdate.revision),
      GraphRevisionOrder.newer,
    );
  });

  test('путь показывает новое название намерения и новые тип и приоритет '
      'связи в прежнем порядке', () async {
    final events = watch(11);
    await next(events);

    await confirm(
      UpdateIntention(
        id: _intention(2),
        title: 'Ходить пешком',
        description: null,
      ),
    );
    final renamed = await next(events);
    expect(
      _existing(renamed.path.steps.first.intention).title,
      'Ходить пешком',
    );

    await confirm(
      UpdateLongTermRelation(
        relationId: _relation(101),
        patch: const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
          priority: LongTermRelationFieldSet(RelationPriority.p3),
        ),
      ),
    );
    final retyped = await next(events);
    final link = _relationOf(retyped.path.steps.first.link);
    expect(link.type, LongTermRelationType.can);
    expect(link.priority, RelationPriority.p3);
    expect(
      [
        retyped.path.root.id,
        for (final step in retyped.path.steps) step.intention.id,
      ],
      [_intention(1), _intention(2), _intention(3)],
    );
  });

  test('удалённые связь и намерение остаются на своих местах с данными на '
      'момент удаления', () async {
    final events = watch(11);
    await next(events);

    await confirm(DeleteLongTermRelation(_relation(102)));
    final withoutRelation = await next(events);
    final deletedLink = withoutRelation.path.steps.last.link;
    expect(deletedLink, isA<DeletedActionPathLink>());
    expect(deletedLink.type, LongTermRelationType.need);

    await confirm(DeleteIntention(_intention(3)));
    final withoutIntention = await next(events);
    final deletedIntention = withoutIntention.path.steps.last.intention;
    expect(deletedIntention, isA<DeletedActionPathIntention>());
    expect(deletedIntention.id, _intention(3));
    expect(deletedIntention.title, 'Намерение 3');
    expect(withoutIntention.path.intentionCount, 3);
  });

  test('заново созданная связь пары делает звено целым, а после архивирования '
      'звено показывает её данные', () async {
    final events = watch(11);
    await next(events);
    await confirm(DeleteLongTermRelation(_relation(101)));
    expect(
      (await next(events)).path.steps.first.link,
      isA<DeletedActionPathLink>(),
    );

    await confirm(
      AddLongTermRelations(
        pageIntentionId: _intention(1),
        group: IntentionRelationGroup.canUse,
        candidateIds: [_intention(2)],
      ),
    );
    final restored = _relationOf((await next(events)).path.steps.first.link);
    expect(restored.id, isNot(_relation(101)));
    expect(restored.type, LongTermRelationType.can);
    expect(restored.priority, RelationPriority.p4);
    expect(restored.scope, RelationScope.active);

    await confirm(ArchiveLongTermRelation(restored.id));
    final archived = _relationOf((await next(events)).path.steps.first.link);
    expect(archived.id, restored.id);
    expect(archived.type, LongTermRelationType.can);
    expect(archived.scope, RelationScope.archived);
  });

  test('повреждённая строка действия даёт отказ «повреждение»', () async {
    seedRawGraph(
      raw,
      () => raw.execute('UPDATE actions SET title = ? WHERE id = ?', [
        '  Пробежка  ',
        seedUuid(11),
      ]),
    );

    final events = watch(11);

    expect(await events.moveNext(), isTrue);
    expect(
      (events.current as ActionReadError).failure,
      isA<ActionReadCorruptionFailure>(),
    );
  });

  for (final (error, failure, code) in <(Object, Type, String)>[
    (
      sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'CANARY-ошибка',
        causingStatement: 'CANARY-запрос',
        parametersToStatement: ['CANARY-название'],
      ),
      ActionReadUnavailableFailure,
      'unavailable',
    ),
    (StateError('CANARY-причина'), ActionReadUnexpectedFailure, 'unexpected'),
  ]) {
    test('сбой чтения ($code) различим по категории, а диагностика не '
        'раскрывает данные', () async {
      readFailure.failure = error;
      final events = watch(11);

      expect(await events.moveNext(), isTrue);
      readFailure.failure = null;

      expect((events.current as ActionReadError).failure.runtimeType, failure);
      expect(diagnostics.events, [
        {'operation': 'actionRead', 'stage': 'read', 'outcome': 'started'},
        {
          'operation': 'actionRead',
          'stage': 'read',
          'outcome': 'failed',
          'failureCode': code,
        },
      ]);
      expect(jsonEncode(diagnostics.events), isNot(contains('CANARY')));
    });
  }
}
