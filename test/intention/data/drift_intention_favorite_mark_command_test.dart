import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late InMemoryDiagnosticsSink diagnostics;
  late _WriteTrace trace;
  late DateTime now;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    diagnostics = InMemoryDiagnosticsSink();
    trace = _WriteTrace();
    now = DateTime.utc(2026, 10, 2, 12);
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        trace,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => now,
      diagnostics,
    );
  });

  tearDown(() => database.close());

  group('Место отметки', () {
    test('первая отметка получает первое место', () async {
      _insertIntention(raw, number: 1, title: 'Гулять');

      await _saved(repository, MarkIntentionFavorite(_id(1)));

      expect(_storedMarks(raw), [(_uuid(1), 1)]);
    });

    test('отметка встаёт после текущего максимума, включая места '
        'архивированных намерений', () async {
      _insertIntention(raw, number: 1, title: 'Активное');
      _insertIntention(raw, number: 2, title: 'Архивное', isArchived: true);
      _insertIntention(raw, number: 3, title: 'Новое');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 3);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 7);

      await _saved(repository, MarkIntentionFavorite(_id(3)));

      expect(_storedMarks(raw), [(_uuid(1), 3), (_uuid(2), 7), (_uuid(3), 8)]);
    });

    test('отметка архивированного намерения встаёт в конец без '
        'восстановления', () async {
      _insertIntention(raw, number: 1, title: 'Активное');
      _insertIntention(
        raw,
        number: 2,
        title: 'Архивное действие',
        isArchived: true,
        isActionReady: true,
      );
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
      final intentionsBefore = _storedIntentions(raw);

      final saved = await _saved(repository, MarkIntentionFavorite(_id(2)));

      expect(_storedMarks(raw), [(_uuid(1), 1), (_uuid(2), 2)]);
      expect(saved.intention.archiveState, IntentionArchiveState.archived);
      expect(saved.intention.readiness, IntentionReadiness.ready);
      expect(_storedIntentions(raw), intentionsBefore);
    });

    test('снятие удаляет строку отметки и сохраняет места остальных', () async {
      for (final number in [1, 2, 3]) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        storeFavoriteMark(raw, intentionId: _uuid(number), position: number);
      }

      await _saved(repository, UnmarkIntentionFavorite(_id(2)));

      expect(_storedMarks(raw), [(_uuid(1), 1), (_uuid(3), 3)]);
    });

    test('новая отметка после снятия снова получает последнее место', () async {
      for (final number in [1, 2, 3]) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _saved(repository, MarkIntentionFavorite(_id(number)));
      }

      await _saved(repository, UnmarkIntentionFavorite(_id(1)));
      await _saved(repository, MarkIntentionFavorite(_id(1)));

      expect(_markOrder(raw), [_uuid(2), _uuid(3), _uuid(1)]);
    });

    test('место следует порядку отметок, а не времени, названию или '
        'идентификатору', () async {
      _insertIntention(raw, number: 1, title: 'Яблоко');
      _insertIntention(raw, number: 2, title: 'Арбуз');
      _insertIntention(raw, number: 3, title: 'Мандарин');

      await _saved(repository, MarkIntentionFavorite(_id(3)));
      // Часы переведены назад: показание раньше времени создания намерений
      // и раньше предыдущей отметки.
      now = DateTime.utc(2020, 1, 1);
      await _saved(repository, MarkIntentionFavorite(_id(1)));
      now = DateTime.utc(2019, 1, 1);
      await _saved(repository, MarkIntentionFavorite(_id(2)));

      expect(_markOrder(raw), [_uuid(3), _uuid(1), _uuid(2)]);
    });
  });

  group('Начальная отметка при создании', () {
    CreateIntention favoriteCreation(String title) =>
        CreateIntention.withInitialState(
          title: title,
          description: null,
          readiness: IntentionReadiness.notReady,
          favoriteMark: FavoriteMark.favorite,
          tagIds: const [],
        );

    test(
      'созданное избранное встаёт в конец единого порядка после '
      'архивированного места, а Главная показывает только активные',
      () async {
        _insertIntention(raw, number: 1, title: 'А');
        _insertIntention(raw, number: 2, title: 'Б', isArchived: true);
        _insertIntention(raw, number: 3, title: 'В');
        for (final number in [1, 2, 3]) {
          storeFavoriteMark(raw, intentionId: _uuid(number), position: number);
        }

        final saved = await _saved(repository, favoriteCreation('Г'));

        final createdId = saved.intention.id;
        expect(_markOrder(raw), [
          _uuid(1),
          _uuid(2),
          _uuid(3),
          createdId.toCanonicalString(),
        ]);
        final favorites = await repository.getFavoriteIntentions();
        expect(favorites, isA<FavoriteIntentionsSuccess>());
        final snapshot = (favorites as FavoriteIntentionsSuccess).value;
        expect(snapshot.items.map((row) => row.id), [
          _id(1),
          _id(3),
          createdId,
        ]);
        expect(snapshot.archivedCount, 1);
      },
    );

    test('место следует текущему максимуму с пропусками, а не числу '
        'избранных', () async {
      _insertIntention(raw, number: 1, title: 'Активное');
      _insertIntention(raw, number: 2, title: 'Архивное', isArchived: true);
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 3);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 7);

      final saved = await _saved(repository, favoriteCreation('Новое'));

      expect(_storedMarks(raw), [
        (_uuid(1), 3),
        (_uuid(2), 7),
        (saved.intention.id.toCanonicalString(), 8),
      ]);
    });

    test('создание с избранным не выполняет отдельную команду отметки и '
        'возвращает отметку в снимке создания', () async {
      await _revision(repository);
      trace.clear();

      final confirmed = await _confirmed(repository, favoriteCreation('Новое'));

      final saved = confirmed.value as IntentionSaved;
      final created = saved.catalogMutation as IntentionCatalogCreated;
      expect(saved.changes, [same(created)]);
      expect(created.entry.summary.favoriteMark, FavoriteMark.favorite);
      expect(
        diagnostics.events.whereType<IntentionCommandDiagnosticsEvent>().map(
          (event) => event.commandType,
        ),
        [IntentionCommandDiagnosticsType.create],
      );
      expect(
        trace.writes.where((sql) => sql.contains('favorite_intentions')),
        hasLength(1),
      );
      expect(trace.writes.join('\n'), isNot(contains('intentions SET')));
    });
  });

  group('Результат команды', () {
    for (final scenario in [
      (
        name: 'отметка',
        storedBefore: false,
        command: MarkIntentionFavorite.new,
        before: FavoriteMark.notFavorite,
        after: FavoriteMark.favorite,
      ),
      (
        name: 'снятие отметки',
        storedBefore: true,
        command: UnmarkIntentionFavorite.new,
        before: FavoriteMark.favorite,
        after: FavoriteMark.notFavorite,
      ),
    ]) {
      test('${scenario.name} возвращает обновление каталога на новой ревизии, '
          'снимки которого различаются только отметкой', () async {
        _insertIntention(
          raw,
          number: 1,
          title: 'Гулять',
          description: 'Каждый вечер',
          isActionReady: true,
        );
        if (scenario.storedBefore) {
          storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
        }
        final intentionsBefore = _storedIntentions(raw);
        final revisionBefore = await _revision(repository);

        final confirmed = await _confirmed(
          repository,
          scenario.command(_id(1)),
        );

        final saved = confirmed.value as IntentionSaved;
        final mutation = saved.catalogMutation as IntentionCatalogUpdated;
        expect(
          confirmed.revision.compareTo(revisionBefore),
          GraphRevisionOrder.newer,
        );
        expect(
          mutation.revision.compareTo(confirmed.revision),
          GraphRevisionOrder.same,
        );
        expect(saved.changes, [same(mutation)]);
        expect(mutation.before.summary.favoriteMark, scenario.before);
        expect(mutation.after.summary.favoriteMark, scenario.after);
        expect(
          _summaryWithoutMark(mutation.after.summary),
          _summaryWithoutMark(mutation.before.summary),
        );
        expect(saved.intention.id, _id(1));
        expect(saved.intention.title, 'Гулять');
        // Команда не пишет в строки намерений и не меняет показания времени.
        expect(_storedIntentions(raw), intentionsBefore);
        expect(trace.writes.join('\n'), isNot(contains('intentions SET')));
        expect((await _details(repository, 1)).favoriteMark, scenario.after);
      });
    }

    test('отметка различает одноимённые намерения по идентификатору', () async {
      _insertIntention(raw, number: 1, title: 'Гулять');
      _insertIntention(raw, number: 2, title: 'Гулять');

      await _saved(repository, MarkIntentionFavorite(_id(2)));

      expect(
        (await _details(repository, 1)).favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(
        (await _details(repository, 2)).favoriteMark,
        FavoriteMark.favorite,
      );
    });

    test('повторная отметка возвращает отсутствие изменения без записи и новой '
        'ревизии и сохраняет прежнее место', () async {
      _insertIntention(raw, number: 1, title: 'Первое');
      _insertIntention(raw, number: 2, title: 'Второе');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 4);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 9);
      final revisionBefore = await _revision(repository);
      final changesBefore = _connectionChanges(raw);
      trace.clear();

      final confirmed = await _confirmed(
        repository,
        MarkIntentionFavorite(_id(1)),
      );

      final saved = confirmed.value as IntentionSaved;
      final mutation = saved.catalogMutation as IntentionCatalogUnchanged;
      expect(mutation.entry.summary.favoriteMark, FavoriteMark.favorite);
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(trace.writes, isEmpty);
      expect(_connectionChanges(raw), changesBefore);
      expect(_storedMarks(raw), [(_uuid(1), 4), (_uuid(2), 9)]);
    });

    test('снятие отсутствующей отметки возвращает отсутствие изменения без '
        'записи и новой ревизии', () async {
      _insertIntention(raw, number: 1, title: 'Первое');
      _insertIntention(raw, number: 2, title: 'Второе');
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 5);
      final revisionBefore = await _revision(repository);
      final changesBefore = _connectionChanges(raw);
      trace.clear();

      final confirmed = await _confirmed(
        repository,
        UnmarkIntentionFavorite(_id(1)),
      );

      final saved = confirmed.value as IntentionSaved;
      final mutation = saved.catalogMutation as IntentionCatalogUnchanged;
      expect(mutation.entry.summary.favoriteMark, FavoriteMark.notFavorite);
      expect(
        confirmed.revision.compareTo(revisionBefore),
        GraphRevisionOrder.same,
      );
      expect(trace.writes, isEmpty);
      expect(_connectionChanges(raw), changesBefore);
      expect(_storedMarks(raw), [(_uuid(2), 5)]);
    });

    for (final scenario in [
      (name: 'отметка', command: MarkIntentionFavorite.new),
      (name: 'снятие отметки', command: UnmarkIntentionFavorite.new),
    ]) {
      test('${scenario.name} отсутствующего намерения сообщает об отсутствии '
          'без создания намерения или отметки', () async {
        _insertIntention(raw, number: 1, title: 'Существующее');
        storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
        final intentionsBefore = _storedIntentions(raw);
        final revisionBefore = await _revision(repository);
        final changesBefore = _connectionChanges(raw);
        trace.clear();

        final result = await repository.execute(scenario.command(_id(2)));

        expect(
          result,
          isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
              .having(
                (failure) => failure.failure,
                'причина',
                isA<IntentionNotFoundFailure>(),
              ),
        );
        expect(trace.writes, isEmpty);
        expect(_connectionChanges(raw), changesBefore);
        expect(_storedIntentions(raw), intentionsBefore);
        expect(_storedMarks(raw), [(_uuid(1), 1)]);
        expect(
          (await _revision(repository)).compareTo(revisionBefore),
          GraphRevisionOrder.same,
        );
      });
    }
  });

  group('Диагностика', () {
    test('различает отметку и её снятие как виды команды намерения', () async {
      _insertIntention(raw, number: 1, title: 'CANARY-название');

      await _saved(repository, MarkIntentionFavorite(_id(1)));
      await _saved(repository, UnmarkIntentionFavorite(_id(1)));
      await repository.execute(MarkIntentionFavorite(_id(2)));

      final events = diagnostics.events
          .whereType<IntentionCommandDiagnosticsEvent>()
          .toList();
      expect(events.map((event) => event.commandType), [
        IntentionCommandDiagnosticsType.markFavorite,
        IntentionCommandDiagnosticsType.unmarkFavorite,
        IntentionCommandDiagnosticsType.markFavorite,
      ]);
      expect(events[0].status, isA<DiagnosticsSucceeded>());
      expect(events[1].status, isA<DiagnosticsSucceeded>());
      expect(
        events[2].status,
        isA<DiagnosticsFailed>().having(
          (status) => status.code,
          'категория',
          DiagnosticsFailureCode.notFound,
        ),
      );
    });
  });
}

