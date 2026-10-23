part of 'drift_personal_graph_repository.dart';

/// Наибольшее число строк одного оператора удаления прежнего графа и строк
/// таблиц графа в одном пакете вставки записей снимка. Журналы операторов в
/// этой сборке SQLite живут в памяти, поэтому операторы замены небольшие, а
/// пакет вставки ограничивает записи, которые удерживаются до вставки.
const _replacementBatchRowLimit = 100;

extension _GraphReplacementWriting on DriftPersonalGraphRepository {
  /// Замена графа [GraphReplacement.replaceGraph] в последовательном
  /// исполнителе одной транзакцией верхнего уровня (ADR-0036).
  ///
  /// Захват фактов выключен на время транзакции, а признак записи единого
  /// пути не ставится: замену отражает в логе пакет «сброс», а не факты.
  /// Любой отказ откатывает транзакцию, в том числе выключение захвата, и
  /// новой эпохи не начинает.
  Future<ConfirmedGraphReplacement> _replaceGraph(
    UnregisteredGraphSnapshot snapshot,
    void Function(double share) onProgress,
    GraphReplacementCancellation cancellation,
  ) => _sequencer.run(() async {
    // Момент копии перед заменой и время записи пакета «сброс» — одно
    // показание часов (ADR-0006).
    final replacedAt = _now();
    final backupCreation = Stopwatch();
    final (resetPosition, addedBackup) = await _database.transaction(() async {
      await _setGraphCapture(false);
      final position = await _selectCurrentLogPosition();
      // Первая копия сравнивается с составом прежнего графа, поэтому сводка
      // считается до его удаления.
      final summary = (await _selectComposition()).isEmpty
          ? null
          : await _createBackupBeforeReplacement(
              GraphBackupCreationDiagnosticsStage.changeSummary,
              backupCreation,
              () => _summaryUpTo(position, null),
            );
      final progress = _ReplacementProgress(
        _recordTotal(await _selectRecordCounts()) +
            _recordTotal(snapshot.counts),
        onProgress,
      );
      await _deletePreviousGraph(progress, cancellation);
      await _insertSnapshotRecords(
        snapshot.readRecords(),
        progress,
        cancellation,
      );
      if (!_sameRecordCounts(await _selectRecordCounts(), snapshot.counts)) {
        throw const GraphReplacementRecordsRejected();
      }
      if (summary != null) {
        await _createBackupBeforeReplacement(
          GraphBackupCreationDiagnosticsStage.registration,
          backupCreation,
          () => _insertBackupRow(
            GraphBackupKind.beforeReplacement,
            replacedAt,
            position,
            summary,
          ),
        );
      }
      final resetPosition = position + 1;
      final snapshotId = await _insertSnapshotRow(
        snapshot.entryAt(resetPosition),
      );
      await _database
          .into(_database.graphLogPackages)
          .insert(
            local.GraphLogPackagesCompanion.insert(
              position: Value(resetPosition),
              recordedAt: replacedAt.microsecondsSinceEpoch,
              kind: 'reset',
              snapshotId: Value(snapshotId),
            ),
          );
      await _setGraphCapture(true);
      // Точка невозврата: после неё транзакцию завершает только COMMIT.
      cancellation.passPointOfNoReturn();
      return (resetPosition, summary != null);
    });
    if (addedBackup) {
      _recordDiagnostics(
        GraphBackupCreationDiagnosticsEvent.succeeded(
          kind: GraphBackupCreationDiagnosticsKind.beforeReplacement,
          duration: backupCreation.elapsed,
        ),
      );
    }
    return _startReplacedGraphEpoch(resetPosition, addedBackup: addedBackup);
  });

