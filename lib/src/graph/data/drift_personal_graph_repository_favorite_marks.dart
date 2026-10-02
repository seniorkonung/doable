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
