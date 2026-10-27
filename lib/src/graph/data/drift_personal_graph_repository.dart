import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' show min;
import 'dart:typed_data';

import '../../data/local/app_database.dart' as local;
import '../../data/local/fts_query.dart';
import '../../data/local/sqlite_failure_classifier.dart';
import '../../daily_choice/application/daily_choice_details.dart';
import '../../daily_choice/application/daily_choice_catalog.dart';
import '../../daily_choice/application/choice_path_continuations.dart';
import '../../daily_choice/application/choice_path_draft.dart';
import '../../daily_choice/application/confirmed_choice_path.dart';
import '../../daily_choice/application/daily_choice_command.dart';
import '../../daily_choice/application/daily_choice_day_statuses.dart';
import '../../daily_choice/application/daily_choice_id_generator.dart';
import '../../daily_choice/application/daily_choice_result.dart';
import '../../daily_choice/domain/calendar_date.dart';
import '../../daily_choice/domain/choice_path_step_id.dart';
import '../../daily_choice/domain/daily_choice.dart';
import '../../daily_choice/domain/daily_choice_id.dart';
import '../../daily_choice/domain/daily_choice_priority.dart';
import '../../daily_choice/domain/daily_choice_schedule.dart';
import '../../data_transfer/application/graph_composition.dart';
import '../../data_transfer/application/graph_replacement.dart';
import '../../graph_backups/graph_backup_registry.dart';
import '../../graph_backups/graph_change_summary.dart';
import '../../graph_format/graph_format_codec.dart'
    show GraphFormatCodec, GraphFormatVersion;
import '../../graph_format/graph_format_records.dart'
    show
        DailyChoiceRecord,
        GraphEntityRecord,
        GraphRecordCounts,
        IntentionRecord,
        LongTermRelationRecord,
        TagAssignmentRecord,
        TagRecord;
import '../../graph_snapshots/graph_fact_log.dart';
import '../../graph_snapshots/graph_snapshot_store.dart'
    show
        GraphHistoryPackage,
        UnregisteredGraphSnapshot,
        graphSnapshotFailureCode;
import '../../intention/application/intention_command.dart';
import '../../intention/application/intention_id_generator.dart';
import '../../intention/application/intention_catalog.dart';
import '../../intention/application/intention_description_preview.dart';
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
import '../../statistics/application/contribution_counts.dart';
import '../../statistics/application/intention_statistics_breakdown.dart';
import '../../statistics/application/intention_statistics_calendar.dart';
import '../../statistics/application/intention_statistics_read_contract.dart';
import '../../statistics/application/statistics_period.dart';
import '../../statistics/application/statistics_read_contract.dart';
import '../../tag/application/tag_catalog.dart';
import '../../tag/application/tag_assignments.dart';
import '../../tag/application/tag_change.dart';
import '../../tag/application/tag_command.dart';
import '../../tag/application/tag_id_generator.dart';
import '../../tag/application/tag_read_result.dart';
import '../../tag/application/tag_result.dart';
import '../../tag/domain/tag.dart' as tag_domain;
import '../../tag/domain/tag_assignment.dart';
import '../../tag/domain/tag_id.dart';
import '../../tag/domain/tag_position.dart';
import '../application/graph_change.dart';
import '../application/graph_command_result.dart';
import '../application/graph_revision.dart';
import '../application/personal_graph_repository.dart';
import 'drift_relation_count_aggregates.dart';
import 'contribution_reachability.dart';
import 'graph_fact_capture.dart';
import 'graph_record_rows.dart';
import 'stored_choice_path_verification.dart';
import 'stored_graph_rows.dart';

import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart';

part 'drift_daily_choice_path_validation.dart';
part 'drift_personal_graph_repository_daily_choice_reads.dart';
part 'drift_personal_graph_repository_daily_choice_catalog.dart';
part 'drift_personal_graph_repository_daily_choice_day_statuses.dart';
part 'drift_personal_graph_repository_daily_choice_commands.dart';
part 'drift_personal_graph_repository_relation_commands.dart';
part 'drift_personal_graph_repository_relation_details.dart';
part 'drift_personal_graph_repository_relation_groups.dart';
part 'drift_personal_graph_repository_choice_path_reads.dart';
part 'drift_personal_graph_repository_tag_reads.dart';
part 'drift_personal_graph_repository_tag_commands.dart';
part 'drift_personal_graph_repository_fact_log.dart';
part 'drift_personal_graph_repository_composition.dart';
part 'drift_personal_graph_repository_backups.dart';
part 'drift_personal_graph_repository_replacement.dart';
part 'drift_personal_graph_repository_statistics.dart';
part 'drift_statistics_relation_snapshot.dart';
part 'drift_statistics_seed_groups.dart';
part 'drift_intention_statistics_source.dart';
part 'drift_intention_statistics_reader.dart';
part 'drift_through_relations_statistics_reader.dart';

