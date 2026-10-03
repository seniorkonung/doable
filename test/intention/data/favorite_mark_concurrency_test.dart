import 'dart:async';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

typedef _CommandResult = Result<ConfirmedGraphResult<IntentionCommandSuccess>>;

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _SqlGate gate;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    gate = _SqlGate();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        gate,
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

  tearDown(() async {
    gate.release();
    await database.close();
  });

  /// Запускает [second], пока [first] остановлена на своём первом чтении
  /// внутри транзакции, и возвращает оба результата.
  Future<(_CommandResult, _CommandResult)> overlap(
    IntentionCommand first,
    IntentionCommand second,
  ) async {
    gate.arm();
    final firstResult = repository.execute(first);
    await gate.entered;
    final secondResult = repository.execute(second);
    gate.release();
    return (await firstResult, await secondResult);
  }

  group('Две одновременные отметки разных намерений', () {
    for (final firstNumber in [3, 4]) {
      final secondNumber = firstNumber == 3 ? 4 : 3;

      test(
        'подтверждаются обе, и каждое намерение занимает собственное '
        'место в конце: первой начата отметка намерения $firstNumber',
        () async {
          _insertIntention(raw, number: 1);
          _insertIntention(raw, number: 2, isArchived: true);
          _insertIntention(raw, number: 3);
          _insertIntention(raw, number: 4);
          storeFavoriteMark(raw, intentionId: _uuid(1), position: 2);
          storeFavoriteMark(raw, intentionId: _uuid(2), position: 5);

          final (first, second) = await overlap(
            MarkIntentionFavorite(_id(firstNumber)),
            MarkIntentionFavorite(_id(secondNumber)),
          );

          final firstConfirmed = _confirmed(first);
          final secondConfirmed = _confirmed(second);
          expect(storedFavoriteMarks(raw), [
            (_uuid(1), 2),
            (_uuid(2), 5),
            (_uuid(firstNumber), 6),
            (_uuid(secondNumber), 7),
          ]);
          // Каждая отметка подтверждена собственной ревизией в порядке
          // последовательного выполнения.
          expect(
            secondConfirmed.revision.compareTo(firstConfirmed.revision),
            GraphRevisionOrder.newer,
          );
          for (final confirmed in [firstConfirmed, secondConfirmed]) {
            final mutation =
                (confirmed.value as IntentionSaved).catalogMutation
                    as IntentionCatalogUpdated;
            expect(
              mutation.before.summary.favoriteMark,
              FavoriteMark.notFavorite,
            );
            expect(mutation.after.summary.favoriteMark, FavoriteMark.favorite);
          }
          expect(_foreignKeyViolations(raw), isEmpty);
        },
      );
    }

    test('много одновременных отметок получают однозначные места подряд '
        'в порядке запуска', () async {
      const count = 20;
      for (var number = 1; number <= count; number++) {
        _insertIntention(raw, number: number);
      }

      final results = await Future.wait([
        for (var number = count; number >= 1; number--)
          repository.execute(MarkIntentionFavorite(_id(number))),
      ]);

      results.forEach(_confirmed);
      expect(storedFavoriteMarks(raw), [
        for (var place = 1; place <= count; place++)
          (_uuid(count + 1 - place), place),
      ]);
    });
  });

  group('Отметка, пересекающаяся с физическим удалением того же намерения', () {
    test(
      'подтверждённая раньше отметка удаляется вместе с намерением',
      () async {
        _insertIntention(raw, number: 1);
        _insertIntention(raw, number: 2);
        _insertIntention(raw, number: 3);
        storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
        storeFavoriteMark(raw, intentionId: _uuid(3), position: 4);

        final (mark, delete) = await overlap(
          MarkIntentionFavorite(_id(2)),
          DeleteIntention(_id(2)),
        );

        final marked = _confirmed(mark);
        final deleted = _confirmed(delete);
        final markMutation =
            (marked.value as IntentionSaved).catalogMutation
                as IntentionCatalogUpdated;
        expect(markMutation.after.summary.favoriteMark, FavoriteMark.favorite);
        // Удаление видит уже подтверждённую отметку: его снимок несёт её.
        final deleteMutation =
            (deleted.value as IntentionDeleted).catalogMutation
                as IntentionCatalogDeleted;
        expect(
          deleteMutation.entry.summary.favoriteMark,
          FavoriteMark.favorite,
        );
        expect(
          deleted.revision.compareTo(marked.revision),
          GraphRevisionOrder.newer,
        );
        expect(_storedIntentionIds(raw), [_uuid(1), _uuid(3)]);
        expect(storedFavoriteMarks(raw), [(_uuid(1), 1), (_uuid(3), 4)]);
        expect(_foreignKeyViolations(raw), isEmpty);
      },
    );

    test('после подтверждённого раньше удаления отметка возвращает '
        'отсутствие намерения', () async {
      _insertIntention(raw, number: 1);
      _insertIntention(raw, number: 2);
      _insertIntention(raw, number: 3);
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
      storeFavoriteMark(raw, intentionId: _uuid(3), position: 4);

      final (delete, mark) = await overlap(
        DeleteIntention(_id(2)),
        MarkIntentionFavorite(_id(2)),
      );

      final deleted = _confirmed(delete);
      final deleteMutation =
          (deleted.value as IntentionDeleted).catalogMutation
              as IntentionCatalogDeleted;
      expect(
        deleteMutation.entry.summary.favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(
        mark,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (result) => result.failure,
              'отказ',
              isA<IntentionNotFoundFailure>(),
            ),
      );
      // Отказавшая отметка не создаёт ни намерения, ни отметки.
      expect(_storedIntentionIds(raw), [_uuid(1), _uuid(3)]);
      expect(storedFavoriteMarks(raw), [(_uuid(1), 1), (_uuid(3), 4)]);
      expect(_foreignKeyViolations(raw), isEmpty);
    });

    test('снятие отметки после подтверждённого раньше удаления избранного '
        'намерения возвращает отсутствие намерения', () async {
      _insertIntention(raw, number: 1);
      _insertIntention(raw, number: 2);
      storeFavoriteMark(raw, intentionId: _uuid(1), position: 1);
      storeFavoriteMark(raw, intentionId: _uuid(2), position: 2);

      final (delete, unmark) = await overlap(
        DeleteIntention(_id(2)),
        UnmarkIntentionFavorite(_id(2)),
      );

      _confirmed(delete);
      expect(
        unmark,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (result) => result.failure,
              'отказ',
              isA<IntentionNotFoundFailure>(),
            ),
      );
      expect(_storedIntentionIds(raw), [_uuid(1)]);
      expect(storedFavoriteMarks(raw), [(_uuid(1), 1)]);
      expect(_foreignKeyViolations(raw), isEmpty);
    });
  });
}

