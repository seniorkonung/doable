import '../../graph/application/graph_command_result.dart';
import '../../graph/application/graph_revision.dart';
import '../application/relation_counts.dart';
import '../application/relation_group_page.dart';

/// Общая механика порций, не зависящая от группы и состояния представления.
final class RelationGroupPaging {
  static const _maxRefreshAttempts = 8;

  var _generation = 0;
  var _invalidation = 0;
  RelationPagingRequest? _activeRequest;
  GraphRevision? _requiredRevision;

  int get generation => _generation;
  bool get hasActiveRequest => _activeRequest != null;
  GraphRevision? get requiredRevision => _requiredRevision;

  /// Новый выбор или завершение потребителя делает прежние ответы непригодными.
  int nextGeneration() {
    _generation += 1;
    cancelRequest();
    return _generation;
  }

  RelationPagingRequest startRequest(int generation) {
    final request = RelationPagingRequest._(generation, _invalidation);
    _activeRequest = request;
    return request;
  }

  bool owns(RelationPagingRequest request) =>
      request._generation == _generation && identical(_activeRequest, request);

  void finishRequest(RelationPagingRequest request) {
    if (identical(_activeRequest, request)) cancelRequest();
  }

  /// Позволяет начать пересборку, не дожидаясь прежнего продолжения.
  void cancelRequest() => _activeRequest = null;

  /// Потребитель отбирает значимые изменения, ядро прерывает их старую сборку.
  void requireRevision(GraphRevision revision) {
    _requiredRevision = revision;
    _invalidation += 1;
  }

  bool precedesRequiredRevision(GraphRevision revision) {
    final required = _requiredRevision;
    return required != null && precedes(revision, required);
  }

  bool precedes(GraphRevision revision, GraphRevision known) =>
      switch (revision.compareTo(known)) {
        GraphRevisionOrder.older || GraphRevisionOrder.differentEpoch => true,
        GraphRevisionOrder.same || GraphRevisionOrder.newer => false,
      };

  /// `null` означает ответ прежнего запроса, который нельзя публиковать.
  Future<RelationPagingResult<Row>?> readFirst<Row, Id extends Object>(
    RelationPagingSource<Row, Id> source,
    RelationPagingRequest request,
  ) async {
    while (owns(request)) {
      final result = await source.readPage(null);
      if (!owns(request)) return null;
      switch (result) {
        case GraphResultSuccess(value: final RelationPagingFirstPage<Row> page):
          if (precedesRequiredRevision(page.revision)) continue;
          return _acceptFirst(source, page);
        case GraphResultSuccess() ||
            GraphResultFailure(failure: RelationGroupSnapshotExpired()):
          return const GraphResultFailure(RelationGroupUnexpectedFailure());
        case GraphResultFailure(:final failure):
          return GraphResultFailure(failure);
      }
    }
    return null;
  }

  /// Несовместимое продолжение возвращает `null`: нужна новая основа.
  /// Владелец отдельно проверяет, принадлежит ли ему ещё сам запрос.
  Future<RelationPagingResult<Row>?> loadMore<Row, Id extends Object>(
    RelationPagingSource<Row, Id> source,
    RelationPagingData<Row> confirmed,
    RelationPagingRequest request,
  ) async {
    final result = await source.readPage(confirmed.nextCursor);
    if (!owns(request) || request._invalidation != _invalidation) return null;
    switch (result) {
      case GraphResultSuccess(
        value: final RelationPagingContinuationPage<Row> page,
      ):
        return _acceptContinuation(source, confirmed, page);
      case GraphResultSuccess():
        return const GraphResultFailure(RelationGroupUnexpectedFailure());
      case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        return null;
      case GraphResultFailure(:final failure):
        return GraphResultFailure(failure);
    }
  }

  /// Собирает загруженную часть и запрошенную порцию на одной ревизии.
  /// Прерывание ревизией повторяет сборку с начала, но число попыток ограничено.
  Future<RelationPagingResult<Row>?> refresh<Row, Id extends Object>(
    RelationPagingSource<Row, Id> source,
    RelationPagingRequest request, {
    required int loadedCount,
    required bool includeRequestedPage,
  }) async {
    final limit = loadedCount + (includeRequestedPage ? source.pageSize : 0);
    while (request._refreshAttempts < _maxRefreshAttempts) {
      request._refreshAttempts += 1;
      final invalidation = _invalidation;
      final result = await _assemble(source, request, invalidation, limit);
      if (!owns(request)) return null;
      if (result is GraphResultSuccess && invalidation != _invalidation) {
        continue;
      }
      if (result != null) return result;
    }
    return const GraphResultFailure(RelationGroupUnavailableFailure());
  }