final class DriftPersonalGraphRepository
    implements
        PersonalGraphRepository,
        ObservableGraphFactLog,
        GraphCompositionSource,
        GraphBackupRegistry,
        GraphReplacement {
  DriftPersonalGraphRepository(
    this._database,
    this._idGenerator,
    this._now,
    this._diagnosticsSink, {
    LongTermRelationIdGenerator? relationIdGenerator,
    DailyChoiceIdGenerator? dailyChoiceIdGenerator,
    ChoicePathStepIdGenerator? choicePathStepIdGenerator,
    TagIdGenerator? tagIdGenerator,
    this._statisticsReachabilityRunner = runContributionReachabilityInIsolate,
    this._intentionStatisticsRunner = runIntentionContributionInIsolate,
  }) : _relationIdGenerator =
           relationIdGenerator ?? UuidV7LongTermRelationIdGenerator(),
       _dailyChoiceIdGenerator =
           dailyChoiceIdGenerator ?? UuidV7DailyChoiceIdGenerator(),
       _choicePathStepIdGenerator =
           choicePathStepIdGenerator ?? UuidV7ChoicePathStepIdGenerator(),
       _tagIdGenerator = tagIdGenerator ?? UuidV7TagIdGenerator();

  final local.AppDatabase _database;
  final IntentionIdGenerator _idGenerator;
  final DateTime Function() _now;
  final DiagnosticsSink _diagnosticsSink;
  final LongTermRelationIdGenerator _relationIdGenerator;
  final DailyChoiceIdGenerator _dailyChoiceIdGenerator;
  final ChoicePathStepIdGenerator _choicePathStepIdGenerator;
  final TagIdGenerator _tagIdGenerator;
  var _epoch = _GraphEpoch();
  final _AsyncSequencer _sequencer = _AsyncSequencer();
  final StreamController<int> _confirmedPositions =
      StreamController.broadcast();

  /// Сигнал подтверждённой записи реестра копий.
  final StreamController<void> _backupsChanged = StreamController.broadcast();
  final Map<IntentionId, Set<StreamController<void>>> _intentionWatchers = {};
  final Map<DailyChoiceId, Set<_DailyChoiceWatchRegistration>>
  _dailyChoiceWatchers = {};
  final Map<LongTermRelationId, Set<_RelationWatchRegistration>>
  _relationWatchers = {};
  var _mutationSequence = 0;
  var _lastRelationChangeSequence = 0;
  ContributionRelationGraph? _statisticsRelationSnapshot;
  final ContributionReachabilityRunner _statisticsReachabilityRunner;
  final List<_ThroughRelationsStatisticsResult> _throughRelationsResults = [];
  final IntentionContributionRunner _intentionStatisticsRunner;
  final List<_IntentionStatisticsResult> _intentionStatisticsResults = [];

  GraphRevision get _currentRevision =>
      _DriftGraphRevision(_epoch, _mutationSequence);

  @override
  Future<StatisticsPageResult> getStatisticsPage(StatisticsQuery query) =>
      switch (query.view) {
        StatisticsView.sourceIntentions => _readStatisticsPage(
          query,
          _SavedPathStatisticsView.source,
        ),
        StatisticsView.intermediateIntentions => _readStatisticsPage(
          query,
          _SavedPathStatisticsView.intermediate,
        ),
        StatisticsView.selectedActions => _readStatisticsPage(
          query,
          _SavedPathStatisticsView.selected,
        ),
        StatisticsView.throughRelations => _readThroughRelationsStatisticsPage(
          query,
        ),
      };

  @override
  Future<IntentionStatisticsSectionResult> getIntentionStatisticsSection(
    IntentionStatisticsQuery query,
  ) async {
    try {
      final section = await _readIntentionStatisticsSection(query);
      return section == null
          ? const IntentionStatisticsSectionError(
              StatisticsIntentionNotFoundFailure(),
            )
          : IntentionStatisticsSectionSuccess(section);
    } on Object catch (error) {
      return IntentionStatisticsSectionError(
        _classifyStatisticsReadFailure(error),
      );
    }
  }

  @override
  Future<IntentionStatisticsBreakdownResult<T>> getIntentionStatisticsBreakdown<
    T
  >(StatisticsBreakdownCursor<T> cursor) async {
    try {
      return IntentionStatisticsBreakdownSuccess(
        await _readIntentionStatisticsBreakdown(cursor),
      );
    } on Object catch (error) {
      return IntentionStatisticsBreakdownError(
        _classifyStatisticsReadFailure(error),
      );
    }
  }

  @override
  Future<TagCatalogResult> getTagCatalog(TagCatalogMode mode) =>
      _readTagCatalog(mode);

  @override
  Future<TagAssignmentsResult> getTagAssignments(IntentionId intentionId) =>
      _readTagAssignments(intentionId);

  @override
  Stream<TagReadResult> watchTag(TagId id) => _watchTag(id);

  @override
  Stream<int> get confirmedPositions => _confirmedPositions.stream;

  @override
  Future<int> readCurrentPosition() => _readCurrentLogPosition();

  @override
  Future<List<StoredGraphLogPackage>> readPackages({
    required int after,
    required int upTo,
  }) => _readStoredLogPackages(after: after, upTo: upTo);

  @override
  Future<GraphRecordPortion> readGraphRecords({GraphRecordOrderKey? after}) =>
      _readGraphRecords(after);

  @override
  Future<GraphSnapshotEntry?> readSnapshotAtOrBefore(int position) =>
      _readSnapshotAtOrBefore(position);

  @override
  Future<Set<String>> readSnapshotFileNames() => _readSnapshotFileNames();

  @override
  Future<void> registerSnapshot(GraphSnapshotEntry snapshot) =>
      _registerSnapshot(snapshot);

  @override
  Future<List<String>> removeHistoryBefore(
    int boundary, {
    required Iterable<GraphSnapshotEntry> retained,
  }) => _removeHistoryBefore(boundary, retained);

  @override
  Stream<GraphCompositionRead> watchComposition() => _watchComposition();

  @override
  Stream<GraphBackupsRead> watchBackups() => _watchBackups();

  @override
  Future<List<GraphBackupEntry>> readBackups() => _selectBackups();

  @override
  Future<bool> insertDailyBackup({
    required DateTime dayStart,
    required GraphChangeTally? since,
  }) => _insertDailyBackup(dayStart, since);

  @override
  Future<void> insertManualBackup({required GraphChangeTally? since}) =>
      _insertManualBackup(since);

  @override
  Future<ConfirmedGraphReplacement> replaceGraph(
    UnregisteredGraphSnapshot snapshot, {
    required void Function(double share) onProgress,
    required GraphReplacementCancellation cancellation,
  }) => _replaceGraph(snapshot, onProgress, cancellation);

  DriftRelationCountAggregates get _relationCountAggregates =>
      DriftRelationCountAggregates(_database);

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => _readChoicePathContinuations(query);

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      _readDailyChoice(id);

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      _watchDailyChoice(id);

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => _readDailyChoiceCatalogPage(query);

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) => _readDailyChoiceDayStatuses(query);

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    final sortField = switch (query.order.field) {
      IntentionCatalogSortField.createdAt =>
        CatalogPageReadDiagnosticsSortField.createdAt,
      IntentionCatalogSortField.updatedAt =>
        CatalogPageReadDiagnosticsSortField.updatedAt,
      IntentionCatalogSortField.title =>
        CatalogPageReadDiagnosticsSortField.title,
    };
    _recordDiagnostics(
      CatalogPageReadDiagnosticsEvent(
        pageSize: query.pageSize,
        sortField: sortField,
        status: const DiagnosticsStarted(),
      ),
    );

    final cursor = query.cursor;
    try {
      final page = await _sequencer.run(
        () => _database.transaction(
          () => switch (cursor) {
            null => _readFirstCatalogPage(query),
            _DriftIntentionCatalogCursor() => _readCatalogContinuationPage(
              query,
              cursor,
            ),
            _ => throw StateError('Недопустимый cursor каталога.'),
          },
        ),
      );
      _recordDiagnostics(
        CatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          sortField: sortField,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(page);
    } on Object catch (error) {
      final failure = _classifyCatalogReadFailure(error);
      _recordDiagnostics(
        CatalogPageReadDiagnosticsEvent(
          pageSize: query.pageSize,
          sortField: sortField,
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
    RelationGroupPageQuery query,
  ) => _readRelationGroupPage(query);

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      _watchRelation(id);

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
          intention: decodeStoredIntention(row.data),
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
        throw const StoredGraphCorruption();
      }
      counts[id] = aggregate.counts;
    }
    return Map.unmodifiable(counts);
  }

  Future<LongTermRelationPermissions> _readRelationPermissions(
    LongTermRelationId id,
  ) async =>
      (await _relationCountAggregates.readPermissions([id]))[id] ??
      (throw const StoredGraphCorruption());

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
      final DailyChoiceCommand dailyChoiceCommand => await _executeDailyChoice(
        dailyChoiceCommand,
      ),
      final CreateTag createTag => await _executeTag(createTag),
      final UpdateTag updateTag => await _executeTag(updateTag),
      final MoveTag moveTag => await _executeTag(moveTag),
      final DeleteTag deleteTag => await _executeTag(deleteTag),
      final AssignTag assignTag => await _executeTag(assignTag),
      final RemoveTagAssignment removeTagAssignment => await _executeTag(
        removeTagAssignment,
      ),
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
    var creationStage = IntentionCreationCommandDiagnosticsStage.validation;

    try {
      _validateCommandText(command);
      final success = await _writeGraph<IntentionCommandSuccess>(
        (clock) => switch (command) {
          CreateIntention() => _createIntention(
            command,
            clock,
            onStage: (stage) => creationStage = stage,
          ),
          UpdateIntention() => _updateIntention(command, clock),
          EnableIntentionReadiness() => _changeReadiness(
            command.id,
            domain.IntentionReadiness.ready,
            clock,
          ),
          DisableIntentionReadiness() => _changeReadiness(
            command.id,
            domain.IntentionReadiness.notReady,
            clock,
          ),
          ArchiveIntention() => _changeArchiveState(
            command.id,
            domain.IntentionArchiveState.archived,
            clock,
          ),
          RestoreIntention() => _changeArchiveState(
            command.id,
            domain.IntentionArchiveState.active,
            clock,
          ),
          DeleteIntention() => _deleteIntention(command.id),
        },
      );
      _recordDiagnostics(
        _commandDiagnosticsEvent(
          command,
          creationStage: creationStage,
          status: DiagnosticsSucceeded(stopwatch.elapsed),
        ),
      );
      return ResultSuccess(success);
    } on Object catch (error) {
      final failure = _classifyCommandFailure(error, command);
      _recordDiagnostics(
        _commandDiagnosticsEvent(
          command,
          creationStage: creationStage,
          status: DiagnosticsFailed(
            duration: stopwatch.elapsed,
            code: _diagnosticsFailureCode(failure),
          ),
        ),
      );
      return ResultFailure(failure);
    }
  }

  /// Единый путь записи графа (ADR-0034): в последовательном исполнителе
  /// выполняет [body] в транзакции, дописывает в неё пакет фактов о
  /// затронутых сущностях и подтверждает её. После подтверждения ревизия
  /// продвигается на единицу, наблюдатели получают изменения команды, а
  /// [confirmedPositions] — позицию пакета.
  ///
  /// Признак записи стоит только внутри транзакции: без него база
  /// отклоняет запись в таблицы графа, пока включён захват фактов.
  ///
  /// Команда без изменений не пишет пакет и сохраняет ревизию. Любой отказ, в
  /// том числе запись сущности длиннее предела записи формата, откатывает и
  /// изменения графа, и пакет. [afterRollback] выполняется в исполнителе
  /// после отката и может заменить отказ своим.
  Future<ConfirmedGraphResult<T>> _writeGraph<T extends GraphCommandOutcome>(
    Future<_GraphWrite<T>> Function(_GraphWriteClock clock) body, {
    Future<void> Function(Object error)? afterRollback,
  }) => _sequencer.run(() async {
    final clock = _GraphWriteClock(_now);
    final (bool, int?, ConfirmedGraphResult<T>) committed;
    try {
      committed = await _database.transaction(() async {
        await _setGraphWriting(true);
        final write = await body(clock);
        final facts = await GraphFactCapture(_database).takeFacts();
        int? packagePosition;
        if (facts.isNotEmpty) {
          // Позиция — rowid пакета: INTEGER PRIMARY KEY AUTOINCREMENT.
          packagePosition = await _database
              .into(_database.graphLogPackages)
              .insert(
                local.GraphLogPackagesCompanion.insert(
                  recordedAt: clock.read().microsecondsSinceEpoch,
                  kind: 'change',
                  formatVersion: Value(GraphFormatVersion.current.number),
                  facts: Value(GraphFormatCodec.encodePackage(facts)),
                ),
              );
        }
        await _setGraphWriting(false);
        // Исполнитель не начнёт другую запись до публикации этой ревизии.
        final revision = write.didMutate
            ? _DriftGraphRevision(_epoch, _mutationSequence + 1)
            : _currentRevision;
        return (
          write.didMutate,
          packagePosition,
          ConfirmedGraphResult(
            revision: revision,
            value: write.toSuccess(revision),
          ),
        );
      });
    } on Object catch (error) {
      await afterRollback?.call(error);
      rethrow;
    }
    final (didMutate, packagePosition, confirmed) = committed;
    if (didMutate) {
      _mutationSequence++;
      _notifyGraphWatchersFor(confirmed.changes);
    }
    if (packagePosition != null) _confirmedPositions.add(packagePosition);
    return confirmed;
  });

  Future<void> _setGraphWriting(bool writing) => _database
      .update(_database.graphLogControl)
      .write(local.GraphLogControlCompanion(writing: Value(writing)));

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
        case DailyChoiceChange(:final intentionCounts):
          affected.addAll(intentionCounts.keys);
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
    _invalidateStatisticsRelationSnapshot(stableChanges);
    _notifyIntentionWatchersFor(stableChanges);
    _notifyDailyChoiceWatchersFor(stableChanges);
    _notifyRelationWatchersFor(stableChanges);
  }

  /// Создаёт намерение вместе с полным начальным состоянием команды.
  /// Вызывается внутри транзакции команды.
  ///
  /// Выбранные теги подтверждаются до генерации идентификатора и показания
  /// часов: отсутствие хотя бы одного отклоняет всё создание. Окончательный
  /// снимок читается и сверяется с командой до подтверждения транзакции,
  /// поэтому любой отказ откатывает намерение и назначения вместе.
  ///
  /// [onStage] сообщает диагностике переход к записи и к проверке
  /// результата: отказ относится к последнему сообщённому этапу, до первого
  /// перехода — к проверке.
  Future<_CommittedIntentionCommand> _createIntention(
    CreateIntention command,
    _GraphWriteClock clock, {
    required void Function(IntentionCreationCommandDiagnosticsStage) onStage,
  }) async {
    final title = IntentionText.normalizeTitle(command.title);
    final description = switch (command.description) {
      null => null,
      final value => IntentionText.normalizeDescription(value),
    };
    await _requireCreationTags(command.tagIds);

    onStage(IntentionCreationCommandDiagnosticsStage.write);
    final createdAt = domain.IntentionTimestamp(clock.read());
    final intention = domain.Intention(
      id: _idGenerator.generate(),
      title: title,
      description: description,
      readiness: command.readiness,
      archiveState: domain.IntentionArchiveState.active,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final intentionId = intention.id.toCanonicalString();

    await _database
        .into(_database.intentions)
        .insert(
          local.IntentionsCompanion.insert(
            id: intentionId,
            title: intention.title,
            description: Value(intention.description),
            isActionReady: Value(
              intention.readiness == domain.IntentionReadiness.ready,
            ),
            isArchived: const Value(false),
            createdAt: intention.createdAt.value.microsecondsSinceEpoch,
            updatedAt: intention.updatedAt.value.microsecondsSinceEpoch,
          ),
        );
    for (final tagId in command.tagIds) {
      await _database
          .into(_database.tagAssignments)
          .insert(
            local.TagAssignmentsCompanion.insert(
              tagId: tagId.toCanonicalString(),
              intentionId: intentionId,
            ),
          );
    }
    onStage(IntentionCreationCommandDiagnosticsStage.resultRead);
    final stored = await _readCommandSnapshot(intention.id);
    if (stored == null) throw const StoredGraphCorruption();
    final storedIntention = stored.intention;
    final after = await _catalogEntrySnapshot(stored);
    final assignedTagIds = [for (final tag in after.summary.tags) tag.id];
    if (!_sameIntention(storedIntention, intention) ||
        assignedTagIds.length != command.tagIds.length ||
        !command.tagIds.containsAll(assignedTagIds)) {
      throw const StoredGraphCorruption();
    }
    return _CommittedIntentionCreated(
      intention: storedIntention,
      after: after,
      assignedTagIds: assignedTagIds,
    );
  }

  /// Подтверждает сохранённые данные выбранных тегов создания.
  /// Вызывается внутри транзакции команды.
  ///
  /// Отсутствующие теги собираются полностью и отклоняют создание одним
  /// отказом; повреждённая строка тега остаётся повреждением.
  Future<void> _requireCreationTags(Set<TagId> tagIds) async {
    if (tagIds.isEmpty) return;
    final found = await _findTagsByIds(tagIds);
    final missing = [
      for (final id in tagIds)
        if (!found.containsKey(id)) id,
    ];
    if (missing.isNotEmpty) throw _IntentionCreationTagsMissing(missing);
  }

  bool _sameIntention(domain.Intention stored, domain.Intention expected) =>
      stored.id == expected.id &&
      stored.title == expected.title &&
      stored.description == expected.description &&
      stored.readiness == expected.readiness &&
      stored.archiveState == expected.archiveState &&
      stored.createdAt == expected.createdAt &&
      stored.updatedAt == expected.updatedAt;

  Future<_CommittedIntentionCommand> _updateIntention(
    UpdateIntention command,
    _GraphWriteClock clock,
  ) async {
    final title = IntentionText.normalizeTitle(command.title);
    final description = switch (command.description) {
      null => null,
      final value => IntentionText.normalizeDescription(value),
    };
    final storedBefore = await _readCommandSnapshot(command.id);
    if (storedBefore == null) throw const _IntentionNotFound();

    final existing = storedBefore.intention;
    final before = await _catalogEntrySnapshot(storedBefore);
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
      updatedAt: domain.IntentionTimestamp(clock.read()),
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
    if (stored == null) throw const StoredGraphCorruption();
    return _CommittedIntentionUpdated(
      intention: stored.intention,
      before: before,
      after: await _catalogEntrySnapshot(stored),
    );
  }

  Future<_CommittedIntentionCommand> _changeReadiness(
    IntentionId id,
    domain.IntentionReadiness readiness,
    _GraphWriteClock clock,
  ) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const _IntentionNotFound();

    final existing = storedBefore.intention;
    final before = await _catalogEntrySnapshot(storedBefore);
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
      updatedAt: domain.IntentionTimestamp(clock.read()),
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
    if (stored == null) throw const StoredGraphCorruption();
    return _CommittedIntentionUpdated(
      intention: stored.intention,
      before: before,
      after: await _catalogEntrySnapshot(stored),
    );
  }

  Future<_CommittedIntentionCommand> _changeArchiveState(
    IntentionId id,
    domain.IntentionArchiveState archiveState,
    _GraphWriteClock clock,
  ) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const _IntentionNotFound();

    final existing = storedBefore.intention;
    final before = await _catalogEntrySnapshot(storedBefore);
    if (existing.archiveState == archiveState) {
      return _CommittedIntentionUnchanged(intention: existing, entry: before);
    }

    final cascadedNeighborIds =
        archiveState == domain.IntentionArchiveState.archived
        ? await _readActiveRelationNeighborIds(id)
        : const <IntentionId>[];
    final archivedRelations = cascadedNeighborIds.isNotEmpty
        ? await _archiveActiveRelations(id)
        : const <_CascadedRelationArchive>[];

    final updated = domain.Intention(
      id: existing.id,
      title: existing.title,
      description: existing.description,
      readiness: existing.readiness,
      archiveState: archiveState,
      createdAt: existing.createdAt,
      updatedAt: domain.IntentionTimestamp(clock.read()),
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
    if (stored == null) throw const StoredGraphCorruption();
    final affectedCounts = archiveState == domain.IntentionArchiveState.archived
        ? await _readVerifiedRelationCountsFor([id, ...cascadedNeighborIds])
        : const <IntentionId, RelationCounts>{};
    return _CommittedIntentionUpdated(
      intention: stored.intention,
      before: before,
      after: await _catalogEntrySnapshot(stored),
      affectedCounts: affectedCounts,
      archivedRelations: archivedRelations,
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
        decodeStoredIntentionId(requiredStoredString(row.data, 'neighbor_id')),
    ];
  }

  Future<List<_CascadedRelationArchive>> _archiveActiveRelations(
    IntentionId id,
  ) async {
    final serializedId = id.toCanonicalString();
    final rows = await _database
        .customSelect(
          '''SELECT relation.creation_sequence, relation.id,
                relation.source_intention_id, relation.related_intention_id,
                relation.type, relation.priority, relation.is_archived,
                EXISTS(SELECT 1 FROM daily_choice_path_steps AS step
                       WHERE step.long_term_relation_id = relation.id) AS is_referenced
         FROM long_term_relations AS relation
         WHERE relation.is_archived = 0 AND
               (relation.source_intention_id = ? OR relation.related_intention_id = ?)''',
          variables: [
            Variable<String>(serializedId),
            Variable<String>(serializedId),
          ],
          readsFrom: {
            _database.longTermRelations,
            _database.dailyChoicePathSteps,
          },
        )
        .get();
    final archived = [
      for (final row in rows)
        _CascadedRelationArchive(
          StoredLongTermRelation.decode(row.data).toDomain(),
          switch (requiredStoredInteger(row.data, 'is_referenced')) {
            0 => const LongTermRelationPermissions.unrestricted(),
            1 => const LongTermRelationPermissions.referencedByDailyPath(),
            _ => throw const StoredGraphCorruption(),
          },
        ),
    ];
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
    return archived;
  }

  Future<_CommittedIntentionCommand> _deleteIntention(IntentionId id) async {
    final storedBefore = await _readCommandSnapshot(id);
    if (storedBefore == null) throw const _IntentionNotFound();
    if (await _hasBlockingRelations(id)) {
      throw _IntentionHasBlockingRelations(id);
    }
    final before = await _catalogEntrySnapshot(storedBefore);
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
    return row == null
        ? null
        : _StoredIntentionCommandSnapshot.fromRow(row.data);
  }

  Future<IntentionCatalogFirstPage> _readFirstCatalogPage(
    IntentionCatalogQuery query,
  ) async {
    final intentions = _database.intentions;
    final condition = _catalogCondition(query);
    // Один подсчёт без условия готовности даёт и числа обоих типов, и общее
    // количество по условию готовности запроса.
    final allExpression = countAll();
    final actionsExpression = countAll(
      filter: intentions.isActionReady.equals(true),
    );
    final countQuery = _database.selectOnly(intentions)
      ..addColumns([allExpression, actionsExpression])
      ..where(_catalogConditionExceptReadiness(query));
    final countRow = await countQuery.getSingle();
    final typeCounts = IntentionTypeCounts(
      all: countRow.read(allExpression)!,
      actions: countRow.read(actionsExpression)!,
    );
    final totalCount = switch (query.readinessFilter) {
      IntentionReadinessFilter.all => typeCounts.all,
      IntentionReadinessFilter.readyOnly => typeCounts.actions,
      IntentionReadinessFilter.notReadyOnly => typeCounts.intentions,
    };
    final rowsQuery = _database.selectOnly(intentions)
      ..addColumns([
        intentions.id,
        intentions.title,
        intentions.titleSearchKey,
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
    final (items, nextCursor) = await _readCatalogPortion(
      await rowsQuery.get(),
      query,
    );

    return IntentionCatalogFirstPage(
      items: items,
      totalCount: totalCount,
      typeCounts: query.requestsTypeCounts ? typeCounts : null,
      nextCursor: nextCursor,
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
        intentions.titleSearchKey,
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
    final (items, nextCursor) = await _readCatalogPortion(
      await rowsQuery.get(),
      query,
    );

    return IntentionCatalogContinuationPage(
      items: items,
      nextCursor: nextCursor,
      revision: _currentRevision,
    );
  }

  Expression<bool> _catalogCondition(IntentionCatalogQuery query) {
    final intentions = _database.intentions;
    final readinessCondition = switch (query.readinessFilter) {
      IntentionReadinessFilter.all => const Constant(true),
      IntentionReadinessFilter.readyOnly => intentions.isActionReady.equals(
        true,
      ),

      IntentionReadinessFilter.notReadyOnly => intentions.isActionReady.equals(
        false,
      ),
    };
    return readinessCondition & _catalogConditionExceptReadiness(query);
  }

  Expression<bool> _catalogConditionExceptReadiness(
    IntentionCatalogQuery query,
  ) {
    final intentions = _database.intentions;
    var condition = switch (query.scope) {
      IntentionScope.active => intentions.isArchived.equals(false),
      IntentionScope.archived => intentions.isArchived.equals(true),
      IntentionScope.all => const Constant<bool>(true),
    };
    final excludedIntentionId = query.excludedIntentionId;
    if (excludedIntentionId != null) {
      condition =
          condition &
          intentions.id.equals(excludedIntentionId.toCanonicalString()).not();
    }
    final requiredTagIds = query.tagFilter.requiredTagIds;
    if (requiredTagIds.isNotEmpty) {
      condition = condition & _RequiredCatalogTagsExpression(requiredTagIds);
    }
    final excludedTagIds = query.tagFilter.excludedTagIds;
    if (excludedTagIds.isNotEmpty) {
      condition = condition & _ExcludedCatalogTagsExpression(excludedTagIds);
    }
    final filter = query.titleFilter;
    if (filter == null) return condition;
    return condition &
        LocalIntentionTitleSearch(filter).conditionFor(intentions);
  }

  OrderingTerm _primaryOrderingTerm(
    local.Intentions intentions,
    IntentionCatalogOrder order,
  ) {
    final column = switch (order.field) {
      IntentionCatalogSortField.createdAt => intentions.createdAt,
      IntentionCatalogSortField.updatedAt => intentions.updatedAt,
      IntentionCatalogSortField.title => intentions.titleSearchKey,
    };
    return switch (order.direction) {
      IntentionCatalogSortDirection.ascending => OrderingTerm.asc(column),
      IntentionCatalogSortDirection.descending => OrderingTerm.desc(column),
    };
  }

  /// Строка следует за курсором в действующем порядке. Отдельное сравнение
  /// значения поля ограничивает диапазон обхода индекса порядка.
  Expression<bool> _keysetCondition(
    IntentionCatalogQuery query,
    _DriftIntentionCatalogCursor cursor,
  ) {
    final intentions = _database.intentions;
    final direction = query.order.direction;
    final (notBefore, after) = switch ((query.order.field, cursor.boundary)) {
      (
        IntentionCatalogSortField.createdAt,
        _CatalogTimestampBoundary(:final timestamp),
      ) =>
        _boundaryConditions(intentions.createdAt, timestamp, direction),
      (
        IntentionCatalogSortField.updatedAt,
        _CatalogTimestampBoundary(:final timestamp),
      ) =>
        _boundaryConditions(intentions.updatedAt, timestamp, direction),
      (
        IntentionCatalogSortField.title,
        _CatalogTitleBoundary(:final storedTitleSearchKey),
      ) =>
        _boundaryConditions(
          intentions.titleSearchKey,
          storedTitleSearchKey,
          direction,
        ),
      _ => throw StateError('Недопустимый cursor каталога.'),
    };
    return notBefore &
        (after |
            intentions.id.isBiggerThanValue(
              cursor.boundaryId.toCanonicalString(),
            ));
  }

  /// Условия «не раньше границы» и «строго после границы» по значению поля.
  (Expression<bool>, Expression<bool>)
  _boundaryConditions<T extends Comparable<Object>>(
    Expression<T> column,
    T boundary,
    IntentionCatalogSortDirection direction,
  ) => switch (direction) {
    IntentionCatalogSortDirection.ascending => (
      column.isBiggerOrEqualValue(boundary),
      column.isBiggerThanValue(boundary),
    ),
    IntentionCatalogSortDirection.descending => (
      column.isSmallerOrEqualValue(boundary),
      column.isSmallerThanValue(boundary),
    ),
  };

  /// Сводки первых `pageSize` строк и курсор после последней из них, если
  /// выборка нашла строку за пределами порции.
  Future<(List<IntentionSummary>, _DriftIntentionCatalogCursor?)>
  _readCatalogPortion(
    List<TypedResult> rows,
    IntentionCatalogQuery query,
  ) async {
    final storedRows = [
      for (final row in rows)
        (
          intention: decodeStoredIntention(row.rawData.data, 'intentions.'),
          titleSearchKey: decodeStoredTitleSearchKey(
            row.rawData.data,
            'intentions.',
          ),
        ),
    ];
    final itemRows = storedRows.take(query.pageSize).toList(growable: false);
    final intentionIds = [for (final row in itemRows) row.intention.id];
    final tags = await _readIntentionTags(intentionIds);
    final items = [
      for (var index = 0; index < itemRows.length; index++)
        _rehydrateSummary(
          itemRows[index].intention,
          itemRows[index].titleSearchKey,
          tags[intentionIds[index]] ?? (throw const StoredGraphCorruption()),
        ),
    ];
    if (rows.length <= query.pageSize) return (items, null);
    final boundary = itemRows.last;
    return (
      items,
      _DriftIntentionCatalogCursor(
        boundary: switch (query.order.field) {
          IntentionCatalogSortField.createdAt => _CatalogTimestampBoundary(
            boundary.intention.createdAt.value.microsecondsSinceEpoch,
          ),
          IntentionCatalogSortField.updatedAt => _CatalogTimestampBoundary(
            boundary.intention.updatedAt.value.microsecondsSinceEpoch,
          ),
          IntentionCatalogSortField.title => _CatalogTitleBoundary(
            boundary.titleSearchKey,
          ),
        },
        boundaryId: boundary.intention.id,
      ),
    );
  }

  IntentionSummary _rehydrateSummary(
    domain.Intention intention,
    String storedTitleSearchKey,
    List<tag_domain.Tag> tags,
  ) => IntentionSummary(
    id: intention.id,
    title: intention.title,
    descriptionPreview: switch (intention.description) {
      final description? => IntentionDescriptionPreview.fromDescription(
        description,
      ),
      null => null,
    },
    readiness: intention.readiness,
    archiveState: intention.archiveState,
    createdAt: intention.createdAt,
    updatedAt: intention.updatedAt,
    titleOrderKey: IntentionTitleOrderKey.fromSearchProjection(
      storedTitleSearchKey,
    ),
    tags: tags,
  );

  Future<IntentionCatalogEntrySnapshot> _catalogEntrySnapshot(
    _StoredIntentionCommandSnapshot stored,
  ) async {
    final intention = stored.intention;
    final tags = await _readIntentionTags([intention.id]);
    return _DriftIntentionCatalogEntrySnapshot(
      summary: _rehydrateSummary(
        intention,
        stored.titleSearchKey,
        tags[intention.id] ?? (throw const StoredGraphCorruption()),
      ),
      storedTitleSearchKey: stored.titleSearchKey,
    );
  }
}

final class _StoredIntentionCommandSnapshot {
  _StoredIntentionCommandSnapshot.fromRow(Map<String, Object?> data)
    : intention = decodeStoredIntention(data),
      titleSearchKey = decodeStoredTitleSearchKey(data);

  final domain.Intention intention;
  final String titleSearchKey;
}

/// Различает ревизии разных поколений графа: каждый экземпляр репозитория
/// начинает свою эпоху и новую — после каждой замены графа (ADR-0036).
final class _GraphEpoch {}

/// Итог тела записи графа: изменило ли оно граф и результат команды при
/// ревизии, которую получает подтверждение.
abstract interface class _GraphWrite<T extends GraphCommandOutcome> {
  bool get didMutate;

  T toSuccess(GraphRevision revision);
}

/// Итог тела, которое собрало результат из проверенного состояния своей
/// транзакции; результату недостаёт только ревизии.
final class _GraphWriteResult<T extends GraphCommandOutcome>
    implements _GraphWrite<T> {
  const _GraphWriteResult({required this.didMutate, required this._toSuccess});

  @override
  final bool didMutate;
  final T Function(GraphRevision revision) _toSuccess;

  @override
  T toSuccess(GraphRevision revision) => _toSuccess(revision);
}

/// Одно показание часов репозитория на запись графа: данные сущностей и время
/// записи пакета фактов получают одно наблюдение момента изменения
/// (ADR-0006). Запись без изменений часы не читает.
final class _GraphWriteClock {
  _GraphWriteClock(this._now);

  final DateTime Function() _now;
  DateTime? _reading;

  DateTime read() => _reading ??= _now();
}

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
    final matchesReadiness = switch (query.readinessFilter) {
      IntentionReadinessFilter.all => true,
      IntentionReadinessFilter.readyOnly =>
        summary.readiness == domain.IntentionReadiness.ready,

      IntentionReadinessFilter.notReadyOnly =>
        summary.readiness == domain.IntentionReadiness.notReady,
    };
    if (!matchesScope ||
        !matchesReadiness ||
        summary.id == query.excludedIntentionId ||
        !query.tagFilter.matches(summary.tags.map((tag) => tag.id).toSet())) {
      return false;
    }

    final filter = query.titleFilter;
    return filter == null ||
        _storedTitleSearchKey.contains(filter.map(titleSearchKey));
  }
}

