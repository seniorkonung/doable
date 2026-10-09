import 'dart:async';

import 'package:doable/src/data/local/app_database.dart'
    hide Intention, TagAssignment;
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_change.dart';
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

void _expectNewer(GraphRevision revision, {required GraphRevision than}) =>
    expect(revision.compareTo(than), GraphRevisionOrder.newer);

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
