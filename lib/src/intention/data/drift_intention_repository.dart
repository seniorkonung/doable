import '../../data/local/app_database.dart' as local;
import '../../data/local/fts_query.dart';
import '../../data/local/sqlite_failure_classifier.dart';
import '../../shared/diagnostics/diagnostics_sink.dart';
import '../application/intention_command.dart';
import '../application/intention_id_generator.dart';
import '../application/intention_repository.dart';
import '../application/intention_result.dart';
import '../domain/intention.dart' as domain;
import '../domain/intention_id.dart';
import '../domain/intention_text.dart';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';

final class DriftIntentionRepository implements IntentionRepository {
  DriftIntentionRepository(
    this._database,
    this._idGenerator,
    this._now,
    this._diagnosticsSink,
  );

  final local.AppDatabase _database;
  final IntentionIdGenerator _idGenerator;
  final DateTime Function() _now;
  final DiagnosticsSink _diagnosticsSink;
  final _CatalogCursorOwner _cursorOwner = _CatalogCursorOwner();

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    _diagnosticsSink.record(
      CatalogPageReadDiagnosticsEvent(
        pageSize: query.pageSize,
        status: const DiagnosticsStarted(),
      ),
    );

    final cursor = query.cursor;
    if (cursor != null &&
        (cursor is! _DriftIntentionCatalogCursor ||
            !cursor.isOwnedBy(_cursorOwner) ||
            !cursor.matches(query))) {
      const failure = IntentionGenericValidationFailure();
      _diagnosticsSink.record(
        CatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      return const ResultFailure(failure);
    }

    try {
      final page = switch (cursor) {
        null => await _database.transaction(() => _readFirstCatalogPage(query)),
        _DriftIntentionCatalogCursor() => await _readCatalogContinuationPage(
          query,
          cursor,
        ),
        _ => throw StateError('Недопустимый cursor каталога.'),
      };
      _diagnosticsSink.record(
        CatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(page);
    } on Object catch (error) {
      final failure = _classifyCatalogReadFailure(error);
      _diagnosticsSink.record(
        CatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      return ResultFailure(failure);
    }
  }

  @override
  Stream<Result<domain.Intention?>> watchById(IntentionId id) async* {
    final stopwatch = Stopwatch()..start();
    _diagnosticsSink.record(
      const IntentionDetailReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );

    try {
      final query = _database.customSelect(
        '''
          SELECT
            id,
            title,
            description,
            is_action_ready,
            is_archived,
            created_at,
            updated_at
          FROM intentions
          WHERE id = ?
        ''',
        variables: [Variable<String>(id.toCanonicalString())],
        readsFrom: {_database.intentions},
      );
      await for (final row in query.watchSingleOrNull()) {
        final intention = row == null ? null : _rehydrateDetailRow(row);
        _diagnosticsSink.record(
          IntentionDetailReadDiagnosticsEvent(
            status: DiagnosticsSucceeded(stopwatch.elapsed),
          ),
        );
        yield ResultSuccess(intention);
      }
    } on Object catch (error) {
      final failure = _classifyDetailReadFailure(error);
      _diagnosticsSink.record(
        IntentionDetailReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      yield ResultFailure(failure);
    }
  }

  @override
  Future<Result<IntentionCommandSuccess>> execute(
    IntentionCommand command,
  ) async {
    final stopwatch = Stopwatch()..start();
    final commandType = _commandDiagnosticsType(command);

    try {
      _validateCommandText(command);
      final success = await _database.transaction(
        () => switch (command) {
          CreateIntention() => _createIntention(command),
          UpdateIntention() => _updateIntention(command),
          EnableIntentionReadiness() => _changeReadiness(
            command.id,
            domain.IntentionReadiness.ready,
          ),
          DisableIntentionReadiness() => _changeReadiness(
            command.id,
            domain.IntentionReadiness.notReady,
          ),
          ArchiveIntention() => _changeArchiveState(
            command.id,
            domain.IntentionArchiveState.archived,
          ),
          RestoreIntention() => _changeArchiveState(
            command.id,
            domain.IntentionArchiveState.active,
          ),
          DeleteIntention() => _deleteIntention(command.id),
        },
      );
      _diagnosticsSink.record(
        IntentionCommandDiagnosticsEvent(
          commandType: commandType,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(success);
    } on Object catch (error) {
      final failure = _classifyCommandFailure(error, command);
      _diagnosticsSink.record(
        IntentionCommandDiagnosticsEvent(
          commandType: commandType,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      return ResultFailure(failure);
    }
  }

  Future<IntentionSaved> _createIntention(CreateIntention command) async {
    final title = IntentionText.normalizeTitle(command.title);
    final description = switch (command.description) {
      null => null,
      final value => IntentionText.normalizeDescription(value),
    };
    final createdAt = domain.IntentionTimestamp(_now());
    final intention = domain.Intention(
      id: _idGenerator.generate(),
      title: title,
      description: description,
      readiness: domain.IntentionReadiness.notReady,
      archiveState: domain.IntentionArchiveState.active,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

    await _database
        .into(_database.intentions)
        .insert(
          local.IntentionsCompanion.insert(
            id: intention.id.toCanonicalString(),
            title: intention.title,
            description: Value(intention.description),
            isActionReady: const Value(false),
            isArchived: const Value(false),
            createdAt: intention.createdAt.value.microsecondsSinceEpoch,
            updatedAt: intention.updatedAt.value.microsecondsSinceEpoch,
          ),
        );
    return IntentionSaved(intention);
  }

  Future<IntentionSaved> _updateIntention(UpdateIntention command) async {
    final title = IntentionText.normalizeTitle(command.title);
    final description = switch (command.description) {
      null => null,
      final value => IntentionText.normalizeDescription(value),
    };
    final row =
        await (_database.select(_database.intentions)
              ..where((row) => row.id.equals(command.id.toCanonicalString())))
            .getSingleOrNull();
    if (row == null) throw const _IntentionNotFound();

    final existing = _rehydrate(row);
    if (existing.title == title && existing.description == description) {
      return IntentionSaved(existing);
    }

    final updated = domain.Intention(
      id: existing.id,
      title: title,
      description: description,
      readiness: existing.readiness,
      archiveState: existing.archiveState,
      createdAt: existing.createdAt,
      updatedAt: domain.IntentionTimestamp(_now()),
    );
    await (_database.update(
      _database.intentions,
    )..where((row) => row.id.equals(command.id.toCanonicalString()))).write(
      local.IntentionsCompanion(
        title: Value(updated.title),
        description: Value(updated.description),
        updatedAt: Value(updated.updatedAt.value.microsecondsSinceEpoch),
      ),
    );
    return IntentionSaved(updated);
  }

  Future<IntentionSaved> _changeReadiness(
    IntentionId id,
    domain.IntentionReadiness readiness,
  ) async {
    final row = await (_database.select(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).getSingleOrNull();
    if (row == null) throw const _IntentionNotFound();

    final existing = _rehydrate(row);
    if (existing.readiness == readiness) return IntentionSaved(existing);

    final updated = domain.Intention(
      id: existing.id,
      title: existing.title,
      description: existing.description,
      readiness: readiness,
      archiveState: existing.archiveState,
      createdAt: existing.createdAt,
      updatedAt: domain.IntentionTimestamp(_now()),
    );
    await (_database.update(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).write(
      local.IntentionsCompanion(
        isActionReady: Value(readiness == domain.IntentionReadiness.ready),
        updatedAt: Value(updated.updatedAt.value.microsecondsSinceEpoch),
      ),
    );
    return IntentionSaved(updated);
  }

  Future<IntentionSaved> _changeArchiveState(
    IntentionId id,
    domain.IntentionArchiveState archiveState,
  ) async {
    final row = await (_database.select(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).getSingleOrNull();
    if (row == null) throw const _IntentionNotFound();

    final existing = _rehydrate(row);
    if (existing.archiveState == archiveState) return IntentionSaved(existing);

    final updated = domain.Intention(
      id: existing.id,
      title: existing.title,
      description: existing.description,
      readiness: existing.readiness,
      archiveState: archiveState,
      createdAt: existing.createdAt,
      updatedAt: domain.IntentionTimestamp(_now()),
    );
    await (_database.update(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).write(
      local.IntentionsCompanion(
        isArchived: Value(
          archiveState == domain.IntentionArchiveState.archived,
        ),
        updatedAt: Value(updated.updatedAt.value.microsecondsSinceEpoch),
      ),
    );
    return IntentionSaved(updated);
  }

  Future<IntentionDeleted> _deleteIntention(IntentionId id) async {
    final deletedRows = await (_database.delete(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).go();
    if (deletedRows == 0) throw const _IntentionNotFound();
    return IntentionDeleted(id);
  }

  Future<IntentionCatalogFirstPage> _readFirstCatalogPage(
    IntentionCatalogQuery query,
  ) async {
    final intentions = _database.intentions;
    final condition = _catalogCondition(query);
    final countExpression = countAll();
    final countQuery = _database.selectOnly(intentions)
      ..addColumns([countExpression])
      ..where(condition);
    final totalCount = (await countQuery.getSingle()).read(countExpression)!;
    final rowsQuery = _database.selectOnly(intentions)
      ..addColumns([
        intentions.id,
        intentions.title,
        intentions.description,
        intentions.isActionReady,
        intentions.isArchived,
        intentions.createdAt,
        intentions.updatedAt,
      ])
      ..where(condition)
      ..orderBy([
        _primaryOrderingTerm(intentions, query.order),
        OrderingTerm.asc(intentions.id),
      ])
      ..limit(query.pageSize + 1);
    final rows = await rowsQuery.get();
    final summaries = [
      for (final row in rows)
        _rehydrateSummary(
          id: row.read(intentions.id)!,
          title: row.read(intentions.title)!,
          description: row.read(intentions.description),
          isActionReady: row.read(intentions.isActionReady)!,
          isArchived: row.read(intentions.isArchived)!,
          createdAt: row.read(intentions.createdAt)!,
          updatedAt: row.read(intentions.updatedAt)!,
        ),
    ];
    final items = summaries.take(query.pageSize).toList(growable: false);
    final hasNextPage = rows.length > query.pageSize;

    return IntentionCatalogFirstPage(
      items: items,
      totalCount: totalCount,
      nextCursor: hasNextPage ? _cursorAt(query, items.last) : null,
    );
  }

  Future<IntentionCatalogContinuationPage> _readCatalogContinuationPage(
    IntentionCatalogQuery query,
    _DriftIntentionCatalogCursor cursor,
  ) async {
    final intentions = _database.intentions;
    final rowsQuery = _database.selectOnly(intentions)
      ..addColumns([
        intentions.id,
        intentions.title,
        intentions.description,
        intentions.isActionReady,
        intentions.isArchived,
        intentions.createdAt,
        intentions.updatedAt,
      ])
      ..where(_catalogCondition(query) & _keysetCondition(query, cursor))
      ..orderBy([
        _primaryOrderingTerm(intentions, query.order),
        OrderingTerm.asc(intentions.id),
      ])
      ..limit(query.pageSize + 1);
    final rows = await rowsQuery.get();
    final summaries = [
      for (final row in rows)
        _rehydrateSummary(
          id: row.read(intentions.id)!,
          title: row.read(intentions.title)!,
          description: row.read(intentions.description),
          isActionReady: row.read(intentions.isActionReady)!,
          isArchived: row.read(intentions.isArchived)!,
          createdAt: row.read(intentions.createdAt)!,
          updatedAt: row.read(intentions.updatedAt)!,
        ),
    ];
    final items = summaries.take(query.pageSize).toList(growable: false);
    final hasNextPage = rows.length > query.pageSize;

    return IntentionCatalogContinuationPage(
      items: items,
      nextCursor: hasNextPage ? _cursorAt(query, items.last) : null,
    );
  }

  Expression<bool> _catalogCondition(IntentionCatalogQuery query) {
    final intentions = _database.intentions;
    final scopeCondition = switch (query.scope) {
      IntentionScope.active => intentions.isArchived.equals(false),
      IntentionScope.archived => intentions.isArchived.equals(true),
      IntentionScope.all => const Constant(true),
    };
    final filter = query.titleFilter;
    if (filter == null) return scopeCondition;
    return scopeCondition &
        LocalIntentionTitleSearch(filter).conditionFor(intentions);
  }

  OrderingTerm _primaryOrderingTerm(
    local.Intentions intentions,
    IntentionCatalogOrder order,
  ) {
    final timestamp = _primaryOrderingColumn(intentions, order);
    return switch (order.direction) {
      IntentionCatalogSortDirection.ascending => OrderingTerm.asc(timestamp),
      IntentionCatalogSortDirection.descending => OrderingTerm.desc(timestamp),
    };
  }

  GeneratedColumn<int> _primaryOrderingColumn(
    local.Intentions intentions,
    IntentionCatalogOrder order,
  ) => switch (order.field) {
    IntentionCatalogSortField.createdAt => intentions.createdAt,
    IntentionCatalogSortField.updatedAt => intentions.updatedAt,
  };

  Expression<bool> _keysetCondition(
    IntentionCatalogQuery query,
    _DriftIntentionCatalogCursor cursor,
  ) {
    final intentions = _database.intentions;
    final timestamp = _primaryOrderingColumn(intentions, query.order);
    final boundaryTimestamp =
        cursor.boundaryTimestamp.value.microsecondsSinceEpoch;
    final afterTimestamp = switch (query.order.direction) {
      IntentionCatalogSortDirection.ascending => timestamp.isBiggerThanValue(
        boundaryTimestamp,
      ),
      IntentionCatalogSortDirection.descending => timestamp.isSmallerThanValue(
        boundaryTimestamp,
      ),
    };
    return afterTimestamp |
        (timestamp.equals(boundaryTimestamp) &
            intentions.id.isBiggerThanValue(
              cursor.boundaryId.toCanonicalString(),
            ));
  }

  IntentionSummary _rehydrateSummary({
    required String id,
    required String title,
    required String? description,
    required bool isActionReady,
    required bool isArchived,
    required int createdAt,
    required int updatedAt,
  }) {
    final intentionId = switch (IntentionId.decode(id)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const _StoredIntentionCorruption(),
    };

    try {
      final normalizedTitle = IntentionText.normalizeTitle(title);
      final normalizedDescription = description == null
          ? null
          : IntentionText.normalizeDescription(description);
      if (normalizedTitle != title || normalizedDescription != description) {
        throw const _StoredIntentionCorruption();
      }
      return IntentionSummary(
        id: intentionId,
        title: title,
        hasDescription: normalizedDescription != null,
        readiness: isActionReady
            ? domain.IntentionReadiness.ready
            : domain.IntentionReadiness.notReady,
        archiveState: isArchived
            ? domain.IntentionArchiveState.archived
            : domain.IntentionArchiveState.active,
        createdAt: domain.IntentionTimestamp(
          DateTime.fromMicrosecondsSinceEpoch(createdAt, isUtc: true),
        ),
        updatedAt: domain.IntentionTimestamp(
          DateTime.fromMicrosecondsSinceEpoch(updatedAt, isUtc: true),
        ),
      );
    } on Object catch (error) {
      if (error is IntentionTextValidationException ||
          error is ArgumentError ||
          error is RangeError) {
        throw const _StoredIntentionCorruption();
      }
      rethrow;
    }
  }

  IntentionCatalogCursor _cursorAt(
    IntentionCatalogQuery query,
    IntentionSummary boundary,
  ) => _DriftIntentionCatalogCursor(
    owner: _cursorOwner,
    scope: query.scope,
    normalizedTitleFilter: query.titleFilter?.map((value) => value),
    order: query.order,
    boundaryTimestamp: switch (query.order.field) {
      IntentionCatalogSortField.createdAt => boundary.createdAt,
      IntentionCatalogSortField.updatedAt => boundary.updatedAt,
    },
    boundaryId: boundary.id,
  );

  domain.Intention _rehydrate(local.Intention row) {
    try {
      return _rehydrateValues(
        id: row.id,
        title: row.title,
        description: row.description,
        readiness: row.isActionReady
            ? domain.IntentionReadiness.ready
            : domain.IntentionReadiness.notReady,
        archiveState: row.isArchived
            ? domain.IntentionArchiveState.archived
            : domain.IntentionArchiveState.active,
        createdAt: domain.IntentionTimestamp(
          DateTime.fromMicrosecondsSinceEpoch(row.createdAt, isUtc: true),
        ),
        updatedAt: domain.IntentionTimestamp(
          DateTime.fromMicrosecondsSinceEpoch(row.updatedAt, isUtc: true),
        ),
      );
    } on ArgumentError catch (_) {
      throw const _StoredIntentionCorruption();
    }
  }

  domain.Intention _rehydrateDetailRow(QueryRow row) {
    final stored = _StoredIntentionDetail.fromRawRow(row);
    return _rehydrateValues(
      id: stored.id,
      title: stored.title,
      description: stored.description,
      readiness: stored.readiness,
      archiveState: stored.archiveState,
      createdAt: stored.createdAt,
      updatedAt: stored.updatedAt,
    );
  }

  domain.Intention _rehydrateValues({
    required String id,
    required String title,
    required String? description,
    required domain.IntentionReadiness readiness,
    required domain.IntentionArchiveState archiveState,
    required domain.IntentionTimestamp createdAt,
    required domain.IntentionTimestamp updatedAt,
  }) {
    final decodedId = switch (IntentionId.decode(id)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const _StoredIntentionCorruption(),
    };

    try {
      final normalizedTitle = IntentionText.normalizeTitle(title);
      final normalizedDescription = description == null
          ? null
          : IntentionText.normalizeDescription(description);
      if (normalizedTitle != title || normalizedDescription != description) {
        throw const _StoredIntentionCorruption();
      }
      return domain.Intention(
        id: decodedId,
        title: normalizedTitle,
        description: normalizedDescription,
        readiness: readiness,
        archiveState: archiveState,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } on Object catch (error) {
      if (error is IntentionTextValidationException ||
          error is ArgumentError ||
          error is RangeError) {
        throw const _StoredIntentionCorruption();
      }
      rethrow;
    }
  }
}

final class _StoredIntentionDetail {
  const _StoredIntentionDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.readiness,
    required this.archiveState,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _StoredIntentionDetail.fromRawRow(QueryRow row) {
    final data = row.data;
    return _StoredIntentionDetail(
      id: _requiredString(data, 'id'),
      title: _requiredString(data, 'title'),
      description: _nullableString(data, 'description'),
      readiness: _readiness(data, 'is_action_ready'),
      archiveState: _archiveState(data, 'is_archived'),
      createdAt: _timestamp(data, 'created_at'),
      updatedAt: _timestamp(data, 'updated_at'),
    );
  }

  final String id;
  final String title;
  final String? description;
  final domain.IntentionReadiness readiness;
  final domain.IntentionArchiveState archiveState;
  final domain.IntentionTimestamp createdAt;
  final domain.IntentionTimestamp updatedAt;

  static String _requiredString(Map<String, dynamic> data, String column) {
    final value = data[column];
    if (value is String) return value;
    throw const _StoredIntentionCorruption();
  }

  static String? _nullableString(Map<String, dynamic> data, String column) {
    final value = data[column];
    if (value == null || value is String) return value;
    throw const _StoredIntentionCorruption();
  }

  static domain.IntentionReadiness _readiness(
    Map<String, dynamic> data,
    String column,
  ) => switch (_integer(data, column)) {
    0 => domain.IntentionReadiness.notReady,
    1 => domain.IntentionReadiness.ready,
    _ => throw const _StoredIntentionCorruption(),
  };

  static domain.IntentionArchiveState _archiveState(
    Map<String, dynamic> data,
    String column,
  ) => switch (_integer(data, column)) {
    0 => domain.IntentionArchiveState.active,
    1 => domain.IntentionArchiveState.archived,
    _ => throw const _StoredIntentionCorruption(),
  };

  static domain.IntentionTimestamp _timestamp(
    Map<String, dynamic> data,
    String column,
  ) {
    final microseconds = _integer(data, column);
    try {
      return domain.IntentionTimestamp(
        DateTime.fromMicrosecondsSinceEpoch(microseconds, isUtc: true),
      );
    } on ArgumentError catch (_) {
      throw const _StoredIntentionCorruption();
    }
  }

  static int _integer(Map<String, dynamic> data, String column) {
    final value = data[column];
    if (value is int) return value;
    throw const _StoredIntentionCorruption();
  }
}

final class _CatalogCursorOwner {}

final class _DriftIntentionCatalogCursor implements IntentionCatalogCursor {
  const _DriftIntentionCatalogCursor({
    required this.owner,
    required this.scope,
    required this.normalizedTitleFilter,
    required this.order,
    required this.boundaryTimestamp,
    required this.boundaryId,
  });

  final _CatalogCursorOwner owner;
  final IntentionScope scope;
  final String? normalizedTitleFilter;
  final IntentionCatalogOrder order;
  final domain.IntentionTimestamp boundaryTimestamp;
  final IntentionId boundaryId;

  bool isOwnedBy(_CatalogCursorOwner candidate) => identical(owner, candidate);

  bool matches(IntentionCatalogQuery query) =>
      scope == query.scope &&
      normalizedTitleFilter == query.titleFilter?.map((value) => value) &&
      order == query.order;
}

IntentionFailure _classifyDetailReadFailure(Object error) {
  if (error is _StoredIntentionCorruption) {
    return const IntentionCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const IntentionCorruptionFailure(),
    SqliteUnavailableFailure() => const IntentionUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const IntentionUnexpectedFailure(),
  };
}

IntentionFailure _classifyCatalogReadFailure(Object error) =>
    _classifyDetailReadFailure(error);

IntentionFailure _classifyCommandFailure(
  Object error,
  IntentionCommand command,
) {
  if (error is IntentionTextValidationException) {
    return IntentionTextInputValidationFailure(error.failure);
  }
  if (error is _IntentionNotFound) {
    return const IntentionNotFoundFailure();
  }
  if (error is _StoredIntentionCorruption) {
    return const IntentionCorruptionFailure();
  }

  return switch (classifySqliteFailure(error)) {
    SqliteConstraintFailure(:final extendedResultCode)
        when command is CreateIntention &&
            extendedResultCode ==
                SqlExtendedError.SQLITE_CONSTRAINT_PRIMARYKEY =>
      const IntentionConflictFailure(),
    SqliteConstraintFailure(:final extendedResultCode)
        when command is DeleteIntention &&
            extendedResultCode ==
                SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY =>
      const IntentionConflictFailure(),
    SqliteCorruptionFailure() => const IntentionCorruptionFailure(),
    SqliteUnavailableFailure() => const IntentionUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const IntentionUnexpectedFailure(),
  };
}

void _validateCommandText(IntentionCommand command) {
  switch (command) {
    case CreateIntention(:final title, :final description):
    case UpdateIntention(:final title, :final description):
      IntentionText.normalizeTitle(title);
      if (description != null) {
        IntentionText.normalizeDescription(description);
      }
    case EnableIntentionReadiness() ||
        DisableIntentionReadiness() ||
        ArchiveIntention() ||
        RestoreIntention() ||
        DeleteIntention():
      return;
  }
}

IntentionCommandDiagnosticsType _commandDiagnosticsType(
  IntentionCommand command,
) => switch (command) {
  CreateIntention() => IntentionCommandDiagnosticsType.create,
  UpdateIntention() => IntentionCommandDiagnosticsType.update,
  EnableIntentionReadiness() => IntentionCommandDiagnosticsType.enableReadiness,
  DisableIntentionReadiness() =>
    IntentionCommandDiagnosticsType.disableReadiness,
  ArchiveIntention() => IntentionCommandDiagnosticsType.archive,
  RestoreIntention() => IntentionCommandDiagnosticsType.restore,
  DeleteIntention() => IntentionCommandDiagnosticsType.delete,
};

DiagnosticsFailureCode _diagnosticsFailureCode(IntentionFailure failure) =>
    switch (failure) {
      IntentionValidationFailure() => DiagnosticsFailureCode.validation,
      IntentionNotFoundFailure() => DiagnosticsFailureCode.notFound,
      IntentionConflictFailure() => DiagnosticsFailureCode.conflict,
      IntentionUnavailableFailure() => DiagnosticsFailureCode.unavailable,
      IntentionCorruptionFailure() => DiagnosticsFailureCode.corruption,
      IntentionUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
    };

final class _StoredIntentionCorruption implements Exception {
  const _StoredIntentionCorruption();
}

final class _IntentionNotFound implements Exception {
  const _IntentionNotFound();
}