/// Записи одного соединения в порядке выполнения.
final class _WriteTrace extends LocalDatabaseConnectionObserver {
  final writes = <String>[];

  void clear() => writes.clear();

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) {
      writes.addAll(statement.statements);
    }
  }
}

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

/// Намерение фикстуры: время создания растёт с номером.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
  String? description,
  bool isArchived = false,
  bool isActionReady = false,
}) {
  final timestamp = DateTime.utc(
    2026,
    10,
    1,
    10,
    number,
  ).microsecondsSinceEpoch;
  database.execute(
    'INSERT INTO intentions (id, title, description, is_action_ready, '
    'is_archived, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [
      _uuid(number),
      title,
      description,
      isActionReady ? 1 : 0,
      isArchived ? 1 : 0,
      timestamp,
      timestamp,
    ],
  );
}

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;

List<Map<String, Object?>> _storedIntentions(sqlite.Database database) => [
  for (final row in database.select('SELECT * FROM intentions ORDER BY id'))
    {...row},
];

/// Отметки с их местами в порядке идентификаторов намерений.
List<(String, int)> _storedMarks(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT intention_id, position FROM favorite_intentions '
    'ORDER BY intention_id',
  ))
    (row['intention_id'] as String, row['position'] as int),
];

/// Идентификаторы избранных намерений в порядке их мест.
List<String> _markOrder(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT intention_id FROM favorite_intentions ORDER BY position',
  ))
    row['intention_id'] as String,
];

