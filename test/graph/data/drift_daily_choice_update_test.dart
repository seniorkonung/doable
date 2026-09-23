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

final class _ResultReadFailure extends LocalDatabaseConnectionObserver {
  bool failSecondChoiceRead = false;
  int choiceReads = 0;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains(
          'FROM daily_choices WHERE id = ?',
        )) {
      choiceReads++;
      if (failSecondChoiceRead && choiceReads == 2) {
        throw StateError('Сбой после записи');
      }
    }
  }
}

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ResultReadFailure readFailure;

  setUp(() async {
    readFailure = _ResultReadFailure();
    diagnostics = InMemoryDiagnosticsSink();
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
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
    for (var number = 1; number <= 2; number++) {
      raw.execute(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number', number == 2 ? 1 : 0],
      );
    }
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority, is_archived)
         VALUES (?, ?, ?, 'need', 2, 0)''',
      [_uuid(101), _uuid(1), _uuid(2)],
    );
  });

  tearDown(() => database.close());

  Future<DailyChoiceId> createChoice({
    String? description = ' Прежнее\nописание ',
  }) async {
    final result = await repository.execute(
      CreateDailyChoice(
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(2),
        path: ConfirmedChoicePath([
          ConfirmedChoicePathStep(
            relationId: _relation(101),
            sourceIntentionId: _intention(1),
            type: LongTermRelationType.need,
            relatedIntentionId: _intention(2),
          ),
        ]),
        date: CalendarDate.fromParts(2026, 9, 23),
        description: description == null
            ? null
            : DailyChoiceDescription.fromInput(description),
        isCompleted: true,
      ),
    );
    return ((result as GraphCommandSucceeded).value.value as DailyChoiceCreated)
        .choice
        .id;
  }

  Future<GraphSnapshot<DailyChoiceDetails?>> read(DailyChoiceId id) async =>
      (await repository.getDailyChoice(id) as DailyChoiceReadSuccess).value;

  test(
    'меняет дату независимо от архивного пути и готовности действия',
    () async {
      final id = await createChoice();
      final before = (await read(id)).value!;
      final sequence = raw.select(
        'SELECT creation_sequence FROM daily_choices WHERE id = ?',
        [id.toCanonicalString()],
      ).single['creation_sequence'];
      raw.execute(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [_uuid(101)],
      );
      raw.execute('UPDATE intentions SET is_action_ready = 0 WHERE id = ?', [
        _uuid(2),
      ]);

      final result = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: id,
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 2)),
          ),
        ),
      );

      final confirmed = (result as GraphCommandSucceeded).value;
      final updated = confirmed.value as DailyChoiceFieldsUpdated;
      final after = (await read(id)).value!;
      expect(updated.changes, hasLength(1));
      expect(
        (updated.changes.single as DailyChoiceChange).releasedRelationIds,
        isEmpty,
      );
      expect(updated.choice.date.toCanonicalString(), '2027-01-02');
      expect(after.choice.description, before.choice.description);
      expect(after.choice.isCompleted, isTrue);
      expect(after.choice.sourceIntentionId, before.choice.sourceIntentionId);
      expect(
        after.choice.selectedIntentionId,
        before.choice.selectedIntentionId,
      );
      expect(
        after.path.map((item) => item.step.id),
        before.path.map((item) => item.step.id),
      );
      expect(after.path.single.relation.scope, RelationScope.archived);
      expect(
        raw.select('SELECT choice_date FROM daily_choices WHERE id = ?', [
          id.toCanonicalString(),
        ]).single['choice_date'],
        '2027-01-02',
      );
      expect(
        raw.select('SELECT creation_sequence FROM daily_choices WHERE id = ?', [
          id.toCanonicalString(),
        ]).single['creation_sequence'],
        sequence,
      );
      final stages = diagnostics.events
          .whereType<DailyChoiceCommandDiagnosticsEvent>()
          .where(
            (event) =>
                event.commandType ==
                DailyChoiceCommandDiagnosticsType.updateFields,
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
    },
  );

  test('дата не зависит от часового пояса часов репозитория', () async {
    final id = await createChoice();
    final changed = await repository.execute(
      UpdateDailyChoiceFields(
        choiceId: id,
        patch: DailyChoiceFieldsPatch(
          date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 12, 31)),
        ),
      ),
    );
    expect(changed, isA<GraphCommandSucceeded>());
    final otherZoneRepository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.parse('2027-01-01T01:00:00+14:00'),
      diagnostics,
    );
    final reread = await otherZoneRepository.getDailyChoice(id);
    expect(
      (reread as DailyChoiceReadSuccess).value.value!.choice.date,
      CalendarDate.fromParts(2026, 12, 31),
    );
  });

  test(
    'меняет описание и выполнение независимо и позволяет очистить описание',
    () async {
      final id = await createChoice();
      final other = await createChoice();
      final otherBefore = (await read(other)).value!;
      const text = '  Новое\nописание  ';
      final first = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: id,
          patch: DailyChoiceFieldsPatch(
            description: DailyChoiceDescriptionSet(
              DailyChoiceDescription.fromInput(text)!,
            ),
            isCompleted: const DailyChoiceFieldSet(false),
          ),
        ),
      );
      expect(first, isA<GraphCommandSucceeded>());
      var after = (await read(id)).value!;
      expect(after.choice.description!.value, text);
      expect(after.choice.isCompleted, isFalse);
      expect(after.choice.date, CalendarDate.fromParts(2026, 9, 23));

      final second = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: id,
          patch: const DailyChoiceFieldsPatch(
            description: DailyChoiceDescriptionCleared(),
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      );
      expect(second, isA<GraphCommandSucceeded>());
      after = (await read(id)).value!;
      expect(after.choice.description, isNull);
      expect(after.choice.isCompleted, isTrue);
      expect(
        (await read(other)).value!.choice.description,
        otherBefore.choice.description,
      );
      expect(
        (await read(other)).value!.choice.isCompleted,
        otherBefore.choice.isCompleted,
      );
    },
  );

  test('пустая правка и прежние значения не продвигают ревизию', () async {
    final id = await createChoice();
    final before = await read(id);
    for (final patch in [
      const DailyChoiceFieldsPatch(),
      DailyChoiceFieldsPatch(
        date: DailyChoiceFieldSet(CalendarDate.fromParts(2026, 9, 23)),
        description: DailyChoiceDescriptionSet(
          DailyChoiceDescription.fromInput(' Прежнее\nописание ')!,
        ),
        isCompleted: const DailyChoiceFieldSet(true),
      ),
    ]) {
      final result = await repository.execute(
        UpdateDailyChoiceFields(choiceId: id, patch: patch),
      );
      final confirmed = (result as GraphCommandSucceeded).value;
      expect(confirmed.value, isA<DailyChoiceFieldsUpdated>());
      expect(
        confirmed.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      expect(
        (await read(id)).revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
    }
  });

  test('отсутствующая запись не создаётся и не меняет ревизию', () async {
    final before = await read(_choice(999));
    final result = await repository.execute(
      UpdateDailyChoiceFields(
        choiceId: _choice(999),
        patch: DailyChoiceFieldsPatch(
          date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 1)),
        ),
      ),
    );
    expect(
      (result as GraphCommandFailed).failure,
      isA<DailyChoiceNotFoundFailure>(),
    );
    expect(
      (await read(_choice(999))).revision.compareTo(before.revision),
      GraphRevisionOrder.same,
    );
  });

  test('неверное описание не допускает составную команду', () async {
    final id = await createChoice();
    final before = await read(id);
    expect(
      () => UpdateDailyChoiceFields(
        choiceId: id,
        patch: DailyChoiceFieldsPatch(
          date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 1)),
          description: DailyChoiceDescriptionSet(
            DailyChoiceDescription.fromInput('x' * 4097)!,
          ),
        ),
      ),
      throwsA(
        isA<DailyChoiceDescriptionValidationException>().having(
          (error) => error.failure.reason,
          'причина',
          DailyChoiceDescriptionValidationReason.tooLong,
        ),
      ),
    );
    final after = await read(id);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.same);
    expect(after.value!.choice.date, before.value!.choice.date);
    expect(after.value!.choice.description, before.value!.choice.description);
  });

  test(
    'повреждённое сохранённое описание отклоняет составную правку',
    () async {
      final id = await createChoice();
      raw.execute('UPDATE daily_choices SET description = ? WHERE id = ?', [
        '   ',
        id.toCanonicalString(),
      ]);
      final result = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: id,
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 1)),
            isCompleted: const DailyChoiceFieldSet(false),
          ),
        ),
      );
      expect(
        (result as GraphCommandFailed).failure,
        isA<DailyChoiceCorruptionFailure>(),
      );
      final stored = raw.select(
        'SELECT choice_date, is_completed FROM daily_choices WHERE id = ?',
        [id.toCanonicalString()],
      ).single;
      expect(stored['choice_date'], '2026-09-23');
      expect(stored['is_completed'], 1);
    },
  );

  test(
    'сбой чтения результата откатывает все поля и не продвигает ревизию',
    () async {
      final id = await createChoice();
      final before = await read(id);
      readFailure.choiceReads = 0;
      readFailure.failSecondChoiceRead = true;
      final result = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: id,
          patch: DailyChoiceFieldsPatch(
            date: DailyChoiceFieldSet(CalendarDate.fromParts(2027, 1, 1)),
            description: const DailyChoiceDescriptionCleared(),
            isCompleted: const DailyChoiceFieldSet(false),
          ),
        ),
      );
      readFailure.failSecondChoiceRead = false;
      expect(
        (result as GraphCommandFailed).failure.category,
        GraphFailureCategory.unexpected,
      );
      final after = await read(id);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      expect(after.value!.choice.date, before.value!.choice.date);
      expect(after.value!.choice.description, before.value!.choice.description);
      expect(after.value!.choice.isCompleted, before.value!.choice.isCompleted);
      final last = diagnostics.events
          .whereType<DailyChoiceCommandDiagnosticsEvent>()
          .last;
      expect(last.commandType, DailyChoiceCommandDiagnosticsType.updateFields);
      expect(last.stage, DailyChoiceCommandDiagnosticsStage.resultRead);
      expect(
        (last.status as DiagnosticsFailed).code,
        DiagnosticsFailureCode.unexpected,
      );
    },
  );

  test(
    'сбой записи диагностируется отдельно и сохраняет прежние поля',
    () async {
      final id = await createChoice();
      final before = await read(id);
      raw.execute('''CREATE TRIGGER reject_daily_choice_update
        BEFORE UPDATE ON daily_choices
        BEGIN SELECT RAISE(ABORT, 'Отказ записи'); END''');
      final result = await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: id,
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(false),
          ),
        ),
      );
      expect(
        (result as GraphCommandFailed).failure.category,
        GraphFailureCategory.unexpected,
      );
      final after = await read(id);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.same,
      );
      expect(after.value!.choice.isCompleted, isTrue);
      final last = diagnostics.events
          .whereType<DailyChoiceCommandDiagnosticsEvent>()
          .last;
      expect(last.commandType, DailyChoiceCommandDiagnosticsType.updateFields);
      expect(last.stage, DailyChoiceCommandDiagnosticsStage.write);
      expect(last.status, isA<DiagnosticsFailed>());
    },
  );
}
