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
      await _verifyInsertedActionPaths();
      await _verifyIntentionKinds();
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
  /// статистики и индекс удержания сбрасываются, а наблюдатели сущностей
  /// перечитывают их: ревизии прежней эпохи с новой несравнимы. Наблюдатели
  /// тегов узнают о замене от обновлений таблиц Drift, наблюдатели состава и
  /// лога — по позиции пакета «сброс» [resetPosition], а наблюдатели списка
  /// копий — если замена добавила копию перед заменой.
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
    _resetIntentionHoldingIndex();
    for (final watchers in List.of(_intentionWatchers.values)) {
      for (final watcher in List.of(watchers)) {
        watcher.add(null);
      }
    }
    for (final registration in List.of(_actionWatchers)) {
      registration.invalidations.add(null);
    }
    for (final registrations in List.of(_relationWatchers.values)) {
      for (final registration in List.of(registrations)) {
        registration.invalidations.add(null);
      }
    }
    _confirmedPositions.add(resetPosition);
    if (addedBackup) _backupsChanged.add(null);
    return ConfirmedGraphReplacement(_currentRevision);
  }

  Future<void> _setGraphCapture(bool capture) => _database
      .update(_database.graphLogControl)
      .write(local.GraphLogControlCompanion(capture: Value(capture)));

  /// Удаляет прежний граф операторами не больше чем по
  /// [_replacementBatchRowLimit] строк в порядке, обратном ссылкам:
  /// надгробия, действия вместе со строками путей, затем связи, назначения
  /// тегов, теги и намерения. Назначения удаляются отдельно, а не каскадом
  /// тегов, а надгробия — отдельно, а не триггером освобождения после
  /// удаления строк пути, поэтому [progress] получает число удалённых
  /// записей каждого вида. Когда удаляются связи и намерения, строк путей
  /// уже нет, поэтому триггеры не создают новых надгробий.
  Future<void> _deletePreviousGraph(
    _ReplacementProgress progress,
    GraphReplacementCancellation cancellation,
  ) async {
    final tables =
        <(TableInfo<Table, Object?>, Set<TableInfo<Table, Object?>>)>[
          (_database.deletedRelationPairs, {_database.deletedRelationPairs}),
          (_database.deletedIntentions, {_database.deletedIntentions}),
          (_database.actions, {_database.actions, _database.actionPathItems}),
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
  /// чем по [_replacementBatchRowLimit] строк: действие занимает строку и по
  /// строке на каждое намерение пути. Пакет из одной записи может быть
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
        ActionRecord(:final path) => 1 + path.intentions.length,
        _ => 1,
      };
      if (batchRows + rows > _replacementBatchRowLimit) await flush();
      batch.add(record);
      batchRows += rows;
    }
    await flush();
  }

  /// Вставляет [records] одним пакетом операторов. Ссылки, уникальность и
  /// активность участников активной связи проверяет схема.
  Future<void> _insertRecordBatch(List<GraphEntityRecord> records) async {
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
                kind: Value(intention.kind.name),
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
                createdAt: record.createdAt.value.microsecondsSinceEpoch,
                updatedAt: record.updatedAt.value.microsecondsSinceEpoch,
              ),
            );
          case DeletedIntentionRecord(:final id, :final title):
            batch.insert(
              _database.deletedIntentions,
              local.DeletedIntentionsCompanion.insert(
                intentionId: id.toCanonicalString(),
                title: title,
              ),
            );
          case DeletedRelationPairRecord():
            batch.insert(
              _database.deletedRelationPairs,
              local.DeletedRelationPairsCompanion.insert(
                sourceIntentionId: record.sourceIntentionId.toCanonicalString(),
                relatedIntentionId: record.relatedIntentionId
                    .toCanonicalString(),
                type: _storedRelationType(record.type),
              ),
            );
          case ActionRecord():
            final actionId = record.id.toCanonicalString();
            batch.insert(
              _database.actions,
              local.ActionsCompanion.insert(
                id: actionId,
                title: record.title.value,
                description: Value(record.description?.value),
                date: record.date.toCanonicalString(),
                scheduledHour: Value(switch (record.schedule) {
                  ActionAllDay() => null,
                  ActionAtHour(:final hour) => hour,
                }),
                priority: record.priority.level,
                isCompleted: record.isCompleted,
                createdAt: record.createdAt.value.microsecondsSinceEpoch,
                updatedAt: record.updatedAt.value.microsecondsSinceEpoch,
              ),
            );
            // Строки пути вставляются по порядку позиций: так их проверяет
            // триггер продолжения предыдущей позиции. Копию ключа порядка
            // вставка берёт из только что вставленного действия.
            final intentions = record.path.intentions;
            for (final (position, intention) in intentions.indexed) {
              batch.customStatement(
                '''INSERT INTO action_path_items
                   (action_id, position, intention_id, previous_intention_id,
                    role, order_date, order_hour, order_sequence)
                   SELECT ?1, ?2, ?3, ?4, ?5,
                          date, COALESCE(scheduled_hour, -1), creation_sequence
                   FROM actions WHERE id = ?1''',
                [
                  actionId,
                  position,
                  intention.toCanonicalString(),
                  position == 0
                      ? null
                      : intentions[position - 1].toCanonicalString(),
                  _StoredActionPathRole.at(position, intentions.length).name,
                ],
              );
            }
        }
      }
    });
  }

  /// Проверяет правила целостности сохранённых путей действий, которых не
  /// выражают триггеры вставки: у каждого звена пути есть связь его пары
  /// или надгробие пары, а каждое надгробие нужно хоть одному пути. Чтение
  /// одно на весь вставленный граф: прежний граф к этому моменту удалён.
  Future<void> _verifyInsertedActionPaths() async {
    final row = await _database
        .customSelect(
          '''SELECT
            EXISTS (
              SELECT 1 FROM action_path_items AS item
              WHERE
                item.previous_intention_id IS NOT NULL AND
                NOT EXISTS (
                  SELECT 1 FROM long_term_relations AS relation
                  WHERE
                    relation.source_intention_id =
                      item.previous_intention_id AND
                    relation.related_intention_id = item.intention_id
                ) AND
                NOT EXISTS (
                  SELECT 1 FROM deleted_relation_pairs AS pair
                  WHERE
                    pair.source_intention_id = item.previous_intention_id AND
                    pair.related_intention_id = item.intention_id
                )
            ) OR
            EXISTS (
              SELECT 1 FROM deleted_intentions AS tombstone
              WHERE NOT EXISTS (
                SELECT 1 FROM action_path_items AS item
                WHERE item.intention_id = tombstone.intention_id
              )
            ) OR
            EXISTS (
              SELECT 1 FROM deleted_relation_pairs AS pair
              WHERE NOT EXISTS (
                SELECT 1 FROM action_path_items AS item
                WHERE
                  item.previous_intention_id = pair.source_intention_id AND
                  item.intention_id = pair.related_intention_id
              )
            ) AS is_violated''',
          readsFrom: {
            _database.actionPathItems,
            _database.longTermRelations,
            _database.deletedIntentions,
            _database.deletedRelationPairs,
          },
        )
        .getSingle();
    if (row.read<bool>('is_violated')) {
      throw const GraphReplacementRecordsRejected();
    }
  }

  Future<void> _verifyIntentionKinds() async {
    final row = await _database
        .customSelect(
          '''SELECT EXISTS (
        SELECT 1 FROM intentions AS intention
        WHERE intention.kind = 'supporting' AND NOT EXISTS (
          SELECT 1 FROM long_term_relations AS relation
          WHERE relation.related_intention_id = intention.id
            AND (intention.is_archived = 1 OR relation.is_archived = 0)
        )
      ) AS is_violated''',
          readsFrom: {_database.intentions, _database.longTermRelations},
        )
        .getSingle();
    if (row.read<bool>('is_violated')) {
      throw const GraphReplacementRecordsRejected();
    }
  }

  /// Количества записей графа каждого вида одним агрегатным чтением.
  Future<GraphRecordCounts> _selectRecordCounts() async {
    final row = await _database
        .customSelect(
          '''SELECT
            (SELECT count(*) FROM tags) AS tags,
            (SELECT count(*) FROM intentions) AS intentions,
            (SELECT count(*) FROM deleted_intentions) AS deleted_intentions,
            (SELECT count(*) FROM tag_assignments) AS tag_assignments,
            (SELECT count(*) FROM long_term_relations) AS long_term_relations,
            (SELECT count(*) FROM deleted_relation_pairs)
              AS deleted_relation_pairs,
            (SELECT count(*) FROM actions) AS actions''',
          readsFrom: {
            _database.tags,
            _database.intentions,
            _database.deletedIntentions,
            _database.tagAssignments,
            _database.longTermRelations,
            _database.deletedRelationPairs,
            _database.actions,
          },
        )
        .getSingle();
    return GraphRecordCounts(
      tags: row.read<int>('tags'),
      intentions: row.read<int>('intentions'),
      deletedIntentions: row.read<int>('deleted_intentions'),
      tagAssignments: row.read<int>('tag_assignments'),
      longTermRelations: row.read<int>('long_term_relations'),
      deletedRelationPairs: row.read<int>('deleted_relation_pairs'),
      actions: row.read<int>('actions'),
    );
  }
}

int _recordTotal(GraphRecordCounts counts) =>
    counts.tags +
    counts.intentions +
    counts.deletedIntentions +
    counts.tagAssignments +
    counts.longTermRelations +
    counts.deletedRelationPairs +
    counts.actions;

bool _sameRecordCounts(GraphRecordCounts a, GraphRecordCounts b) =>
    a.tags == b.tags &&
    a.intentions == b.intentions &&
    a.deletedIntentions == b.deletedIntentions &&
    a.tagAssignments == b.tagAssignments &&
    a.longTermRelations == b.longTermRelations &&
    a.deletedRelationPairs == b.deletedRelationPairs &&
    a.actions == b.actions;

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
