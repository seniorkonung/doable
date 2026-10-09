import 'dart:convert';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_draft.dart';
import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
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
      for (final id in [1, 2, 3, 4, 5, 101, 102, 103, 104, 202, 301, 302])
        durabilityUuid(id),
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

enum _FailurePoint { catalogRead, groupRead, continuationRead }

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
      _FailurePoint.catalogRead =>
        sql.contains('FROM daily_choices') &&
            sql.contains('ORDER BY choice_date'),
      _FailurePoint.groupRead => sql.contains('FROM daily_choices INDEXED BY'),
      _FailurePoint.continuationRead =>
        sql.contains('WITH RECURSIVE') || sql.contains('WITH visited(id)'),
      null => false,
    };
    if (targeted) {
      didFail = true;
      throw StateError('Управляемый отказ: Секретный текст SQL.');
    }
  }
}
