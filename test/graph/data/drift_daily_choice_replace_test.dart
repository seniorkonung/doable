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
DailyChoiceId _choice(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

final class _WriteFailure extends LocalDatabaseConnectionObserver {
  bool failStepInsert = false;
  bool failResultRead = false;
  int choiceReads = 0;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains(
          'FROM daily_choices WHERE id = ?',
        )) {
      choiceReads++;
      if (failResultRead && choiceReads == 2) {
        throw StateError('Сбой чтения результата');
      }
    }
    if (failStepInsert &&
        statement.operation == LocalDatabaseSqlOperation.insert &&
        statement.statements.single.contains(
          'INSERT INTO daily_choice_path_steps',
        )) {
      throw StateError('Сбой записи шага');
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _WriteFailure writeFailure;

  setUp(() async {
    writeFailure = _WriteFailure();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        writeFailure,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    for (var number = 1; number <= 5; number++) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [
          _uuid(number),
          'Намерение $number',
          number == 3 || number == 4 ? 1 : 0,
        ],
      );
    }
    for (final (number, source, selected) in [
      (101, 1, 2),
      (102, 2, 3),
      (103, 2, 4),
      (104, 5, 4),
    ]) {
      raw.execute(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived)
           VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(number), _uuid(source), _uuid(selected)],
      );
    }
  });
  tearDown(() => database.close());

  ConfirmedChoicePath path(List<int> ids) => ConfirmedChoicePath([
    for (final number in ids)
      ConfirmedChoicePathStep(
        relationId: _relation(number),
        sourceIntentionId: _intention(switch (number) {
          101 => 1,
          102 || 103 => 2,
          104 => 5,
          _ => throw ArgumentError.value(number),
        }),
        type: LongTermRelationType.need,
        relatedIntentionId: _intention(switch (number) {
          101 => 2,
          102 => 3,
          103 || 104 => 4,
          _ => throw ArgumentError.value(number),
        }),
      ),
  ]);

  Future<DailyChoiceId> createChoice() async {
    final result = await repository.execute(
      CreateDailyChoice(
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(3),
        path: path([101, 102]),
        date: CalendarDate.fromParts(2026, 9, 23),
        description: DailyChoiceDescription.fromInput(' Описание\nвыбора '),
        isCompleted: true,
      ),
    );
    return ((result as GraphCommandSucceeded).value.value as DailyChoiceCreated)
        .choice
        .id;
  }

  Future<GraphSnapshot<DailyChoiceDetails?>> read(DailyChoiceId id) async =>
      (await repository.getDailyChoice(id) as DailyChoiceReadSuccess).value;

  ReplaceDailyChoicePath replace(
    DailyChoiceId id, {
    int source = 5,
    int selected = 4,
    List<int> relations = const [104],
  }) => ReplaceDailyChoicePath(
    choiceId: id,
    sourceIntentionId: _intention(source),
    selectedIntentionId: _intention(selected),
    path: path(relations),
  );

  test('заменяет участников и шаги архивного выполненного выбора', () async {
    final id = await createChoice();
    final before = await read(id);
    final sequence = raw.select(
      'SELECT creation_sequence FROM daily_choices WHERE id = ?',
      [id.toCanonicalString()],
    ).single['creation_sequence'];
    raw.execute('UPDATE long_term_relations SET is_archived = 1 WHERE id = ?', [
      _uuid(102),
    ]);

    final result = await repository.execute(replace(id));

    final confirmed = (result as GraphCommandSucceeded).value;
    final replaced = confirmed.value as DailyChoicePathReplaced;
    final after = (await read(id)).value!;
    expect(replaced.before.id, id);
    expect(after.choice.id, id);
    expect(after.choice.sourceIntentionId, _intention(5));
    expect(after.choice.selectedIntentionId, _intention(4));
    expect(after.choice.date, before.value!.choice.date);
    expect(after.choice.description, before.value!.choice.description);
    expect(after.choice.isCompleted, isTrue);
    expect(after.path.map((item) => item.relation.id), [_relation(104)]);
    expect(
      replaced.path.steps.map((step) => step.id),
      after.path.map((item) => item.step.id),
    );
    expect(
      raw.select('SELECT creation_sequence FROM daily_choices WHERE id = ?', [
        id.toCanonicalString(),
      ]).single['creation_sequence'],
      sequence,
    );
    expect(
      raw.select(
        'SELECT COUNT(*) AS total FROM daily_choice_path_steps WHERE daily_choice_id = ?',
        [id.toCanonicalString()],
      ).single['total'],
      1,
    );
    final change = replaced.changes.single as DailyChoiceChange;
    expect(change.releasedRelationIds, {_relation(101), _relation(102)});
    expect(change.occupiedRelationIds, {_relation(104)});
    expect(change.intentionCounts[_intention(1)]!.dailySource, 0);
    expect(change.intentionCounts[_intention(3)]!.dailySelected, 0);
    expect(change.intentionCounts[_intention(5)]!.dailySource, 1);
    expect(change.intentionCounts[_intention(4)]!.dailySelected, 1);
    expect(change.relationPermissions[_relation(101)]!.canDelete, isTrue);
    expect(change.relationPermissions[_relation(102)]!.canDelete, isTrue);
    expect(change.relationPermissions[_relation(104)]!.canDelete, isFalse);
    expect(
      change.revision.compareTo(confirmed.revision),
      GraphRevisionOrder.same,
    );
    expect(
      before.revision.compareTo(confirmed.revision),
      GraphRevisionOrder.older,
    );
    final stages = diagnostics.events
        .whereType<DailyChoiceCommandDiagnosticsEvent>()
        .where(
          (event) =>
              event.commandType ==
              DailyChoiceCommandDiagnosticsType.replacePath,
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

  test(
    'общий участок остаётся занятым, а непоследняя ссылка не освобождается',
    () async {
      final first = await createChoice();
      final second = await createChoice();

      final result = await repository.execute(
        replace(first, source: 1, relations: [101, 103]),
      );

      final change =
          ((result as GraphCommandSucceeded).value.value
                      as DailyChoicePathReplaced)
                  .changes
                  .single
              as DailyChoiceChange;
      expect(change.releasedRelationIds, {_relation(102)});
      expect(change.occupiedRelationIds, {_relation(103)});
      expect(change.relationPermissions[_relation(102)]!.canDelete, isFalse);
      expect(change.relationPermissions[_relation(103)]!.canDelete, isFalse);
      expect((await read(second)).value!.path.map((item) => item.relation.id), [
        _relation(101),
        _relation(102),
      ]);

      final last = await repository.execute(replace(second));
      final lastChange =
          ((last as GraphCommandSucceeded).value.value
                      as DailyChoicePathReplaced)
                  .changes
                  .single
              as DailyChoiceChange;
      expect(lastChange.relationPermissions[_relation(102)]!.canDelete, isTrue);
      expect(
        lastChange.relationPermissions[_relation(101)]!.canDelete,
        isFalse,
      );
    },
  );

  test(
    'недопустимый новый путь оставляет архивный старый путь целым',
    () async {
      final id = await createChoice();
      raw.execute(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [_uuid(102)],
      );
      raw.execute('UPDATE intentions SET is_action_ready = 0 WHERE id = ?', [
        _uuid(4),
      ]);
      final before = await read(id);

      final result = await repository.execute(replace(id));

      expect(
        (result as GraphCommandFailed).failure,
        isA<DailyChoiceConflictFailure>().having(
          (failure) => failure.reason,
          'причина',
          DailyChoiceConflictReason.selectedIntentionNotReady,
        ),
      );
      final after = await read(id);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      expect(
        after.value!.choice.sourceIntentionId,
        before.value!.choice.sourceIntentionId,
      );
      expect(
        after.value!.choice.selectedIntentionId,
        before.value!.choice.selectedIntentionId,
      );
      expect(
        after.value!.path.map((item) => item.step.id),
        before.value!.path.map((item) => item.step.id),
      );
    },
  );

  test('сбой после удаления прежних шагов откатывает всю замену', () async {
    final id = await createChoice();
    final before = await read(id);
    writeFailure.failStepInsert = true;

    final result = await repository.execute(replace(id));

    expect(
      (result as GraphCommandFailed).failure,
      isA<DailyChoiceUnexpectedFailure>(),
    );
    final after = await read(id);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.same);
    expect(
      after.value!.choice.sourceIntentionId,
      before.value!.choice.sourceIntentionId,
    );
    expect(
      after.value!.choice.selectedIntentionId,
      before.value!.choice.selectedIntentionId,
    );
    expect(
      after.value!.path.map((item) => item.step.id),
      before.value!.path.map((item) => item.step.id),
    );
    expect(
      after.value!.path.map((item) => item.relation.id),
      before.value!.path.map((item) => item.relation.id),
    );
  });

  test(
    'изменённый после подтверждения смысл пути сохраняет прежний выбор',
    () async {
      final id = await createChoice();
      final before = await read(id);
      raw.execute('UPDATE long_term_relations SET type = ? WHERE id = ?', [
        'can',
        _uuid(104),
      ]);

      final result = await repository.execute(replace(id));

      expect(
        (result as GraphCommandFailed).failure,
        isA<DailyChoiceConflictFailure>().having(
          (failure) => failure.reason,
          'причина',
          DailyChoiceConflictReason.confirmedPathChanged,
        ),
      );
      final after = await read(id);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      expect(
        after.value!.path.map((item) => item.step.id),
        before.value!.path.map((item) => item.step.id),
      );
      expect(
        diagnostics.events
            .whereType<DailyChoicePathValidationDiagnosticsEvent>()
            .last
            .status,
        isA<DiagnosticsFailed>(),
      );
    },
  );

  test(
    'повтор того же подтверждённого пути не меняет шаги и ревизию',
    () async {
      final id = await createChoice();
      final before = await read(id);

      final result = await repository.execute(
        replace(id, source: 1, selected: 3, relations: [101, 102]),
      );

      final confirmed = (result as GraphCommandSucceeded).value;
      final replaced = confirmed.value as DailyChoicePathReplaced;
      final after = await read(id);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      expect(
        after.value!.path.map((item) => item.step.id),
        before.value!.path.map((item) => item.step.id),
      );
      final change = replaced.changes.single as DailyChoiceChange;
      expect(change.releasedRelationIds, isEmpty);
      expect(change.occupiedRelationIds, isEmpty);
    },
  );

  test('сбой чтения результата откатывает участников и все шаги', () async {
    final id = await createChoice();
    final before = await read(id);
    writeFailure.choiceReads = 0;
    writeFailure.failResultRead = true;

    final result = await repository.execute(replace(id));

    expect(
      (result as GraphCommandFailed).failure,
      isA<DailyChoiceUnexpectedFailure>(),
    );
    writeFailure.failResultRead = false;
    final after = await read(id);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.same);
    expect(
      after.value!.choice.sourceIntentionId,
      before.value!.choice.sourceIntentionId,
    );
    expect(
      after.value!.choice.selectedIntentionId,
      before.value!.choice.selectedIntentionId,
    );
    expect(
      after.value!.path.map((item) => item.step.id),
      before.value!.path.map((item) => item.step.id),
    );
  });

  test('отсутствующий и повреждённый выбор не создаются заново', () async {
    final missing = await repository.execute(replace(_choice(999)));
    expect(
      (missing as GraphCommandFailed).failure,
      isA<DailyChoiceNotFoundFailure>(),
    );
    final id = await createChoice();
    raw.execute(
      'DELETE FROM daily_choice_path_steps WHERE daily_choice_id = ?',
      [id.toCanonicalString()],
    );
    final corrupt = await repository.execute(replace(id));
    expect(
      (corrupt as GraphCommandFailed).failure,
      isA<DailyChoiceCorruptionFailure>(),
    );
    expect(
      raw.select(
        'SELECT COUNT(*) AS total FROM daily_choice_path_steps WHERE daily_choice_id = ?',
        [id.toCanonicalString()],
      ).single['total'],
      0,
    );
  });
}