/// Поля сводки, которые команда отметки не меняет.
List<Object?> _summaryWithoutMark(IntentionSummary summary) => [
  summary.id,
  summary.title,
  summary.hasDescription,
  summary.readiness,
  summary.archiveState,
  summary.activeRelationCount,
  summary.createdAt.value,
  summary.updatedAt.value,
  summary.tags,
];

Future<ConfirmedGraphResult<IntentionCommandSuccess>> _confirmed(
  DriftPersonalGraphRepository repository,
  IntentionCommand command,
) async {
  final result = await repository.execute(command);
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  return (result
          as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
      .value;
}

Future<IntentionSaved> _saved(
  DriftPersonalGraphRepository repository,
  IntentionCommand command,
) async => (await _confirmed(repository, command)).value as IntentionSaved;

Future<GraphRevision> _revision(DriftPersonalGraphRepository repository) async {
  final result = await repository.getCatalogPage(
    IntentionCatalogQuery(
      scope: IntentionScope.all,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtAscending,
      pageSize: 10,
    ),
  );
  return (result as ResultSuccess<IntentionCatalogPage>).value.revision;
}

Future<IntentionDetails> _details(
  DriftPersonalGraphRepository repository,
  int number,
) async {
  final result = await repository.watchIntention(_id(number)).first;
  expect(result, isA<ResultSuccess<GraphSnapshot<IntentionDetails?>>>());
  return (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>)
      .value
      .value!;
}
