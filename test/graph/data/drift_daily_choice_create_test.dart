import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/application/daily_choice_result.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int n) =>
    '018f0b5d-6b2e-7c80-8000-${n.toRadixString(16).padLeft(12, '0')}';
IntentionId _intention(int n) =>
    (IntentionId.decode(_uuid(n)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int n) => (LongTermRelationId.decode(
  _uuid(n),
) as LongTermRelationIdDecodingSuccess).id;
DailyChoiceId _choice(int n) =>
    (DailyChoiceId.decode(_uuid(n)) as DailyChoiceIdDecodingSuccess).id;
ChoicePathStepId _step(int n) =>
    (ChoicePathStepId.decode(_uuid(n)) as ChoicePathStepIdDecodingSuccess).id;

final class _ChoiceIds implements DailyChoiceIdGenerator {
  _ChoiceIds(this.values);
  final List<DailyChoiceId> values;
  @override
  DailyChoiceId generate() => values.removeAt(0);
}

final class _StepIds implements ChoicePathStepIdGenerator {
  _StepIds(this.values);
  final List<ChoicePathStepId> values;
  @override
  ChoicePathStepId generate() => values.removeAt(0);
}

void main() {
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late InMemoryDiagnosticsSink diagnostics;
  late _ChoiceIds choiceIds;
  late _StepIds stepIds;
  late _ReadFailureProbe readProbe;

  setUp(() async {
    readProbe = _ReadFailureProbe();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        readProbe,
      ),
    );
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    choiceIds = _ChoiceIds([_choice(201), _choice(202)]);
    stepIds = _StepIds([_step(301), _step(302), _step(303), _step(304)]);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
      dailyChoiceIdGenerator: choiceIds,
      choicePathStepIdGenerator: stepIds,
    );
    for (var n = 1; n <= 3; n++) {
      await database.customInsert(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        variables: [
          Variable.withString(_uuid(n)),
          Variable.withString('Намерение $n'),
          Variable.withInt(n == 3 ? 1 : 0),
        ],
      );
    }
    for (final (n, source, target, type) in [
      (101, 1, 2, 'need'),
      (102, 2, 3, 'can'),
    ]) {
      await database.customInsert(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority, is_archived)
           VALUES (?, ?, ?, ?, 2, 0)''',
        variables: [
          Variable.withString(_uuid(n)),
          Variable.withString(_uuid(source)),
          Variable.withString(_uuid(target)),
          Variable.withString(type),
        ],
      );
    }
  });
  tearDown(() => database.close());

  ConfirmedChoicePath route([int length = 2]) => ConfirmedChoicePath([
    ConfirmedChoicePathStep(
      relationId: _relation(101),
      sourceIntentionId: _intention(1),
      type: LongTermRelationType.need,
      relatedIntentionId: _intention(2),
    ),
    if (length == 2)
      ConfirmedChoicePathStep(
        relationId: _relation(102),
        sourceIntentionId: _intention(2),
        type: LongTermRelationType.can,
        relatedIntentionId: _intention(3),
      ),
  ]);

  CreateDailyChoice command({ConfirmedChoicePath? path, int selected = 3}) =>
      CreateDailyChoice(
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(selected),
        path: path ?? route(),
        date: CalendarDate.fromParts(2026, 9, 23),
        description: null,
        isCompleted: true,
      );

  Future<int> rows(String table) async =>
      (await database
              .customSelect('SELECT COUNT(*) AS total FROM $table')
              .getSingle())
          .read<int>('total');

  test('сохраняет подтверждённый путь и публикует одну ревизию', () async {
    final before = await repository.getDailyChoice(_choice(201));
    final result = await repository.execute(command());
    expect(result, isA<GraphCommandSucceeded>());
    final confirmed = (result as GraphCommandSucceeded).value;
    final created = confirmed.value as DailyChoiceCreated;
    expect(created.choice.id, _choice(201));
    expect(created.choice.isCompleted, isTrue);
    expect(created.path.steps.map((s) => s.relationId), [
      _relation(101),
      _relation(102),
    ]);
    expect(created.path.steps.map((s) => s.previousStepId), [null, _step(301)]);
    expect(created.changes, hasLength(1));
    final change = created.changes.single as DailyChoiceChange;
    expect(
      change.revision.compareTo(confirmed.revision),
      GraphRevisionOrder.same,
    );
    expect(change.intentionCounts[_intention(1)]!.dailySource, 1);
    expect(change.intentionCounts[_intention(3)]!.dailySelected, 1);
    expect(change.relationPermissions[_relation(101)]!.canDelete, isFalse);
    expect(
      (before as DailyChoiceReadSuccess).value.revision.compareTo(
        confirmed.revision,
      ),
      GraphRevisionOrder.older,
    );
    expect(await rows('daily_choices'), 1);
    expect(await rows('daily_choice_path_steps'), 2);
    expect(
      (await repository.getDailyChoice(
        _choice(201),
      ) as GraphResultSuccess).value.value!.path,
      hasLength(2),
    );
    expect(
      diagnostics.events
          .whereType<DailyChoiceCommandDiagnosticsEvent>()
          .last
          .status,
      isA<DiagnosticsSucceeded>(),
    );
  });

  test('полный повтор создаёт самостоятельную запись', () async {
    expect(await repository.execute(command()), isA<GraphCommandSucceeded>());
    final second = await repository.execute(command());
    expect(
      ((second as GraphCommandSucceeded).value.value as DailyChoiceCreated)
          .choice
          .id,
      _choice(202),
    );
    expect(await rows('daily_choices'), 2);
    expect(await rows('daily_choice_path_steps'), 4);
  });

  test('изменённый смысл маршрута возвращает конфликт без записи', () async {
    await database.customUpdate(
      "UPDATE long_term_relations SET type = 'need' WHERE id = ?",
      variables: [Variable.withString(_uuid(102))],
    );
    final result = await repository.execute(command());
    expect(
      result,
      isA<GraphCommandFailed>().having(
        (r) => r.failure,
        'причина',
        isA<DailyChoiceConflictFailure>().having(
          (f) => f.reason,
          'маршрут',
          DailyChoiceConflictReason.confirmedPathChanged,
        ),
      ),
    );
    expect(await rows('daily_choices'), 0);
    expect(await rows('daily_choice_path_steps'), 0);
  });

  test('допускает готовое исходное действие и один переход', () async {
    await database.customUpdate(
      'UPDATE intentions SET is_action_ready = 1 WHERE id = ?',
      variables: [Variable.withString(_uuid(1))],
    );
    await database.customUpdate(
      'UPDATE intentions SET is_action_ready = 1 WHERE id = ?',
      variables: [Variable.withString(_uuid(2))],
    );
    final result = await repository.execute(
      command(path: route(1), selected: 2),
    );
    expect(result, isA<GraphCommandSucceeded>());
    expect(
      ((result as GraphCommandSucceeded).value.value as DailyChoiceCreated)
          .path
          .steps,
      hasLength(1),
    );
  });

  test('отклоняет разрыв, цикл и неверную границу до записи', () async {
    final invalidRoutes = [
      ConfirmedChoicePath([
        ConfirmedChoicePathStep(
          relationId: _relation(102),
          sourceIntentionId: _intention(2),
          type: LongTermRelationType.can,
          relatedIntentionId: _intention(3),
        ),
      ]),
      ConfirmedChoicePath([
        ...route().steps,
        ConfirmedChoicePathStep(
          relationId: _relation(101),
          sourceIntentionId: _intention(3),
          type: LongTermRelationType.need,
          relatedIntentionId: _intention(1),
        ),
      ]),
      route(1),
    ];
    for (final path in invalidRoutes) {
      final result = await repository.execute(command(path: path));
      expect(
        result,
        isA<GraphCommandFailed>().having(
          (r) => r.failure.category,
          'категория',
          GraphFailureCategory.validation,
        ),
      );
    }
    expect(await rows('daily_choices'), 0);
  });

  test('архив и утрата готовности дают разные конфликты', () async {
    await database.customUpdate(
      'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
      variables: [Variable.withString(_uuid(102))],
    );
    var result = await repository.execute(command());
    expect(
      (result as GraphCommandFailed).failure,
      isA<DailyChoiceConflictFailure>().having(
        (f) => f.reason,
        'причина',
        DailyChoiceConflictReason.relationArchived,
      ),
    );
    await database.customUpdate(
      'UPDATE long_term_relations SET is_archived = 0 WHERE id = ?',
      variables: [Variable.withString(_uuid(102))],
    );
    await database.customUpdate(
      'UPDATE intentions SET is_action_ready = 0 WHERE id = ?',
      variables: [Variable.withString(_uuid(3))],
    );
    result = await repository.execute(command());
    expect(
      (result as GraphCommandFailed).failure,
      isA<DailyChoiceConflictFailure>().having(
        (f) => f.reason,
        'причина',
        DailyChoiceConflictReason.selectedIntentionNotReady,
      ),
    );
    expect(await rows('daily_choices'), 0);
  });

  test(
    'повреждение сохранённой связи отличается от конфликта маршрута',
    () async {
      await database.customStatement('PRAGMA ignore_check_constraints = ON');
      await database.customUpdate(
        'UPDATE long_term_relations SET priority = 9 WHERE id = ?',
        variables: [Variable.withString(_uuid(102))],
      );
      final result = await repository.execute(command());
      expect(
        result,
        isA<GraphCommandFailed>().having(
          (r) => r.failure.category,
          'категория',
          GraphFailureCategory.corruption,
        ),
      );
      expect(await rows('daily_choices'), 0);
      expect(
        (diagnostics.events
                    .whereType<DailyChoicePathValidationDiagnosticsEvent>()
                    .last
                    .status
                as DiagnosticsFailed)
            .code,
        DiagnosticsFailureCode.corruption,
      );
    },
  );

  test('коллизия выбора сохраняет прежнюю запись без новой ревизии', () async {
    expect(await repository.execute(command()), isA<GraphCommandSucceeded>());
    final before = (await repository.getDailyChoice(
      _choice(201),
    ) as DailyChoiceReadSuccess).value.revision;
    choiceIds.values
      ..clear()
      ..add(_choice(201));
    final result = await repository.execute(command());
    expect(result, isA<GraphCommandFailed>());
    expect(await rows('daily_choices'), 1);
    expect(await rows('daily_choice_path_steps'), 2);
    final after = (await repository.getDailyChoice(
      _choice(201),
    ) as DailyChoiceReadSuccess).value.revision;
    expect(before.compareTo(after), GraphRevisionOrder.same);
  });

  test('отказ второго шага откатывает выбор и первый шаг', () async {
    expect(await repository.execute(command()), isA<GraphCommandSucceeded>());
    final before = (await repository.getDailyChoice(
      _choice(201),
    ) as DailyChoiceReadSuccess).value.revision;
    stepIds.values
      ..clear()
      ..addAll([_step(303), _step(301)]);
    final result = await repository.execute(command());
    expect(result, isA<GraphCommandFailed>());
    expect(await rows('daily_choices'), 1);
    expect(await rows('daily_choice_path_steps'), 2);
    expect(
      (await repository.getDailyChoice(
        _choice(202),
      ) as DailyChoiceReadSuccess).value.value,
      isNull,
    );
    final after = (await repository.getDailyChoice(
      _choice(201),
    ) as DailyChoiceReadSuccess).value.revision;
    expect(before.compareTo(after), GraphRevisionOrder.same);
  });

  test(
    'постороннее изменение ревизии не отменяет подтверждённый маршрут',
    () async {
      expect(
        await repository.execute(EnableIntentionReadiness(_intention(1))),
        isA<GraphCommandSucceeded>(),
      );
      expect(await repository.execute(command()), isA<GraphCommandSucceeded>());
      expect(await rows('daily_choices'), 1);
    },
  );

  test('неизвестный отказ чтения результата откатывает все записи', () async {
    readProbe.failure = StateError('сбой чтения результата');
    final result = await repository.execute(command());
    expect(
      result,
      isA<GraphCommandFailed>().having(
        (r) => r.failure.category,
        'категория',
        GraphFailureCategory.unexpected,
      ),
    );
    readProbe.failure = null;
    expect(await rows('daily_choices'), 0);
    expect(await rows('daily_choice_path_steps'), 0);
    expect(
      diagnostics.events.whereType<DailyChoiceCommandDiagnosticsEvent>().last,
      isA<DailyChoiceCommandDiagnosticsEvent>()
          .having(
            (event) => event.stage,
            'этап',
            DailyChoiceCommandDiagnosticsStage.resultRead,
          )
          .having(
            (event) => (event.status as DiagnosticsFailed).code,
            'код',
            DiagnosticsFailureCode.unexpected,
          ),
    );
  });
}

final class _ReadFailureProbe extends LocalDatabaseConnectionObserver {
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains(
          'FROM daily_choices WHERE id = ?',
        )) {
      final error = failure;
      if (error != null) throw error;
    }
  }
}
