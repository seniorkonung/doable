part of 'drift_personal_graph_repository.dart';

extension _DailyChoiceCommandExecution on DriftPersonalGraphRepository {
  Future<DailyChoiceCommandResult> _executeDailyChoice(
    DailyChoiceCommand command,
  ) async {
    if (command is UpdateDailyChoiceFields) {
      return _updateDailyChoiceFields(command);
    }
    final stopwatch = Stopwatch()..start();
    var stage = DailyChoiceCommandDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      DailyChoiceCommandDiagnosticsEvent(
        commandType: DailyChoiceCommandDiagnosticsType.create,
        stage: stage,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      if (command is! CreateDailyChoice) {
        throw UnsupportedError('Команда дневного выбора пока не реализована.');
      }
      final created = await _sequencer.run(() async {
        final committed = await _database.transaction(() async {
          final pathStopwatch = Stopwatch()..start();
          _recordDiagnostics(
            const DailyChoicePathValidationDiagnosticsEvent(
              commandType: DailyChoicePathCommandDiagnosticsType.create,
              status: DiagnosticsStarted(),
            ),
          );
          try {
            await _validateConfirmedChoicePath(command);
            _recordDiagnostics(
              DailyChoicePathValidationDiagnosticsEvent(
                commandType: DailyChoicePathCommandDiagnosticsType.create,
                status: DiagnosticsSucceeded(pathStopwatch.elapsed),
              ),
            );
          } on Object catch (error) {
            final failure = _classifyDailyChoiceCommandFailure(error);
            _recordDiagnostics(
              DailyChoicePathValidationDiagnosticsEvent(
                commandType: DailyChoicePathCommandDiagnosticsType.create,
                status: DiagnosticsFailed(
                  duration: pathStopwatch.elapsed,
                  code: _graphCommandDiagnosticsFailureCode(failure),
                ),
              ),
            );
            rethrow;
          }
          final countsBefore = await _readVerifiedRelationCountsFor([
            command.sourceIntentionId,
            command.selectedIntentionId,
          ]);
          record(DiagnosticsSucceeded(stopwatch.elapsed));
          stage = DailyChoiceCommandDiagnosticsStage.write;
          record(const DiagnosticsStarted());

          final choiceId = _dailyChoiceIdGenerator.generate();
          await _database.customInsert(
            '''INSERT INTO daily_choices
               (id, source_intention_id, selected_intention_id,
                choice_date, description, is_completed)
               VALUES (?, ?, ?, ?, ?, ?)''',
            variables: [
              Variable<String>(choiceId.toCanonicalString()),
              Variable<String>(command.sourceIntentionId.toCanonicalString()),
              Variable<String>(command.selectedIntentionId.toCanonicalString()),
              Variable<String>(command.date.toCanonicalString()),
              Variable<String>(command.description?.value),
              Variable<int>(command.isCompleted ? 1 : 0),
            ],
            updates: {_database.dailyChoices},
          );
          ChoicePathStepId? previousId;
          final generatedStepIds = <ChoicePathStepId>[];
          for (final expected in command.path.steps) {
            final stepId = _choicePathStepIdGenerator.generate();
            await _database.customInsert(
              '''INSERT INTO daily_choice_path_steps
                 (id, daily_choice_id, long_term_relation_id, previous_step_id)
                 VALUES (?, ?, ?, ?)''',
              variables: [
                Variable<String>(stepId.toCanonicalString()),
                Variable<String>(choiceId.toCanonicalString()),
                Variable<String>(expected.relationId.toCanonicalString()),
                Variable<String>(previousId?.toCanonicalString()),
              ],
              updates: {_database.dailyChoicePathSteps},
            );
            generatedStepIds.add(stepId);
            previousId = stepId;
          }
          record(DiagnosticsSucceeded(stopwatch.elapsed));
          stage = DailyChoiceCommandDiagnosticsStage.resultRead;
          record(const DiagnosticsStarted());

          final details = await _readVerifiedDailyChoice(choiceId);
          if (details == null ||
              details.choice.sourceIntentionId != command.sourceIntentionId ||
              details.choice.selectedIntentionId !=
                  command.selectedIntentionId ||
              details.choice.date != command.date ||
              details.choice.description != command.description ||
              details.choice.isCompleted != command.isCompleted ||
              details.path.length != command.path.steps.length) {
            throw const _StoredIntentionCorruption();
          }
          for (var index = 0; index < details.path.length; index++) {
            if (details.path[index].step.id != generatedStepIds[index] ||
                details.path[index].relation.id !=
                    command.path.steps[index].relationId) {
              throw const _StoredIntentionCorruption();
            }
          }
          final affectedCounts = await _readVerifiedRelationCountsFor([
            command.sourceIntentionId,
            command.selectedIntentionId,
          ]);
          final sourceBefore = countsBefore[command.sourceIntentionId]!;
          final selectedBefore = countsBefore[command.selectedIntentionId]!;
          final sourceAfter = affectedCounts[command.sourceIntentionId]!;
          final selectedAfter = affectedCounts[command.selectedIntentionId]!;
          if (sourceAfter.dailySource != sourceBefore.dailySource + 1 ||
              sourceAfter.dailySelected != sourceBefore.dailySelected ||
              selectedAfter.dailySelected != selectedBefore.dailySelected + 1 ||
              selectedAfter.dailySource != selectedBefore.dailySource ||
              sourceAfter.longTermTotal != sourceBefore.longTermTotal ||
              selectedAfter.longTermTotal != selectedBefore.longTermTotal) {
            throw const _StoredIntentionCorruption();
          }
          final relationIds = command.path.steps
              .map((step) => step.relationId)
              .toSet();
          final permissions =
              <LongTermRelationId, LongTermRelationPermissions>{};
          final orderedIds = relationIds.toList();
          for (var start = 0; start < orderedIds.length; start += 400) {
            permissions.addAll(
              await _relationCountAggregates.readPermissions(
                orderedIds.skip(start).take(400),
              ),
            );
          }
          if (permissions.values.any((permission) => permission.canDelete)) {
            throw const _StoredIntentionCorruption();
          }
          final revision = _DriftGraphRevision(_epoch, _mutationSequence + 1);
          final change = DailyChoiceChange(
            revision: revision,
            before: null,
            after: details.choice,
            releasedRelationIds: const [],
            occupiedRelationIds: relationIds,
            intentionCounts: affectedCounts,
            relationPermissions: permissions,
          );
          final success = DailyChoiceCreated(
            choice: details.choice,
            path: StoredChoicePath(details.path.map((item) => item.step)),
            changes: [change],
          );
          record(DiagnosticsSucceeded(stopwatch.elapsed));
          return ConfirmedGraphResult(revision: revision, value: success);
        });
        _mutationSequence++;
        _notifyGraphWatchersFor(committed.changes);
        return committed;
      });
      return GraphCommandSucceeded(created);
    } on Object catch (error) {
      final failure = _classifyDailyChoiceCommandFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return GraphCommandFailed(failure);
    }
  }

