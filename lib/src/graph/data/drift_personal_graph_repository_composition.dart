part of 'drift_personal_graph_repository.dart';

extension _GraphCompositionReading on DriftPersonalGraphRepository {
  /// Состав меняют только создание и удаление сущностей, а каждое
  /// подтверждённое изменение графа дописывает пакет в лог фактов (ADR-0034).
  /// Поэтому состав перечитывается после подтверждённых пакетов: подписка
  /// появляется до первого чтения, а пакеты, подтверждённые во время чтения,
  /// дают одно следующее чтение.
  Stream<GraphCompositionRead> _watchComposition() {
    late final StreamController<GraphCompositionRead> controller;
    StreamSubscription<int>? confirmations;
    var isObserving = true;
    var isChanged = true;
    var isReading = false;
    GraphComposition? previous;

    Future<void> readWhileChanged() async {
      isReading = true;
      try {
        while (isChanged && isObserving) {
          isChanged = false;
          final read = await _readComposition();
          if (!isObserving) return;
          switch (read) {
            case GraphCompositionReadSucceeded(:final composition)
                when composition == previous:
              continue;
            case GraphCompositionReadSucceeded(:final composition):
              previous = composition;
              controller.add(read);
            case GraphCompositionReadFailed():
              isObserving = false;
              controller.add(read);
              unawaited(confirmations?.cancel());
              unawaited(controller.close());
          }
        }
      } finally {
        isReading = false;
      }
    }

    controller = StreamController(
      onListen: () {
        confirmations = _confirmedPositions.stream.listen((_) {
          isChanged = true;
          if (!isReading) unawaited(readWhileChanged());
        });
        unawaited(readWhileChanged());
      },
      onCancel: () {
        isObserving = false;
        return confirmations?.cancel();
      },
    );
    return controller.stream;
  }

  /// Одно агрегатное чтение без строк сущностей: один оператор SQLite
  /// читает все числа на одном подтверждённом состоянии.
  Future<GraphCompositionRead> _readComposition() async {
    final stopwatch = Stopwatch()..start();
    try {
      final row = await _sequencer.run(
        () => _database
            .customSelect(
              '''SELECT
                (SELECT count(*) FROM intentions) AS intention_count,
                (SELECT count(*) FROM long_term_relations) AS relation_count,
                (SELECT count(*) FROM daily_choices) AS daily_choice_count,
                (SELECT count(*) FROM tags) AS tag_count''',
              readsFrom: {
                _database.intentions,
                _database.longTermRelations,
                _database.dailyChoices,
                _database.tags,
              },
            )
            .getSingle(),
      );
      _recordDiagnostics(
        GraphCompositionReadDiagnosticsEvent.succeeded(
          duration: stopwatch.elapsed,
        ),
      );
      return GraphCompositionReadSucceeded(
        GraphComposition(
          intentionCount: row.read<int>('intention_count'),
          relationCount: row.read<int>('relation_count'),
          dailyChoiceCount: row.read<int>('daily_choice_count'),
          tagCount: row.read<int>('tag_count'),
        ),
      );
    } on Object catch (error) {
      _recordDiagnostics(
        GraphCompositionReadDiagnosticsEvent.failed(
          duration: stopwatch.elapsed,
          code: switch (classifySqliteFailure(error)) {
            SqliteCorruptionFailure() => DiagnosticsFailureCode.corruption,
            SqliteUnavailableFailure() => DiagnosticsFailureCode.unavailable,
            SqliteConstraintFailure() ||
            SqliteUnexpectedFailure() => DiagnosticsFailureCode.unexpected,
          },
        ),
      );
      return const GraphCompositionReadFailed();
    }
  }
}
