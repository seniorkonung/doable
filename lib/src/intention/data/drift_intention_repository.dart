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
        (cursor is! _DriftIntentionCatalogCursor || !cursor.matches(query))) {
      const failure = IntentionValidationFailure();
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
      final query = _database.select(_database.intentions)
        ..where((row) => row.id.equals(id.toCanonicalString()));
      await for (final row in query.watchSingleOrNull()) {
        final intention = row == null ? null : _rehydrate(row);
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
      final success = await _database.transaction(
        () => switch (command) {
          CreateIntention() => _createIntention(command),
          UpdateIntention() => _updateIntention(command),
          _ => throw StateError('Неподдерживаемая команда намерения.'),
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
            titleSearchKey: intention.title.toLowerCase(),
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
        titleSearchKey: Value(updated.title.toLowerCase()),
        description: Value(updated.description),
        updatedAt: Value(updated.updatedAt.value.microsecondsSinceEpoch),
      ),
    );
    return IntentionSaved(updated);
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
    final hasDescriptionExpression = intentions.description.isNotNull();

    final rowsQuery = _database.selectOnly(intentions)
      ..addColumns([hasDescriptionExpression])
      ..addColumns([
        intentions.id,
        intentions.title,
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
    final items = [
      for (final row in rows.take(query.pageSize))
        _rehydrateSummary(
          id: row.read(intentions.id)!,
          title: row.read(intentions.title)!,
          hasDescription: row.read(hasDescriptionExpression)!,
          isActionReady: row.read(intentions.isActionReady)!,
          isArchived: row.read(intentions.isArchived)!,
          createdAt: row.read(intentions.createdAt)!,
          updatedAt: row.read(intentions.updatedAt)!,
        ),
    ];
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
    final hasDescriptionExpression = intentions.description.isNotNull();
    final rowsQuery = _database.selectOnly(intentions)
      ..addColumns([hasDescriptionExpression])
      ..addColumns([
        intentions.id,
        intentions.title,
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
    final items = [
      for (final row in rows.take(query.pageSize))
        _rehydrateSummary(
          id: row.read(intentions.id)!,
          title: row.read(intentions.title)!,
          hasDescription: row.read(hasDescriptionExpression)!,
          isActionReady: row.read(intentions.isActionReady)!,
          isArchived: row.read(intentions.isArchived)!,
          createdAt: row.read(intentions.createdAt)!,
          updatedAt: row.read(intentions.updatedAt)!,
        ),
    ];
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
    required bool hasDescription,
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
      if (normalizedTitle != title) throw const _StoredIntentionCorruption();
      return IntentionSummary(
        id: intentionId,
        title: title,
        hasDescription: hasDescription,
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
          error is domain.IntentionTimestampOrderException ||
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
    final id = switch (IntentionId.decode(row.id)) {
      IntentionIdDecodingSuccess(:final id) => id,
      InvalidIntentionIdDecoding() => throw const _StoredIntentionCorruption(),
    };

    try {
      final title = IntentionText.normalizeTitle(row.title);
      final description = row.description == null
          ? null
          : IntentionText.normalizeDescription(row.description!);
      if (title != row.title ||
          description != row.description ||
          row.titleSearchKey != title.toLowerCase()) {
        throw const _StoredIntentionCorruption();
      }
      final createdAt = domain.IntentionTimestamp(
        DateTime.fromMicrosecondsSinceEpoch(row.createdAt, isUtc: true),
      );
      final updatedAt = domain.IntentionTimestamp(
        DateTime.fromMicrosecondsSinceEpoch(row.updatedAt, isUtc: true),
      );
      return domain.Intention(
        id: id,
        title: title,
        description: description,
        readiness: row.isActionReady
            ? domain.IntentionReadiness.ready
            : domain.IntentionReadiness.notReady,
        archiveState: row.isArchived
            ? domain.IntentionArchiveState.archived
            : domain.IntentionArchiveState.active,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    } on Object catch (error) {
      if (error is IntentionTextValidationException ||
          error is domain.IntentionTimestampOrderException ||
          error is ArgumentError ||
          error is RangeError) {
        throw const _StoredIntentionCorruption();
      }
      rethrow;
    }
  }
}

final class _DriftIntentionCatalogCursor implements IntentionCatalogCursor {
  const _DriftIntentionCatalogCursor({
    required this.scope,
    required this.normalizedTitleFilter,
    required this.order,
    required this.boundaryTimestamp,
    required this.boundaryId,
  });

  final IntentionScope scope;
  final String? normalizedTitleFilter;
  final IntentionCatalogOrder order;
  final domain.IntentionTimestamp boundaryTimestamp;
  final IntentionId boundaryId;

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
    return const IntentionValidationFailure();
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
    SqliteCorruptionFailure() => const IntentionCorruptionFailure(),
    SqliteUnavailableFailure() => const IntentionUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const IntentionUnexpectedFailure(),
  };
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
