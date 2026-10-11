import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/local_database_harness.dart';

const _firstIntention = '018f0b5d-6b2e-7c80-8000-000000000001';
const _secondIntention = '018f0b5d-6b2e-7c80-8000-000000000002';
const _thirdIntention = '018f0b5d-6b2e-7c80-8000-000000000003';
const _missingIntention = '018f0b5d-6b2e-7c80-8000-000000000004';

void main() {
  late LocalDatabaseHarness harness;
  late sqlite.Database raw;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    await harness.openReadyDatabase(setup: (connection) => raw = connection);
    raw.execute(
      '''INSERT INTO intentions (id, title, is_archived, created_at, updated_at)
         VALUES (?, ?, 0, 1, 1), (?, ?, 1, 1, 1), (?, ?, 0, 1, 1)''',
      [
        _firstIntention,
        'Первое',
        _secondIntention,
        'Архивированное',
        _thirdIntention,
        'Третье',
      ],
    );
  });

  tearDown(() => harness.dispose());

  test('отклоняет отметку отсутствующего намерения', () {
    _addFavorite(raw, _firstIntention, 1);

    for (final intentionId in [_missingIntention, null]) {
      expect(
        () => _addFavorite(raw, intentionId, 2),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Отметка возможна только у существующего намерения.',
      );
    }

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('отклоняет вторую отметку того же намерения', () {
    _addFavorite(raw, _firstIntention, 1);

    expect(
      () => _addFavorite(raw, _firstIntention, 2),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('отклоняет второе намерение на занятом месте', () {
    _addFavorite(raw, _firstIntention, 1);
    _addFavorite(raw, _secondIntention, 2);

    expect(
      () => _addFavorite(raw, _thirdIntention, 1),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute(
        'UPDATE favorite_intentions SET position = 1 WHERE intention_id = ?',
        [_secondIntention],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(_favorites(raw), [(_firstIntention, 1), (_secondIntention, 2)]);
  });

  test('отклоняет отсутствующее, неположительное и нецелое место', () {
    _addFavorite(raw, _firstIntention, 1);

    // Три проверки ограничения: обязательность, тип и положительность
    // (граница 0); прочие значения проходят те же проверки.
    for (final position in <Object?>[null, 0, 1.5]) {
      expect(
        () => _addFavorite(raw, _secondIntention, position),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Место $position недопустимо при отметке.',
      );
      expect(
        () => raw.execute(
          'UPDATE favorite_intentions SET position = ? WHERE intention_id = ?',
          [position, _firstIntention],
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Место $position недопустимо при изменении.',
      );
    }

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('отклоняет недопустимую запись целиком вместе с допустимыми', () {
    _addFavorite(raw, _firstIntention, 1);

    expect(
      () => raw.execute(
        'INSERT INTO favorite_intentions (intention_id, position) '
        'VALUES (?, 2), (?, 1)',
        [_secondIntention, _thirdIntention],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );
    expect(
      () => raw.execute(
        'INSERT INTO favorite_intentions (intention_id, position) '
        'VALUES (?, 2), (?, 3)',
        [_secondIntention, _missingIntention],
      ),
      throwsA(isA<sqlite.SqliteException>()),
    );

    expect(_favorites(raw), [(_firstIntention, 1)]);
  });

  test('запрещает подменять намерение отметки и допускает смену места', () {
    _addFavorite(raw, _firstIntention, 1);
    _addFavorite(raw, _secondIntention, 2);

    for (final intentionId in [_thirdIntention, _missingIntention, null]) {
      expect(
        () => raw.execute(
          'UPDATE favorite_intentions SET intention_id = ? '
          'WHERE intention_id = ?',
          [intentionId, _firstIntention],
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'Отметка не переносится на $intentionId.',
      );
    }
    expect(_favorites(raw), [(_firstIntention, 1), (_secondIntention, 2)]);

    raw.execute(
      'UPDATE favorite_intentions SET position = 5 WHERE intention_id = ?',
      [_firstIntention],
    );
    raw.execute(
      'UPDATE favorite_intentions SET intention_id = ?, position = 1 '
      'WHERE intention_id = ?',
      [_secondIntention, _secondIntention],
    );

    expect(_favorites(raw), [(_secondIntention, 1), (_firstIntention, 5)]);
  });
}

void _addFavorite(sqlite.Database db, String? intentionId, Object? position) {
  db.execute(
    'INSERT INTO favorite_intentions (intention_id, position) VALUES (?, ?)',
    [intentionId, position],
  );
}

List<(Object?, Object?)> _favorites(sqlite.Database db) => [
  for (final row in db.select(
    'SELECT intention_id, position FROM favorite_intentions ORDER BY position',
  ))
    (row['intention_id'], row['position']),
];
