import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _WriteTrace trace;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    trace = _WriteTrace();
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
      () => DateTime.utc(2026, 10, 2, 12),
      InMemoryDiagnosticsSink(),
    );
  });

  tearDown(() => database.close());

  group('Пустой снимок', () {
    test('хранилище без намерений даёт успех с нулём архивированных', () async {
      final snapshot = await _favorites(repository);

      expect(snapshot.items, isEmpty);
      expect(snapshot.archivedCount, 0);
    });

    test(
      'намерения без отметок не входят в список и не получают отметок',
      () async {
        _insertIntention(raw, number: 1, title: 'Гулять');
        _insertIntention(raw, number: 2, title: 'Архивное', isArchived: true);

        final snapshot = await _favorites(repository);

        expect(snapshot.items, isEmpty);
        expect(snapshot.archivedCount, 0);
        expect(storedFavoriteMarks(raw), isEmpty);
      },
    );
  });

  group('Порядок мест', () {
    test(
      'не выводится из времени создания, названия или идентификатора',
      () async {
        // Отметки ставятся против порядка идентификаторов, времени создания
        // и названий.
        _insertIntention(raw, number: 1, title: 'Б');
        _insertIntention(raw, number: 2, title: 'В');
        _insertIntention(raw, number: 3, title: 'А');
        for (final number in [2, 3, 1]) {
          await _execute(repository, MarkIntentionFavorite(_id(number)));
        }

        expect(await _order(repository), [_uuid(2), _uuid(3), _uuid(1)]);
      },
    );

    test('следует сохранённым местам с пропусками', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
      }
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 40);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 3);
      storeFavoriteMark(raw, intentionId: _uuid(3), position: 17);

      expect(await _order(repository), [_uuid(2), _uuid(3), _uuid(1)]);
    });

    test('новая отметка стоит последней', () async {
      for (var number = 1; number <= 4; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
      }
      for (final number in [3, 1, 4]) {
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }

      await _execute(repository, MarkIntentionFavorite(_id(2)));

      expect(await _order(repository), [
        _uuid(3),
        _uuid(1),
        _uuid(4),
        _uuid(2),
      ]);
    });

    test('снятая и поставленная заново отметка снова последняя', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }

      await _execute(repository, UnmarkIntentionFavorite(_id(1)));
      expect(await _order(repository), [_uuid(2), _uuid(3)]);

      await _execute(repository, MarkIntentionFavorite(_id(1)));
      expect(await _order(repository), [_uuid(2), _uuid(3), _uuid(1)]);
    });

    test('повторная отметка не меняет место', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }

      await _execute(repository, MarkIntentionFavorite(_id(1)));

      expect(await _order(repository), [_uuid(1), _uuid(2), _uuid(3)]);
    });
  });

  group('Состав списка', () {
    test('неизбранные намерения не входят в список', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
      }
      await _execute(repository, MarkIntentionFavorite(_id(2)));

      final snapshot = await _favorites(repository);

      expect(snapshot.items.map(_rowId), [_uuid(2)]);
      expect(snapshot.archivedCount, 0);
    });

    test(
      'одноимённые намерения — отдельные строки, каждое ровно один раз',
      () async {
        _insertIntention(raw, number: 1, title: 'Гулять');
        _insertIntention(raw, number: 2, title: 'Гулять');
        _insertIntention(raw, number: 3, title: 'Гулять');
        await _execute(repository, MarkIntentionFavorite(_id(3)));
        await _execute(repository, MarkIntentionFavorite(_id(1)));

        final snapshot = await _favorites(repository);

        expect(snapshot.items.map(_rowId), [_uuid(3), _uuid(1)]);
        expect(snapshot.items.map((row) => row.title), ['Гулять', 'Гулять']);
      },
    );

    test('архивированное избранное скрыто и учтено числом', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }

      await _execute(repository, ArchiveIntention(_id(2)));

      final snapshot = await _favorites(repository);
      expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(3)]);
      expect(snapshot.archivedCount, 1);
    });

    test('восстановленное избранное стоит на своём месте', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }
      await _execute(repository, ArchiveIntention(_id(2)));
      // Новая отметка занимает место после архивированного намерения.
      _insertIntention(raw, number: 4, title: 'Намерение 4');
      await _execute(repository, MarkIntentionFavorite(_id(4)));

      await _execute(repository, RestoreIntention(_id(2)));

      final snapshot = await _favorites(repository);
      expect(snapshot.items.map(_rowId), [
        _uuid(1),
        _uuid(2),
        _uuid(3),
        _uuid(4),
      ]);
      expect(snapshot.archivedCount, 0);
    });

    test(
      'отметка архивированного намерения проявляется после восстановления',
      () async {
        _insertIntention(raw, number: 1, title: 'А');
        _insertIntention(raw, number: 2, title: 'Б');
        _insertIntention(raw, number: 3, title: 'Г', isArchived: true);
        await _execute(repository, MarkIntentionFavorite(_id(1)));
        await _execute(repository, MarkIntentionFavorite(_id(2)));

        await _execute(repository, MarkIntentionFavorite(_id(3)));
        final hidden = await _favorites(repository);
        expect(hidden.items.map(_rowId), [_uuid(1), _uuid(2)]);
        expect(hidden.archivedCount, 1);

        await _execute(repository, RestoreIntention(_id(3)));
        expect(await _order(repository), [_uuid(1), _uuid(2), _uuid(3)]);
      },
    );

    test('все избранные архивированы: пустой список с их числом', () async {
      _insertIntention(raw, number: 1, title: 'Первое', isArchived: true);
      _insertIntention(raw, number: 2, title: 'Второе', isArchived: true);
      _insertIntention(raw, number: 3, title: 'Неизбранное');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 2);

      final snapshot = await _favorites(repository);

      expect(snapshot.items, isEmpty);
      expect(snapshot.archivedCount, 2);
    });
  });

  group('Строка списка', () {
    test('несёт название без изменения и готовность к действию', () async {
      _insertIntention(
        raw,
        number: 1,
        title: 'Гулять  По Утрам',
        isActionReady: true,
      );
      _insertIntention(raw, number: 2, title: 'читать');
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 2);

      final snapshot = await _favorites(repository);

      expect(snapshot.items.map((row) => row.title), [
        'Гулять  По Утрам',
        'читать',
      ]);
      expect(snapshot.items.map((row) => row.readiness), [
        IntentionReadiness.ready,
        IntentionReadiness.notReady,
      ]);
    });

    test('переименование меняет строку без изменения порядка', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }

      await _execute(
        repository,
        UpdateIntention(id: _id(2), title: 'Аааа', description: 'Описание'),
      );

      final snapshot = await _favorites(repository);
      expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(2), _uuid(3)]);
      expect(snapshot.items[1].title, 'Аааа');
    });

    test('изменение готовности меняет строку без изменения порядка', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }

      await _execute(repository, EnableIntentionReadiness(_id(1)));
      final enabled = await _favorites(repository);
      expect(enabled.items.map(_rowId), [_uuid(1), _uuid(2), _uuid(3)]);
      expect(enabled.items.map((row) => row.readiness), [
        IntentionReadiness.ready,
        IntentionReadiness.notReady,
        IntentionReadiness.notReady,
      ]);

      await _execute(repository, DisableIntentionReadiness(_id(1)));
      final disabled = await _favorites(repository);
      expect(disabled.items.map(_rowId), [_uuid(1), _uuid(2), _uuid(3)]);
      expect(
        disabled.items.map((row) => row.readiness),
        everyElement(IntentionReadiness.notReady),
      );
    });

    test(
      'физическое удаление убирает строку и сохраняет порядок остальных',
      () async {
        for (var number = 1; number <= 4; number++) {
          _insertIntention(raw, number: number, title: 'Намерение $number');
        }
        for (final number in [4, 2, 1, 3]) {
          await _execute(repository, MarkIntentionFavorite(_id(number)));
        }

        await _execute(repository, DeleteIntention(_id(2)));

        final snapshot = await _favorites(repository);
        expect(snapshot.items.map(_rowId), [_uuid(4), _uuid(1), _uuid(3)]);
        expect(snapshot.archivedCount, 0);
      },
    );

    test('несёт точное число активных связей обоих направлений', () async {
      for (var number = 1; number <= 5; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
      }
      await _execute(repository, MarkIntentionFavorite(_id(1)));
      await _execute(repository, MarkIntentionFavorite(_id(5)));
      await _execute(repository, MarkIntentionFavorite(_id(2)));
      // У намерения 1 три активные связи и одна архивированная; у 2 — одна
      // активная; у 5 связей нет.
      await _relate(repository, source: 1, related: 2);
      await _relate(repository, source: 3, related: 1);
      await _relate(
        repository,
        source: 1,
        related: 3,
        type: LongTermRelationType.can,
      );
      final archived = await _relate(repository, source: 4, related: 1);
      await _executeRelation(repository, ArchiveLongTermRelation(archived));

      final snapshot = await _favorites(repository);

      expect(snapshot.items.map(_rowId), [_uuid(1), _uuid(5), _uuid(2)]);
      expect(snapshot.items.map((row) => row.activeRelationCount), [3, 0, 1]);
    });
  });

  group('Согласованность снимка', () {
    test('список и счётчики связей относятся к одной ревизии', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
        await _execute(repository, MarkIntentionFavorite(_id(number)));
      }
      await _relate(repository, source: 1, related: 2);
      final confirmed = await repository.execute(
        CreateLongTermRelation(
          sourceIntentionId: _id(2),
          relatedIntentionId: _id(3),
          type: LongTermRelationType.need,
          priority: RelationPriority.p1,
          description: null,
        ),
      );
      final confirmedRevision =
          (confirmed
                  as GraphCommandSucceeded<
                    LongTermRelationCommandSuccess,
                    LongTermRelationCommandFailure
                  >)
              .value
              .revision;

      final snapshot = await _favorites(repository);

      expect(
        snapshot.revision.compareTo(confirmedRevision),
        GraphRevisionOrder.same,
      );
      for (final row in snapshot.items) {
        final counts = await repository.getRelationCounts(row.id);
        final counted =
            (counts as ResultSuccess<GraphSnapshot<RelationCounts>>).value;
        expect(
          counted.revision.compareTo(snapshot.revision),
          GraphRevisionOrder.same,
        );
        expect(row.activeRelationCount, counted.value.active);
      }
    });

    test('чтение не пишет на соединение и не продвигает ревизию', () async {
      for (var number = 1; number <= 3; number++) {
        _insertIntention(raw, number: number, title: 'Намерение $number');
      }
      await _execute(repository, MarkIntentionFavorite(_id(1)));
      await _execute(repository, MarkIntentionFavorite(_id(3)));
      await _execute(repository, ArchiveIntention(_id(3)));
      final storedBefore = storedFavoriteMarks(raw);
      final changesBefore = _connectionChanges(raw);
      trace.writes.clear();

      final first = await _favorites(repository);
      final second = await _favorites(repository);

      expect(trace.writes, isEmpty);
      expect(_connectionChanges(raw), changesBefore);
      expect(storedFavoriteMarks(raw), storedBefore);
      expect(
        second.revision.compareTo(first.revision),
        GraphRevisionOrder.same,
      );
      expect(second.items.map(_rowId), first.items.map(_rowId));
      expect(second.archivedCount, first.archivedCount);
    });

    test('подтверждённое изменение даёт снимок новой ревизии', () async {
      _insertIntention(raw, number: 1, title: 'Первое');
      _insertIntention(raw, number: 2, title: 'Второе');
      await _execute(repository, MarkIntentionFavorite(_id(1)));
      final before = await _favorites(repository);

      await _execute(repository, MarkIntentionFavorite(_id(2)));
      final after = await _favorites(repository);

      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
      expect(before.items.map(_rowId), [_uuid(1)]);
      expect(after.items.map(_rowId), [_uuid(1), _uuid(2)]);
    });

    test('снимок неизменяем', () async {
      _insertIntention(raw, number: 1, title: 'Первое');
      await _execute(repository, MarkIntentionFavorite(_id(1)));

      final snapshot = await _favorites(repository);

      expect(() => snapshot.items.clear(), throwsUnsupportedError);
    });
  });
}