  /// `null` прерывает только попытку; отказ останавливает всю пересборку.
  Future<RelationPagingResult<Row>?> _assemble<Row, Id extends Object>(
    RelationPagingSource<Row, Id> source,
    RelationPagingRequest request,
    int invalidation,
    int limit,
  ) async {
    bool isCurrent() => owns(request) && invalidation == _invalidation;

    final firstResult = await source.readPage(null);
    if (!isCurrent()) return null;
    final RelationPagingFirstPage<Row> firstPage;
    switch (firstResult) {
      case GraphResultSuccess(value: final RelationPagingFirstPage<Row> page):
        firstPage = page;
      case GraphResultSuccess() ||
          GraphResultFailure(failure: RelationGroupSnapshotExpired()):
        return const GraphResultFailure(RelationGroupUnexpectedFailure());
      case GraphResultFailure(:final failure):
        return GraphResultFailure(failure);
    }
    if (precedesRequiredRevision(firstPage.revision)) return null;
    RelationPagingData<Row> data;
    switch (_acceptFirst(source, firstPage)) {
      case GraphResultSuccess(:final value):
        data = value;
      case GraphResultFailure(:final failure):
        return GraphResultFailure(failure);
    }
    var cursor = data.nextCursor;
    while (cursor != null && data.items.length < limit) {
      final result = await source.readPage(cursor);
      if (!isCurrent()) return null;
      switch (result) {
        case GraphResultSuccess(
          value: final RelationPagingContinuationPage<Row> page,
        ):
          switch (_acceptContinuation(source, data, page)) {
            case GraphResultSuccess(:final value):
              data = value;
              cursor = data.nextCursor;
            case GraphResultFailure(:final failure):
              return GraphResultFailure(failure);
            case null:
              return null;
          }
        case GraphResultSuccess():
          return const GraphResultFailure(RelationGroupUnexpectedFailure());
        case GraphResultFailure(failure: RelationGroupSnapshotExpired()):
          return null;
        case GraphResultFailure(:final failure):
          return GraphResultFailure(failure);
      }
    }
    return GraphResultSuccess(data);
  }

  RelationPagingResult<Row>? _acceptContinuation<Row, Id extends Object>(
    RelationPagingSource<Row, Id> source,
    RelationPagingData<Row> confirmed,
    RelationPagingContinuationPage<Row> page,
  ) {
    if (page.revision.compareTo(confirmed.revision) !=
        GraphRevisionOrder.same) {
      return null;
    }
    final items = _combine(
      loaded: confirmed.items,
      page: page.items,
      pageSize: source.pageSize,
      identify: source.identify,
    );
    if (items == null ||
        !_hasConsistentTotal(
          items.length,
          page.nextCursor,
          confirmed.totalCount,
        )) {
      return const GraphResultFailure(RelationGroupUnexpectedFailure());
    }
    return GraphResultSuccess(
      RelationPagingData(
        items: items,
        counts: confirmed.counts,
        totalCount: confirmed.totalCount,
        revision: confirmed.revision,
        nextCursor: page.nextCursor,
      ),
    );
  }

  RelationPagingResult<Row> _acceptFirst<Row, Id extends Object>(
    RelationPagingSource<Row, Id> source,
    RelationPagingFirstPage<Row> page,
  ) {
    final items = _combine(
      loaded: <Row>[],
      page: page.items,
      pageSize: source.pageSize,
      identify: source.identify,
    );
    if (items == null ||
        !_hasConsistentTotal(items.length, page.nextCursor, page.totalCount)) {
      return const GraphResultFailure(RelationGroupUnexpectedFailure());
    }
    return GraphResultSuccess(
      RelationPagingData(
        items: items,
        counts: page.counts,
        totalCount: page.totalCount,
        revision: page.revision,
        nextCursor: page.nextCursor,
      ),
    );
  }

  /// Проверка принадлежности возвращает идентификатор строки своей группы
  /// или `null` для чужой строки. Повторы не добавляются второй раз.
  List<Row>? _combine<Row, Id extends Object>({
    required List<Row> loaded,
    required List<Row> page,
    required int pageSize,
    required Id? Function(Row) identify,
  }) {
    if (page.length > pageSize) return null;
    final knownIds = {for (final item in loaded) identify(item)};
    final combined = [...loaded];
    for (final item in page) {
      final id = identify(item);
      if (id == null) return null;
      if (knownIds.add(id)) combined.add(item);
    }
    return combined;
  }

