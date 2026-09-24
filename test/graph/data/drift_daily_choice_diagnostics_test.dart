import 'dart:convert';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';

void main() {
  late AppDatabase database;
  late _FailureProbe probe;
  late _RecordingSink diagnostics;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    probe = _FailureProbe();
    diagnostics = _RecordingSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        probe,
      ),
    );
    await database.open();
    await seedDurabilityGraph(database);
    repository = _repository(database, diagnostics);
  });

  tearDown(() => database.close());

  test(
    'успех разделяет проверку, запись, чтение результата и чтение выбора',
    () async {
      final result = await repository.execute(
        durabilityCreate(description: 'Секретное описание №739'),
      );
      expect(result, isA<GraphCommandSucceeded>());
      expect(
        await repository.getDailyChoice(durabilityChoice(201)),
        isA<DailyChoiceReadSuccess>(),
      );

      expect(_commandStages(diagnostics.events), [
        'validation:started',
        'validation:succeeded',
        'write:started',
        'write:succeeded',
        'resultRead:started',
        'resultRead:succeeded',
      ]);
      expect(_pathStatuses(diagnostics.events), ['started', 'succeeded']);
      expect(
        diagnostics.events.whereType<DailyChoiceReadDiagnosticsEvent>().map(
          (event) => _status(event.status),
        ),
        ['started', 'succeeded'],
      );
      _expectSafeLogs(diagnostics.logs);
    },
  );

  test('новые чтения различаются по операции, этапу и исходу', () async {
    expect(
      await repository.execute(durabilityCreate()),
      isA<GraphCommandSucceeded>(),
    );
    diagnostics.events.clear();
    diagnostics.logs.clear();

    expect(
      await repository.getDailyChoiceCatalogPage(DailyChoiceCatalogQuery()),
      isA<DailyChoiceCatalogPageSuccess>(),
    );
    expect(
      await repository.getRelationGroupPage(
        DailyChoiceGroupQuery(
          intentionId: durabilityIntention(1),
          role: DailyChoiceRelationRole.source,
          pageSize: 50,
        ),
      ),
      isA<RelationGroupPageSuccess>(),
    );
    expect(
      await repository.getChoicePathContinuations(
        ChoicePathContinuationQuery(
          draft: ChoicePathDraftStart(durabilityIntention(1)),
        ),
      ),
      isA<ChoicePathContinuationSuccess>(),
    );
    expect(
      await repository.getChoicePathContinuations(
        ChoicePathContinuationQuery(
          draft: ChoicePathDraftBottomStart(durabilityIntention(3)),
        ),
      ),
      isA<ChoicePathContinuationSuccess>(),
    );

    expect(
      diagnostics.logs.map((line) {
        final event = jsonDecode(line) as Map<String, dynamic>;
        return '${event['operation']}:${event['stage']}:${event['outcome']}';
      }),
      [
        'dailyChoiceCatalogPageRead:read:started',
        'dailyChoiceCatalogPageRead:read:succeeded',
        'dailyChoiceGroupPageRead:read:started',
        'dailyChoiceGroupPageRead:read:succeeded',
        'choicePathContinuationRead:validation:started',
        'choicePathContinuationRead:validation:succeeded',
        'choicePathContinuationRead:read:started',
        'choicePathContinuationRead:read:succeeded',
        'choicePathContinuationRead:validation:started',
        'choicePathContinuationRead:validation:succeeded',
        'choicePathContinuationRead:read:started',
        'choicePathContinuationRead:read:succeeded',
      ],
    );
    _expectSafeLogs(diagnostics.logs);
  });

  test(
    'ошибки новых чтений сохраняют категорию без исходного исключения',
    () async {
      expect(
        await repository.execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );

      for (final point in [
        _FailurePoint.catalogRead,
        _FailurePoint.groupRead,
        _FailurePoint.continuationRead,
      ]) {
        diagnostics.events.clear();
        diagnostics.logs.clear();
        probe.arm(point);

        final category = switch (point) {
          _FailurePoint.catalogRead =>
            (await repository.getDailyChoiceCatalogPage(
              DailyChoiceCatalogQuery(),
            ) as DailyChoiceCatalogPageError).failure.category,
          _FailurePoint.groupRead => (await repository.getRelationGroupPage(
            DailyChoiceGroupQuery(
              intentionId: durabilityIntention(1),
              role: DailyChoiceRelationRole.source,
              pageSize: 50,
            ),
          ) as RelationGroupPageFailure).failure.category,
          _FailurePoint.continuationRead =>
            (await repository.getChoicePathContinuations(
              ChoicePathContinuationQuery(
                draft: ChoicePathDraftStart(durabilityIntention(1)),
              ),
            ) as ChoicePathContinuationError).failure.category,
          _ => throw StateError('Неприменимая точка отказа'),
        };

        expect(probe.didFail, isTrue);
        expect(category, GraphFailureCategory.unexpected);
        expect(
          diagnostics.logs.map((line) {
            final event = jsonDecode(line) as Map<String, dynamic>;
            return '${event['outcome']}:${event['failureCode']}';
          }),
          point == _FailurePoint.continuationRead
              ? [
                  'started:null',
                  'succeeded:null',
                  'started:null',
                  'failed:unexpected',
                ]
              : ['started:null', 'failed:unexpected'],
        );
        _expectSafeLogs(diagnostics.logs);
      }
    },
  );

  test('нижняя проверка сообщает конфликт до чтения продолжений', () async {
    final result = await repository.getChoicePathContinuations(
      ChoicePathContinuationQuery(
        draft: ChoicePathDraftBottomStart(durabilityIntention(1)),
      ),
    );
    expect(
      (result as ChoicePathContinuationError).failure,
      isA<ChoicePathContinuationSnapshotExpired>(),
    );
    expect(
      diagnostics.logs.map((line) {
        final event = jsonDecode(line) as Map<String, dynamic>;
        return '${event['stage']}:${event['outcome']}:${event['failureCode']}';
      }),
      ['validation:started:null', 'validation:failed:conflict'],
    );
    _expectSafeLogs(diagnostics.logs);
  });

  test('падающий получатель не меняет результат новых чтений', () async {
    expect(
      await repository.execute(durabilityCreate()),
      isA<GraphCommandSucceeded>(),
    );
    final withFailure = _repository(database, _ThrowingSink());

    for (final graph in [repository, withFailure]) {
      expect(
        await graph.getDailyChoiceCatalogPage(DailyChoiceCatalogQuery()),
        isA<DailyChoiceCatalogPageSuccess>(),
      );
      expect(
        await graph.getRelationGroupPage(
          DailyChoiceGroupQuery(
            intentionId: durabilityIntention(1),
            role: DailyChoiceRelationRole.source,
            pageSize: 50,
          ),
        ),
        isA<RelationGroupPageSuccess>(),
      );
      expect(
        await graph.getChoicePathContinuations(
          ChoicePathContinuationQuery(
            draft: ChoicePathDraftStart(durabilityIntention(1)),
          ),
        ),
        isA<ChoicePathContinuationSuccess>(),
      );
      expect(
        (await graph.getChoicePathContinuations(
          ChoicePathContinuationQuery(
            draft: ChoicePathDraftStart(durabilityIntention(999)),
          ),
        ) as ChoicePathContinuationError).failure.category,
        GraphFailureCategory.notFound,
      );
    }
  });

  test('архивированная связь диагностируется как конфликт проверки', () async {
    expect(
      await repository.execute(
        ArchiveLongTermRelation(durabilityRelation(101)),
      ),
      isA<GraphCommandSucceeded>(),
    );
    diagnostics.events.clear();
    diagnostics.logs.clear();

    final result = await repository.execute(durabilityCreate());

    expect(
      (result as GraphCommandFailed).failure.category,
      GraphFailureCategory.conflict,
    );
    expect(_commandStages(diagnostics.events), [
      'validation:started',
      'validation:failed:conflict',
    ]);
    expect(_pathStatuses(diagnostics.events), ['started', 'failed:conflict']);
    expect(await durabilityRows(database, 'daily_choices'), isEmpty);
    _expectSafeLogs(diagnostics.logs);
  });

  for (final point in [_FailurePoint.write, _FailurePoint.resultRead]) {
    test('отказ ${point.label} сохраняет исход и безопасный этап', () async {
      final before = await durabilityState(database);
      probe.arm(point);

      final result = await repository.execute(durabilityCreate());

      expect(probe.didFail, isTrue);
      expect(
        (result as GraphCommandFailed).failure.category,
        GraphFailureCategory.unexpected,
      );
      expect(await durabilityState(database), before);
      expect(_pathStatuses(diagnostics.events), ['started', 'succeeded']);
      expect(
        _commandStages(diagnostics.events),
        point == _FailurePoint.write
            ? [
                'validation:started',
                'validation:succeeded',
                'write:started',
                'write:failed:unexpected',
              ]
            : [
                'validation:started',
                'validation:succeeded',
                'write:started',
                'write:succeeded',
                'resultRead:started',
                'resultRead:failed:unexpected',
              ],
      );
      _expectSafeLogs(diagnostics.logs);
    });
  }

  test('падающий получатель диагностики не меняет успех и конфликт', () async {
    await database.close();
    Future<(List<Object>, Type, Type, GraphFailureCategory)> run(
      DiagnosticsSink sink,
    ) async {
      final local = AppDatabase(openInMemoryLocalDatabase());
      try {
        await local.open();
        await seedDurabilityGraph(local);
        final graph = _repository(local, sink);
        final success = await graph.execute(durabilityCreate());
        expect(success, isA<GraphCommandSucceeded>());
        expect(
          await graph.execute(ArchiveLongTermRelation(durabilityRelation(103))),
          isA<GraphCommandSucceeded>(),
        );
        final failure = await graph.execute(durabilityCreate(path: [103]));
        final rejected = (failure as GraphCommandFailed).failure;
        return (
          await durabilityState(local),
          success.runtimeType,
          rejected.runtimeType,
          rejected.category,
        );
      } finally {
        await local.close();
      }
    }

    final healthy = await run(_RecordingSink());
    final throwing = await run(_ThrowingSink());
    expect(throwing.$1, healthy.$1);
    expect(throwing.$2, healthy.$2);
    expect(throwing.$3, healthy.$3);
    expect(throwing.$4, GraphFailureCategory.conflict);
    expect(throwing.$4, healthy.$4);
  });
}

