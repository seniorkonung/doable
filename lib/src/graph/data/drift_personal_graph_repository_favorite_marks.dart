part of 'drift_personal_graph_repository.dart';

extension _FavoriteMarkReading on DriftPersonalGraphRepository {
  /// Получает подтверждённую отметку избранного одного намерения.
  /// Вызывается внутри транзакции и последовательного исполнения чтения или команды.
  Future<domain.FavoriteMark> _readFavoriteMark(
    IntentionId intentionId,
  ) async =>
      (await _readFavoriteMarks([intentionId]))[intentionId] ??
      (throw const _StoredIntentionCorruption());

  /// Получает подтверждённые отметки избранного запрошенных намерений одним
  /// чтением. Вызывается внутри транзакции и последовательного исполнения
  /// чтения или команды.
  ///
  /// Результат содержит каждое запрошенное намерение: отсутствие строки —
  /// проверенное отсутствие отметки. Проверяются только прочитанные строки,
  /// то есть отметки запрошенных намерений: недопустимое место даёт
  /// повреждение, а не отсутствие отметки. Строки остальных избранных
  /// намерений чтение не получает, поэтому его стоимость ограничена числом
  /// запрошенных идентификаторов.
  Future<Map<IntentionId, domain.FavoriteMark>> _readFavoriteMarks(
    List<IntentionId> intentionIds,
  ) async {
    if (intentionIds.isEmpty) return const {};
    final requested = {
      for (final id in intentionIds) id.toCanonicalString(): id,
    };
    final rows = await _database
        .customSelect(
          '''SELECT intention_id, position
       FROM favorite_intentions
       WHERE intention_id IN (${List.filled(requested.length, '?').join(', ')})''',
          variables: [for (final id in requested.keys) Variable<String>(id)],
          readsFrom: {_database.favoriteIntentions},
        )
        .get();
    final marks = {
      for (final id in intentionIds) id: domain.FavoriteMark.notFavorite,
    };
    for (final row in rows) {
      final id = requested[_requiredStoredString(row.data, 'intention_id')];
      if (id == null || marks[id] == domain.FavoriteMark.favorite) {
        throw const _StoredIntentionCorruption();
      }
      if (_requiredStoredInteger(row.data, 'position') <= 0) {
        throw const _StoredIntentionCorruption();
      }
      marks[id] = domain.FavoriteMark.favorite;
    }
    return marks;
  }
}

extension _FavoriteMarkCommands on DriftPersonalGraphRepository {
  /// Отмечает существующее намерение избранным на месте после текущего
  /// максимума всего порядка, включая места архивированных намерений.
  /// Вызывается внутри транзакции команды.
  Future<_CommittedIntentionCommand> _markFavorite(
    IntentionId id, {
    required void Function() onWrite,
  }) => _changeFavoriteMark(
    id,
    domain.FavoriteMark.favorite,
    onWrite: onWrite,
    write: () => _database.customInsert(
      '''INSERT INTO favorite_intentions (intention_id, position)
       SELECT ?, COALESCE(MAX(position), 0) + 1 FROM favorite_intentions''',
      variables: [Variable<String>(id.toCanonicalString())],
      updates: {_database.favoriteIntentions},
    ),
  );

  /// Снимает отметку избранного существующего намерения удалением её строки;
  /// места остальных избранных намерений не меняются. Вызывается внутри
  /// транзакции команды.
  Future<_CommittedIntentionCommand> _unmarkFavorite(
    IntentionId id, {
    required void Function() onWrite,
  }) => _changeFavoriteMark(
    id,
    domain.FavoriteMark.notFavorite,
    onWrite: onWrite,
    write: () => _database.customUpdate(
      'DELETE FROM favorite_intentions WHERE intention_id = ?',
      variables: [Variable<String>(id.toCanonicalString())],
      updates: {_database.favoriteIntentions},
      updateKind: UpdateKind.delete,
    ),
  );

  /// Проверяет существование намерения и текущую отметку и выполняет [write]
  /// только при фактическом изменении. Строки намерений команда не пишет,
  /// поэтому снимки до и после различаются только отметкой.
  ///
  /// [onWrite] сообщает диагностике переход от этапа проверки к этапу записи:
  /// отказ до него относится к проверке, после него — к записи.
  Future<_CommittedIntentionCommand> _changeFavoriteMark(
    IntentionId id,
    domain.FavoriteMark favoriteMark, {
    required void Function() onWrite,
    required Future<void> Function() write,
  }) async {
    final stored = await _readCommandSnapshot(id);
    if (stored == null) throw const _IntentionNotFound();

    final existing = _rehydrateStored(stored.detail);
    final counts = await _readVerifiedRelationCounts(id);
    final before = await _catalogEntrySnapshot(stored, counts);
    if (before.summary.favoriteMark == favoriteMark) {
      return _CommittedIntentionUnchanged(intention: existing, entry: before);
    }

    onWrite();
    await write();
    return _CommittedIntentionUpdated(
      intention: existing,
      before: before,
      after: await _catalogEntrySnapshot(stored, counts),
    );
  }
}
