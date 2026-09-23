import 'dart:async';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/selected_relations.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _SelectedReadFailureObserver observer;

  setUp(() async {
    observer = _SelectedReadFailureObserver();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
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
}

final class _SelectedReadFailureObserver
    extends LocalDatabaseConnectionObserver {
  var failSelectedRead = false;
  var selectedReads = 0;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
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