DriftPersonalGraphRepository _repository(
  AppDatabase database,
  DiagnosticsSink sink,
) => DriftPersonalGraphRepository(
  database,
  UuidV7IntentionIdGenerator(),
  () => DateTime.utc(2026, 9, 23),
  sink,
  dailyChoiceIdGenerator: FixedChoiceIds(durabilityChoice(201)),
  choicePathStepIdGenerator: SequentialStepIds(301),
);

List<String> _commandStages(Iterable<DiagnosticsEvent> events) => [
  for (final event in events.whereType<DailyChoiceCommandDiagnosticsEvent>())
    '${event.stage.name}:${_status(event.status)}',
];

List<String> _pathStatuses(Iterable<DiagnosticsEvent> events) => [
  for (final event
      in events.whereType<DailyChoicePathValidationDiagnosticsEvent>())
    _status(event.status),
];

String _status(DiagnosticsStatus status) => switch (status) {
  DiagnosticsStarted() => 'started',
  DiagnosticsSucceeded() => 'succeeded',
  DiagnosticsFailed(:final code) => 'failed:${code.name}',
};

void _expectSafeLogs(List<String> logs) {
  expect(logs, isNotEmpty);
  for (final line in logs) {
    final event = jsonDecode(line) as Map<String, dynamic>;
    expect(
      {
        'operation',
        'commandType',
        'stage',
        'outcome',
        'durationMicros',
        'failureCode',
        'pageSize',
        'isContinuation',
        'requiresNewSnapshot',
      }.containsAll(event.keys),
      isTrue,
    );
    expect(event['operation'], isA<String>());
    expect(event['outcome'], anyOf('started', 'succeeded', 'failed'));
    if (event.containsKey('durationMicros')) {
      expect(event['durationMicros'], isA<int>());
    }
    for (final forbidden in [
      'Секретное описание',
      'Выбор',
      'Намерение',
      '2026-09-23',
      durabilityUuid(101),
      durabilityUuid(201),
      'INSERT INTO',
      'Управляемый отказ',
      'Секретный текст SQL',
    ]) {
      expect(line, isNot(contains(forbidden)));
    }
  }
}