  Future<DailyChoiceCommandResult> _updateDailyChoiceFields(
    UpdateDailyChoiceFields command,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = DailyChoiceCommandDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      DailyChoiceCommandDiagnosticsEvent(
        commandType: DailyChoiceCommandDiagnosticsType.updateFields,
        stage: stage,
        status: status,
      ),
    );

    record(const DiagnosticsStarted());
    try {
      final confirmed = await _sequencer.run(() async {
        final result = await _database.transaction(() async {
          final existing = await _readVerifiedDailyChoice(command.choiceId);
          if (existing == null) throw const DailyChoiceNotFoundFailure();
          final before = existing.choice;
          final date = switch (command.patch.date) {
            DailyChoiceFieldUnchanged<CalendarDate>() => before.date,
            DailyChoiceFieldSet<CalendarDate>(:final value) => value,
          };
          final description = switch (command.patch.description) {
            DailyChoiceDescriptionUnchanged() => before.description,
            DailyChoiceDescriptionCleared() => null,
            DailyChoiceDescriptionSet(:final value) => value,
          };
          final isCompleted = switch (command.patch.isCompleted) {
            DailyChoiceFieldUnchanged<bool>() => before.isCompleted,
            DailyChoiceFieldSet<bool>(:final value) => value,
          };
          final didMutate =
              date != before.date ||
              description != before.description ||
              isCompleted != before.isCompleted;
          record(DiagnosticsSucceeded(stopwatch.elapsed));

          var verified = existing;
          if (didMutate) {
            stage = DailyChoiceCommandDiagnosticsStage.write;
            record(const DiagnosticsStarted());
            final updatedRows =
                await (_database.update(_database.dailyChoices)..where(
                      (row) =>
                          row.id.equals(command.choiceId.toCanonicalString()),
                    ))
                    .write(
                      local.DailyChoicesCompanion(
                        choiceDate: switch (command.patch.date) {
                          DailyChoiceFieldUnchanged<CalendarDate>() =>
                            const Value.absent(),
                          DailyChoiceFieldSet<CalendarDate>(:final value) =>
                            Value(value.toCanonicalString()),
                        },
                        description: switch (command.patch.description) {
                          DailyChoiceDescriptionUnchanged() =>
                            const Value.absent(),
                          DailyChoiceDescriptionCleared() => const Value(null),
                          DailyChoiceDescriptionSet(:final value) => Value(
                            value.value,
                          ),
                        },
                        isCompleted: switch (command.patch.isCompleted) {
                          DailyChoiceFieldUnchanged<bool>() =>
                            const Value.absent(),
                          DailyChoiceFieldSet<bool>(:final value) => Value(
                            value,
                          ),
                        },
                      ),
                    );
            if (updatedRows != 1) throw const _StoredIntentionCorruption();
            record(DiagnosticsSucceeded(stopwatch.elapsed));
            stage = DailyChoiceCommandDiagnosticsStage.resultRead;
            record(const DiagnosticsStarted());
            verified =
                await _readVerifiedDailyChoice(command.choiceId) ??
                (throw const _StoredIntentionCorruption());
            final after = verified.choice;
            if (after.sourceIntentionId != before.sourceIntentionId ||
                after.selectedIntentionId != before.selectedIntentionId ||
                after.date != date ||
                after.description != description ||
                after.isCompleted != isCompleted ||
                verified.path.length != existing.path.length) {
              throw const _StoredIntentionCorruption();
            }
            for (var index = 0; index < existing.path.length; index++) {
              final oldStep = existing.path[index].step;
              final newStep = verified.path[index].step;
              if (newStep.id != oldStep.id ||
                  newStep.dailyChoiceId != oldStep.dailyChoiceId ||
                  newStep.relationId != oldStep.relationId ||
                  newStep.previousStepId != oldStep.previousStepId) {
                throw const _StoredIntentionCorruption();
              }
            }
          }

          final revision = _DriftGraphRevision(
            _epoch,
            _mutationSequence + (didMutate ? 1 : 0),
          );
          final counts = await _readVerifiedRelationCountsFor([
            before.sourceIntentionId,
            before.selectedIntentionId,
          ]);
          final change = DailyChoiceChange(
            revision: revision,
            before: before,
            after: verified.choice,
            releasedRelationIds: const [],
            occupiedRelationIds: const [],
            intentionCounts: counts,
            relationPermissions: const {},
          );
          final success = DailyChoiceFieldsUpdated(
            before: before,
            choice: verified.choice,
            path: StoredChoicePath(verified.path.map((item) => item.step)),
            changes: [change],
          );
          if (didMutate) record(DiagnosticsSucceeded(stopwatch.elapsed));
          return (
            didMutate,
            ConfirmedGraphResult(revision: revision, value: success),
          );
        });
        if (result.$1) {
          _mutationSequence++;
          _notifyGraphWatchersFor(result.$2.changes);
        }
        return result.$2;
      });
      return GraphCommandSucceeded(confirmed);
    } on Object catch (error) {
      final failure = _classifyDailyChoiceCommandFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return GraphCommandFailed(failure);
    }
  }

  Future<void> _validateConfirmedChoicePath(CreateDailyChoice command) async {
    final steps = command.path.steps;
    final visited = <IntentionId>{command.sourceIntentionId};
    var current = command.sourceIntentionId;
    for (final step in steps) {
      if (step.sourceIntentionId != current ||
          !visited.add(step.relatedIntentionId)) {
        throw const DailyChoiceValidationFailure(
          DailyChoiceValidationField.path,
        );
      }
      current = step.relatedIntentionId;
    }
    if (current != command.selectedIntentionId) {
      throw const DailyChoiceValidationFailure(DailyChoiceValidationField.path);
    }

    for (final expected in steps) {
      final actual = await _readStoredRelation(expected.relationId);
      if (actual == null ||
          actual.sourceIntentionId != expected.sourceIntentionId ||
          actual.relatedIntentionId != expected.relatedIntentionId ||
          actual.type != expected.type) {
        throw const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.confirmedPathChanged,
        );
      }
      if (actual.scope == relation_domain.RelationScope.archived) {
        throw const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.relationArchived,
        );
      }
    }
    for (final id in visited) {
      final row = await _database
          .customSelect(
            '''SELECT id, title, description, is_action_ready, is_archived,
                      created_at, updated_at FROM intentions WHERE id = ?''',
            variables: [Variable<String>(id.toCanonicalString())],
            readsFrom: {_database.intentions},
          )
          .getSingleOrNull();
      if (row == null) {
        throw const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.confirmedPathChanged,
        );
      }
      final intention = _rehydrateDetailRow(row);
      if (intention.archiveState == domain.IntentionArchiveState.archived) {
        throw const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.participantArchived,
        );
      }
      if (id == command.selectedIntentionId &&
          intention.readiness != domain.IntentionReadiness.ready) {
        throw const DailyChoiceConflictFailure(
          DailyChoiceConflictReason.selectedIntentionNotReady,
        );
      }
    }
  }
}

DailyChoiceCommandFailure _classifyDailyChoiceCommandFailure(Object error) {
  if (error is DailyChoiceCommandFailure) return error;
  if (error is _StoredIntentionCorruption) {
    return const DailyChoiceCorruptionFailure();
  }
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const DailyChoiceCorruptionFailure(),
    SqliteUnavailableFailure() => const DailyChoiceUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteUnexpectedFailure() => const DailyChoiceUnexpectedFailure(),
  };
}
