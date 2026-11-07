part of 'drift_personal_graph_repository.dart';

extension _ActionCommandExecution on DriftPersonalGraphRepository {
  Future<ActionCommandResult> _executeAction(ActionCommand command) =>
      switch (command) {
        final CreateAction create => _runActionCommand(
          ActionCommandDiagnosticsType.create,
          (clock, enterStage) => _createAction(create, clock, enterStage),
        ),
        final UpdateActionFields update => _runActionCommand(
          ActionCommandDiagnosticsType.updateFields,
          (clock, enterStage) => _updateActionFields(update, clock, enterStage),
        ),
        final SetActionPath update => _runActionCommand(
          ActionCommandDiagnosticsType.setPath,
          (clock, enterStage) => _setActionPath(update, clock, enterStage),
        ),
        final DeleteAction delete => _runActionCommand(
          ActionCommandDiagnosticsType.delete,
          (_, enterStage) => _deleteAction(delete, enterStage),
        ),
      };

  /// Исполняет [body] единой записью графа и ведёт диагностику по этапам.
  /// Тело сообщает о переходе к следующему этапу через `enterStage`; отказ
  /// относится к последнему начатому этапу.
  Future<ActionCommandResult> _runActionCommand(
    ActionCommandDiagnosticsType commandType,
    Future<_GraphWrite<ActionCommandSuccess>> Function(
      _GraphWriteClock clock,
      void Function(ActionCommandDiagnosticsStage next) enterStage,
    )
    body,
  ) async {
    final stopwatch = Stopwatch()..start();
    var stage = ActionCommandDiagnosticsStage.validation;
    void record(DiagnosticsStatus status) => _recordDiagnostics(
      ActionCommandDiagnosticsEvent(
        commandType: commandType,
        stage: stage,
        status: status,
      ),
    );
    void enterStage(ActionCommandDiagnosticsStage next) {
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      stage = next;
      record(const DiagnosticsStarted());
    }

    record(const DiagnosticsStarted());
    try {
      final confirmed = await _writeGraph<ActionCommandSuccess>(
        (clock) => body(clock, enterStage),
      );
      record(DiagnosticsSucceeded(stopwatch.elapsed));
      return GraphCommandSucceeded(confirmed);
    } on Object catch (error) {
      final failure = _classifyActionCommandFailure(error);
      record(
        DiagnosticsFailed(
          duration: stopwatch.elapsed,
          code: _graphCommandDiagnosticsFailureCode(failure),
        ),
      );
      return GraphCommandFailed(failure);
    }
  }

  Future<_GraphWrite<ActionCommandSuccess>> _createAction(
    CreateAction command,
    _GraphWriteClock clock,
    void Function(ActionCommandDiagnosticsStage next) enterStage,
  ) async {
    await _validateActionPath(command.path);
    final id = switch (ActionId.decode(const Uuid().v7())) {
      ActionIdDecodingSuccess(:final id) => id,
      InvalidActionIdDecoding() => throw StateError(
        'Недопустимый UUID действия.',
      ),
    };
    final serialized = id.toCanonicalString();
    final timestamp = clock.read().microsecondsSinceEpoch;
    enterStage(ActionCommandDiagnosticsStage.write);
    await _database
        .into(_database.actions)
        .insert(
          local.ActionsCompanion.insert(
            id: serialized,
            title: command.title.value,
            description: Value(command.description?.value),
            date: command.date.toCanonicalString(),
            scheduledHour: Value(switch (command.schedule) {
              ActionAllDay() => null,
              ActionAtHour(:final hour) => hour,
            }),
            priority: command.priority.level,
            isCompleted: false,
            createdAt: timestamp,
            updatedAt: timestamp,
          ),
        );
    await _insertActionPath(serialized, command.path);
    enterStage(ActionCommandDiagnosticsStage.resultRead);
    final action =
        await _readStoredAction(id) ?? (throw const StoredGraphCorruption());
    return _GraphWriteResult<ActionCommandSuccess>(
      didMutate: true,
      toSuccess: (revision) => ActionCreated(
        action: action,
        changes: [ActionCreatedChange(revision: revision, action: action)],
      ),
    );
  }