  /// Конец списка подтверждает только полная группа.
  bool _hasConsistentTotal(
    int loadedCount,
    RelationGroupCursor? nextCursor,
    int totalCount,
  ) =>
      nextCursor == null ? loadedCount == totalCount : loadedCount < totalCount;

  /// Выбирает ближайшую сохранившуюся строку, при равном расстоянии —
  /// следующую. При полной замене сохраняет позицию в пределах нового списка.
  RelationPagingAnchor<Id>? chooseAnchor<Row, Id extends Object>({
    required List<Row> previous,
    required List<Row> replacement,
    required Id? visibleId,
    required Id Function(Row) identify,
  }) {
    if (visibleId == null || previous.isEmpty || replacement.isEmpty) {
      return null;
    }
    final previousIndex = previous.indexWhere(
      (item) => identify(item) == visibleId,
    );
    if (previousIndex < 0) return null;
    final replacementIndexes = <Id, int>{
      for (var index = 0; index < replacement.length; index += 1)
        identify(replacement[index]): index,
    };
    var targetId = visibleId;
    var targetIndex = replacementIndexes[visibleId];
    for (
      var distance = 1;
      targetIndex == null && distance < previous.length;
      distance += 1
    ) {
      final after = previousIndex + distance;
      final before = previousIndex - distance;
      if (after < previous.length) {
        final candidate = identify(previous[after]);
        final candidateIndex = replacementIndexes[candidate];
        if (candidateIndex != null) {
          targetId = candidate;
          targetIndex = candidateIndex;
          break;
        }
      }
      if (before >= 0) {
        final candidate = identify(previous[before]);
        final candidateIndex = replacementIndexes[candidate];
        if (candidateIndex != null) {
          targetId = candidate;
          targetIndex = candidateIndex;
        }
      }
    }
    if (targetIndex == null) {
      targetIndex = previousIndex.clamp(0, replacement.length - 1);
      targetId = identify(replacement[targetIndex]);
    }
    return RelationPagingAnchor(id: targetId, index: targetIndex);
  }
}

/// Возможности чтения одной группы. Проверка строки одновременно извлекает
/// её идентификатор: `null` запрещает включать строку в эту группу.
final class RelationPagingSource<Row, Id extends Object> {
  const RelationPagingSource({
    required this.readPage,
    required this.pageSize,
    required this.identify,
  });

  final Future<RelationPagingPageResult<Row>> Function(RelationGroupCursor?)
  readPage;
  final int pageSize;
  final Id? Function(Row) identify;
}

/// Запрос принадлежит поколению и не возвращается в работу после отмены.
final class RelationPagingRequest {
  RelationPagingRequest._(this._generation, this._invalidation);

  final int _generation;
  final int _invalidation;
  var _refreshAttempts = 0;
}

/// Порция после преобразования предметного чтения потребителем ядра.
sealed class RelationPagingPage<Row> {
  const RelationPagingPage({
    required this.items,
    required this.revision,
    required this.nextCursor,
  });

  final List<Row> items;
  final GraphRevision revision;
  final RelationGroupCursor? nextCursor;
}

final class RelationPagingFirstPage<Row> extends RelationPagingPage<Row> {
  const RelationPagingFirstPage({
    required super.items,
    required super.revision,
    required super.nextCursor,
    required this.counts,
    required this.totalCount,
  });

  final RelationCounts counts;
  final int totalCount;
}

final class RelationPagingContinuationPage<Row>
    extends RelationPagingPage<Row> {
  const RelationPagingContinuationPage({
    required super.items,
    required super.revision,
    required super.nextCursor,
  });
}

/// Загруженная часть, полное количество и продолжение на одной ревизии.
final class RelationPagingData<Row> {
  RelationPagingData({
    required List<Row> items,
    required this.counts,
    required this.totalCount,
    required this.revision,
    required this.nextCursor,
  }) : items = List.unmodifiable(items);

  final List<Row> items;
  final RelationCounts counts;
  final int totalCount;
  final GraphRevision revision;
  final RelationGroupCursor? nextCursor;
}

typedef RelationPagingResult<Row> =
    GraphResult<RelationPagingData<Row>, RelationGroupReadFailure>;
typedef RelationPagingPageResult<Row> =
    GraphResult<RelationPagingPage<Row>, RelationGroupReadFailure>;

/// Стабильная строка и её позиция в согласованной замене списка.
final class RelationPagingAnchor<Id extends Object> {
  const RelationPagingAnchor({required this.id, required this.index});

  final Id id;
  final int index;
}