  /// Выполняет [run] — этап [stage] создания копии перед заменой; его
  /// длительность добавляется к [duration]. Отказ этапа диагностируется и
  /// передаётся вызывающему, а успех диагностирует подтверждённая замена:
  /// копия появляется только вместе с ней.
  Future<T> _createBackupBeforeReplacement<T>(
    GraphBackupCreationDiagnosticsStage stage,
    Stopwatch duration,
    Future<T> Function() run,
  ) async {
    duration.start();
    try {
      return await run();
    } on Object catch (error) {
      _recordDiagnostics(
        GraphBackupCreationDiagnosticsEvent.failed(
          kind: GraphBackupCreationDiagnosticsKind.beforeReplacement,
          stage: stage,
          duration: duration.elapsed,
          code: graphSnapshotFailureCode(error),
        ),
      );
      rethrow;
    } finally {
      duration.stop();
    }
  }

  /// Начинает после подтверждённой замены графа новую эпоху ревизий
  /// (ADR-0036) и возвращает результат замены с первой ревизией этой эпохи.
  ///
  /// Номер изменения продолжает расти: курсоры и загрузка снимка связей
  /// статистики, которые сверяют только его, тоже устаревают. Кэши
  /// статистики сбрасываются, а наблюдатели сущностей перечитывают их:
  /// ревизии прежней эпохи с новой несравнимы. Наблюдатели тегов узнают о
  /// замене от обновлений таблиц Drift, наблюдатели состава и лога — по
  /// позиции пакета «сброс» [resetPosition], а наблюдатели списка копий —
  /// если замена добавила копию перед заменой.
  ConfirmedGraphReplacement _startReplacedGraphEpoch(
    int resetPosition, {
    required bool addedBackup,
  }) {
    _epoch = _GraphEpoch();
    _mutationSequence++;
    _lastRelationChangeSequence = _mutationSequence;
    _statisticsRelationSnapshot = null;
    _throughRelationsResults.clear();
    _intentionStatisticsResults.clear();
    for (final watchers in List.of(_intentionWatchers.values)) {
      for (final watcher in List.of(watchers)) {
        watcher.add(null);
      }
    }
    for (final registrations in List.of(_dailyChoiceWatchers.values)) {
      for (final registration in List.of(registrations)) {
        registration.invalidations.add(null);
      }
    }
    for (final registrations in List.of(_relationWatchers.values)) {
      for (final registration in List.of(registrations)) {
        registration.invalidations.add(null);
      }
    }
    for (final registration in List.of(_selectedRelationsWatchers)) {
      registration.invalidations.add(null);
    }
    _confirmedPositions.add(resetPosition);
    if (addedBackup) _backupsChanged.add(null);
    return ConfirmedGraphReplacement(_currentRevision);
  }

  Future<void> _setGraphCapture(bool capture) => _database
      .update(_database.graphLogControl)
      .write(local.GraphLogControlCompanion(capture: Value(capture)));

  /// Удаляет прежний граф операторами не больше чем по
  /// [_replacementBatchRowLimit] строк в порядке, обратном ссылкам: дневные
  /// выборы вместе с шагами путей, которые каскадом удаляются с ними, затем
  /// связи, назначения тегов, теги и намерения. Назначения удаляются
  /// отдельно, а не каскадом тегов, поэтому [progress] получает число
  /// удалённых записей каждого вида.
  Future<void> _deletePreviousGraph(
    _ReplacementProgress progress,
    GraphReplacementCancellation cancellation,
  ) async {
    final tables =
        <(TableInfo<Table, Object?>, Set<TableInfo<Table, Object?>>)>[
          (
            _database.dailyChoices,
            {_database.dailyChoices, _database.dailyChoicePathSteps},
          ),
          (_database.longTermRelations, {_database.longTermRelations}),
          (_database.tagAssignments, {_database.tagAssignments}),
          (_database.tags, {_database.tags}),
          (_database.intentions, {_database.intentions}),
        ];
    for (final (table, updates) in tables) {
      final name = table.actualTableName;
      while (true) {
        cancellation.throwIfRequested();
        final deleted = await _database.customUpdate(
          'DELETE FROM $name WHERE rowid IN (SELECT rowid FROM $name LIMIT ?)',
          variables: [Variable.withInt(_replacementBatchRowLimit)],
          updates: updates,
          updateKind: UpdateKind.delete,
        );
        if (deleted == 0) break;
        progress.add(deleted);
      }
    }
  }

