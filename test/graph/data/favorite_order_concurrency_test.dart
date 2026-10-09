import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, TagAssignment;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/favorite_storage_fixture.dart';
import '../../support/in_memory_diagnostics_sink.dart';

typedef _IntentionResult =
    Result<ConfirmedGraphResult<IntentionCommandSuccess>>;

/// Сохранённая отметка фикстуры: номер намерения и его место.
typedef _Mark = (int number, int position);

/// Места фикстуры до пересекающихся операций: избранные 1, архивированное
/// 2, 3 и 4 идут в этом порядке с пропусками мест, а 5 не отмечено.
const _initialMarks = <_Mark>[(1, 2), (2, 5), (3, 6), (4, 9)];

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late _SqlGate gate;
  late DriftPersonalGraphRepository repository;
  late GraphRevision initialRevision;

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
      _SequentialIntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 3, 12),
      InMemoryDiagnosticsSink(),
    );
    _seedFavorites(raw);
    initialRevision = (await _favorites(repository)).revision;
  });

  tearDown(() async {
    gate.release();
    await database.close();
  });

  /// Запускает [second], пока [first] остановлена на своём первом чтении
  /// внутри транзакции, и возвращает оба результата. Первой подтверждается
  /// операция, начатая первой.
  Future<(TFirst, TSecond)> overlap<TFirst, TSecond>(
    Future<TFirst> Function() first,
    Future<TSecond> Function() second,
  ) async {
    gate.arm();
    final firstResult = first();
    await gate.entered;
    var secondCompleted = false;
    final secondResult = second().whenComplete(() => secondCompleted = true);
    await pumpEventQueue();
    // Вторая операция уже запущена, но не обгоняет незавершённую первую.
    expect(secondCompleted, isFalse);
    gate.release();
    return (await firstResult, await secondResult);
  }

  Future<FavoriteOrderCommandResult> move(int number, {required int after}) =>
      repository.execute(
        MoveFavoriteIntention(
          intentionId: _id(number),
          placement: AfterFavoritePlacement(_id(after)),
        ),
      );

  Future<_IntentionResult> run(IntentionCommand command) =>
      repository.execute(command);

  /// Проверяет сохранённые места всех избранных намерений, список Главной и
  /// то, что подтверждение [lastRevision] осталось текущей ревизией графа.
  Future<void> expectConfirmedState({
    required List<_Mark> marks,
    required List<int> visible,
    required GraphRevision lastRevision,
  }) async {
    expect(storedFavoriteMarks(raw), [
      for (final (number, position) in marks) (_uuid(number), position),
    ]);
    final snapshot = await _favorites(repository);
    expect(snapshot.items.map((row) => row.id), visible.map(_id));
    expect(snapshot.revision.compareTo(lastRevision), GraphRevisionOrder.same);
    expect(_foreignKeyViolations(raw), isEmpty);
  }

  group('Перестановка и отметка нового намерения', () {
    test('отметка, подтверждённая после перестановки, ставит намерение в '
        'конец нового порядка', () async {
      final (moveResult, markResult) = await overlap(
        () => move(4, after: 1),
        () => run(MarkIntentionFavorite(_id(5))),
      );

      final moved = _moved(moveResult);
      final marked = _updated(markResult);
      expect(marked.after.summary.favoriteMark, FavoriteMark.favorite);
      _expectNewer(moved.revision, than: initialRevision);
      _expectNewer(marked.revision, than: moved.revision);
      await expectConfirmedState(
        marks: [(1, 1), (4, 2), (2, 3), (3, 4), (5, 5)],
        visible: [1, 4, 3, 5],
        lastRevision: marked.revision,
      );
    });
  });

  group('Создание избранного намерения с тегом и пересекающиеся операции', () {
    // Создаваемое намерение получает номер 6, его единственный тег — «Дом».
    const created = 6;
    final homeTagId = _tagId(_homeTagNumber);

    setUp(() async {
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _uuid(_homeTagNumber),
        'Дом',
      ]);
      initialRevision = (await _favorites(repository)).revision;
    });

    Future<_IntentionResult> create() => run(
      CreateIntention.withInitialState(
        title: 'Новое избранное',
        description: null,
        readiness: IntentionReadiness.notReady,
        favoriteMark: FavoriteMark.favorite,
        tagIds: [homeTagId],
      ),
    );

    Future<TagCommandResult> deleteHomeTag() =>
        repository.execute(DeleteTag(homeTagId));

    test('создание, подтверждённое раньше отметки, занимает место перед '
        'отмеченным позже намерением', () async {
      final (createResult, markResult) = await overlap(
        create,
        () => run(MarkIntentionFavorite(_id(5))),
      );

      final createdResult = _created(createResult, tagId: homeTagId);
      final marked = _updated(markResult);
      _expectNewer(createdResult.revision, than: initialRevision);
      _expectNewer(marked.revision, than: createdResult.revision);
      await expectConfirmedState(
        marks: [..._initialMarks, (created, 10), (5, 11)],
        visible: [1, 3, 4, created, 5],
        lastRevision: marked.revision,
      );
    });

    test('отметка, подтверждённая раньше, ставит создаваемое намерение после '
        'отмеченного', () async {
      final (markResult, createResult) = await overlap(
        () => run(MarkIntentionFavorite(_id(5))),
        create,
      );

      final marked = _updated(markResult);
      final createdResult = _created(createResult, tagId: homeTagId);
      _expectNewer(marked.revision, than: initialRevision);
      _expectNewer(createdResult.revision, than: marked.revision);
      await expectConfirmedState(
        marks: [..._initialMarks, (5, 10), (created, 11)],
        visible: [1, 3, 4, 5, created],
        lastRevision: createdResult.revision,
      );
    });

    test('удаление тега, подтверждённое раньше, отклоняет всё создание '
        'отсутствием тега без намерения и места', () async {
      final (deleteResult, createResult) = await overlap(deleteHomeTag, create);

      final deletedRevision = _tagDeleted(deleteResult, homeTagId);
      _expectNewer(deletedRevision, than: initialRevision);
      expect(
        createResult,
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>()
            .having(
              (result) => result.failure,
              'причина',
              isA<IntentionCreationTagsMissingFailure>().having(
                (failure) => failure.missingTagIds,
                'отсутствующие теги',
                {homeTagId},
              ),
            ),
      );
      expect(_storedIntentionIds(raw), _uuids([1, 2, 3, 4, 5]));
      expect(_storedTagAssignments(raw), isEmpty);
      await expectConfirmedState(
        marks: _initialMarks,
        visible: [1, 3, 4],
        lastRevision: deletedRevision,
      );
    });
  });
}

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