ConfirmedGraphResult<IntentionCommandSuccess> _confirmed(
  _CommandResult result,
) {
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  return (result
          as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
      .value;
}

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

/// Намерение фикстуры без связей: его физическое удаление допустимо.
void _insertIntention(
  sqlite.Database database, {
  required int number,
  bool isArchived = false,
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
    'is_archived, created_at, updated_at) VALUES (?, ?, NULL, 0, ?, ?, ?)',
    [
      _uuid(number),
      'Намерение $number',
      isArchived ? 1 : 0,
      timestamp,
      timestamp,
    ],
  );
}

List<String> _storedIntentionIds(sqlite.Database database) => [
  for (final row in database.select('SELECT id FROM intentions ORDER BY id'))
    row['id'] as String,
];

List<Map<String, Object?>> _foreignKeyViolations(sqlite.Database database) => [
  for (final row in database.select('PRAGMA foreign_key_check')) {...row},
];

/// Останавливает первое чтение после [arm] до [release]: вторая операция
/// запускается, пока первая находится внутри своей транзакции.
final class _SqlGate extends LocalDatabaseConnectionObserver {
  Completer<void> _entered = Completer<void>();
  Completer<void> _released = Completer<void>();
  bool _armed = false;

  Future<void> get entered => _entered.future;

  void arm() {
    _entered = Completer<void>();
    _released = Completer<void>();
    _armed = true;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (!_armed || statement.operation != LocalDatabaseSqlOperation.select) {
      return;
    }
    _armed = false;
    _entered.complete();
    await _released.future;
  }
}