sealed class _CommittedIntentionCommand
    implements _GraphWrite<IntentionCommandSuccess> {
  const _CommittedIntentionCommand();

  IntentionId get intentionId;
}

final class _CommittedIntentionCreated extends _CommittedIntentionCommand {
  _CommittedIntentionCreated({
    required this.intention,
    required this.after,
    required Iterable<TagId> assignedTagIds,
  }) : assignedTagIds = List.unmodifiable(assignedTagIds);

  final domain.Intention intention;
  final IntentionCatalogEntrySnapshot after;

  /// Созданные назначения в порядке собственных тегов снимка [after].
  final List<TagId> assignedTagIds;

  @override
  IntentionId get intentionId => intention.id;

  @override
  bool get didMutate => true;

  @override
  IntentionCommandSuccess toSuccess(GraphRevision revision) => IntentionSaved(
    intention,
    catalogMutation: IntentionCatalogCreated(revision: revision, entry: after),
    additionalChanges: [
      for (final tagId in assignedTagIds)
        TagAssignmentChangedChange(
          revision: revision,
          assignment: TagAssignment(tagId: tagId, intentionId: intention.id),
          state: TagAssignmentState.assigned,
        ),
    ],
  );
}

final class _CommittedIntentionUpdated extends _CommittedIntentionCommand {
  _CommittedIntentionUpdated({
    required this.intention,
    required this.before,
    required this.after,
    Map<IntentionId, RelationCounts> affectedCounts = const {},
    List<_CascadedRelationArchive> archivedRelations = const [],
  }) : affectedCounts = Map.unmodifiable(affectedCounts),
       archivedRelations = List.unmodifiable(archivedRelations);

