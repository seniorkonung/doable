part of 'drift_personal_graph_repository.dart';

extension _ChoicePathSuggestionsReading on DriftPersonalGraphRepository {
  Future<ChoicePathSuggestionsResult> _readChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = ChoicePathSuggestionReadStage.candidateSelection;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      ChoicePathSuggestionReadDiagnosticsEvent(stage: stage, status: status),
    );

    record(const DiagnosticsStarted());
    try {
      final snapshot = await _sequencer.run(
        () => _database.transaction(() async {
          final participantRow = await _database
              .customSelect(
                '''SELECT id, title, description, is_action_ready,
                          is_archived, created_at, updated_at
                   FROM intentions WHERE id = ?''',
                variables: [
                  Variable<String>(query.participantId.toCanonicalString()),
                ],
                readsFrom: {_database.intentions},
              )
              .getSingleOrNull();
          if (participantRow == null) {
            throw const _ChoicePathSuggestionParticipantNotFound();
          }
          if (_rehydrateDetailRow(participantRow).id != query.participantId) {
            throw const _StoredIntentionCorruption();
          }

          final participantColumn = switch (query) {
            ChoicePathSuggestionsForSource() => 'source_intention_id',
            ChoicePathSuggestionsForAction() => 'selected_intention_id',
          };
          final candidateRows = await _database
              .customSelect(
                '''SELECT id FROM daily_choices
                   WHERE $participantColumn = ?
                   ORDER BY creation_sequence DESC
                   LIMIT ?''',
                variables: [
                  Variable<String>(query.participantId.toCanonicalString()),
                  const Variable<int>(
                    ChoicePathSuggestionsSnapshot.maxCandidates,
                  ),
                ],
                readsFrom: {_database.dailyChoices},
              )
              .get();
          record(DiagnosticsSucceeded(stopwatch.elapsed));
          stopwatch.reset();
          stage = ChoicePathSuggestionReadStage.pathValidation;
          record(const DiagnosticsStarted());

          final suggestions = <ChoicePathSuggestion>[];
          final seenPaths = <List<LongTermRelationId>>[];
          for (final row in candidateRows) {
            final id = switch (DailyChoiceId.decode(
              _requiredStoredString(row.data, 'id'),
            )) {
              DailyChoiceIdDecodingSuccess(:final id) => id,
              InvalidDailyChoiceIdDecoding() =>
                throw const _StoredIntentionCorruption(),
            };
            final details = await _readVerifiedDailyChoice(id);
            if (details == null) throw const _StoredIntentionCorruption();
            final suggestion = ChoicePathSuggestion.fromDetails(details);
            if (suggestions.length >=
                ChoicePathSuggestionsSnapshot.maxSuggestions) {
              continue;
            }
            final path = [for (final step in suggestion.path) step.relation.id];
            if (seenPaths.any((seen) => _sameSuggestionPath(seen, path))) {
              continue;
            }
            seenPaths.add(path);
            suggestions.add(suggestion);
          }
          return ChoicePathSuggestionsSnapshot(
            query: query,
            items: suggestions,
            revision: _currentRevision,
          );
        }),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return ChoicePathSuggestionsSuccess(snapshot);
    } on Object catch (error) {
      final failure = switch (error) {
        _ChoicePathSuggestionParticipantNotFound() =>
          const ChoicePathSuggestionsIntentionNotFoundFailure(),
        _StoredIntentionCorruption() ||
        ChoicePathSuggestionCorruptionException() =>
          const ChoicePathSuggestionsCorruptionFailure(),
        _ => switch (classifySqliteFailure(error)) {
          SqliteCorruptionFailure() =>
            const ChoicePathSuggestionsCorruptionFailure(),
          SqliteUnavailableFailure() =>
            const ChoicePathSuggestionsUnavailableFailure(),
          SqliteConstraintFailure() || SqliteUnexpectedFailure() =>
            const ChoicePathSuggestionsUnexpectedFailure(),
        },
      };
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return ChoicePathSuggestionsError(failure);
    }
  }
}

bool _sameSuggestionPath(
  List<LongTermRelationId> left,
  List<LongTermRelationId> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

final class _ChoicePathSuggestionParticipantNotFound implements Exception {
  const _ChoicePathSuggestionParticipantNotFound();
}
