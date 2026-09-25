import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late Database raw;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _SelectedReadFailureObserver observer;

  setUp(() async {
    observer = _SelectedReadFailureObserver();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        observer,
      ),
    );
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    for (final (id, title) in [
      (_owner, 'Владелец'),
      (_neighbor, 'Сосед'),
      (_other, 'Другой'),
    ]) {
      await database.customStatement(
        'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, 1, 1)',
        [id.toCanonicalString(), title],
      );
    }
    for (final (id, source, related) in [
      (_first, _owner, _neighbor),
      (_second, _other, _owner),
      (_foreign, _neighbor, _other),
    ]) {
      await database.customStatement(
        "INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, 'need', 2, 0)",
        [
          id.toCanonicalString(),
          source.toCanonicalString(),
          related.toCanonicalString(),
        ],
      );
    }
  });

  tearDown(() => database.close());

  test(
    'возвращает каждый идентификатор и участников на одной ревизии',
    () async {
      final query = SelectedRelationsQuery(
        intentionId: _owner,
        relationIds: [_first, _second, _foreign, _missing],
      );
      final result = await repository.getSelectedRelations(query);
      final snapshot = (result as SelectedRelationsReadSuccess).value;

      expect(snapshot.value.entries.keys.toSet(), query.relationIds);
      expect(snapshot.value.entries[_first], isA<SelectedRelationPresent>());
      expect(snapshot.value.entries[_second], isA<SelectedRelationPresent>());
      expect(
        snapshot.value.entries[_foreign],
        isA<SelectedRelationNoLongerBlocking>(),
      );
      expect(snapshot.value.entries[_missing], isA<SelectedRelationMissing>());
      final first = snapshot.value.entries[_first] as SelectedRelationPresent;
      expect(first.details.source.activeRelationCount, 2);
      expect(first.details.related.activeRelationCount, 2);
      expect(
        diagnostics.events.whereType<SelectedRelationsReadDiagnosticsEvent>(),
        hasLength(2),
      );
    },
  );

  test(
    'выбранные связи получают разные разрешения из фактических шагов',
    () async {
      const choiceId = '018f0b5d-6b2e-7c80-8000-000000000201';
      const stepId = '018f0b5d-6b2e-7c80-8000-000000000202';
      await database.customStatement(
        '''
        INSERT INTO daily_choices
          (id, source_intention_id, selected_intention_id, choice_date, is_completed)
        VALUES (?, ?, ?, '2026-09-23', 0)
      ''',
        [choiceId, _owner.toCanonicalString(), _neighbor.toCanonicalString()],
      );
      await database.customStatement(
        '''
        INSERT INTO daily_choice_path_steps
          (id, daily_choice_id, long_term_relation_id)
        VALUES (?, ?, ?)
      ''',
        [stepId, choiceId, _first.toCanonicalString()],
      );

      final result = await repository.getSelectedRelations(
        SelectedRelationsQuery(
          intentionId: _owner,
          relationIds: [_first, _second],
        ),
      );
      final entries =
          (result as SelectedRelationsReadSuccess).value.value.entries;
      final first = entries[_first] as SelectedRelationPresent;
      final second = entries[_second] as SelectedRelationPresent;
      expect(
        first.details.permissions.restriction,
        LongTermRelationPermissionRestriction.referencedByDailyPath,
      );
      expect(second.details.permissions.canDelete, isTrue);
    },
  );

  test('наблюдает один набор при изменении участника и счётчика', () async {
    final query = SelectedRelationsQuery(
      intentionId: _owner,
      relationIds: [_first, _second],
    );
    final events = StreamIterator(repository.watchSelectedRelations(query));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    final first = (events.current as SelectedRelationsReadSuccess).value;

    await repository.execute(
      UpdateIntention(id: _neighbor, title: 'Новое имя', description: null),
    );
    expect(await events.moveNext(), isTrue);
    final renamed = (events.current as SelectedRelationsReadSuccess).value;
    expect(
      renamed.revision.compareTo(first.revision),
      GraphRevisionOrder.newer,
    );
    expect(
      (renamed.value.entries[_first] as SelectedRelationPresent)
          .details
          .related
          .title,
      'Новое имя',
    );

    await repository.execute(DeleteLongTermRelation(_foreign));
    expect(await events.moveNext(), isTrue);
    final recounted = (events.current as SelectedRelationsReadSuccess).value;
    expect(
      (recounted.value.entries[_first] as SelectedRelationPresent)
          .details
          .related
          .activeRelationCount,
      1,
    );
  });

  test(
    'наблюдает разрешение ранее выбранной связи при изменении пути',
    () async {
      await database.customStatement(
        'UPDATE intentions SET is_action_ready = 1 WHERE id = ?',
        [_neighbor.toCanonicalString()],
      );
      final query = SelectedRelationsQuery(
        intentionId: _owner,
        relationIds: [_first, _second],
      );
      final events = StreamIterator(repository.watchSelectedRelations(query));
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      final initial = (events.current as SelectedRelationsReadSuccess).value;

      final creation = await repository.execute(
        CreateDailyChoice(
          sourceIntentionId: _owner,
          selectedIntentionId: _neighbor,
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: _first,
              sourceIntentionId: _owner,
              type: LongTermRelationType.need,
              relatedIntentionId: _neighbor,
            ),
          ]),
          date: CalendarDate.fromParts(2026, 9, 23),
          description: null,
          isCompleted: false,
        ),
      );
      final choiceId =
          ((creation as GraphCommandSucceeded).value.value
                  as DailyChoiceCreated)
              .choice
              .id;
      expect(await events.moveNext(), isTrue);
      final occupied = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        occupied.revision.compareTo(initial.revision),
        GraphRevisionOrder.newer,
      );
      expect(
        (occupied.value.entries[_first] as SelectedRelationPresent)
            .details
            .permissions
            .canDelete,
        isFalse,
      );
      expect(
        (occupied.value.entries[_second] as SelectedRelationPresent)
            .details
            .permissions
            .canDelete,
        isTrue,
      );

      await repository.execute(DeleteDailyChoice(choiceId));
      expect(await events.moveNext(), isTrue);
      final released = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        released.revision.compareTo(occupied.revision),
        GraphRevisionOrder.newer,
      );
      expect(
        (released.value.entries[_first] as SelectedRelationPresent)
            .details
            .permissions
            .canDelete,
        isTrue,
      );
    },
  );

  test('объединяет два инвалидирования в один новый снимок', () async {
    final query = SelectedRelationsQuery(
      intentionId: _owner,
      relationIds: [_first, _second],
    );
    final events = StreamIterator(repository.watchSelectedRelations(query));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    final initial = (events.current as SelectedRelationsReadSuccess).value;

    await repository.execute(
      UpdateIntention(id: _neighbor, title: 'Новый сосед', description: null),
    );
    await repository.execute(
      UpdateIntention(id: _other, title: 'Новый другой', description: null),
    );

    expect(await events.moveNext(), isTrue);
    final latest = (events.current as SelectedRelationsReadSuccess).value;
    expect(
      latest.revision.compareTo(initial.revision),
      GraphRevisionOrder.newer,
    );
    expect(
      (latest.value.entries[_first] as SelectedRelationPresent)
          .details
          .related
          .title,
      'Новый сосед',
    );
    expect(
      (latest.value.entries[_second] as SelectedRelationPresent)
          .details
          .source
          .title,
      'Новый другой',
    );
    expect(observer.selectedReads, 2);
  });

  test('наблюдение явно сообщает утрату принадлежности и удаление', () async {
    final query = SelectedRelationsQuery(
      intentionId: _owner,
      relationIds: [_first, _second],
    );
    final events = StreamIterator(repository.watchSelectedRelations(query));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);

    await repository.execute(
      UpdateLongTermRelation(
        relationId: _first,
        patch: LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(_other),
        ),
      ),
    );
    expect(await events.moveNext(), isTrue);
    final moved = (events.current as SelectedRelationsReadSuccess).value;
    expect(
      moved.value.entries[_first],
      isA<SelectedRelationNoLongerBlocking>(),
    );
    expect(moved.value.entries[_second], isA<SelectedRelationPresent>());

    await repository.execute(DeleteLongTermRelation(_second));
    expect(await events.moveNext(), isTrue);
    final deleted = (events.current as SelectedRelationsReadSuccess).value;
    expect(
      deleted.value.entries[_first],
      isA<SelectedRelationNoLongerBlocking>(),
    );
    expect(deleted.value.entries[_second], isA<SelectedRelationMissing>());
  });

  test('повреждение одной выбранной связи отказывает всему набору', () async {
    await database.customStatement('PRAGMA ignore_check_constraints = ON');
    await database.customStatement(
      'UPDATE long_term_relations SET description = ? WHERE id = ?',
      [' ', _second.toCanonicalString()],
    );
    final result = await repository.getSelectedRelations(
      SelectedRelationsQuery(
        intentionId: _owner,
        relationIds: [_first, _second],
      ),
    );
    expect(
      result,
      isA<SelectedRelationsReadError>().having(
        (error) => error.failure,
        'отказ',
        isA<SelectedRelationsReadCorruptionFailure>(),
      ),
    );
  });

  test('недоступность одной SQL-порции не выдаёт частичный набор', () async {
    observer.failSelectedRead = true;
    final result = await repository.getSelectedRelations(
      SelectedRelationsQuery(
        intentionId: _owner,
        relationIds: [_first, _second],
      ),
    );
    expect(
      result,
      isA<SelectedRelationsReadError>().having(
        (error) => error.failure,
        'отказ',
        isA<SelectedRelationsReadUnavailableFailure>(),
      ),
    );
    expect(
      (diagnostics.events.last as SelectedRelationsReadDiagnosticsEvent).status,
      isA<DiagnosticsFailed>().having(
        (status) => status.code,
        'категория',
        DiagnosticsFailureCode.unavailable,
      ),
    );
  });

  test('смешанный набор различает виды, принадлежность и отсутствие', () async {
    final sameUuid = _choice(_first.toCanonicalString());
    final selectedRole = _choice(_relation(36).toCanonicalString());
    final foreign = _choice(_relation(30).toCanonicalString());
    final missing = _choice(_relation(31).toCanonicalString());
    _insertChoice(raw, sameUuid, source: _owner, selected: _neighbor);
    _insertChoice(raw, selectedRole, source: _other, selected: _owner);
    _insertChoice(raw, foreign, source: _neighbor, selected: _other);
    final query = SelectedRelationsQuery.mixed(
      intentionId: _owner,
      references: [
        LongTermBlockingRelationReference(_first),
        DailyChoiceBlockingRelationReference(sameUuid),
        DailyChoiceBlockingRelationReference(selectedRole),
        DailyChoiceBlockingRelationReference(foreign),
        DailyChoiceBlockingRelationReference(missing),
      ],
    );

    final result = await repository.getSelectedRelations(query);
    final entries =
        (result as SelectedRelationsReadSuccess).value.value.entriesByReference;
    expect(entries.keys.toSet(), query.references);
    expect(
      entries[LongTermBlockingRelationReference(_first)],
      isA<SelectedRelationPresent>(),
    );
    final daily = entries[DailyChoiceBlockingRelationReference(sameUuid)];
    expect(daily, isA<SelectedDailyChoicePresent>());
    expect((daily as SelectedDailyChoicePresent).item.source.id, _owner);
    expect(daily.item.selected.id, _neighbor);
    expect(daily.item.date, CalendarDate.fromParts(2026, 9, 23));
    expect(daily.canDelete, isTrue);
    final incoming =
        entries[DailyChoiceBlockingRelationReference(selectedRole)]
            as SelectedDailyChoicePresent;
    expect(incoming.item.source.id, _other);
    expect(incoming.item.selected.id, _owner);
    expect(
      entries[DailyChoiceBlockingRelationReference(foreign)],
      isA<SelectedDailyChoiceNoLongerBlocking>(),
    );
    expect(
      entries[DailyChoiceBlockingRelationReference(missing)],
      isA<SelectedDailyChoiceMissing>(),
    );
  });

  test(
    'наблюдает поля, участника, замену пути и удаление дневной связи',
    () async {
      final choiceId = _choice(_relation(32).toCanonicalString());
      _insertChoice(raw, choiceId, source: _owner, selected: _neighbor);
      raw.execute('UPDATE intentions SET is_action_ready = 1 WHERE id = ?', [
        _other.toCanonicalString(),
      ]);
      final reference = DailyChoiceBlockingRelationReference(choiceId);
      final events = StreamIterator(
        repository.watchSelectedRelations(
          SelectedRelationsQuery.mixed(
            intentionId: _owner,
            references: [reference],
          ),
        ),
      );
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      final initial = (events.current as SelectedRelationsReadSuccess).value;

      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: choiceId,
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 9, 24)),
            isCompleted: const DailyChoiceFieldSet(true),
          ),
        ),
      );
      expect(await events.moveNext(), isTrue);
      final changed = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        changed.revision.compareTo(initial.revision),
        GraphRevisionOrder.newer,
      );
      final item =
          (changed.value.entriesByReference[reference]
                  as SelectedDailyChoicePresent)
              .item;
      expect(item.date, CalendarDate.fromParts(2026, 9, 24));
      expect(item.isCompleted, isTrue);

      await repository.execute(
        UpdateIntention(
          id: _neighbor,
          title: 'Новое действие',
          description: null,
        ),
      );
      expect(await events.moveNext(), isTrue);
      final renamed = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        (renamed.value.entriesByReference[reference]
                as SelectedDailyChoicePresent)
            .item
            .selected
            .title,
        'Новое действие',
      );

      await repository.execute(
        ReplaceDailyChoicePath(
          choiceId: choiceId,
          sourceIntentionId: _neighbor,
          selectedIntentionId: _other,
          path: ConfirmedChoicePath([
            ConfirmedChoicePathStep(
              relationId: _foreign,
              sourceIntentionId: _neighbor,
              type: LongTermRelationType.need,
              relatedIntentionId: _other,
            ),
          ]),
        ),
      );
      expect(await events.moveNext(), isTrue);
      final moved = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        moved.value.entriesByReference[reference],
        isA<SelectedDailyChoiceNoLongerBlocking>(),
      );

      await repository.execute(DeleteDailyChoice(choiceId));
      expect(await events.moveNext(), isTrue);
      final deleted = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        deleted.value.entriesByReference[reference],
        isA<SelectedDailyChoiceMissing>(),
      );
    },
  );

  test(
    'разрешение связи меняется только после удаления последней ссылки',
    () async {
      final firstChoice = _choice(_relation(33).toCanonicalString());
      final secondChoice = _choice(_relation(34).toCanonicalString());
      _insertChoice(raw, firstChoice, source: _owner, selected: _neighbor);
      _insertChoice(raw, secondChoice, source: _owner, selected: _neighbor);
      final relationReference = LongTermBlockingRelationReference(_first);
      final events = StreamIterator(
        repository.watchSelectedRelations(
          SelectedRelationsQuery.mixed(
            intentionId: _owner,
            references: [
              relationReference,
              DailyChoiceBlockingRelationReference(firstChoice),
              DailyChoiceBlockingRelationReference(secondChoice),
            ],
          ),
        ),
      );
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      expect(
        (events.current as SelectedRelationsReadSuccess)
            .value
            .value
            .entriesByReference[relationReference],
        isA<SelectedRelationPresent>().having(
          (entry) => entry.canDelete,
          'удаление',
          isFalse,
        ),
      );

      await repository.execute(DeleteDailyChoice(firstChoice));
      expect(await events.moveNext(), isTrue);
      final remaining = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        (remaining.value.entriesByReference[relationReference]
                as SelectedRelationPresent)
            .canDelete,
        isFalse,
      );
      expect(
        remaining.value.entriesByReference[DailyChoiceBlockingRelationReference(
          firstChoice,
        )],
        isA<SelectedDailyChoiceMissing>(),
      );

      await repository.execute(DeleteDailyChoice(secondChoice));
      expect(await events.moveNext(), isTrue);
      final released = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        (released.value.entriesByReference[relationReference]
                as SelectedRelationPresent)
            .canDelete,
        isTrue,
      );
    },
  );

  test('читает 405 выбранных дневных связей ограниченными пакетами', () async {
    final ids = <DailyChoiceId>[];
    for (var number = 500; number < 905; number++) {
      final id = _choice(_relation(number).toCanonicalString());
      ids.add(id);
      _insertChoice(raw, id, source: _owner, selected: _neighbor);
    }
    final query = SelectedRelationsQuery.mixed(
      intentionId: _owner,
      references: [
        LongTermBlockingRelationReference(_first),
        ...ids.map(DailyChoiceBlockingRelationReference.new),
      ],
    );

    final result = await repository.getSelectedRelations(query);
    final entries =
        (result as SelectedRelationsReadSuccess).value.value.entriesByReference;
    expect(entries.length, ids.length + 1);
    expect(
      entries[LongTermBlockingRelationReference(_first)],
      isA<SelectedRelationPresent>(),
    );
    expect(
      entries.values.whereType<SelectedDailyChoicePresent>(),
      hasLength(ids.length),
    );
    expect(observer.dailyReads, 2);

    observer.failDailyReadAt = observer.dailyReads + 2;
    final unavailable = await repository.getSelectedRelations(query);
    expect(
      unavailable,
      isA<SelectedRelationsReadError>().having(
        (error) => error.failure,
        'отказ всего набора',
        isA<SelectedRelationsReadUnavailableFailure>(),
      ),
    );
    observer.failDailyReadAt = null;

    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [ids.last.toCanonicalString()],
    );
    final corrupted = await repository.getSelectedRelations(query);
    expect(
      corrupted,
      isA<SelectedRelationsReadError>().having(
        (error) => error.failure,
        'отказ всего набора',
        isA<SelectedRelationsReadCorruptionFailure>(),
      ),
    );
  });

  test(
    'смешанное наблюдение пропускает поздний снимок и снимает регистрацию',
    () async {
      final choiceId = _choice(_relation(35).toCanonicalString());
      _insertChoice(raw, choiceId, source: _owner, selected: _neighbor);
      final reference = DailyChoiceBlockingRelationReference(choiceId);
      final events = StreamIterator(
        repository.watchSelectedRelations(
          SelectedRelationsQuery.mixed(
            intentionId: _owner,
            references: [LongTermBlockingRelationReference(_first), reference],
          ),
        ),
      );
      addTearDown(events.cancel);
      expect(await events.moveNext(), isTrue);
      final initial = (events.current as SelectedRelationsReadSuccess).value;

      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: choiceId,
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      await repository.execute(
        UpdateIntention(
          id: _neighbor,
          title: 'Актуальное имя',
          description: null,
        ),
      );
      expect(await events.moveNext(), isTrue);
      final latest = (events.current as SelectedRelationsReadSuccess).value;
      expect(
        latest.revision.compareTo(initial.revision),
        GraphRevisionOrder.newer,
      );
      final item =
          (latest.value.entriesByReference[reference]
                  as SelectedDailyChoicePresent)
              .item;
      expect(item.isCompleted, isTrue);
      expect(item.selected.title, 'Актуальное имя');
      expect(observer.dailyReads, 2);

      await events.cancel();
      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: choiceId,
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(false),
          ),
        ),
      );
      expect(observer.dailyReads, 2);
    },
  );
}