  final domain.Intention intention;
  final IntentionCatalogEntrySnapshot before;
  final IntentionCatalogEntrySnapshot after;
  final Map<IntentionId, RelationCounts> affectedCounts;
  final List<_CascadedRelationArchive> archivedRelations;

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
      for (final relation in archivedRelations) relation.toChange(revision),
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

/// Набор идентификаторов передаётся одним параметром: JSON-массивом
/// различных канонических строк для `json_each(?)`. Чтение ничего не пишет на
/// соединение, а размер набора не ограничен числом параметров SQL-выражения.
final class _CatalogIdsParameter {
  _CatalogIdsParameter(Iterable<String> canonicalIds)
    : _canonicalIds = {...canonicalIds};

  _CatalogIdsParameter.tags(Set<TagId> tagIds)
    : this(tagIds.map((id) => id.toCanonicalString()));

  final Set<String> _canonicalIds;

  int get distinctCount => _canonicalIds.length;

  void writeInto(GenerationContext context) =>
      Variable<String>(jsonEncode([..._canonicalIds])).writeInto(context);
}

/// Намерение имеет собственные назначения всех обязательных тегов.
///
/// Набор читается из параметра один раз на выполнение запроса: некоррелированный
/// подзапрос отбирает намерения, у которых число собственных назначений
/// обязательных тегов равно числу различных обязательных идентификаторов, а
/// кандидат проверяется адресным поиском в отобранном множестве. Уникальность
/// `(tag_id, intention_id)` исключает повторный счёт одного назначения.
///
/// Унарный `+` запрещает SQLite вести выборку по отобранному множеству через
/// первичный ключ: иначе порция и продолжение сортируют все совпадения во
/// временном B-дереве. С ним выборку ведёт индекс порядка охвата, и она
/// завершается после `pageSize + 1` подходящих строк.
final class _RequiredCatalogTagsExpression extends Expression<bool> {
  _RequiredCatalogTagsExpression(Set<TagId> tagIds)
    : _tagIds = _CatalogIdsParameter.tags(tagIds);