  /// Вставляет записи снимка [records] в порядке файла пакетами не больше
  /// чем по [_replacementBatchRowLimit] строк: дневной выбор занимает строку
  /// и по строке на каждый шаг пути. Пакет из одной записи может быть
  /// больше: длина записи ограничена пределом записи формата.
  Future<void> _insertSnapshotRecords(
    Stream<GraphEntityRecord> records,
    _ReplacementProgress progress,
    GraphReplacementCancellation cancellation,
  ) async {
    final batch = <GraphEntityRecord>[];
    var batchRows = 0;
    Future<void> flush() async {
      if (batch.isEmpty) return;
      cancellation.throwIfRequested();
      await _insertRecordBatch(batch);
      progress.add(batch.length);
      batch.clear();
      batchRows = 0;
    }

    await for (final record in records) {
      final rows = switch (record) {
        DailyChoiceRecord(:final path) => 1 + path.steps.length,
        _ => 1,
      };
      if (batchRows + rows > _replacementBatchRowLimit) await flush();
      batch.add(record);
      batchRows += rows;
    }
    await flush();
  }

  /// Вставляет [records] одним пакетом операторов. Ссылки, уникальность и
  /// активность участников активной связи проверяет схема, а непрерывность
  /// путей вставленных выборов — общая проверка сохранённого пути.
  Future<void> _insertRecordBatch(List<GraphEntityRecord> records) async {
    final choices = <DailyChoice>[];
    await _database.batch((batch) {
      for (final record in records) {
        switch (record) {
          case TagRecord(:final tag):
            batch.insert(
              _database.tags,
              local.TagsCompanion.insert(
                id: tag.id.toCanonicalString(),
                name: tag.name.value,
                color: Value(tag.color?.code),
                position: tag.position.value,
              ),
            );
          case IntentionRecord(:final intention):
            batch.insert(
              _database.intentions,
              local.IntentionsCompanion.insert(
                id: intention.id.toCanonicalString(),
                title: intention.title,
                description: Value(intention.description),
                isActionReady: Value(
                  intention.readiness == domain.IntentionReadiness.ready,
                ),
                isArchived: Value(
                  intention.archiveState ==
                      domain.IntentionArchiveState.archived,
                ),
                createdAt: intention.createdAt.value.microsecondsSinceEpoch,
                updatedAt: intention.updatedAt.value.microsecondsSinceEpoch,
              ),
            );
          case TagAssignmentRecord(:final assignment):
            batch.insert(
              _database.tagAssignments,
              local.TagAssignmentsCompanion.insert(
                tagId: assignment.tagId.toCanonicalString(),
                intentionId: assignment.intentionId.toCanonicalString(),
              ),
            );
          case LongTermRelationRecord():
            batch.insert(
              _database.longTermRelations,
              local.LongTermRelationsCompanion.insert(
                id: record.id.toCanonicalString(),
                sourceIntentionId: record.sourceIntentionId.toCanonicalString(),
                relatedIntentionId: record.relatedIntentionId
                    .toCanonicalString(),
                type: _storedRelationType(record.type),
                priority: _storedRelationPriority(record.priority),
                description: Value(record.description?.value),
                isArchived: Value(
                  record.scope == relation_domain.RelationScope.archived,
                ),
              ),
            );
          case DailyChoiceRecord(:final choice, :final path):
            batch.insert(
              _database.dailyChoices,
              local.DailyChoicesCompanion.insert(
                id: choice.id.toCanonicalString(),
                sourceIntentionId: choice.sourceIntentionId.toCanonicalString(),
                selectedIntentionId: choice.selectedIntentionId
                    .toCanonicalString(),
                choiceDate: choice.date.toCanonicalString(),
                description: Value(choice.description?.value),
                isCompleted: choice.isCompleted,
                scheduledMinute: Value(switch (choice.schedule) {
                  DailyChoiceAllDay() => null,
                  DailyChoiceTime(:final minuteOfDay) => minuteOfDay,
                }),
                priority: Value(choice.priority.level),
              ),
            );
            batch.insertAll(_database.dailyChoicePathSteps, [
              for (final step in path.steps)
                local.DailyChoicePathStepsCompanion.insert(
                  id: step.id.toCanonicalString(),
                  dailyChoiceId: step.dailyChoiceId.toCanonicalString(),
                  longTermRelationId: step.relationId.toCanonicalString(),
                  previousStepId: Value(
                    step.previousStepId?.toCanonicalString(),
                  ),
                ),
            ]);
            choices.add(choice);
        }
      }
    });
    if (choices.isNotEmpty) await _verifyInsertedChoicePaths(choices);
  }