DailyChoiceId _choice(String uuid) =>
    (DailyChoiceId.decode(uuid) as DailyChoiceIdDecodingSuccess).id;

void _insertChoice(
  Database raw,
  DailyChoiceId id, {
  required IntentionId source,
  required IntentionId selected,
}) {
  raw.execute(
    '''INSERT INTO daily_choices
       (id, source_intention_id, selected_intention_id, choice_date, is_completed)
       VALUES (?, ?, ?, '2026-09-23', 0)''',
    [
      id.toCanonicalString(),
      source.toCanonicalString(),
      selected.toCanonicalString(),
    ],
  );
  raw.execute(
    '''INSERT INTO daily_choice_path_steps
       (id, daily_choice_id, long_term_relation_id) VALUES (?, ?, ?)''',
    [
      id.toCanonicalString(),
      id.toCanonicalString(),
      (source == _owner
              ? _first
              : source == _neighbor
              ? _foreign
              : _second)
          .toCanonicalString(),
    ],
  );
}

final class _SelectedReadFailureObserver
    extends LocalDatabaseConnectionObserver {
  var failSelectedRead = false;
  var selectedReads = 0;
  var dailyReads = 0;
  int? failDailyReadAt;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('FROM daily_choices') &&
        statement.statements.single.contains('WHERE id IN (')) {
      dailyReads++;
      if (dailyReads == failDailyReadAt) {
        throw SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY,
          message: 'Временная недоступность',
        );
      }
    }
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('WHERE id IN (')) {
      selectedReads++;
      if (!failSelectedRead) return;
      throw SqliteException(
        extendedResultCode: SqlError.SQLITE_BUSY,
        message: 'Временная недоступность',
      );
    }
  }
}

IntentionId _intention(int index) => (IntentionId.decode(
  '018f0b5d-6b2e-7c80-8001-${index.toRadixString(16).padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relation(int index) => (LongTermRelationId.decode(
  '018f0b5d-6b2e-7c80-8002-${index.toRadixString(16).padLeft(12, '0')}',
) as LongTermRelationIdDecodingSuccess).id;

final _owner = _intention(1);
final _neighbor = _intention(2);
final _other = _intention(3);
final _first = _relation(1);
final _second = _relation(2);
final _foreign = _relation(3);
final _missing = _relation(4);
