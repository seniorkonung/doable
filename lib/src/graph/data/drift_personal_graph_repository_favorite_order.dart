part of 'drift_personal_graph_repository.dart';

extension _FavoriteOrderCommandExecution on DriftPersonalGraphRepository {
  /// Перемещает избранное намерение одной транзакцией общего
  /// последовательного исполнителя личного графа.
  ///
  /// Транзакция читает полный порядок, включая архивированные избранные
  /// намерения, проверяет сохранённые места и вычисляет новый порядок
  /// единственным правилом [moveInFavoriteOrder]. Утрата отметки или
  /// физическое удаление участника отклоняются правилом до записи, а
  /// архивирование участника допустимо. Изменение порядка и новая ревизия
  /// появляются только после commit; перемещение без видимого изменения не
  /// пишет и ревизию не продвигает.
  ///
  /// Диагностика отражает этап, на котором перестановка завершилась, и не
  /// несёт данных личного графа. Отказ её получателя поглощается и не влияет
  /// на исход.
  Future<FavoriteOrderCommandResult> _executeFavoriteOrder(
    MoveFavoriteIntention command,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = FavoriteOrderCommandDiagnosticsStage.read;

    _recordDiagnostics(const FavoriteOrderCommandDiagnosticsEvent.started());
    try {
      final confirmed = await _sequencer.run(() async {
        final committed = await _database.transaction(() async {
          stage = FavoriteOrderCommandDiagnosticsStage.read;
          final rows = await _readStoredFavoriteOrder();
          stage = FavoriteOrderCommandDiagnosticsStage.validation;
          final stored = _verifiedFavoriteOrder(rows);
          switch (moveInFavoriteOrder(
            stored.order,
            intentionId: command.intentionId,
            placement: command.placement,
          )) {
            case final FavoriteOrderMoveRejected rejection:
              throw _FavoriteOrderMoveRejection(rejection);
            case FavoriteOrderMoveWithoutChange():
              return _CommittedFavoriteOrder.unchanged;
            case FavoriteOrderMoveApplied(:final order):
              stage = FavoriteOrderCommandDiagnosticsStage.write;
              await _rewriteFavoritePlaces(
                order,
                maxPosition: stored.maxPosition,
              );
              return _CommittedFavoriteOrder.moved;
          }
        });

        if (committed == _CommittedFavoriteOrder.moved) _mutationSequence++;
        final revision = _currentRevision;
        final FavoriteOrderCommandSuccess outcome = switch (committed) {
          _CommittedFavoriteOrder.moved => FavoriteOrderMoved(
            FavoriteOrderChangedChange(revision: revision),
          ),
          _CommittedFavoriteOrder.unchanged => FavoriteOrderUnchanged(
            FavoriteOrderUnchangedChange(revision: revision),
          ),
        };
        final result = ConfirmedGraphResult(revision: revision, value: outcome);
        if (committed == _CommittedFavoriteOrder.moved) {
          _notifyGraphWatchersFor(result.changes);
        }
        return result;
      });
      _recordDiagnostics(switch (confirmed.value) {
        FavoriteOrderMoved() => FavoriteOrderCommandDiagnosticsEvent.moved(
          duration: stopwatch.elapsed,
        ),
        FavoriteOrderUnchanged() =>
          FavoriteOrderCommandDiagnosticsEvent.unchanged(
            duration: stopwatch.elapsed,
          ),
      });
      return FavoriteOrderCommandSucceeded(confirmed);
    } on Object catch (error) {
      final failure = _classifyFavoriteOrderCommandFailure(error);
      _recordDiagnostics(
        FavoriteOrderCommandDiagnosticsEvent.failed(
          stage: stage,
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return FavoriteOrderCommandFailed(failure);
    }
  }

  /// Читает места всех избранных намерений, включая архивированные, вместе с
  /// существованием и архивным состоянием их намерений. Вызывается внутри
  /// транзакции команды.
  Future<List<QueryRow>> _readStoredFavoriteOrder() => _database
      .customSelect(
        '''SELECT f.intention_id, f.position, i.id, i.is_archived
       FROM favorite_intentions f
       LEFT JOIN intentions i ON i.id = f.intention_id
       ORDER BY f.position ASC''',
        readsFrom: {_database.favoriteIntentions, _database.intentions},
      )
      .get();

  /// Проверяет все сохранённые места до вычисления и записи. Место без
  /// существующего намерения, неоднозначный порядок, недопустимое место,
  /// недопустимый идентификатор и недопустимое архивное состояние дают
  /// повреждение без пропуска или исправления данных.
  ({FavoriteOrder order, int maxPosition}) _verifiedFavoriteOrder(
    List<QueryRow> rows,
  ) {
    var previousPosition = 0;
    final entries = <FavoriteOrderEntry>[];
    for (final row in rows) {
      final position = _requiredStoredInteger(row.data, 'position');
      if (position <= previousPosition) {
        throw const _StoredIntentionCorruption();
      }
      previousPosition = position;
      final storedId = _requiredStoredString(row.data, 'intention_id');
      // Канонический вид идентификатора гарантирует декодирование, поэтому
      // итоговые места назначаются по тем же строкам, что хранятся.
      final intentionId = _decodeStoredIntentionId(storedId);
      if (row.data['id'] != storedId) throw const _StoredIntentionCorruption();
      entries.add(
        FavoriteOrderEntry(
          intentionId: intentionId,
          archiveState: switch (_requiredStoredInteger(
            row.data,
            'is_archived',
          )) {
            0 => domain.IntentionArchiveState.active,
            1 => domain.IntentionArchiveState.archived,
            _ => throw const _StoredIntentionCorruption(),
          },
        ),
      );
    }
    try {
      return (order: FavoriteOrder(entries), maxPosition: previousPosition);
    } on FavoriteOrderValidationException {
      throw const _StoredIntentionCorruption();
    }
  }

  /// Переписывает места всех избранных намерений значениями `1..n` в порядке
  /// [order] двумя инструкциями, число которых не зависит от n.
  ///
  /// SQLite проверяет уникальность места построчно, поэтому сначала все места
  /// сдвигаются за прежний максимум [maxPosition]: промежуточные места
  /// положительны и не совпадают ни с прежними, ни с итоговыми. Затем каждое
  /// намерение получает итоговое место по своей позиции в переданном списке
  /// идентификаторов. Непредставимое промежуточное место отклоняется
  /// проверкой схемы, и транзакция откатывается целиком.
  Future<void> _rewriteFavoritePlaces(
    FavoriteOrder order, {
    required int maxPosition,
  }) async {
    final shifted = await _database.customUpdate(
      'UPDATE favorite_intentions SET position = position + ?',
      variables: [Variable<int>(maxPosition)],
      updates: {_database.favoriteIntentions},
    );
    final assigned = await _database.customUpdate(
      '''UPDATE favorite_intentions
       SET position = new_order.place
       FROM (
         SELECT value AS intention_id, key + 1 AS place FROM json_each(?)
       ) AS new_order
       WHERE favorite_intentions.intention_id = new_order.intention_id''',
      variables: [
        Variable<String>(
          jsonEncode([
            for (final id in order.intentionIds) id.toCanonicalString(),
          ]),
        ),
      ],
      updates: {_database.favoriteIntentions},
    );
    // Каждое прочитанное место должно получить итоговое значение: иначе
    // транзакция откатывается, а не оставляет частично переписанный порядок.
    final count = order.intentionIds.length;
    if (shifted != count || assigned != count) {
      throw const _FavoriteOrderRewriteMismatch();
    }
  }
}

enum _CommittedFavoriteOrder { moved, unchanged }

final class _FavoriteOrderMoveRejection implements Exception {
  const _FavoriteOrderMoveRejection(this.rejection);

  final FavoriteOrderMoveRejected rejection;
}

/// Запись затронула не все прочитанные места порядка.
final class _FavoriteOrderRewriteMismatch implements Exception {
  const _FavoriteOrderRewriteMismatch();
}

FavoriteOrderCommandFailure _classifyFavoriteOrderCommandFailure(Object error) {
  if (error is _FavoriteOrderMoveRejection) {
    return FavoriteOrderCommandFailure.rejected(error.rejection);
  }
  if (error is _StoredIntentionCorruption) {
    return const FavoriteOrderCorruptionFailure();
  }
  if (error is _FavoriteOrderRewriteMismatch) {
    return const FavoriteOrderUnexpectedFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const FavoriteOrderCorruptionFailure(),
    SqliteUnavailableFailure() => const FavoriteOrderUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const FavoriteOrderUnexpectedFailure(),
  };
}