  /// Проверяет сохранённые пути вставленных выборов [choices] по их шагам
  /// и концам связей этих шагов: схема не выражает непрерывности пути.
  Future<void> _verifyInsertedChoicePaths(List<DailyChoice> choices) async {
    final paths = await readStoredChoicePaths(
      _database,
      choiceIds: List.filled(choices.length, '?').join(', '),
      variables: [
        for (final choice in choices)
          Variable.withString(choice.id.toCanonicalString()),
      ],
      readsFrom: const {},
    );
    try {
      for (final choice in choices) {
        verifyStoredChoicePath(
          choice: choice,
          steps: paths.steps[choice.id] ?? const [],
          relations: paths.relations,
        );
      }
    } on StoredGraphCorruption catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const GraphReplacementRecordsRejected(),
        stackTrace,
      );
    }
  }

  /// Количества записей графа каждого вида одним агрегатным чтением.
  Future<GraphRecordCounts> _selectRecordCounts() async {
    final row = await _database
        .customSelect(
          '''SELECT
            (SELECT count(*) FROM tags) AS tags,
            (SELECT count(*) FROM intentions) AS intentions,
            (SELECT count(*) FROM tag_assignments) AS tag_assignments,
            (SELECT count(*) FROM long_term_relations) AS long_term_relations,
            (SELECT count(*) FROM daily_choices) AS daily_choices''',
          readsFrom: {
            _database.tags,
            _database.intentions,
            _database.tagAssignments,
            _database.longTermRelations,
            _database.dailyChoices,
          },
        )
        .getSingle();
    return GraphRecordCounts(
      tags: row.read<int>('tags'),
      intentions: row.read<int>('intentions'),
      tagAssignments: row.read<int>('tag_assignments'),
      longTermRelations: row.read<int>('long_term_relations'),
      dailyChoices: row.read<int>('daily_choices'),
    );
  }
}

int _recordTotal(GraphRecordCounts counts) =>
    counts.tags +
    counts.intentions +
    counts.tagAssignments +
    counts.longTermRelations +
    counts.dailyChoices;

bool _sameRecordCounts(GraphRecordCounts a, GraphRecordCounts b) =>
    a.tags == b.tags &&
    a.intentions == b.intentions &&
    a.tagAssignments == b.tagAssignments &&
    a.longTermRelations == b.longTermRelations &&
    a.dailyChoices == b.dailyChoices;

/// Ход замены графа: доля обработанных записей от [_total], которая
/// сообщается, когда достигает следующей сотой доли.
final class _ReplacementProgress {
  _ReplacementProgress(this._total, this._onProgress);

  final int _total;
  final void Function(double share) _onProgress;
  var _processed = 0;
  var _reportedSteps = 0;

  /// Учитывает ещё [records] обработанных записей.
  void add(int records) {
    _processed += records;
    final steps = _processed * _replacementProgressSteps ~/ _total;
    if (steps > _reportedSteps) {
      _reportedSteps = steps;
      _onProgress(_processed / _total);
    }
  }
}

/// Число долей, которыми сообщается ход замены графа.
const _replacementProgressSteps = 100;
