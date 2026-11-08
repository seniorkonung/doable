part of 'drift_personal_graph_repository.dart';

/// Подсчёт удержания получает только типизированные массивы; очередь и SQLite
/// ему недоступны. Подмена позволяет управлять завершением изолята в
/// проверках. Возвращает признаки [computeIntentionHolding] либо передаёт
/// отказ подсчёта.
typedef IntentionHoldingRunner = Future<Uint8List> Function(
  IntentionHoldingGraph graph,
);

/// Отдельная функция исключает захват репозитория замыканием изолята:
/// https://api.dart.dev/dart-isolate/Isolate/run.html
Future<Uint8List> runIntentionHoldingInIsolate(IntentionHoldingGraph graph) =>
    Isolate.run(() => computeIntentionHolding(graph));

/// Индекс удержания ревизии графа (ADR-0056). Годен, пока не подтверждён
/// пакет с [IntentionHoldingChanged]: такие пакеты несут все операции,
/// меняющие связи, вид, архивное состояние или состав намерений, а новую
/// эпоху начинает замена графа.
final class _IntentionHoldingIndex {
  _IntentionHoldingIndex({
    required this.sequence,
    required this.graph,
    required this.indexes,
    required this.ids,
    required Uint8List held,
  }) : held = held.asUnmodifiableView();

  /// Номер изменения удержания, на котором построен индекс.
  final int sequence;

  /// Смежность и признаки намерений, по которым посчитан [held].
  final IntentionHoldingGraph graph;
  final Map<IntentionId, int> indexes;
  final List<IntentionId> ids;
  final Uint8List held;

  /// Намерения нет в индексе, только если оно создано после построения:
  /// созданное намерение главное и активное, а создание индекс не сбрасывает.
  IntentionHolding holdingOf(IntentionId id) => switch (indexes[id]) {
    null => IntentionHolding.held,
    final int index when held[index] == 1 => IntentionHolding.held,
    _ => IntentionHolding.notHeld,
  };
}

/// Порционное чтение строк графа удержания по возрастающему ключу.
typedef _HoldingRowsQuery = ({
  String query,
  TableInfo<Table, Object?> table,
  Variable firstKey,
  Variable Function(Map<String, Object?> data) nextKey,
  void Function(Map<String, Object?> data) add,
});

/// Индекс удержания устарел до окончания построения.
final class _IntentionHoldingIndexExpired implements Exception {
  const _IntentionHoldingIndexExpired();
}

extension _IntentionHoldingIndexReading on DriftPersonalGraphRepository {
  Future<IntentionHoldingResult> _readIntentionHolding(
    Set<IntentionId> ids,
  ) async {
    final _IntentionHoldingIndex index;
    try {
      index = await _loadIntentionHoldingIndex();
    } on _IntentionHoldingIndexExpired {
      return const IntentionHoldingExpired();
    } on Object {
      return const IntentionHoldingFailed();
    }
    // Сброс индекса и продвижение ревизии выполняются вместе синхронно после
    // подтверждения, поэтому годный индекс относится к текущей ревизии.
    if (index.sequence != _lastHoldingChangeSequence) {
      return const IntentionHoldingExpired();
    }
    return IntentionHoldingRead(
      revision: _currentRevision,
      holdings: {for (final id in ids) id: index.holdingOf(id)},
    );
  }

  /// Одновременные чтения одного номера изменения удержания ждут одно
  /// построение; отказавшее построение не запоминается.
  Future<_IntentionHoldingIndex> _loadIntentionHoldingIndex() {
    if (_intentionHoldingIndex case final index?) return Future.value(index);
    final sequence = _lastHoldingChangeSequence;
    if (_intentionHoldingBuild
        case (sequence: final buildSequence, :final index)
        when buildSequence == sequence) {
      return index;
    }
    final build = _buildIntentionHoldingIndex(sequence);
    _intentionHoldingBuild = (sequence: sequence, index: build);
    unawaited(
      build
          .then<void>((_) {}, onError: (Object _, StackTrace _) {})
          .whenComplete(() {
            if (identical(_intentionHoldingBuild?.index, build)) {
              _intentionHoldingBuild = null;
            }
          }),
    );
    return build;
  }

  /// Читает граф короткими транзакциями очереди и считает удержание вне её.
  /// Изменение удержания во время построения даёт
  /// [_IntentionHoldingIndexExpired] без внутреннего повтора.
  Future<_IntentionHoldingIndex> _buildIntentionHoldingIndex(
    int sequence,
  ) async {
    final builder = IntentionHoldingGraphBuilder();
    // Каждая порция занимает отдельную транзакцию очереди: команды ждут
    // только короткие чтения (ADR-0026). Граница транзакции находится внутри
    // отдельного входа в очередь:
    // https://drift.simonbinder.eu/dart_api/transactions/
    Future<List<QueryRow>> readPage(Future<List<QueryRow>> Function() read) =>
        _sequencer
            .run(() {
              _requireHoldingSequence(sequence);
              return _database.transaction(read);
            })
            .then((rows) {
              _requireHoldingSequence(sequence);
              return rows;
            });
    await _holdingIndexStage(
      IntentionHoldingIndexDiagnosticsStage.intentions,
      () => _readHoldingPages(_holdingIntentionRows(builder), readPage),
    );
    await _holdingIndexStage(
      IntentionHoldingIndexDiagnosticsStage.relations,
      () => _readHoldingPages(_holdingRelationRows(builder), readPage),
    );
    final (:graph, :indexes, :ids) = builder.build();
    final held = await _holdingIndexStage(
      IntentionHoldingIndexDiagnosticsStage.computation,
      () async {
        final held = await _intentionHoldingRunner(graph);
        _requireHoldingSequence(sequence);
        return held;
      },
    );
    final index = _IntentionHoldingIndex(
      sequence: sequence,
      graph: graph,
      indexes: indexes,
      ids: ids,
      held: held,
    );
    _intentionHoldingIndex = index;
    return index;
  }