  final _CatalogIdsParameter _tagIds;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write(
      '+intentions.id IN (SELECT assignment.intention_id '
      'FROM tag_assignments AS assignment '
      'WHERE assignment.tag_id IN ('
      'SELECT required_tag.value FROM json_each(',
    );
    _tagIds.writeInto(context);
    context.buffer.write(
      ') AS required_tag) '
      'GROUP BY assignment.intention_id HAVING COUNT(*) = ',
    );
    Variable<int>(_tagIds.distinctCount).writeInto(context);
    context.buffer.write(')');
  }
}

/// Намерение не имеет собственных назначений ни одного исключённого тега.
///
/// Набор читается из параметра один раз на выполнение запроса:
/// некоррелированный подзапрос отбирает намерения с назначением хотя бы одного
/// исключённого тега, а кандидат проверяется адресным поиском в этом
/// множестве. Столбец `intention_id` обязателен, поэтому `NULL` в множество не
/// попадает и `NOT IN` определён для каждого кандидата.
final class _ExcludedCatalogTagsExpression extends Expression<bool> {
  _ExcludedCatalogTagsExpression(Set<TagId> tagIds)
    : _tagIds = _CatalogIdsParameter.tags(tagIds);

  final _CatalogIdsParameter _tagIds;

  @override
  void writeInto(GenerationContext context) {
    context.buffer.write(
      'intentions.id NOT IN (SELECT assignment.intention_id '
      'FROM tag_assignments AS assignment '
      'WHERE assignment.tag_id IN ('
      'SELECT excluded_tag.value FROM json_each(',
    );
    _tagIds.writeInto(context);
    context.buffer.write(') AS excluded_tag))');
  }
}

