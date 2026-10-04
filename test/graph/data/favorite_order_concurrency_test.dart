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
import 'package:doable/src/tag/application/tag_assignments.dart';
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

    test('перестановка, подтверждённая после отметки, сохраняет отмеченное '
        'намерение последним', () async {
      final (markResult, moveResult) = await overlap(
        () => run(MarkIntentionFavorite(_id(5))),
        () => move(4, after: 1),
      );

      final marked = _updated(markResult);
      final moved = _moved(moveResult);
      expect(marked.after.summary.favoriteMark, FavoriteMark.favorite);
      _expectNewer(marked.revision, than: initialRevision);
      _expectNewer(moved.revision, than: marked.revision);
      await expectConfirmedState(
        marks: [(1, 1), (4, 2), (2, 3), (3, 4), (5, 5)],
        visible: [1, 4, 3, 5],
        lastRevision: moved.revision,
      );
    });

    test('перестановка после намерения, отмеченного позже, — конфликт без '
        'изменения порядка', () async {
      final (moveResult, markResult) = await overlap(
        () => move(4, after: 5),
        () => run(MarkIntentionFavorite(_id(5))),
      );

      _expectConflict(moveResult);
      final marked = _updated(markResult);
      _expectNewer(marked.revision, than: initialRevision);
      await expectConfirmedState(
        marks: [..._initialMarks, (5, 10)],
        visible: [1, 3, 4, 5],
        lastRevision: marked.revision,
      );
    });

    test('перестановка после намерения, отмеченного раньше, ставит '
        'перемещаемое намерение сразу за ним', () async {
      final (markResult, moveResult) = await overlap(
        () => run(MarkIntentionFavorite(_id(5))),
        () => move(4, after: 5),
      );

      final marked = _updated(markResult);
      final moved = _moved(moveResult);
      _expectNewer(moved.revision, than: marked.revision);
      await expectConfirmedState(
        marks: [(1, 1), (2, 2), (3, 3), (5, 4), (4, 5)],
        visible: [1, 3, 5, 4],
        lastRevision: moved.revision,
      );
    });
  });

  for (final participant in _Participant.values) {
    group('Перестановка и снятие отметки с ${participant.name}', () {
      test('снятие, подтверждённое после перестановки, убирает намерение из '
          'нового порядка без изменения остальных мест', () async {
        final (moveResult, unmarkResult) = await overlap(
          () => move(4, after: 1),
          () => run(UnmarkIntentionFavorite(_id(participant.number))),
        );

        final moved = _moved(moveResult);
        final unmarked = _updated(unmarkResult);
        expect(unmarked.after.summary.favoriteMark, FavoriteMark.notFavorite);
        _expectNewer(unmarked.revision, than: moved.revision);
        await expectConfirmedState(
          marks: _withoutMark([
            (1, 1),
            (4, 2),
            (2, 3),
            (3, 4),
          ], participant.number),
          visible: [1, 4, 3].where((n) => n != participant.number).toList(),
          lastRevision: unmarked.revision,
        );
      });

      test('снятие, подтверждённое раньше, отклоняет перестановку как '
          'конфликт без записи', () async {
        final (unmarkResult, moveResult) = await overlap(
          () => run(UnmarkIntentionFavorite(_id(participant.number))),
          () => move(4, after: 1),
        );

        final unmarked = _updated(unmarkResult);
        expect(unmarked.after.summary.favoriteMark, FavoriteMark.notFavorite);
        _expectConflict(moveResult);
        _expectNewer(unmarked.revision, than: initialRevision);
        await expectConfirmedState(
          marks: _withoutMark(_initialMarks, participant.number),
          visible: [1, 3, 4].where((n) => n != participant.number).toList(),
          lastRevision: unmarked.revision,
        );
      });
    });

    group('Перестановка и физическое удаление ${participant.name}', () {
      test('удаление, подтверждённое после перестановки, убирает отметку '
          'вместе с намерением без изменения остальных мест', () async {
        final (moveResult, deleteResult) = await overlap(
          () => move(4, after: 1),
          () => run(DeleteIntention(_id(participant.number))),
        );

        final moved = _moved(moveResult);
        final deleted = _deleted(deleteResult);
        expect(deleted.entry.summary.favoriteMark, FavoriteMark.favorite);
        _expectNewer(deleted.revision, than: moved.revision);
        expect(
          _storedIntentionIds(raw),
          _uuids([1, 2, 3, 4, 5].where((n) => n != participant.number)),
        );
        await expectConfirmedState(
          marks: _withoutMark([
            (1, 1),
            (4, 2),
            (2, 3),
            (3, 4),
          ], participant.number),
          visible: [1, 4, 3].where((n) => n != participant.number).toList(),
          lastRevision: deleted.revision,
        );
      });

      test('удаление, подтверждённое раньше, отклоняет перестановку как '
          'конфликт без записи', () async {
        final (deleteResult, moveResult) = await overlap(
          () => run(DeleteIntention(_id(participant.number))),
          () => move(4, after: 1),
        );

        final deleted = _deleted(deleteResult);
        _expectConflict(moveResult);
        _expectNewer(deleted.revision, than: initialRevision);
        expect(
          _storedIntentionIds(raw),
          _uuids([1, 2, 3, 4, 5].where((n) => n != participant.number)),
        );
        await expectConfirmedState(
          marks: _withoutMark(_initialMarks, participant.number),
          visible: [1, 3, 4].where((n) => n != participant.number).toList(),
          lastRevision: deleted.revision,
        );
      });
    });

    group('Перестановка и архивирование ${participant.name}', () {
      test('архивирование, подтверждённое после перестановки, сохраняет '
          'новое место архивированного намерения', () async {
        final (moveResult, archiveResult) = await overlap(
          () => move(4, after: 1),
          () => run(ArchiveIntention(_id(participant.number))),
        );

        final moved = _moved(moveResult);
        final archived = _updated(archiveResult);
        expect(
          archived.after.summary.archiveState,
          IntentionArchiveState.archived,
        );
        _expectNewer(archived.revision, than: moved.revision);
        await expectConfirmedState(
          marks: [(1, 1), (4, 2), (2, 3), (3, 4)],
          visible: [1, 4, 3].where((n) => n != participant.number).toList(),
          lastRevision: archived.revision,
        );
      });

      test('архивирование, подтверждённое раньше, не отклоняет '
          'перестановку', () async {
        final (archiveResult, moveResult) = await overlap(
          () => run(ArchiveIntention(_id(participant.number))),
          () => move(4, after: 1),
        );

        final archived = _updated(archiveResult);
        final moved = _moved(moveResult);
        _expectNewer(moved.revision, than: archived.revision);
        await expectConfirmedState(
          marks: [(1, 1), (4, 2), (2, 3), (3, 4)],
          visible: [1, 4, 3].where((n) => n != participant.number).toList(),
          lastRevision: moved.revision,
        );
      });
    });
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

    test('перестановка, подтверждённая после создания, сохраняет созданное '
        'намерение последним', () async {
      final (createResult, moveResult) = await overlap(
        create,
        () => move(4, after: 1),
      );

      final createdResult = _created(createResult, tagId: homeTagId);
      final moved = _moved(moveResult);
      _expectNewer(createdResult.revision, than: initialRevision);
      _expectNewer(moved.revision, than: createdResult.revision);
      await expectConfirmedState(
        marks: [(1, 1), (4, 2), (2, 3), (3, 4), (created, 5)],
        visible: [1, 4, 3, created],
        lastRevision: moved.revision,
      );
    });

    test('создание, подтверждённое после перестановки, занимает конец нового '
        'порядка', () async {
      final (moveResult, createResult) = await overlap(
        () => move(4, after: 1),
        create,
      );

      final moved = _moved(moveResult);
      final createdResult = _created(createResult, tagId: homeTagId);
      _expectNewer(moved.revision, than: initialRevision);
      _expectNewer(createdResult.revision, than: moved.revision);
      await expectConfirmedState(
        marks: [(1, 1), (4, 2), (2, 3), (3, 4), (created, 5)],
        visible: [1, 4, 3, created],
        lastRevision: createdResult.revision,
      );
    });

    test('перестановка после созданного раньше намерения ставит перемещаемое '
        'намерение сразу за ним', () async {
      final (createResult, moveResult) = await overlap(
        create,
        () => move(4, after: created),
      );

      final createdResult = _created(createResult, tagId: homeTagId);
      final moved = _moved(moveResult);
      _expectNewer(moved.revision, than: createdResult.revision);
      await expectConfirmedState(
        marks: [(1, 1), (2, 2), (3, 3), (created, 4), (4, 5)],
        visible: [1, 3, created, 4],
        lastRevision: moved.revision,
      );
    });

    test('перестановка после ещё не созданного намерения — конфликт без '
        'изменения порядка, а создание занимает конец', () async {
      final (moveResult, createResult) = await overlap(
        () => move(4, after: created),
        create,
      );

      _expectConflict(moveResult);
      final createdResult = _created(createResult, tagId: homeTagId);
      _expectNewer(createdResult.revision, than: initialRevision);
      await expectConfirmedState(
        marks: [..._initialMarks, (created, 10)],
        visible: [1, 3, 4, created],
        lastRevision: createdResult.revision,
      );
    });

    test('удаление тега, подтверждённое после создания, снимает назначение '
        'целиком созданного намерения без изменения его места', () async {
      final (createResult, deleteResult) = await overlap(create, deleteHomeTag);

      final createdResult = _created(createResult, tagId: homeTagId);
      final deletedRevision = _tagDeleted(deleteResult, homeTagId);
      _expectNewer(createdResult.revision, than: initialRevision);
      _expectNewer(deletedRevision, than: createdResult.revision);
      expect(_storedIntentionIds(raw), _uuids([1, 2, 3, 4, 5, created]));
      expect(_storedTagAssignments(raw), isEmpty);
      final assignments = await repository.getTagAssignments(_id(created));
      expect(assignments, isA<TagAssignmentsSuccess>());
      expect((assignments as TagAssignmentsSuccess).value.items, isEmpty);
      await expectConfirmedState(
        marks: [..._initialMarks, (created, 10)],
        visible: [1, 3, 4, created],
        lastRevision: deletedRevision,
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

  group('Перестановка, видимость которой меняет архивирование опоры', () {
    // Перемещение 3 после 1 не меняет список Главной, пока 1 активно: между
    // ними стоит только скрытое архивированное 2.
    test('архивирование, подтверждённое после перестановки без видимого '
        'изменения, оставляет все места прежними', () async {
      final (moveResult, archiveResult) = await overlap(
        () => move(3, after: 1),
        () => run(ArchiveIntention(_id(1))),
      );

      final unchanged = _unchanged(moveResult);
      final archived = _updated(archiveResult);
      expect(
        unchanged.revision.compareTo(initialRevision),
        GraphRevisionOrder.same,
      );
      _expectNewer(archived.revision, than: initialRevision);
      await expectConfirmedState(
        marks: _initialMarks,
        visible: [3, 4],
        lastRevision: archived.revision,
      );
    });

    test('перестановка после опоры, архивированной раньше, ставит намерение '
        'сразу за ней перед скрытым архивированным намерением', () async {
      final (archiveResult, moveResult) = await overlap(
        () => run(ArchiveIntention(_id(1))),
        () => move(3, after: 1),
      );

      final archived = _updated(archiveResult);
      final moved = _moved(moveResult);
      _expectNewer(moved.revision, than: archived.revision);
      await expectConfirmedState(
        marks: [(1, 1), (3, 2), (2, 3), (4, 4)],
        visible: [3, 4],
        lastRevision: moved.revision,
      );
    });
  });

  group('Перестановка и восстановление скрытого архивированного '
      'намерения', () {
    test('восстановление, подтверждённое после перестановки, возвращает '
        'намерение на его место в новом порядке', () async {
      final (moveResult, restoreResult) = await overlap(
        () => move(4, after: 1),
        () => run(RestoreIntention(_id(2))),
      );

      final moved = _moved(moveResult);
      final restored = _updated(restoreResult);
      expect(restored.after.summary.archiveState, IntentionArchiveState.active);
      _expectNewer(restored.revision, than: moved.revision);
      await expectConfirmedState(
        marks: [(1, 1), (4, 2), (2, 3), (3, 4)],
        visible: [1, 4, 2, 3],
        lastRevision: restored.revision,
      );
    });

    test('перестановка, подтверждённая после восстановления, сохраняет '
        'место восстановленного намерения относительно остальных', () async {
      final (restoreResult, moveResult) = await overlap(
        () => run(RestoreIntention(_id(2))),
        () => move(4, after: 1),
      );

      final restored = _updated(restoreResult);
      final moved = _moved(moveResult);
      _expectNewer(moved.revision, than: restored.revision);
      await expectConfirmedState(
        marks: [(1, 1), (4, 2), (2, 3), (3, 4)],
        visible: [1, 4, 2, 3],
        lastRevision: moved.revision,
      );
    });

    test('восстановление, подтверждённое после перестановки без видимого '
        'изменения, возвращает намерение на прежнее место', () async {
      final (moveResult, restoreResult) = await overlap(
        () => move(3, after: 1),
        () => run(RestoreIntention(_id(2))),
      );

      final unchanged = _unchanged(moveResult);
      final restored = _updated(restoreResult);
      expect(
        unchanged.revision.compareTo(initialRevision),
        GraphRevisionOrder.same,
      );
      _expectNewer(restored.revision, than: initialRevision);
      await expectConfirmedState(
        marks: _initialMarks,
        visible: [1, 2, 3, 4],
        lastRevision: restored.revision,
      );
    });

    test('перестановка, подтверждённая после восстановления, ставит '
        'намерение сразу за опорой перед восстановленным', () async {
      final (restoreResult, moveResult) = await overlap(
        () => run(RestoreIntention(_id(2))),
        () => move(3, after: 1),
      );

      final restored = _updated(restoreResult);
      final moved = _moved(moveResult);
      _expectNewer(moved.revision, than: restored.revision);
      await expectConfirmedState(
        marks: [(1, 1), (3, 2), (2, 3), (4, 4)],
        visible: [1, 3, 2, 4],
        lastRevision: moved.revision,
      );
    });
  });
}

/// Участник перестановки 4 после 1, состояние которого меняет пересекающаяся
/// операция.
enum _Participant {
  moved(number: 4, name: 'перемещаемого намерения'),
  anchor(number: 1, name: 'опорного намерения');

  const _Participant({required this.number, required this.name});

  final int number;
  final String name;
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

List<_Mark> _withoutMark(List<_Mark> marks, int number) => [
  for (final mark in marks)
    if (mark.$1 != number) mark,
];

/// Намерения 1–5 без связей, из которых 2 архивировано, и отметки
/// [_initialMarks]. Физическое удаление любого намерения допустимо.
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

/// Перестановка подтверждена без видимого изменения порядка.
ConfirmedGraphResult<FavoriteOrderCommandSuccess> _unchanged(
  FavoriteOrderCommandResult result,
) {
  final confirmed = _orderConfirmed(result);
  expect(confirmed.value, isA<FavoriteOrderUnchanged>());
  return confirmed;
}

void _expectConflict(FavoriteOrderCommandResult result) => switch (result) {
  FavoriteOrderCommandFailed(:final failure) => expect(
    failure,
    isA<FavoriteOrderConflictFailure>(),
  ),
  FavoriteOrderCommandSucceeded(:final value) => fail(
    'Ожидался конфликт перестановки, получен ${value.value.runtimeType}.',
  ),
};

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

/// Физическое удаление подтверждено снимком удалённого намерения.
({GraphRevision revision, IntentionCatalogEntrySnapshot entry}) _deleted(
  _IntentionResult result,
) {
  final confirmed = _intentionConfirmed(result);
  final mutation = confirmed.value.catalogMutation;
  expect(mutation, isA<IntentionCatalogDeleted>());
  return (
    revision: confirmed.revision,
    entry: (mutation as IntentionCatalogDeleted).entry,
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