/// Номер тега, выбранного при создании намерения.
const _homeTagNumber = 301;

TagId _tagId(int number) => switch (TagId.decode(_uuid(number))) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw ArgumentError.value(number, 'number'),
};

/// Выдаёт созданным намерениям номера по порядку после фикстуры 1–5.
final class _SequentialIntentionIdGenerator implements IntentionIdGenerator {
  var _next = 6;

  @override
  IntentionId generate() => _id(_next++);
}

List<String> _uuids(Iterable<int> numbers) => numbers.map(_uuid).toList();

IntentionId _id(int number) => switch (IntentionId.decode(_uuid(number))) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(number, 'number'),
};

/// Намерения 1–5 без связей, из которых 2 архивировано, и отметки
/// [_initialMarks].
void _seedFavorites(sqlite.Database database) {
  for (var number = 1; number <= 5; number++) {
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
        number == 2 ? 1 : 0,
        timestamp,
        timestamp,
      ],
    );
  }
  for (final (number, position) in _initialMarks) {
    storeFavoriteMark(database, intentionId: _uuid(number), position: position);
  }
}

Future<FavoriteIntentionsSnapshot> _favorites(
  DriftPersonalGraphRepository repository,
) async {
  final result = await repository.getFavoriteIntentions();
  expect(result, isA<FavoriteIntentionsSuccess>());
  return (result as FavoriteIntentionsSuccess).value;
}

ConfirmedGraphResult<FavoriteOrderCommandSuccess> _orderConfirmed(
  FavoriteOrderCommandResult result,
) => switch (result) {
  FavoriteOrderCommandSucceeded(:final value) => value,
  FavoriteOrderCommandFailed(:final failure) => fail(
    'Ожидался успех перестановки, получен ${failure.runtimeType}.',
  ),
};

/// Перестановка подтверждена фактическим изменением порядка.
ConfirmedGraphResult<FavoriteOrderCommandSuccess> _moved(
  FavoriteOrderCommandResult result,
) {
  final confirmed = _orderConfirmed(result);
  expect(confirmed.value, isA<FavoriteOrderMoved>());
  return confirmed;
}

ConfirmedGraphResult<IntentionCommandSuccess> _intentionConfirmed(
  _IntentionResult result,
) {
  expect(
    result,
    isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
  );
  return (result
          as ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>)
      .value;
}

/// Команда намерения подтверждена изменением сохранённого намерения.
({GraphRevision revision, IntentionCatalogEntrySnapshot after}) _updated(
  _IntentionResult result,
) {
  final confirmed = _intentionConfirmed(result);
  final mutation = confirmed.value.catalogMutation;
  expect(mutation, isA<IntentionCatalogUpdated>());
  return (
    revision: confirmed.revision,
    after: (mutation as IntentionCatalogUpdated).after,
  );
}

/// Создание подтверждено одним целым пакетом: снимок нового избранного
/// намерения с тегом [tagId] и факт этого назначения на той же ревизии.
({GraphRevision revision, IntentionCatalogEntrySnapshot entry}) _created(
  _IntentionResult result, {
  required TagId tagId,
}) {
  final confirmed = _intentionConfirmed(result);
  final mutation = confirmed.value.catalogMutation;
  expect(mutation, isA<IntentionCatalogCreated>());
  final entry = (mutation as IntentionCatalogCreated).entry;
  final id = entry.summary.id;
  expect(entry.summary.favoriteMark, FavoriteMark.favorite);
  expect(entry.summary.tags.map((tag) => tag.id), [tagId]);
  expect(confirmed.changes, [
    same(mutation),
    isA<TagAssignmentChangedChange>()
        .having(
          (change) => change.assignment,
          'назначение',
          TagAssignment(tagId: tagId, intentionId: id),
        )
        .having(
          (change) => change.state,
          'состояние',
          TagAssignmentState.assigned,
        ),
  ]);
  return (revision: confirmed.revision, entry: entry);
}

/// Удаление тега [tagId] подтверждено; возвращает его ревизию.
GraphRevision _tagDeleted(TagCommandResult result, TagId tagId) =>
    switch (result) {
      TagCommandSucceeded(:final value) => () {
        expect(
          value.value,
          isA<TagDeleted>().having((deleted) => deleted.tagId, 'тег', tagId),
        );
        return value.revision;
      }(),
      TagCommandFailed(:final failure) => fail(
        'Ожидалось удаление тега, получен ${failure.runtimeType}.',
      ),
    };

void _expectNewer(GraphRevision revision, {required GraphRevision than}) =>
    expect(revision.compareTo(than), GraphRevisionOrder.newer);

List<(String, String)> _storedTagAssignments(sqlite.Database database) => [
  for (final row in database.select(
    'SELECT tag_id, intention_id FROM tag_assignments ORDER BY 1, 2',
  ))
    (row['tag_id'] as String, row['intention_id'] as String),
];

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