  Future<void> _validateActionPath(ActionPath actionPath) async {
    final path = actionPath.intentions;
    for (final (position, intention) in path.indexed) {
      final id = intention.toCanonicalString();
      final active = await _database
          .customSelect(
            'SELECT 1 FROM intentions WHERE id = ? AND is_archived = 0',
            variables: [Variable<String>(id)],
            readsFrom: {_database.intentions},
          )
          .getSingleOrNull();
      if (active == null) throw const ActionPathConflictFailure();
      if (position > 0) {
        final relation = await _database
            .customSelect(
              'SELECT 1 FROM long_term_relations WHERE source_intention_id = ? AND related_intention_id = ? AND is_archived = 0',
              variables: [
                Variable<String>(path[position - 1].toCanonicalString()),
                Variable<String>(id),
              ],
              readsFrom: {_database.longTermRelations},
            )
            .getSingleOrNull();
        if (relation == null) throw const ActionPathConflictFailure();
      }
    }
  }

  Future<void> _insertActionPath(
    String serialized,
    ActionPath actionPath,
  ) async {
    final path = actionPath.intentions;
    for (final (position, intention) in path.indexed) {
      await _database.customStatement(
        """INSERT INTO action_path_items
           (action_id, position, intention_id, previous_intention_id, role, order_date, order_hour, order_sequence)
           SELECT ?1, ?2, ?3, ?4, ?5, date, COALESCE(scheduled_hour, -1), creation_sequence FROM actions WHERE id = ?1""",
        [
          serialized,
          position,
          intention.toCanonicalString(),
          position == 0 ? null : path[position - 1].toCanonicalString(),
          _StoredActionPathRole.at(position, path.length).name,
        ],
      );
    }
  }

  Future<_GraphWrite<ActionCommandSuccess>> _setActionPath(
    SetActionPath command,
    _GraphWriteClock clock,
    void Function(ActionCommandDiagnosticsStage next) enterStage,
  ) async {
    final before = await _readStoredAction(command.actionId);
    if (before == null) throw const ActionNotFoundFailure();
    await _validateActionPath(command.path);
    final oldPath = before.path.intentions;
    final newPath = command.path.intentions;
    final didMutate =
        oldPath.length != newPath.length ||
        oldPath.indexed.any((item) => item.$2 != newPath[item.$1]);
    var after = before;
    if (didMutate) {
      enterStage(ActionCommandDiagnosticsStage.write);
      final id = command.actionId.toCanonicalString();
      await (_database.delete(
        _database.actionPathItems,
      )..where((row) => row.actionId.equals(id))).go();
      await _insertActionPath(id, command.path);
      await (_database.update(
        _database.actions,
      )..where((row) => row.id.equals(id))).write(
        local.ActionsCompanion(
          updatedAt: Value(clock.read().microsecondsSinceEpoch),
        ),
      );
      enterStage(ActionCommandDiagnosticsStage.resultRead);
      after =
          await _readStoredAction(command.actionId) ??
          (throw const StoredGraphCorruption());
    }
    return _GraphWriteResult<ActionCommandSuccess>(
      didMutate: didMutate,
      toSuccess: (revision) => ActionPathUpdated(
        action: after,
        changes: [
          ActionUpdatedChange(revision: revision, before: before, after: after),
        ],
      ),
    );
  }

