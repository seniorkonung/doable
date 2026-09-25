part of 'drift_personal_graph_repository.dart';

extension _TagReading on DriftPersonalGraphRepository {
  Future<TagCatalogPageResult> _readTagCatalogPage(
    TagCatalogQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = TagReadDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagCatalogPageReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final page = await _sequencer.run(
        () => _database.transaction(() async {
          final cursor = query.cursor;
          if (cursor != null &&
              (cursor is! _DriftTagCatalogCursor ||
                  !cursor.matches(query, _epoch))) {
            throw const _InvalidTagCatalogCursor();
          }
          if (cursor is _DriftTagCatalogCursor &&
              cursor.revision.compareTo(_currentRevision) !=
                  GraphRevisionOrder.same) {
            throw const _TagCatalogSnapshotHasExpired();
          }
          stage = TagReadDiagnosticsStage.read;
          final boundary = cursor is _DriftTagCatalogCursor
              ? cursor.boundarySequence
              : null;
          final rows = await _database
              .customSelect(
                '''SELECT creation_sequence, id, name FROM tags
                   ${boundary == null ? '' : 'WHERE creation_sequence > ?'}
                   ORDER BY creation_sequence ASC LIMIT ?''',
                variables: [
                  if (boundary != null) Variable<int>(boundary),
                  Variable<int>(query.pageSize + 1),
                ],
                readsFrom: {_database.tags},
              )
              .get();
          var previousSequence = boundary ?? 0;
          final decoded = <tag_domain.Tag>[];
          for (final row in rows) {
            final sequence = _requiredStoredInteger(
              row.data,
              'creation_sequence',
            );
            if (sequence <= previousSequence) {
              throw const _StoredIntentionCorruption();
            }
            previousSequence = sequence;
            decoded.add(_decodeStoredTag(row.data));
          }
          final hasNext = decoded.length > query.pageSize;
          final revision = _currentRevision;
          return TagCatalogPage(
            items: decoded.take(query.pageSize).toList(),
            pageSize: query.pageSize,
            nextCursor: hasNext
                ? _DriftTagCatalogCursor(
                    epoch: _epoch,
                    revision: revision,
                    pageSize: query.pageSize,
                    boundarySequence: _requiredStoredInteger(
                      rows[query.pageSize - 1].data,
                      'creation_sequence',
                    ),
                  )
                : null,
            revision: revision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return TagCatalogPageSuccess(page);
    } on Object catch (error) {
      final failure = _classifyTagCatalogReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return TagCatalogPageError(failure);
    }
  }

  Stream<TagReadResult> _watchTag(TagId id) async* {
    final stopwatch = Stopwatch()..start();
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      TagDetailReadDiagnosticsEvent(
        stage: TagReadDiagnosticsStage.read,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    GraphSnapshot<tag_domain.Tag?>? previous;
    try {
      await for (final _
          in _database
              .customSelect(
                'SELECT id FROM tags WHERE id = ?',
                variables: [Variable<String>(id.toCanonicalString())],
                readsFrom: {_database.tags},
              )
              .watch()) {
        final snapshot = await _sequencer.run(
          () => _database.transaction(() async {
            final row = await _database
                .customSelect(
                  'SELECT id, name FROM tags WHERE id = ?',
                  variables: [Variable<String>(id.toCanonicalString())],
                  readsFrom: {_database.tags},
                )
                .getSingleOrNull();
            final tag = row == null ? null : _decodeStoredTag(row.data);
            if (tag != null && tag.id != id) {
              throw const _StoredIntentionCorruption();
            }
            return GraphSnapshot(value: tag, revision: _currentRevision);
          }),
        );
        if (previous case final old?) {
          if (old.revision.compareTo(snapshot.revision) ==
                  GraphRevisionOrder.same &&
              old.value?.id == snapshot.value?.id &&
              old.value?.name == snapshot.value?.name) {
            continue;
          }
        }
        previous = snapshot;
        record(DiagnosticsSucceeded(stopwatch.elapsed));
        yield TagReadSuccess(snapshot);
      }
    } on Object catch (error) {
      final failure = _classifyTagReadFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      yield TagReadError(failure);
    }
  }
}

tag_domain.Tag _decodeStoredTag(Map<String, Object?> data) {
  final id = switch (TagId.decode(_requiredStoredString(data, 'id'))) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw const _StoredIntentionCorruption(),
  };
  try {
    return tag_domain.Tag(
      id: id,
      name: TagName.fromStored(_requiredStoredString(data, 'name')),
    );
  } on TagNameValidationException {
    throw const _StoredIntentionCorruption();
  }
}

final class _DriftTagCatalogCursor implements TagCatalogCursor {
  const _DriftTagCatalogCursor({
    required this.epoch,
    required this.revision,
    required this.pageSize,
    required this.boundarySequence,
  });

  final _GraphEpoch epoch;
  final GraphRevision revision;
  final int pageSize;
  final int boundarySequence;

  bool matches(TagCatalogQuery query, _GraphEpoch owner) =>
      identical(epoch, owner) && pageSize == query.pageSize;
}

final class _InvalidTagCatalogCursor implements Exception {
  const _InvalidTagCatalogCursor();
}

final class _TagCatalogSnapshotHasExpired implements Exception {
  const _TagCatalogSnapshotHasExpired();
}

TagCatalogReadFailure _classifyTagCatalogReadFailure(Object error) {
  if (error is _InvalidTagCatalogCursor) {
    return const TagCatalogInvalidCursor();
  }
  if (error is _TagCatalogSnapshotHasExpired) {
    return const TagCatalogSnapshotExpired();
  }
  if (error is _StoredIntentionCorruption ||
      error is TagCatalogPageValidationException) {
    return const TagCatalogCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagCatalogCorruptionFailure(),
    SqliteUnavailableFailure() => const TagCatalogUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagCatalogUnexpectedFailure(),
  };
}

TagReadFailure _classifyTagReadFailure(Object error) {
  if (error is _StoredIntentionCorruption) {
    return const TagReadCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const TagReadCorruptionFailure(),
    SqliteUnavailableFailure() => const TagReadUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const TagReadUnexpectedFailure(),
  };
}
