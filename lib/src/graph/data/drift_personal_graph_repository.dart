import 'dart:async';

import '../../data/local/app_database.dart' as local;
import '../../data/local/fts_query.dart';
import '../../data/local/sqlite_failure_classifier.dart';
import '../../daily_choice/application/daily_choice_details.dart';
import '../../daily_choice/domain/calendar_date.dart';
import '../../daily_choice/domain/choice_path_step_id.dart';
import '../../daily_choice/domain/daily_choice.dart';
import '../../daily_choice/domain/daily_choice_description.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_id_generator.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_details.dart';
import '../../intention/application/intention_result.dart';
import '../../intention/application/title_search_key.dart';
import '../../intention/domain/intention.dart' as domain;
import '../../intention/domain/intention_id.dart';
import '../../intention/domain/intention_text.dart';
import '../../long_term_relation/application/long_term_relation_command.dart';
import '../../long_term_relation/application/long_term_relation_id_generator.dart';
import '../../long_term_relation/application/long_term_relation_projection.dart';
import '../../long_term_relation/application/long_term_relation_permissions.dart';
import '../../long_term_relation/application/relation_counts.dart';
import '../../long_term_relation/application/relation_group_page.dart';
import '../../long_term_relation/domain/long_term_relation.dart'
    as relation_domain;
import '../../long_term_relation/domain/long_term_relation_description.dart';
import '../../long_term_relation/domain/long_term_relation_id.dart';
import '../../shared/diagnostics/diagnostics_sink.dart';
import '../application/delete_blocking_relations.dart';
import '../application/graph_change.dart';
import '../application/graph_command_result.dart';
import '../application/graph_revision.dart';
import '../application/personal_graph_repository.dart';
import '../application/selected_relations.dart';
import 'drift_relation_count_aggregates.dart';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';

part 'drift_daily_choice_path_validation.dart';
part 'drift_personal_graph_repository_daily_choice_reads.dart';
part 'drift_personal_graph_repository_relation_commands.dart';
part 'drift_personal_graph_repository_blocking_relations.dart';
part 'drift_personal_graph_repository_relation_details.dart';
part 'drift_personal_graph_repository_relation_groups.dart';
part 'drift_personal_graph_repository_selected_relations.dart';

final class DriftPersonalGraphRepository implements PersonalGraphRepository {
  DriftPersonalGraphRepository(
    this._database,
    this._idGenerator,
    this._now,
    this._diagnosticsSink, {
    LongTermRelationIdGenerator? relationIdGenerator,
  }) : _relationIdGenerator =
           relationIdGenerator ?? UuidV7LongTermRelationIdGenerator();

  final local.AppDatabase _database;
  final IntentionIdGenerator _idGenerator;
  final DateTime Function() _now;
  final DiagnosticsSink _diagnosticsSink;
  final LongTermRelationIdGenerator _relationIdGenerator;
  final _GraphEpoch _epoch = _GraphEpoch();
  final _AsyncSequencer _sequencer = _AsyncSequencer();
  final Map<IntentionId, Set<StreamController<void>>> _intentionWatchers = {};
  final Map<LongTermRelationId, Set<_RelationWatchRegistration>>
  _relationWatchers = {};
  final Set<_SelectedRelationsWatchRegistration> _selectedRelationsWatchers =
      {};
  var _mutationSequence = 0;

  GraphRevision get _currentRevision =>
      _DriftGraphRevision(_epoch, _mutationSequence);

