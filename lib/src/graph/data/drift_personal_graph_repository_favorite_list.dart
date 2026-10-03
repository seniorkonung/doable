part of 'drift_personal_graph_repository.dart';

extension _FavoriteListReading on DriftPersonalGraphRepository {
  /// Получает полный список избранных намерений одной транзакцией: строки
  /// избранного в порядке мест одним чтением и счётчики активных связей
  /// существующим пакетным агрегатом на той же ревизии.
  ///
  /// Архивированные избранные намерения в список не входят и учитываются
  /// числом. Место без существующего намерения, неоднозначный порядок и
  /// недопустимые сохранённые значения дают повреждение без частичного
  /// списка, пропуска или исправления.
  ///
  /// Диагностика различает чтение строк и проверку сохранённых данных
  /// избранного и не несёт данных личного графа.
  Future<FavoriteIntentionsResult> _readFavoriteIntentions() async {
    final stopwatch = Stopwatch()..start();
    var stage = FavoriteIntentionsReadDiagnosticsStage.read;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      FavoriteIntentionsReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          stage = FavoriteIntentionsReadDiagnosticsStage.read;
          final rows = await _database
              .customSelect(
                '''SELECT f.intention_id, f.position, i.id, i.title,
                 i.description, i.is_action_ready, i.is_archived,
                 i.created_at, i.updated_at
               FROM favorite_intentions f
               LEFT JOIN intentions i ON i.id = f.intention_id
               ORDER BY f.position ASC''',
                readsFrom: {_database.favoriteIntentions, _database.intentions},
              )
              .get();
          stage = FavoriteIntentionsReadDiagnosticsStage.validation;
          var previousPosition = 0;
          var archivedCount = 0;
          final seen = <IntentionId>{};
          final active = <domain.Intention>[];
          for (final row in rows) {
            final position = _requiredStoredInteger(row.data, 'position');
            if (position <= previousPosition) {
              throw const _StoredIntentionCorruption();
            }
            previousPosition = position;
            final intention = _rehydrateDetailRow(row);
            if (_requiredStoredString(row.data, 'intention_id') !=
                    intention.id.toCanonicalString() ||
                !seen.add(intention.id)) {
              throw const _StoredIntentionCorruption();
            }
            switch (intention.archiveState) {
              case domain.IntentionArchiveState.active:
                active.add(intention);
              case domain.IntentionArchiveState.archived:
                archivedCount++;
            }
          }
          stage = FavoriteIntentionsReadDiagnosticsStage.read;
          final Map<IntentionId, RelationCounts> counts;
          try {
            counts = await _readVerifiedRelationCountsFor(
              active.map((intention) => intention.id),
            );
          } on _StoredIntentionCorruption {
            // Нарушение целостности счётчиков выявляет проверка агрегата, а
            // не отказ его чтения.
            stage = FavoriteIntentionsReadDiagnosticsStage.validation;
            rethrow;
          }
          stage = FavoriteIntentionsReadDiagnosticsStage.validation;
          return FavoriteIntentionsSnapshot(
            items: [
              for (final intention in active)
                FavoriteIntentionRow(
                  id: intention.id,
                  title: intention.title,
                  readiness: intention.readiness,
                  activeRelationCount:
                      (counts[intention.id] ??
                              (throw const _StoredIntentionCorruption()))
                          .active,
                ),
            ],
            archivedCount: archivedCount,
            revision: _currentRevision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return FavoriteIntentionsSuccess(snapshot);
    } on Object catch (error) {
      final failure = _classifyFavoriteIntentionsReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return FavoriteIntentionsError(failure);
    }
  }
}

FavoriteIntentionsReadFailure _classifyFavoriteIntentionsReadFailure(
  Object error,
) {
  if (error is _StoredIntentionCorruption) {
    return const FavoriteIntentionsCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const FavoriteIntentionsCorruptionFailure(),
    SqliteUnavailableFailure() => const FavoriteIntentionsUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const FavoriteIntentionsUnexpectedFailure(),
  };
}