  Future<_GraphWrite<ActionCommandSuccess>> _updateActionFields(
    UpdateActionFields command,
    _GraphWriteClock clock,
    void Function(ActionCommandDiagnosticsStage next) enterStage,
  ) async {
    final before = await _readStoredAction(command.actionId);
    if (before == null) throw const ActionNotFoundFailure();
    final patch = command.patch;
    final title = patch.title.resolve(before.title);
    final description = patch.description.resolve(before.description);
    final date = patch.date.resolve(before.date);
    final schedule = patch.schedule.resolve(before.schedule);
    final priority = patch.priority.resolve(before.priority);
    final isCompleted = patch.isCompleted.resolve(before.isCompleted);
    final didMutate =
        title != before.title ||
        description != before.description ||
        date != before.date ||
        schedule != before.schedule ||
        priority != before.priority ||
        isCompleted != before.isCompleted;
    if (!didMutate) {
      return _GraphWriteResult<ActionCommandSuccess>(
        didMutate: false,
        toSuccess: (revision) => ActionFieldsUpdated(
          action: before,
          changes: [
            ActionUpdatedChange(
              revision: revision,
              before: before,
              after: before,
            ),
          ],
        ),
      );
    }

    enterStage(ActionCommandDiagnosticsStage.write);
    await (_database.update(_database.actions)
          ..where((row) => row.id.equals(command.actionId.toCanonicalString())))
        .write(
          local.ActionsCompanion(
            title: Value(title.value),
            description: Value(description?.value),
            date: Value(date.toCanonicalString()),
            scheduledHour: Value(switch (schedule) {
              ActionAllDay() => null,
              ActionAtHour(:final hour) => hour,
            }),
            priority: Value(priority.level),
            isCompleted: Value(isCompleted),
            updatedAt: Value(clock.read().microsecondsSinceEpoch),
          ),
        );

    enterStage(ActionCommandDiagnosticsStage.resultRead);
    final after =
        await _readStoredAction(command.actionId) ??
        (throw const StoredGraphCorruption());
    return _GraphWriteResult<ActionCommandSuccess>(
      didMutate: true,
      toSuccess: (revision) => ActionFieldsUpdated(
        action: after,
        changes: [
          ActionUpdatedChange(revision: revision, before: before, after: after),
        ],
      ),
    );
  }

  /// Путь удаляется каскадом схемы, а надгробия, на которые никто больше не
  /// ссылается, — её триггерами.
  Future<_GraphWrite<ActionCommandSuccess>> _deleteAction(
    DeleteAction command,
    void Function(ActionCommandDiagnosticsStage next) enterStage,
  ) async {
    final before = await _readStoredAction(command.actionId);
    if (before == null) throw const ActionNotFoundFailure();

    enterStage(ActionCommandDiagnosticsStage.write);
    await (_database.delete(_database.actions)
          ..where((row) => row.id.equals(command.actionId.toCanonicalString())))
        .go();
    return _GraphWriteResult<ActionCommandSuccess>(
      didMutate: true,
      toSuccess: (revision) => ActionDeleted(
        action: before,
        changes: [ActionDeletedChange(revision: revision, action: before)],
      ),
    );
  }

  /// Действие вместе с путём или `null`, если его нет. Строка вне формы
  /// хранения даёт [StoredGraphCorruption].
  Future<Action?> _readStoredAction(ActionId id) async {
    final row = await _database
        .customSelect(
          '''SELECT creation_sequence, id, title, description, date,
                    scheduled_hour, priority, is_completed, created_at,
                    updated_at
             FROM actions WHERE id = ?''',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.actions},
        )
        .getSingleOrNull();
    if (row == null) return null;
    final pathRows = await _database
        .customSelect(
          '''SELECT position, intention_id, previous_intention_id
             FROM action_path_items WHERE action_id = ? ORDER BY position''',
          variables: [Variable<String>(id.toCanonicalString())],
          readsFrom: {_database.actionPathItems},
        )
        .get();
    return decodeStoredAction(row.data, pathRows.map((path) => path.data));
  }
}

ActionCommandFailure _classifyActionCommandFailure(Object error) {
  if (error is ActionCommandFailure) return error;
  if (error is StoredGraphCorruption) return const ActionCorruptionFailure();
  return switch (classifySqliteFailure(error)) {
    SqliteCorruptionFailure() => const ActionCorruptionFailure(),
    SqliteUnavailableFailure() => const ActionUnavailableFailure(),
    SqliteConstraintFailure() ||
    SqliteStorageFullFailure() ||
    SqliteUnexpectedFailure() => const ActionUnexpectedFailure(),
  };
}