  DriftRelationCountAggregates get _relationCountAggregates =>
      DriftRelationCountAggregates(_database);

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      _readDailyChoice(id);

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      CatalogPageReadDiagnosticsEvent(
        pageSize: query.pageSize,
        status: const DiagnosticsStarted(),
      ),
    );

    final cursor = query.cursor;
    if (cursor != null &&
        (cursor is! _DriftIntentionCatalogCursor ||
            !cursor.isOwnedBy(_epoch) ||
            !cursor.matches(query))) {
      const failure = IntentionGenericValidationFailure();
      _recordDiagnostics(
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
      final page = await _sequencer.run(
        () async => switch (cursor) {
          null => await _database.transaction(
            () => _readFirstCatalogPage(query),
          ),
          _DriftIntentionCatalogCursor() => await _database.transaction(
            () => _readCatalogContinuationPage(query, cursor),
          ),
          _ => throw StateError('Недопустимый cursor каталога.'),
        },
      );
      _recordDiagnostics(
        CatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(page);
    } on Object catch (error) {
      final failure = _classifyCatalogReadFailure(error);
      _recordDiagnostics(
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
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) async {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const RelationCountsReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );

    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          final exists = await _database
              .customSelect(
                'SELECT 1 FROM intentions WHERE id = ?',
                variables: [Variable<String>(intentionId.toCanonicalString())],
                readsFrom: {_database.intentions},
              )
              .getSingleOrNull();
          if (exists == null) throw const _IntentionNotFound();
          return GraphSnapshot(
            value: await _readVerifiedRelationCounts(intentionId),
            revision: _currentRevision,
          );
        }),
      );
      _recordDiagnostics(
        RelationCountsReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifyRelationCountsReadFailure(error);
      _recordDiagnostics(
        RelationCountsReadDiagnosticsEvent(
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
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupQuery query,
  ) => _readRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _watchRelation(id);

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => _readSelectedRelations(query);

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => _watchSelectedRelations(query);

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) async* {
    final stopwatch = Stopwatch()..start();
    _recordDiagnostics(
      const IntentionDetailReadDiagnosticsEvent(status: DiagnosticsStarted()),
    );
    final invalidations = StreamController<void>();
    _intentionWatchers.putIfAbsent(id, () => {}).add(invalidations);

    try {
      final initial = await _readIntentionSnapshot(id);
      var lastRevision = initial.revision;
      _recordDiagnostics(
        IntentionDetailReadDiagnosticsEvent(
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      yield ResultSuccess(initial);

      await for (final _ in invalidations.stream) {
        final snapshot = await _readIntentionSnapshot(id);
        if (lastRevision.compareTo(snapshot.revision) ==
            GraphRevisionOrder.same) {
          continue;
        }
        lastRevision = snapshot.revision;
        _recordDiagnostics(
          IntentionDetailReadDiagnosticsEvent(
            status: DiagnosticsSucceeded(stopwatch.elapsed),
          ),
        );
        yield ResultSuccess(snapshot);
      }
    } on Object catch (error) {
      final failure = _classifyDetailReadFailure(error);
      _recordDiagnostics(
        IntentionDetailReadDiagnosticsEvent(
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      yield ResultFailure(failure);
    } finally {
      final watchers = _intentionWatchers[id];
      watchers?.remove(invalidations);
      if (watchers?.isEmpty ?? false) {
        _intentionWatchers.remove(id);
      }
      unawaited(invalidations.close());
    }
  }

  Future<GraphSnapshot<IntentionDetails?>> _readIntentionSnapshot(
    IntentionId id,
  ) => _sequencer.run(
    () => _database.transaction(() async {
      final row = await _database
          .customSelect(
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
          )
          .getSingleOrNull();
      if (row == null) {
        return GraphSnapshot(value: null, revision: _currentRevision);
      }
      return GraphSnapshot(
        value: IntentionDetails(
          intention: _rehydrateDetailRow(row),
          relationCounts: await _readVerifiedRelationCounts(id),
        ),
        revision: _currentRevision,
      );
    }),
  );

  Future<RelationCounts> _readVerifiedRelationCounts(IntentionId id) async {
    return (await _readVerifiedRelationCountsFor([id]))[id]!;
  }

  Future<Map<IntentionId, RelationCounts>> _readVerifiedRelationCountsFor(
    Iterable<IntentionId> ids,
  ) async {
    final uniqueIds = ids.toSet().toList(growable: false);
    final aggregates = <IntentionId, RelationCountAggregate>{};
    const batchSize = 400;
    for (var start = 0; start < uniqueIds.length; start += batchSize) {
      final end = start + batchSize < uniqueIds.length
          ? start + batchSize
          : uniqueIds.length;
      aggregates.addAll(
        await _relationCountAggregates.read(uniqueIds.sublist(start, end)),
      );
    }
    final counts = <IntentionId, RelationCounts>{};
    for (final id in uniqueIds) {
      final aggregate = aggregates[id];
      if (aggregate == null || aggregate.hasIntegrityViolation) {
        throw const _StoredIntentionCorruption();
      }
      counts[id] = aggregate.counts;
    }
    return Map.unmodifiable(counts);
  }

  Future<LongTermRelationPermissions> _readRelationPermissions(
    LongTermRelationId id,
  ) async =>
      (await _relationCountAggregates.readPermissions([id]))[id] ??
      (throw const _StoredIntentionCorruption());

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    final Object result = switch (command) {
      final IntentionCommand intentionCommand => await _executeIntention(
        intentionCommand,
      ),
      final LongTermRelationCommand relationCommand =>
        await _executeLongTermRelation(relationCommand),
      final DeleteBlockingRelations deleteCommand =>
        await _executeDeleteBlockingRelations(deleteCommand),
      _ => throw UnsupportedError(
        'Команда не поддерживается модулем личного графа.',
      ),
    };

    // Dart не выражает зависимость generic-результата от конкретного sealed
    // семейства команды. Ветка выше исчерпывающе сохраняет эту зависимость.
    return result as GraphCommandResult<TSuccess, TFailure>;
  }

  Future<GraphCommandResult<IntentionCommandSuccess, IntentionFailure>>
  _executeIntention(IntentionCommand command) async {
    final stopwatch = Stopwatch()..start();
    final commandType = _commandDiagnosticsType(command);

    try {
      _validateCommandText(command);
      final success = await _sequencer.run(() async {
        final committed = await _database.transaction(
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
        if (committed.didMutate) {
          _mutationSequence++;
        }
        final revision = _currentRevision;
        final value = committed.toSuccess(revision);
        final result = ConfirmedGraphResult(revision: revision, value: value);
        if (committed.didMutate) {
          _notifyGraphWatchersFor(value.changes);
        }
        return result;
      });
      _recordDiagnostics(
        IntentionCommandDiagnosticsEvent(
          commandType: commandType,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(success);
    } on Object catch (error) {
      final failure = _classifyCommandFailure(error, command);
      _recordDiagnostics(
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

  void _recordDiagnostics(DiagnosticsEvent event) {
    recordDiagnosticsSafely(_diagnosticsSink, event);
  }

  void _notifyIntentionWatchers(IntentionId id) {
    final watchers = _intentionWatchers[id];
    if (watchers == null) return;
    for (final watcher in List.of(watchers)) {
      watcher.add(null);
    }
  }

  void _notifyIntentionWatchersFor(Iterable<GraphChange> changes) {
    final affected = <IntentionId>{};
    for (final change in changes) {
      switch (change) {
        case IntentionRelationCountsChanged(:final intentionId):
          affected.add(intentionId);
        case IntentionCatalogMutation(:final before, :final after):
          final beforeId = before?.summary.id;
          final afterId = after?.summary.id;
          if (beforeId != null) affected.add(beforeId);
          if (afterId != null) affected.add(afterId);
        case GraphChange():
          break;
      }
    }
    for (final id in affected) {
      _notifyIntentionWatchers(id);
    }
  }

  void _notifyGraphWatchersFor(Iterable<GraphChange> changes) {
    final stableChanges = List<GraphChange>.unmodifiable(changes);
    _notifyIntentionWatchersFor(stableChanges);
    _notifyRelationWatchersFor(stableChanges);
    _notifySelectedRelationsWatchersFor(stableChanges);
  }

  Future<_CommittedIntentionCommand> _createIntention(
    CreateIntention command,
  ) async {
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
    final stored = await _readCommandSnapshot(intention.id);
    if (stored == null) throw const _StoredIntentionCorruption();
    final counts = await _readVerifiedRelationCounts(intention.id);
    return _CommittedIntentionCreated(
      intention: _rehydrateStored(stored.detail),
      after: _catalogEntrySnapshot(stored, counts),
    );
  }

  Future<_CommittedIntentionCommand> _updateIntention(
    UpdateIntention command,
  ) async {
    final title = IntentionText.normalizeTitle(command.title);
    final description = switch (command.description) {
      null => null,
      final value => IntentionText.normalizeDescription(value),
    };
    final storedBefore = await _readCommandSnapshot(command.id);
    if (storedBefore == null) throw const _IntentionNotFound();

    final existing = _rehydrateStored(storedBefore.detail);
    final counts = await _readVerifiedRelationCounts(command.id);
    final before = _catalogEntrySnapshot(storedBefore, counts);
    if (existing.title == title && existing.description == description) {
      return _CommittedIntentionUnchanged(intention: existing, entry: before);
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
    final stored = await _readCommandSnapshot(command.id);
    if (stored == null) throw const _StoredIntentionCorruption();
    return _CommittedIntentionUpdated(
      intention: _rehydrateStored(stored.detail),
      before: before,
      after: _catalogEntrySnapshot(stored, counts),
    );
  }

  Future<_CommittedIntentionCommand> _changeReadiness(
    IntentionId id,
    domain.IntentionReadiness readiness,
  ) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const _IntentionNotFound();

    final existing = _rehydrateStored(storedBefore.detail);
    final counts = await _readVerifiedRelationCounts(id);
    final before = _catalogEntrySnapshot(storedBefore, counts);
    if (existing.readiness == readiness) {
      return _CommittedIntentionUnchanged(intention: existing, entry: before);
    }

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
    final stored = await _readCommandSnapshot(id);
    if (stored == null) throw const _StoredIntentionCorruption();
    return _CommittedIntentionUpdated(
      intention: _rehydrateStored(stored.detail),
      before: before,
      after: _catalogEntrySnapshot(stored, counts),
    );
  }

  Future<_CommittedIntentionCommand> _changeArchiveState(
    IntentionId id,
    domain.IntentionArchiveState archiveState,
  ) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const _IntentionNotFound();

    final existing = _rehydrateStored(storedBefore.detail);
    final counts = await _readVerifiedRelationCounts(id);
    final before = _catalogEntrySnapshot(storedBefore, counts);
    if (existing.archiveState == archiveState) {
      return _CommittedIntentionUnchanged(intention: existing, entry: before);
    }

    final cascadedNeighborIds =
        archiveState == domain.IntentionArchiveState.archived
        ? await _readActiveRelationNeighborIds(id)
        : const <IntentionId>[];
    if (cascadedNeighborIds.isNotEmpty) {
      await _archiveActiveRelations(id);
    }

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
    final stored = await _readCommandSnapshot(id);
    if (stored == null) throw const _StoredIntentionCorruption();
    final affectedCounts = archiveState == domain.IntentionArchiveState.archived
        ? await _readVerifiedRelationCountsFor([id, ...cascadedNeighborIds])
        : const <IntentionId, RelationCounts>{};
    return _CommittedIntentionUpdated(
      intention: _rehydrateStored(stored.detail),
      before: before,
      after: _catalogEntrySnapshot(stored, affectedCounts[id] ?? counts),
      affectedCounts: affectedCounts,
    );
  }

  Future<List<IntentionId>> _readActiveRelationNeighborIds(
    IntentionId id,
  ) async {
    final serializedId = id.toCanonicalString();
    final rows = await _database
        .customSelect(
          '''
            SELECT DISTINCT
              CASE
                WHEN source_intention_id = ? THEN related_intention_id
                ELSE source_intention_id
              END AS neighbor_id
            FROM long_term_relations
            WHERE
              is_archived = 0 AND
              (source_intention_id = ? OR related_intention_id = ?)
            ORDER BY neighbor_id
          ''',
          variables: [
            Variable<String>(serializedId),
            Variable<String>(serializedId),
            Variable<String>(serializedId),
          ],
          readsFrom: {_database.longTermRelations},
        )
        .get();
    return [
      for (final row in rows)
        _decodeStoredNeighborIntentionId(row.data['neighbor_id']),
    ];
  }

  Future<void> _archiveActiveRelations(IntentionId id) async {
    final serializedId = id.toCanonicalString();
    await _database.customUpdate(
      '''
        UPDATE long_term_relations
        SET is_archived = 1
        WHERE
          is_archived = 0 AND
          (source_intention_id = ? OR related_intention_id = ?)
      ''',
      variables: [
        Variable<String>(serializedId),
        Variable<String>(serializedId),
      ],
      updates: {_database.longTermRelations},
    );
  }

  IntentionId _decodeStoredNeighborIntentionId(Object? value) {
    if (value is! String) throw const _StoredIntentionCorruption();
    return _decodeStoredIntentionId(value);
  }

  Future<_CommittedIntentionCommand> _deleteIntention(IntentionId id) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const _IntentionNotFound();
    if (await _hasBlockingRelations(id)) {
      throw _IntentionHasBlockingRelations(id);
    }
    final counts = await _readVerifiedRelationCounts(id);
    final before = _catalogEntrySnapshot(storedBefore, counts);
    final deletedRows = await (_database.delete(
      _database.intentions,
    )..where((row) => row.id.equals(id.toCanonicalString()))).go();
    if (deletedRows == 0) throw const _IntentionNotFound();
    return _CommittedIntentionDeleted(id: id, before: before);
  }

  Future<bool> _hasBlockingRelations(IntentionId id) async {
    final serializedId = id.toCanonicalString();
    final row = await _database
        .customSelect(
          '''
            SELECT EXISTS (
              SELECT 1
              FROM long_term_relations
              WHERE source_intention_id = ? OR related_intention_id = ?
              LIMIT 1
            ) OR EXISTS (
              SELECT 1
              FROM daily_choices
              WHERE source_intention_id = ? OR selected_intention_id = ?
              LIMIT 1
            ) AS has_blocking_relations
          ''',
          variables: [
            Variable<String>(serializedId),
            Variable<String>(serializedId),
            Variable<String>(serializedId),
            Variable<String>(serializedId),
          ],
          readsFrom: {_database.longTermRelations, _database.dailyChoices},
        )
        .getSingle();
    return row.read<int>('has_blocking_relations') == 1;
  }

  Future<_StoredIntentionCommandSnapshot?> _readCommandSnapshot(
    IntentionId id,
  ) async {
    final row = await _database
        .customSelect(
          '''
            SELECT
              id,
              title,
              title_search_key,
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
        )
        .getSingleOrNull();
    return row == null ? null : _StoredIntentionCommandSnapshot.fromRawRow(row);
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
    final items = await _readCatalogItems(rows, query.pageSize);
    final hasNextPage = rows.length > query.pageSize;

    return IntentionCatalogFirstPage(
      items: items,
      totalCount: totalCount,
      nextCursor: hasNextPage ? _cursorAt(query, items.last) : null,
      revision: _currentRevision,
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
    final items = await _readCatalogItems(rows, query.pageSize);
    final hasNextPage = rows.length > query.pageSize;

    return IntentionCatalogContinuationPage(
      items: items,
      nextCursor: hasNextPage ? _cursorAt(query, items.last) : null,
      revision: _currentRevision,
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

  Future<List<IntentionSummary>> _readCatalogItems(
    List<TypedResult> rows,
    int pageSize,
  ) async {
    final validatedRows = [for (final row in rows) _validateCatalogRow(row)];
    final itemRows = validatedRows.take(pageSize).toList(growable: false);
    final intentionIds = [for (final row in itemRows) row.intentionId];
    final aggregates = await _relationCountAggregates.read(intentionIds);
    return [
      for (var index = 0; index < itemRows.length; index++)
        _rehydrateSummary(
          itemRows[index],
          _requireValidAggregate(aggregates[intentionIds[index]]),
        ),
    ];
  }

  RelationCounts _requireValidAggregate(RelationCountAggregate? aggregate) {
    if (aggregate == null || aggregate.hasIntegrityViolation) {
      throw const _StoredIntentionCorruption();
    }
    return aggregate.counts;
  }

  IntentionId _decodeStoredIntentionId(String value) =>
      switch (IntentionId.decode(value)) {
        IntentionIdDecodingSuccess(:final id) => id,
        InvalidIntentionIdDecoding() =>
          throw const _StoredIntentionCorruption(),
      };

  ({IntentionId intentionId, _StoredIntentionDetail stored})
  _validateCatalogRow(TypedResult row) {
    final stored = _StoredIntentionDetail.fromCatalogRow(row);
    final intentionId = _decodeStoredIntentionId(stored.id);

    try {
      final normalizedTitle = IntentionText.normalizeTitle(stored.title);
      final normalizedDescription = stored.description == null
          ? null
          : IntentionText.normalizeDescription(stored.description!);
      if (normalizedTitle != stored.title ||
          normalizedDescription != stored.description) {
        throw const _StoredIntentionCorruption();
      }
      return (intentionId: intentionId, stored: stored);
    } on Object catch (error) {
      if (error is IntentionTextValidationException ||
          error is ArgumentError ||
          error is RangeError) {
        throw const _StoredIntentionCorruption();
      }
      rethrow;
    }
  }

  IntentionSummary _rehydrateSummary(
    ({IntentionId intentionId, _StoredIntentionDetail stored}) row,
    RelationCounts relationCounts,
  ) => IntentionSummary(
    id: row.intentionId,
    title: row.stored.title,
    hasDescription: row.stored.description != null,
    readiness: row.stored.readiness,
    archiveState: row.stored.archiveState,
    activeRelationCount: relationCounts.active,
    createdAt: row.stored.createdAt,
    updatedAt: row.stored.updatedAt,
  );

  IntentionCatalogCursor _cursorAt(
    IntentionCatalogQuery query,
    IntentionSummary boundary,
  ) => _DriftIntentionCatalogCursor(
    epoch: _epoch,
    scope: query.scope,
    normalizedTitleFilter: query.titleFilter?.map((value) => value),
    order: query.order,
    boundaryTimestamp: switch (query.order.field) {
      IntentionCatalogSortField.createdAt => boundary.createdAt,
      IntentionCatalogSortField.updatedAt => boundary.updatedAt,
    },
    boundaryId: boundary.id,
  );

  domain.Intention _rehydrateStored(_StoredIntentionDetail stored) =>
      _rehydrateValues(
        id: stored.id,
        title: stored.title,
        description: stored.description,
        readiness: stored.readiness,
        archiveState: stored.archiveState,
        createdAt: stored.createdAt,
        updatedAt: stored.updatedAt,
      );

  IntentionCatalogEntrySnapshot _catalogEntrySnapshot(
    _StoredIntentionCommandSnapshot stored,
    RelationCounts relationCounts,
  ) {
    final intention = _rehydrateStored(stored.detail);
    return _DriftIntentionCatalogEntrySnapshot(
      summary: IntentionSummary(
        id: intention.id,
        title: intention.title,
        hasDescription: intention.description != null,
        readiness: intention.readiness,
        archiveState: intention.archiveState,
        activeRelationCount: relationCounts.active,
        createdAt: intention.createdAt,
        updatedAt: intention.updatedAt,
      ),
      storedTitleSearchKey: stored.titleSearchKey,
    );
  }

  domain.Intention _rehydrateDetailRow(QueryRow row) {
    return _rehydrateStored(_StoredIntentionDetail.fromRawRow(row));
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

final class _StoredIntentionCommandSnapshot {
  const _StoredIntentionCommandSnapshot({
    required this.detail,
    required this.titleSearchKey,
  });

  factory _StoredIntentionCommandSnapshot.fromRawRow(QueryRow row) {
    final data = row.data;
    final titleSearchKey = _StoredIntentionDetail._requiredString(
      data,
      _StoredIntentionColumnNames.titleSearchKey,
    );
    try {
      IntentionText.ensureValidUnicodeRepertoire(
        titleSearchKey,
        field: IntentionTextField.title,
      );
    } on IntentionTextValidationException catch (_) {
      throw const _StoredIntentionCorruption();
    }
    if (titleSearchKey.isEmpty) throw const _StoredIntentionCorruption();

    return _StoredIntentionCommandSnapshot(
      detail: _StoredIntentionDetail._fromRawData(
        data,
        _StoredIntentionColumnNames.detail,
      ),
      titleSearchKey: titleSearchKey,
    );
  }

  final _StoredIntentionDetail detail;
  final String titleSearchKey;
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
    return _StoredIntentionDetail._fromRawData(
      row.data,
      _StoredIntentionColumnNames.detail,
    );
  }

  factory _StoredIntentionDetail.fromCatalogRow(TypedResult row) {
    return _StoredIntentionDetail._fromRawData(
      row.rawData.data,
      _StoredIntentionColumnNames.catalog,
    );
  }

  factory _StoredIntentionDetail._fromRawData(
    Map<String, dynamic> data,
    _StoredIntentionColumnNames columns,
  ) {
    return _StoredIntentionDetail(
      id: _requiredString(data, columns.id),
      title: _requiredString(data, columns.title),
      description: _nullableString(data, columns.description),
      readiness: _readiness(data, columns.isActionReady),
      archiveState: _archiveState(data, columns.isArchived),
      createdAt: _timestamp(data, columns.createdAt),
      updatedAt: _timestamp(data, columns.updatedAt),
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

final class _StoredIntentionColumnNames {
  const _StoredIntentionColumnNames({
    required this.id,
    required this.title,
    required this.description,
    required this.isActionReady,
    required this.isArchived,
    required this.createdAt,
    required this.updatedAt,
  });

  static const detail = _StoredIntentionColumnNames(
    id: 'id',
    title: 'title',
    description: 'description',
    isActionReady: 'is_action_ready',
    isArchived: 'is_archived',
    createdAt: 'created_at',
    updatedAt: 'updated_at',
  );

  static const catalog = _StoredIntentionColumnNames(
    id: 'intentions.id',
    title: 'intentions.title',
    description: 'intentions.description',
    isActionReady: 'intentions.is_action_ready',
    isArchived: 'intentions.is_archived',
    createdAt: 'intentions.created_at',
    updatedAt: 'intentions.updated_at',
  );

  static const titleSearchKey = 'title_search_key';

  final String id;
  final String title;
  final String description;
  final String isActionReady;
  final String isArchived;
  final String createdAt;
  final String updatedAt;
}

final class _GraphEpoch {}

final class _AsyncSequencer {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}

final class _DriftGraphRevision implements GraphRevision {
  const _DriftGraphRevision(this._epoch, this._sequence);

  final _GraphEpoch _epoch;
  final int _sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _DriftGraphRevision || !identical(_epoch, other._epoch)) {
      return GraphRevisionOrder.differentEpoch;
    }
    final comparison = _sequence.compareTo(other._sequence);
    return switch (comparison) {
      < 0 => GraphRevisionOrder.older,
      0 => GraphRevisionOrder.same,
      _ => GraphRevisionOrder.newer,
    };
  }
}

final class _DriftIntentionCatalogEntrySnapshot
    implements IntentionCatalogEntrySnapshot {
  const _DriftIntentionCatalogEntrySnapshot({
    required this.summary,
    required this._storedTitleSearchKey,
  });

  @override
  final IntentionSummary summary;
  final String _storedTitleSearchKey;

  @override
  bool matches(IntentionCatalogQuery query) {
    final matchesScope = switch (query.scope) {
      IntentionScope.active =>
        summary.archiveState == domain.IntentionArchiveState.active,
      IntentionScope.archived =>
        summary.archiveState == domain.IntentionArchiveState.archived,
      IntentionScope.all => true,
    };
    if (!matchesScope) return false;

    final filter = query.titleFilter;
    return filter == null ||
        _storedTitleSearchKey.contains(filter.map(titleSearchKey));
  }
}

sealed class _CommittedIntentionCommand {
  const _CommittedIntentionCommand();

  bool get didMutate;

  IntentionId get intentionId;

  IntentionCommandSuccess toSuccess(GraphRevision revision);
}

final class _CommittedIntentionCreated extends _CommittedIntentionCommand {
  const _CommittedIntentionCreated({
    required this.intention,
    required this.after,
  });

  final domain.Intention intention;
  final IntentionCatalogEntrySnapshot after;

  @override
  IntentionId get intentionId => intention.id;

  @override
  bool get didMutate => true;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) => IntentionSaved(
    intention,
    catalogMutation: IntentionCatalogCreated(revision: revision, entry: after),
  );
}

final class _CommittedIntentionUpdated extends _CommittedIntentionCommand {
  _CommittedIntentionUpdated({
    required this.intention,
    required this.before,
    required this.after,
    Map<IntentionId, RelationCounts> affectedCounts = const {},
  }) : affectedCounts = Map.unmodifiable(affectedCounts);

  final domain.Intention intention;
  final IntentionCatalogEntrySnapshot before;
  final IntentionCatalogEntrySnapshot after;
  final Map<IntentionId, RelationCounts> affectedCounts;

  @override
  IntentionId get intentionId => intention.id;

  @override
  bool get didMutate => true;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) => IntentionSaved(
    intention,
    catalogMutation: IntentionCatalogUpdated(
      revision: revision,
      before: before,
      after: after,
    ),
    additionalChanges: [
      for (final entry in affectedCounts.entries)
        IntentionRelationCountsChanged(
          revision: revision,
          intentionId: entry.key,
          counts: entry.value,
        ),
    ],
  );
}

final class _CommittedIntentionUnchanged extends _CommittedIntentionCommand {
  const _CommittedIntentionUnchanged({
    required this.intention,
    required this.entry,
  });

  final domain.Intention intention;
  final IntentionCatalogEntrySnapshot entry;

  @override
  IntentionId get intentionId => intention.id;

  @override
  bool get didMutate => false;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) => IntentionSaved(
    intention,
    catalogMutation: IntentionCatalogUnchanged(
      revision: revision,
      entry: entry,
    ),
  );
}

final class _CommittedIntentionDeleted extends _CommittedIntentionCommand {
  const _CommittedIntentionDeleted({required this.id, required this.before});

  final IntentionId id;
  final IntentionCatalogEntrySnapshot before;

  @override
  IntentionId get intentionId => id;

  @override
  bool get didMutate => true;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) => IntentionDeleted(
    id,
    catalogMutation: IntentionCatalogDeleted(revision: revision, entry: before),
  );
}

final class _DriftIntentionCatalogCursor implements IntentionCatalogCursor {
  const _DriftIntentionCatalogCursor({
    required this.epoch,
    required this.scope,
    required this.normalizedTitleFilter,
    required this.order,
    required this.boundaryTimestamp,
    required this.boundaryId,
  });

  final _GraphEpoch epoch;
  final IntentionScope scope;
  final String? normalizedTitleFilter;
  final IntentionCatalogOrder order;
  final domain.IntentionTimestamp boundaryTimestamp;
  final IntentionId boundaryId;

  bool isOwnedBy(_GraphEpoch candidate) => identical(epoch, candidate);

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

IntentionFailure _classifyRelationCountsReadFailure(Object error) {
  if (error is _IntentionNotFound) {
    return const IntentionNotFoundFailure();
  }
  return _classifyDetailReadFailure(error);
}

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
  if (error case _IntentionHasBlockingRelations(:final intentionId)) {
    return IntentionHasBlockingRelationsFailure(intentionId);
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
      IntentionHasBlockingRelationsFailure() => DiagnosticsFailureCode.conflict,
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

final class _IntentionHasBlockingRelations implements Exception {
  const _IntentionHasBlockingRelations(this.intentionId);

  final IntentionId intentionId;
}
