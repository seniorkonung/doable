import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_description.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';
IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;

final class _DeleteFailure extends LocalDatabaseConnectionObserver {
  bool failAfterDelete = false;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (failAfterDelete &&
        statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains('AS remaining_steps')) {
      throw StateError('Сбой проверки результата');
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _DeleteFailure failure;

  setUp(() async {
    failure = _DeleteFailure();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        failure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    for (var number = 1; number <= 3; number++) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number', number == 3 ? 1 : 0],
      );
    }
    for (final (number, source, target) in [(101, 1, 2), (102, 2, 3)]) {
      raw.execute(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived)
           VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(number), _uuid(source), _uuid(target)],
      );
    }
  });
  tearDown(() => database.close());

  Future<DailyChoiceId> createChoice({int length = 2}) async {
    final result = await repository.execute(
      CreateDailyChoice(
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(length + 1),
        path: ConfirmedChoicePath([
          for (var index = 1; index <= length; index++)
            ConfirmedChoicePathStep(
              relationId: _relation(100 + index),
              sourceIntentionId: _intention(index),
              type: LongTermRelationType.need,
              relatedIntentionId: _intention(index + 1),
            ),
        ]),
        date: CalendarDate.fromParts(2026, 9, 23),
        description: DailyChoiceDescription.fromInput(' Описание '),
        isCompleted: true,
      ),
    );
    return ((result as GraphCommandSucceeded).value.value as DailyChoiceCreated)
        .choice
        .id;
  }

  Future<GraphSnapshot<DailyChoiceDetails?>> read(DailyChoiceId id) async =>
      (await repository.getDailyChoice(id) as DailyChoiceReadSuccess).value;

  test('удаляет выполненный выбор с архивным путём и все его шаги', () async {
    final id = await createChoice();
    final before = await read(id);
    raw.execute('UPDATE long_term_relations SET is_archived = 1');
    raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
      _uuid(1),
    ]);
    raw.execute('UPDATE intentions SET is_action_ready = 0 WHERE id = ?', [
      _uuid(3),
    ]);

    final result = await repository.execute(DeleteDailyChoice(id));

    final confirmed = (result as GraphCommandSucceeded).value;
    final deleted = confirmed.value as DailyChoiceDeleted;
    final change = deleted.changes.single as DailyChoiceChange;
    expect(deleted.choice.id, id);
    expect(deleted.choice.isCompleted, isTrue);
    expect(deleted.choice.description!.value, ' Описание ');
    expect(change.before!.id, id);
    expect(change.after, isNull);
    expect(change.releasedRelationIds, {_relation(101), _relation(102)});
    expect(change.occupiedRelationIds, isEmpty);
    expect(change.intentionCounts[_intention(1)]!.dailySource, 0);
    expect(change.intentionCounts[_intention(3)]!.dailySelected, 0);
    expect(change.relationPermissions[_relation(101)]!.canDelete, isTrue);
    expect(change.relationPermissions[_relation(102)]!.canDelete, isTrue);
    expect((await read(id)).value, isNull);
    expect(raw.select('SELECT * FROM daily_choice_path_steps'), isEmpty);
    expect(raw.select('SELECT * FROM intentions'), hasLength(3));
    expect(raw.select('SELECT * FROM long_term_relations'), hasLength(2));
    expect(
      confirmed.revision.compareTo(before.revision),
      GraphRevisionOrder.newer,
    );
    final stages = diagnostics.events
        .whereType<DailyChoiceCommandDiagnosticsEvent>()
        .where(
          (event) =>
              event.commandType == DailyChoiceCommandDiagnosticsType.delete,
        )
        .toList();
    expect(stages.map((event) => event.stage), [
      DailyChoiceCommandDiagnosticsStage.validation,
      DailyChoiceCommandDiagnosticsStage.validation,
      DailyChoiceCommandDiagnosticsStage.write,
      DailyChoiceCommandDiagnosticsStage.write,
      DailyChoiceCommandDiagnosticsStage.resultRead,
      DailyChoiceCommandDiagnosticsStage.resultRead,
    ]);
    expect(stages.last.status, isA<DiagnosticsSucceeded>());
  });

  test('другая запись сохраняет прямую и путевую зависимости', () async {
    final removed = await createChoice();
    final retained = await createChoice();
    final result = await repository.execute(DeleteDailyChoice(removed));

    final change =
        ((result as GraphCommandSucceeded).value.value as DailyChoiceDeleted)
                .changes
                .single
            as DailyChoiceChange;
    expect((await read(retained)).value!.path, hasLength(2));
    expect(change.intentionCounts[_intention(1)]!.dailySource, 1);
    expect(change.intentionCounts[_intention(3)]!.dailySelected, 1);
    expect(change.relationPermissions[_relation(101)]!.canDelete, isFalse);
    expect(change.relationPermissions[_relation(102)]!.canDelete, isFalse);
    expect(raw.select('SELECT * FROM daily_choice_path_steps'), hasLength(2));
  });

  test('удаляет длинную цепочку без ограничения длины пути', () async {
    const length = 405;
    for (var index = 4; index <= length + 1; index++) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [_uuid(index), 'Намерение $index', index == length + 1 ? 1 : 0],
      );
    }
    for (var index = 3; index <= length; index++) {
      raw.execute(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived)
           VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(100 + index), _uuid(index), _uuid(index + 1)],
      );
    }
    final id = await createChoice(length: length);

    final result = await repository.execute(DeleteDailyChoice(id));

    final change =
        ((result as GraphCommandSucceeded).value.value as DailyChoiceDeleted)
                .changes
                .single
            as DailyChoiceChange;
    expect(change.releasedRelationIds, hasLength(length));
    expect(change.relationPermissions, hasLength(length));
    expect(raw.select('SELECT * FROM daily_choice_path_steps'), isEmpty);
  });

  test('сбой после записи откатывает удаление и ревизию', () async {
    final id = await createChoice();
    final before = await read(id);
    failure.failAfterDelete = true;

    final result = await repository.execute(DeleteDailyChoice(id));

    failure.failAfterDelete = false;
    expect(
      (result as GraphCommandFailed).failure,
      isA<DailyChoiceUnexpectedFailure>(),
    );
    final after = await read(id);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.same);
    expect(after.value!.path, hasLength(2));
    expect(raw.select('SELECT * FROM daily_choice_path_steps'), hasLength(2));
    final last = diagnostics.events
        .whereType<DailyChoiceCommandDiagnosticsEvent>()
        .last;
    expect(last.stage, DailyChoiceCommandDiagnosticsStage.resultRead);
    expect(
      (last.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.unexpected,
    );
  });

  test('повторное удаление сообщает об отсутствии без новой ревизии', () async {
    final id = await createChoice();
    final first = await repository.execute(DeleteDailyChoice(id));
    final revision = (first as GraphCommandSucceeded).value.revision;

    final second = await repository.execute(DeleteDailyChoice(id));

    expect(
      (second as GraphCommandFailed).failure,
      isA<DailyChoiceNotFoundFailure>(),
    );
    expect(
      (await read(id)).revision.compareTo(revision),
      GraphRevisionOrder.same,
    );
    expect(raw.select('SELECT * FROM daily_choices'), isEmpty);
  });
}
