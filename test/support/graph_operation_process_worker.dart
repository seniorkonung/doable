import 'dart:async';
import 'dart:io';

import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
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

import 'large_blocking_relations_fixture.dart';

const _operationEnvironment = 'DOABLE_GRAPH_OPERATION';
const _stopPointEnvironment = 'DOABLE_GRAPH_STOP_POINT';
const _databasePathEnvironment = 'DOABLE_GRAPH_DATABASE_PATH';
const _startedMarker = 'DOABLE_GRAPH_WORKER_STARTED';
const _readyMarker = 'DOABLE_GRAPH_WORKER_READY';

const _sourceIdValue = '018f0b5d-6b2e-7c80-8000-000000000901';
const _firstNeighborIdValue = '018f0b5d-6b2e-7c80-8000-000000000902';
const _secondNeighborIdValue = '018f0b5d-6b2e-7c80-8000-000000000903';
const _unrelatedIdValue = '018f0b5d-6b2e-7c80-8000-000000000904';
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
          _GraphOperation.update => await repository.execute(
            UpdateLongTermRelation(
              relationId: _relationId(_workerRelationIdValue),
              patch: LongTermRelationPatch(
                sourceIntentionId: LongTermRelationFieldSet(
                  _intentionId(_secondNeighborIdValue),
                ),
                relatedIntentionId: LongTermRelationFieldSet(
                  _intentionId(_unrelatedIdValue),
                ),
                type: const LongTermRelationFieldSet(LongTermRelationType.can),
                priority: const LongTermRelationFieldSet(RelationPriority.p4),
                description: LongTermRelationDescriptionReplaced(
                  LongTermRelationDescription.fromInput(
                    'Изменено дочерним процессом',
                  )!,
                ),
              ),
            ),
          ),
          _GraphOperation.archive => await repository.execute(
            ArchiveLongTermRelation(_relationId(_workerRelationIdValue)),
          ),
          _GraphOperation.restore => await repository.execute(
            RestoreLongTermRelation(_relationId(_workerRelationIdValue)),
          ),
          _GraphOperation.delete => await repository.execute(
            DeleteLongTermRelation(_relationId(_workerRelationIdValue)),
          ),
          _GraphOperation.bulkDelete => await repository.execute(
            DeleteBlockingRelations.longTerm(
              intentionId: _intentionId(_sourceIdValue),
              relationIds: LargeBlockingRelationsFixture.selectedIds,
            ),
          ),
        };
        final succeeded = switch (operation) {
          _GraphOperation.create ||
          _GraphOperation.update ||
          _GraphOperation.archive ||
          _GraphOperation.restore ||
          _GraphOperation.delete => result is GraphCommandSucceeded,
          _GraphOperation.bulkDelete => result is GraphCommandSucceeded,
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
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (operation == _GraphOperation.bulkDelete &&
        stopPoint == _GraphStopPoint.beforeDelete &&
        _isBulkDelete(statement)) {
      await _reportReadyAndWait();
    }
  }

  @override
  Future<void> afterStatement(LocalDatabaseSqlStatement statement) async {
    if (operation == _GraphOperation.bulkDelete &&
        stopPoint == _GraphStopPoint.duringDelete &&
        _isBulkDelete(statement)) {
      await _reportReadyAndWait();
    }
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
      _GraphOperation.update ||
      _GraphOperation.archive ||
      _GraphOperation.restore =>
        statement.operation == LocalDatabaseSqlOperation.update &&
            statement.statements.any(
              (sql) => sql.contains('long_term_relations'),
            ),
      _GraphOperation.delete =>
        statement.operation == LocalDatabaseSqlOperation.delete &&
            statement.statements.any(
              (sql) => sql.contains('long_term_relations'),
            ),
      _GraphOperation.bulkDelete => false,
    };
    if (matches) await _reportReadyAndWait();
  }
}

bool _isBulkDelete(LocalDatabaseSqlStatement statement) =>
    statement.operation == LocalDatabaseSqlOperation.update &&
    statement.statements.any(
      (sql) => sql.startsWith('DELETE FROM long_term_relations WHERE id IN'),
    );

Future<Never> _reportReadyAndWait() async {
  stdout.writeln('$_readyMarker:$pid');
  await stdout.flush();
  await Completer<void>().future;
  throw StateError('Недостижимое завершение ожидания прерывания процесса.');
}

enum _GraphOperation {
  create,
  cascade,
  update,
  archive,
  restore,
  delete,
  bulkDelete;

  static _GraphOperation parse(String? value) => switch (value) {
    'create' => create,
    'cascade' => cascade,
    'update' => update,
    'archive' => archive,
    'restore' => restore,
    'delete' => delete,
    'bulk_delete' => bulkDelete,
    _ => throw StateError('Неизвестная операция графа: $value.'),
  };
}

enum _GraphStopPoint {
  beforeCommit,
  beforeDelete,
  duringDelete,
  afterCommit;

  static _GraphStopPoint parse(String? value) => switch (value) {
    'before_commit' => beforeCommit,
    'before_delete' => beforeDelete,
    'during_delete' => duringDelete,
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
