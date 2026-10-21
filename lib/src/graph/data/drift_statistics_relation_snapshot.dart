part of 'drift_personal_graph_repository.dart';

/// Внутреннее чтение адаптера для подсчёта достижимости; не расширяет
/// [PersonalGraphRepository] и не передаёт снимок в прикладной слой.
extension DriftStatisticsRelationSnapshotReading
    on DriftPersonalGraphRepository {
  /// Лениво получает граф активных связей, переиспользуя его до подтверждённого
  /// изменения связей. Каждая порция занимает отдельную транзакцию очереди.
  /// Изменение связей во время загрузки даёт [StatisticsSnapshotExpired]
  /// без внутреннего повтора; ошибки хранилища и декодирования передаются
  /// чтению статистики для общей классификации отказа.
  Future<ContributionRelationGraph> loadStatisticsRelationSnapshot() async {
    if (_statisticsRelationSnapshot case final graph?) return graph;
    final sequence = _lastRelationChangeSequence;
    final builder = _RelationSnapshotBuilder();
    var after = 0;
    const pageSize = 512;
    while (true) {
      // Граница транзакции находится внутри отдельного входа в очередь:
      // https://drift.simonbinder.eu/dart_api/transactions/
      final rows = await _sequencer.run(() async {
        _requireRelationSnapshotSequence(sequence);
        return _database.transaction(
          () => _database
              .customSelect(
                '''SELECT creation_sequence, source_intention_id, related_intention_id
               FROM long_term_relations
               WHERE creation_sequence > ? AND is_archived = 0
               ORDER BY creation_sequence LIMIT ?''',
                variables: [
                  Variable<int>(after),
                  const Variable<int>(pageSize),
                ],
                readsFrom: {_database.longTermRelations},
              )
              .get(),
        );
      });
      _requireRelationSnapshotSequence(sequence);
      for (final row in rows) {
        builder.add(
          decodeStoredIntentionId(
            requiredStoredString(row.data, 'source_intention_id'),
          ),
          decodeStoredIntentionId(
            requiredStoredString(row.data, 'related_intention_id'),
          ),
        );
      }
      if (rows.length < pageSize) break;
      after = requiredStoredInteger(rows.last.data, 'creation_sequence');
    }
    return _statisticsRelationSnapshot = builder.build();
  }

  void _requireRelationSnapshotSequence(int sequence) {
    if (sequence != _lastRelationChangeSequence) {
      throw const StatisticsSnapshotExpired();
    }
  }

  void _invalidateStatisticsRelationSnapshot(Iterable<GraphChange> changes) {
    if (changes.any(
      (change) =>
          change is LongTermRelationChange &&
          change is! LongTermRelationUnchangedChange,
    )) {
      _lastRelationChangeSequence = _mutationSequence;
      _statisticsRelationSnapshot = null;
    }
  }
}

final class _RelationSnapshotBuilder {
  final _ids = <IntentionId>[];
  final _indexes = <IntentionId, int>{};
  final _sources = <int>[];
  final _targets = <int>[];

  int _index(IntentionId id) => _indexes.putIfAbsent(id, () {
    _ids.add(id);
    return _ids.length - 1;
  });

  void add(IntentionId source, IntentionId target) {
    _sources.add(_index(source));
    _targets.add(_index(target));
  }

  ContributionRelationGraph build() {
    final children = _adjacency(_sources, _targets);
    final parents = _adjacency(_targets, _sources);
    return ContributionRelationGraph(
      intentionIds: _ids,
      childOffsets: children.offsets,
      children: children.neighbors,
      parentOffsets: parents.offsets,
      parents: parents.neighbors,
    );
  }

  ({Uint32List offsets, Uint32List neighbors}) _adjacency(
    List<int> sources,
    List<int> targets,
  ) {
    final offsets = Uint32List(_ids.length + 1);
    for (final source in sources) {
      offsets[source + 1]++;
    }
    for (var i = 1; i < offsets.length; i++) {
      offsets[i] += offsets[i - 1];
    }
    final positions = Uint32List.fromList(offsets);
    final neighbors = Uint32List(targets.length);
    for (var edge = 0; edge < sources.length; edge++) {
      neighbors[positions[sources[edge]]++] = targets[edge];
    }
    return (offsets: offsets, neighbors: neighbors);
  }
}
