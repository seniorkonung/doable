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
  Future<FavoriteIntentionsResult> _readFavoriteIntentions() async {
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
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
          final counts = await _readVerifiedRelationCountsFor(
            active.map((intention) => intention.id),
          );
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
      return FavoriteIntentionsSuccess(snapshot);
    } on Object catch (error) {
      return FavoriteIntentionsError(
        _classifyFavoriteIntentionsReadFailure(error),
      );
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
