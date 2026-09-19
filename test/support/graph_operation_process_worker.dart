import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_description.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';

const _operationEnvironment = 'DOABLE_GRAPH_OPERATION';
const _stopPointEnvironment = 'DOABLE_GRAPH_STOP_POINT';
const _databasePathEnvironment = 'DOABLE_GRAPH_DATABASE_PATH';
const _startedMarker = 'DOABLE_GRAPH_WORKER_STARTED';
const _readyMarker = 'DOABLE_GRAPH_WORKER_READY';

const _sourceIdValue = '018f0b5d-6b2e-7c80-8000-000000000901';
const _firstNeighborIdValue = '018f0b5d-6b2e-7c80-8000-000000000902';
const _workerRelationIdValue = '018f0b5d-6b2e-7c80-8000-000000000954';

void main() {
  test(
    'дочерний процесс останавливается в заданной точке операции графа',
    () async {
      stdout.writeln('$_startedMarker:$pid');
      await stdout.flush();
      final databasePath = Platform.environment[_databasePathEnvironment];
      if (databasePath == null || databasePath.isEmpty) {
        throw StateError('Не задан путь к файлу личного графа.');
      }
      final operation = _GraphOperation.parse(
        Platform.environment[_operationEnvironment],
      );
      final stopPoint = _GraphStopPoint.parse(
        Platform.environment[_stopPointEnvironment],
      );
      final observer = _GraphOperationStopObserver(operation, stopPoint);
      final database = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openFileBackedLocalDatabase(File(databasePath)),
          observer,
        ),
      );

      try {
        await database.open();
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 20, 12),
          const _DiscardingDiagnosticsSink(),
          relationIdGenerator: _DeterministicRelationIdGenerator(
            _relationId(_workerRelationIdValue),
          ),
        );
        final result = switch (operation) {
          _GraphOperation.create => await repository.execute(
            CreateLongTermRelation(
              sourceIntentionId: _intentionId(_sourceIdValue),
              relatedIntentionId: _intentionId(_firstNeighborIdValue),
              type: LongTermRelationType.need,
              priority: RelationPriority.p2,
              description: LongTermRelationDescription.fromInput(
                'Создано дочерним процессом',
              ),
            ),
          ),
          _GraphOperation.cascade => await repository.execute(
            ArchiveIntention(_intentionId(_sourceIdValue)),
          ),
        };
        final succeeded = switch (operation) {
          _GraphOperation.create => result is GraphCommandSucceeded,
          _GraphOperation.cascade => result is ResultSuccess,
        };
        if (!succeeded) {
          throw StateError(
            'Операция графа завершилась отказом до точки commit.',
          );
        }
        if (stopPoint == _GraphStopPoint.afterCommit) {
          await _reportReadyAndWait();
        }
      } finally {
        await database.close();
      }
    },
    timeout: Timeout.none,
  );
}

final class _GraphOperationStopObserver
    extends LocalDatabaseConnectionObserver {
  const _GraphOperationStopObserver(this.operation, this.stopPoint);

  final _GraphOperation operation;
  final _GraphStopPoint stopPoint;

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    if (stopPoint != _GraphStopPoint.beforeCommit) return;
    final matches = switch (operation) {
      _GraphOperation.create =>
        statement.operation == LocalDatabaseSqlOperation.insert &&
            statement.statements.any(
              (sql) => sql.contains('long_term_relations'),
            ),
      _GraphOperation.cascade =>
        statement.operation == LocalDatabaseSqlOperation.update &&
            statement.statements.any(
              (sql) => sql.contains('UPDATE long_term_relations'),
            ),
    };
    if (matches) await _reportReadyAndWait();
  }
}

Future<Never> _reportReadyAndWait() async {
  stdout.writeln('$_readyMarker:$pid');
  await stdout.flush();
  await Completer<void>().future;
  throw StateError('Недостижимое завершение ожидания прерывания процесса.');
}

enum _GraphOperation {
  create,
  cascade;

  static _GraphOperation parse(String? value) => switch (value) {
    'create' => create,
    'cascade' => cascade,
    _ => throw StateError('Неизвестная операция графа: $value.'),
  };
}

enum _GraphStopPoint {
  beforeCommit,
  afterCommit;

  static _GraphStopPoint parse(String? value) => switch (value) {
    'before_commit' => beforeCommit,
    'after_commit' => afterCommit,
    _ => throw StateError('Неизвестная точка остановки операции: $value.'),
  };
}

final class _DeterministicRelationIdGenerator
    implements LongTermRelationIdGenerator {
  const _DeterministicRelationIdGenerator(this.id);

  final LongTermRelationId id;

  @override
  LongTermRelationId generate() => id;
}

final class _DiscardingDiagnosticsSink implements DiagnosticsSink {
  const _DiscardingDiagnosticsSink();

  @override
  void record(DiagnosticsEvent event) {}
}

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw ArgumentError.value(
        value,
        'value',
      ),
    };
