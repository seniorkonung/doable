import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;
  late _SuggestionsProbe probe;
  late InMemoryDiagnosticsSink diagnostics;

  setUp(() async {
    probe = _SuggestionsProbe();
    diagnostics = InMemoryDiagnosticsSink();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        probe,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      diagnostics,
    );
  });

  tearDown(() => database.close());

  void addIntention(int number, {int archived = 0, int ready = 0}) {
    raw.execute(
      '''INSERT INTO intentions
         (id, title, description, is_action_ready, is_archived, created_at, updated_at)
         VALUES (?, ?, NULL, ?, ?, 1, 1)''',
      [_uuid(number), 'Намерение $number', ready, archived],
    );
  }

  void addRelation(int number, int source, int action, {int archived = 0}) {
    raw.execute(
      '''INSERT INTO long_term_relations
         (id, source_intention_id, related_intention_id, type, priority, description, is_archived)
         VALUES (?, ?, ?, 'need', 2, NULL, ?)''',
      [_uuid(number), _uuid(source), _uuid(action), archived],
    );
  }

  void addChoice(int number, int source, int action, int relation) {
    raw.execute(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date, description, is_completed)
         VALUES (?, ?, ?, '2026-09-23', NULL, 0)''',
      [_uuid(number), _uuid(source), _uuid(action)],
    );
    raw.execute(
      '''INSERT INTO daily_choice_path_steps
         (id, daily_choice_id, long_term_relation_id, previous_step_id)
         VALUES (?, ?, ?, NULL)''',
      [_uuid(number + 1000), _uuid(number), _uuid(relation)],
    );
  }

  Future<ChoicePathSuggestionsSnapshot> read(
    ChoicePathSuggestionsQuery query,
  ) async {
    final result = await repository.getChoicePathSuggestions(query);
    expect(result, isA<ChoicePathSuggestionsSuccess>());
    return (result as ChoicePathSuggestionsSuccess).value;
  }

  test('различает отсутствие участника и пустую историю', () async {
    expect(
      await repository.getChoicePathSuggestions(
        ChoicePathSuggestionsForSource(_intention(1)),
      ),
      isA<ChoicePathSuggestionsError>().having(
        (result) => result.failure.category,
        'категория',
        GraphFailureCategory.notFound,
      ),
    );
    addIntention(1);
    final empty = await read(ChoicePathSuggestionsForSource(_intention(1)));
    expect(empty.items, isEmpty);
    expect(empty.revision, isNotNull);
  });

  test(
    'ограничивает историю двадцатью записями до устранения повторов',
    () async {
      addIntention(1);
      for (var action = 2; action <= 8; action++) {
        addIntention(action, ready: 1);
        addRelation(100 + action, 1, action);
      }
      addChoice(1001, 1, 8, 108);
      for (var index = 2; index <= 20; index++) {
        final action = 2 + (index % 6);
        addChoice(1000 + index, 1, action, 100 + action);
      }

      final twenty = await read(ChoicePathSuggestionsForSource(_intention(1)));
      expect(twenty.items, hasLength(5));
      expect(
        twenty.items.first.originChoiceId.toCanonicalString(),
        _uuid(1020),
      );
      addChoice(1021, 1, 5, 105);
      probe.selects.clear();

      final result = await read(ChoicePathSuggestionsForSource(_intention(1)));
      expect(result.items, hasLength(5));
      expect(
        result.items.map((item) => item.originChoiceId.toCanonicalString()),
        [for (var index = 21; index >= 17; index--) _uuid(1000 + index)],
      );
      expect(result.items, everyElement(isA<AvailableChoicePathSuggestion>()));
      expect(
        probe.selects.where(
          (sql) => sql.contains('FROM daily_choices WHERE id = ?'),
        ),
        hasLength(20),
      );
      expect(probe.selects.any((sql) => sql.contains('LIMIT ?')), isTrue);
    },
  );

  test(
    'возвращает меньше пяти подсказок для повторов в обоих направлениях',
    () async {
      addIntention(1);
      addIntention(2, ready: 1);
      addIntention(3, ready: 1);
      addRelation(101, 1, 2);
      addRelation(102, 1, 3);
      addChoice(1001, 1, 3, 102);
      for (var index = 2; index <= 21; index++) {
        addChoice(1000 + index, 1, 2, 101);
      }
      final top = await read(ChoicePathSuggestionsForSource(_intention(1)));
      final bottom = await read(ChoicePathSuggestionsForAction(_intention(2)));
      expect(top.items, hasLength(1));
      expect(bottom.items, hasLength(1));
      expect(top.items.single.originChoiceId.toCanonicalString(), _uuid(1021));
      expect(
        bottom.items.single.originChoiceId,
        top.items.single.originChoiceId,
      );
    },
  );

  test('пять новых недоступных путей не вытесняют шестой допустимый', () async {
    addIntention(1);
    for (var action = 2; action <= 7; action++) {
      addIntention(action, ready: 1);
      addRelation(100 + action, 1, action);
      addChoice(1000 + action, 1, action, 100 + action);
    }
    for (var action = 3; action <= 7; action++) {
      raw.execute(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [_uuid(100 + action)],
      );
    }

    final top = await read(ChoicePathSuggestionsForSource(_intention(1)));
    expect(top.items.map((item) => item.originChoiceId.toCanonicalString()), [
      _uuid(1002),
    ]);

    addIntention(20, ready: 1);
    for (var source = 21; source <= 26; source++) {
      addIntention(source);
      addRelation(100 + source, source, 20);
      addChoice(2000 + source, source, 20, 100 + source);
    }
    for (var source = 22; source <= 26; source++) {
      raw.execute(
        'UPDATE long_term_relations SET is_archived = 1 WHERE id = ?',
        [_uuid(100 + source)],
      );
      raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
        _uuid(source),
      ]);
    }
    final bottom = await read(ChoicePathSuggestionsForAction(_intention(20)));
    expect(
      bottom.items.map((item) => item.originChoiceId.toCanonicalString()),
      [_uuid(2021)],
    );
    expect(bottom.observedIntentionIds, contains(_intention(26)));
    expect(
      top.observedRelationIds.map((id) => id.toCanonicalString()),
      contains(_uuid(107)),
    );
  });

  test('двадцать недоступных записей не открывают двадцать первую', () async {
    addIntention(1);
    addIntention(2, ready: 1);
    addIntention(3, ready: 1);
    addRelation(101, 1, 2);
    addRelation(102, 1, 3);
    addChoice(1001, 1, 2, 101);
    for (var number = 1002; number <= 1021; number++) {
      addChoice(number, 1, 3, 102);
    }
    raw.execute('UPDATE intentions SET is_action_ready = 0 WHERE id = ?', [
      _uuid(3),
    ]);
    probe.selects.clear();

    final result = await read(ChoicePathSuggestionsForSource(_intention(1)));
    expect(result.items, isEmpty);
    expect(
      probe.selects.where(
        (sql) => sql.contains('FROM daily_choices WHERE id = ?'),
      ),
      hasLength(20),
    );
    expect(result.observedIntentionIds, contains(_intention(3)));
  });

  test(
    'подтверждение устаревшей подсказки даёт конфликт без новой записи',
    () async {
      addIntention(1);
      addIntention(2, ready: 1);
      addRelation(101, 1, 2);
      addChoice(1001, 1, 2, 101);
      final suggestion = (await read(
        ChoicePathSuggestionsForSource(_intention(1)),
      )).items.single;
      raw.execute('UPDATE intentions SET is_action_ready = 0 WHERE id = ?', [
        _uuid(2),
      ]);

      final result = await repository.execute(
        CreateDailyChoice(
          sourceIntentionId: suggestion.source.id,
          selectedIntentionId: suggestion.action.id,
          path: suggestion.confirmedPath,
          date: CalendarDate.fromParts(2026, 9, 25),
          description: null,
          isCompleted: false,
        ),
      );
      expect(
        result,
        isA<GraphCommandFailed>().having(
          (failure) => failure.failure.category,
          'категория',
          GraphFailureCategory.conflict,
        ),
      );
      expect(
        raw
            .select('SELECT COUNT(*) AS count FROM daily_choices')
            .single['count'],
        1,
      );
    },
  );

  test('возвращает одну запись и учитывает замену текущего пути', () async {
    addIntention(1);
    addIntention(2, ready: 1);
    addIntention(3, ready: 1);
    addRelation(101, 1, 2);
    addRelation(102, 1, 3);
    addChoice(1001, 1, 2, 101);
    final one = await read(ChoicePathSuggestionsForSource(_intention(1)));
    expect(one.items.single.originChoiceId.toCanonicalString(), _uuid(1001));

    addChoice(1002, 1, 2, 101);
    raw.execute(
      'UPDATE daily_choices SET selected_intention_id = ? WHERE id = ?',
      [_uuid(3), _uuid(1001)],
    );
    raw.execute(
      'UPDATE daily_choice_path_steps SET long_term_relation_id = ? WHERE daily_choice_id = ?',
      [_uuid(102), _uuid(1001)],
    );
    final replaced = await read(ChoicePathSuggestionsForSource(_intention(1)));
    expect(replaced.items, hasLength(2));
    expect(
      replaced.items.map((item) => item.originChoiceId.toCanonicalString()),
      [_uuid(1002), _uuid(1001)],
    );
    expect(replaced.items.last.action.id, _intention(3));
    expect(
      (replaced.items.last as AvailableChoicePathSuggestion)
          .confirmedPath
          .steps
          .single
          .relationId
          .toCanonicalString(),
      _uuid(102),
    );
  });

  test('исключает архивные пути и действия без готовности, сохраняя выборы', () async {
    addIntention(1);
    addIntention(2, ready: 1);
    addIntention(3, ready: 1);
    addRelation(101, 1, 2);
    addRelation(102, 1, 3);
    addChoice(1001, 1, 2, 101);
    addChoice(1002, 1, 3, 102);
    raw.execute(
      'UPDATE daily_choices SET choice_date = ?, is_completed = 1 WHERE id = ?',
      ['2030-01-01', _uuid(1001)],
    );
    raw.execute('UPDATE intentions SET title = ? WHERE id = ?', [
      'Новое название',
      _uuid(2),
    ]);
    raw.execute('UPDATE long_term_relations SET is_archived = 1 WHERE id = ?', [
      _uuid(101),
    ]);
    raw.execute('UPDATE intentions SET is_action_ready = 0 WHERE id = ?', [
      _uuid(3),
    ]);

    final result = await read(ChoicePathSuggestionsForSource(_intention(1)));
    expect(result.items, isEmpty);

    raw.execute('UPDATE intentions SET is_archived = 1 WHERE id = ?', [
      _uuid(2),
    ]);
    final archived = await read(ChoicePathSuggestionsForAction(_intention(2)));
    expect(archived.items, isEmpty);
    expect(
      raw.select('SELECT COUNT(*) AS count FROM daily_choices').single['count'],
      2,
    );
  });

  test('проверяет повреждённый дубликат до объединения', () async {
    addIntention(1);
    addIntention(2, ready: 1);
    addRelation(101, 1, 2);
    addChoice(1001, 1, 2, 101);
    addChoice(1002, 1, 2, 101);
    raw.execute('PRAGMA ignore_check_constraints = ON');
    raw.execute('UPDATE daily_choices SET choice_date = ? WHERE id = ?', [
      'некорректная дата',
      _uuid(1001),
    ]);
    final result = await repository.getChoicePathSuggestions(
      ChoicePathSuggestionsForSource(_intention(1)),
    );
    expect(
      result,
      isA<ChoicePathSuggestionsError>().having(
        (value) => value.failure.category,
        'категория',
        GraphFailureCategory.corruption,
      ),
    );
    final failureEvent = diagnostics.events
        .whereType<ChoicePathSuggestionReadDiagnosticsEvent>()
        .last;
    expect(failureEvent.stage, ChoicePathSuggestionReadStage.pathValidation);
    expect(
      (failureEvent.status as DiagnosticsFailed).code,
      DiagnosticsFailureCode.corruption,
    );
  });

  test(
    'повреждённый кандидат после пяти подсказок отклоняет всё чтение',
    () async {
      addIntention(1);
      for (var action = 2; action <= 7; action++) {
        addIntention(action, ready: 1);
        addRelation(100 + action, 1, action);
        addChoice(1000 + action, 1, action, 100 + action);
      }
      raw.execute('PRAGMA ignore_check_constraints = ON');
      raw.execute('UPDATE daily_choices SET choice_date = ? WHERE id = ?', [
        'некорректная дата',
        _uuid(1002),
      ]);

      final result = await repository.getChoicePathSuggestions(
        ChoicePathSuggestionsForSource(_intention(1)),
      );
      expect(
        result,
        isA<ChoicePathSuggestionsError>().having(
          (value) => value.failure.category,
          'категория',
          GraphFailureCategory.corruption,
        ),
      );
    },
  );

  test(
    'различает временный и неизвестный отказ и безопасно диагностирует этап',
    () async {
      addIntention(1);
      probe.failure = sqlite.SqliteException(
        extendedResultCode: sqlite.SqlError.SQLITE_BUSY,
        message: 'занято',
      );
      expect(
        await repository.getChoicePathSuggestions(
          ChoicePathSuggestionsForSource(_intention(1)),
        ),
        isA<ChoicePathSuggestionsError>().having(
          (value) => value.failure.category,
          'категория',
          GraphFailureCategory.unavailable,
        ),
      );
      probe.failure = StateError('неизвестный отказ');
      expect(
        await repository.getChoicePathSuggestions(
          ChoicePathSuggestionsForSource(_intention(1)),
        ),
        isA<ChoicePathSuggestionsError>().having(
          (value) => value.failure.category,
          'категория',
          GraphFailureCategory.unexpected,
        ),
      );
      expect(
        diagnostics.events
            .whereType<ChoicePathSuggestionReadDiagnosticsEvent>(),
        isNotEmpty,
      );
      final failures = diagnostics.events
          .whereType<ChoicePathSuggestionReadDiagnosticsEvent>()
          .map((event) => event.status)
          .whereType<DiagnosticsFailed>()
          .toList();
      expect(failures.map((event) => event.code), [
        DiagnosticsFailureCode.unavailable,
        DiagnosticsFailureCode.unexpected,
      ]);
      expect(
        diagnostics.events
            .whereType<ChoicePathSuggestionReadDiagnosticsEvent>()
            .map((event) => event.stage),
        everyElement(ChoicePathSuggestionReadStage.candidateSelection),
      );
    },
  );
}

final class _SuggestionsProbe extends LocalDatabaseConnectionObserver {
  Object? failure;
  final selects = <String>[];

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    final sql = statement.statements.single;
    selects.add(sql);
    if (sql.contains('FROM daily_choices') && failure != null) {
      throw failure!;
    }
  }
}