/// Записи одного соединения в порядке выполнения.
final class _WriteTrace extends LocalDatabaseConnectionObserver {
  final writes = <String>[];

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

String _rowId(FavoriteIntentionRow row) => row.id.toCanonicalString();

/// Намерение фикстуры: время создания растёт с номером.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  required String title,
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
      null,
      isActionReady ? 1 : 0,
      isArchived ? 1 : 0,
      timestamp,
      timestamp,
    ],
  );
}

int _connectionChanges(sqlite.Database database) =>
    database.select('SELECT total_changes() AS count').single['count'] as int;

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}

/// Идентификаторы строк списка в порядке снимка.
Future<List<String>> _order(DriftPersonalGraphRepository repository) async =>
    (await _favorites(repository)).items.map(_rowId).toList();

Future<void> _execute(
  DriftPersonalGraphRepository repository,
  IntentionCommand command,
) async {
  expect(
    await repository.execute(command),
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
    reason: '${command.runtimeType}',
  );
}

Future<void> _executeRelation(
  DriftPersonalGraphRepository repository,
  LongTermRelationCommand command,
) async {
  expect(
    await repository.execute(command),
    isA<
      GraphCommandSucceeded<
        LongTermRelationCommandSuccess,
        LongTermRelationCommandFailure
      >
    >(),
    reason: '${command.runtimeType}',
  );
}

/// Создаёт активную долговременную связь и возвращает её идентификатор.
Future<LongTermRelationId> _relate(
  DriftPersonalGraphRepository repository, {
  required int source,
  required int related,
  LongTermRelationType type = LongTermRelationType.need,
}) async {
  final result = await repository.execute(
    CreateLongTermRelation(
      sourceIntentionId: _id(source),
      relatedIntentionId: _id(related),
      type: type,
      priority: RelationPriority.p2,
      description: null,
    ),
  );
  return switch (result) {
    GraphCommandSucceeded(
      value: ConfirmedGraphResult(:final LongTermRelationCreated value),
    ) =>
      value.relation.id,
    final other => fail('Связь не создана: $other'),
  };
}