  /// Индекс удержания текущей ревизии для транзакции команды: годный индекс
  /// берётся как есть, а устаревший или ещё не построенный строится в этой
  /// транзакции (ADR-0056). Подсчёт идёт в ней же без изолята: подменяемый
  /// подсчёт обслуживает построение вне очереди, а транзакция уже держит
  /// очередь записи.
  Future<_IntentionHoldingIndex> _holdingIndexInTransaction() async {
    if (_intentionHoldingIndex case final index?
        when index.sequence == _lastHoldingChangeSequence) {
      return index;
    }
    final builder = IntentionHoldingGraphBuilder();
    Future<List<QueryRow>> readPage(Future<List<QueryRow>> Function() read) =>
        read();
    await _readHoldingPages(_holdingIntentionRows(builder), readPage);
    await _readHoldingPages(_holdingRelationRows(builder), readPage);
    final (:graph, :indexes, :ids) = builder.build();
    return _IntentionHoldingIndex(
      sequence: _lastHoldingChangeSequence,
      graph: graph,
      indexes: indexes,
      ids: ids,
      held: computeIntentionHolding(graph),
    );
  }

  _HoldingRowsQuery _holdingIntentionRows(
    IntentionHoldingGraphBuilder builder,
  ) => (
    query: '''SELECT id AS page_key, id, kind, is_archived FROM intentions
           WHERE id > ? ORDER BY id LIMIT ?''',
    table: _database.intentions,
    firstKey: const Variable<String>(''),
    nextKey: (data) => Variable<String>(requiredStoredString(data, 'page_key')),
    add: (data) => builder.addIntention(
      decodeStoredIntentionId(requiredStoredString(data, 'id')),
      decodeStoredIntentionKind(data, 'kind'),
      decodeStoredIntentionArchiveState(data, 'is_archived'),
    ),
  );

  _HoldingRowsQuery _holdingRelationRows(
    IntentionHoldingGraphBuilder builder,
  ) => (
    query: '''SELECT creation_sequence AS page_key, source_intention_id,
                  related_intention_id, type, priority, is_archived
           FROM long_term_relations
           WHERE creation_sequence > ? ORDER BY creation_sequence LIMIT ?''',
    table: _database.longTermRelations,
    firstKey: const Variable<int>(0),
    nextKey: (data) => Variable<int>(requiredStoredInteger(data, 'page_key')),
    add: (data) => builder.addRelation(
      decodeStoredIntentionId(
        requiredStoredString(data, 'source_intention_id'),
      ),
      decodeStoredIntentionId(
        requiredStoredString(data, 'related_intention_id'),
      ),
      decodeStoredRelationScope(data),
      type: decodeStoredRelationType(data),
      priority: decodeStoredRelationPriority(data),
      creationSequence: requiredStoredInteger(data, 'page_key'),
    ),
  );

  /// Читает строки [rows] порциями по ключу; [readPage] выполняет чтение
  /// одной порции.
  Future<void> _readHoldingPages(
    _HoldingRowsQuery rows,
    Future<List<QueryRow>> Function(Future<List<QueryRow>> Function() read)
    readPage,
  ) async {
    const pageSize = 1024;
    var after = rows.firstKey;
    while (true) {
      final page = await readPage(
        () => _database
            .customSelect(
              rows.query,
              variables: [after, const Variable<int>(pageSize)],
              readsFrom: {rows.table},
            )
            .get(),
      );
      for (final row in page) {
        rows.add(row.data);
      }
      if (page.length < pageSize) return;
      after = rows.nextKey(page.last.data);
    }
  }

  void _requireHoldingSequence(int sequence) {
    if (sequence != _lastHoldingChangeSequence) {
      throw const _IntentionHoldingIndexExpired();
    }
  }

  void _invalidateIntentionHoldingIndex(Iterable<GraphChange> changes) {
    if (changes.any((change) => change is IntentionHoldingChanged)) {
      _resetIntentionHoldingIndex();
    }
  }

  void _resetIntentionHoldingIndex() {
    _lastHoldingChangeSequence = _mutationSequence;
    _intentionHoldingIndex = null;
  }

  Future<T> _holdingIndexStage<T>(
    IntentionHoldingIndexDiagnosticsStage stage,
    Future<T> Function() run,
  ) async {
    final stopwatch = Stopwatch()..start();
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      IntentionHoldingIndexDiagnosticsEvent(stage: stage, status: status),
    );
    record(const DiagnosticsStarted());
    try {
      final result = await run();
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return result;
    } on Object catch (error) {
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _intentionHoldingFailureCode(error),
        ),
      );
      rethrow;
    }
  }
}

DiagnosticsFailureCode _intentionHoldingFailureCode(Object error) {
  if (error is _IntentionHoldingIndexExpired) {
    return DiagnosticsFailureCode.conflict;
  }
  if (error is StoredGraphCorruption ||
      error is IntentionHoldingGraphIncomplete) {
    return DiagnosticsFailureCode.corruption;
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => DiagnosticsFailureCode.corruption,
    SqliteUnavailableFailure() => DiagnosticsFailureCode.unavailable,
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
  };
}