final class _RecordingSink implements DiagnosticsSink {
  final List<DiagnosticsEvent> events = [];
  final List<String> logs = [];

  @override
  void record(DiagnosticsEvent event) {
    events.add(event);
    DeveloperDiagnosticsSink(logs.add).record(event);
  }
}

final class _ThrowingSink implements DiagnosticsSink {
  @override
  void record(DiagnosticsEvent event) {
    throw StateError('Получатель диагностики недоступен.');
  }
}

enum _FailurePoint {
  write('записи'),
  resultRead('чтения результата'),
  catalogRead('каталога'),
  groupRead('дневной группы'),
  continuationRead('продолжений пути');

  const _FailurePoint(this.label);
  final String label;
}

final class _FailureProbe extends LocalDatabaseConnectionObserver {
  _FailurePoint? _point;
  bool didFail = false;

  void arm(_FailurePoint point) {
    _point = point;
    didFail = false;
  }

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (didFail || statement.operation != LocalDatabaseSqlOperation.select) {
      return;
    }
    final sql = statement.statements.single;
    final targeted = switch (_point) {
      _FailurePoint.resultRead => sql.contains(
        'FROM daily_choices WHERE id = ?',
      ),
      _FailurePoint.catalogRead =>
        sql.contains('FROM daily_choices') &&
            sql.contains('ORDER BY choice_date'),
      _FailurePoint.groupRead => sql.contains('FROM daily_choices INDEXED BY'),
      _FailurePoint.continuationRead => sql.contains('WITH RECURSIVE'),
      _ => false,
    };
    if (targeted) {
      didFail = true;
      throw StateError('Управляемый отказ: Секретный текст SQL.');
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (_point != _FailurePoint.write || didFail) return;
    if (statement.operation == LocalDatabaseSqlOperation.insert &&
        statement.statements.any(
          (sql) => sql.contains('INSERT INTO daily_choices'),
        )) {
      didFail = true;
      throw StateError('Управляемый отказ записи.');
    }
  }
}