final class _DriftIntentionCatalogCursor implements IntentionCatalogCursor {
  const _DriftIntentionCatalogCursor({
    required this.boundary,
    required this.boundaryId,
  });

  final _CatalogCursorBoundary boundary;
  final IntentionId boundaryId;
}

/// Сохранённое значение поля порядка у последней строки порции.
sealed class _CatalogCursorBoundary {
  const _CatalogCursorBoundary();
}

final class _CatalogTimestampBoundary extends _CatalogCursorBoundary {
  const _CatalogTimestampBoundary(this.timestamp);

  /// Микросекунды эпохи, как хранит колонка временной метки.
  final int timestamp;
}

final class _CatalogTitleBoundary extends _CatalogCursorBoundary {
  const _CatalogTitleBoundary(this.storedTitleSearchKey);

  final String storedTitleSearchKey;
}

IntentionFailure _classifyDetailReadFailure(Object error) {
  if (error is StoredGraphCorruption) {
    return const IntentionCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const IntentionCorruptionFailure(),
    SqliteUnavailableFailure() => const IntentionUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
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
  if (error case _IntentionCreationTagsMissing(:final tagIds)) {
    return IntentionCreationTagsMissingFailure(tagIds);
  }
  if (error is StoredGraphCorruption) {
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
    SqliteStorageFullFailure() ||
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

/// Событие диагностики команды намерения. Этап [creationStage] несёт
/// только создание.
IntentionCommandDiagnosticsEvent _commandDiagnosticsEvent(
  IntentionCommand command, {
  required IntentionCreationCommandDiagnosticsStage creationStage,
  required DiagnosticsStatus status,
}) {
  IntentionCommandDiagnosticsEvent event(
    IntentionCommandDiagnosticsType commandType,
  ) => IntentionCommandDiagnosticsEvent(
    commandType: commandType,
    status: status,
  );

  return switch (command) {
    CreateIntention() => IntentionCommandDiagnosticsEvent.create(
      stage: creationStage,
      status: status,
    ),
    UpdateIntention() => event(IntentionCommandDiagnosticsType.update),
    EnableIntentionReadiness() => event(
      IntentionCommandDiagnosticsType.enableReadiness,
    ),
    DisableIntentionReadiness() => event(
      IntentionCommandDiagnosticsType.disableReadiness,
    ),
    ArchiveIntention() => event(IntentionCommandDiagnosticsType.archive),
    RestoreIntention() => event(IntentionCommandDiagnosticsType.restore),
    DeleteIntention() => event(IntentionCommandDiagnosticsType.delete),
  };
}

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

final class _IntentionNotFound implements Exception {
  const _IntentionNotFound();
}

final class _IntentionHasBlockingRelations implements Exception {
  const _IntentionHasBlockingRelations(this.intentionId);

  final IntentionId intentionId;
}

/// Выбранные теги создания [tagIds] отсутствуют на момент проверки в
/// транзакции.
final class _IntentionCreationTagsMissing implements Exception {
  const _IntentionCreationTagsMissing(this.tagIds);

  final List<TagId> tagIds;
}
