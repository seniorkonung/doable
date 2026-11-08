import 'dart:async';

import 'package:doable/src/action/application/action_day.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/day/action_day_snapshot_assembly.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'собирает разные объёмы секций порциями, сохраняя числа и остаток',
    () async {
      final reader = _PageReader();
      final assembly = _assemble(reader, incomplete: 75, completed: 125);
      final incompleteCursor = _Cursor();
      final completedCursor = _Cursor();

      // Каждая первая порция несёт числа обеих секций и общий признак времени.
      reader.first(
        0,
        _items(1, 50),
        incompleteCount: 400,
        completedCount: 700,
        hasTimedActions: true,
        cursor: _Cursor(),
      );
      await pumpEventQueue();
      // Обе первые порции нужны до восстановления загруженного объёма.
      reader.first(
        1,
        _items(501, 50, isCompleted: true),
        incompleteCount: 400,
        completedCount: 700,
        hasTimedActions: true,
        cursor: _Cursor(),
      );
      await pumpEventQueue();
      reader.more(2, _items(51, 50), cursor: incompleteCursor);
      await pumpEventQueue();
      reader.more(3, _items(551, 50, isCompleted: true), cursor: _Cursor());
      await pumpEventQueue();
      reader.more(
        4,
        _items(601, 50, isCompleted: true),
        cursor: completedCursor,
      );

      final snapshot = (await assembly as ActionDayAssemblyReady).snapshot;
      expect(_ids(snapshot.incomplete), _idsOf(1, 100));
      expect(_ids(snapshot.completed), _idsOf(501, 150));
      expect(snapshot.incomplete.totalCount, 400);
      expect(snapshot.incomplete.nextCursor, incompleteCursor);
      expect(snapshot.completed.totalCount, 700);
      expect(snapshot.completed.nextCursor, completedCursor);
      // Загруженные строки не имеют времени, но признак относится ко всему
      // дню, включая неполученные порции.
      expect(snapshot.hasTimedActions, isTrue);
      expect(reader.queries.map((query) => query.section), [
        ActionDaySection.incomplete,
        ActionDaySection.completed,
        ActionDaySection.incomplete,
        ActionDaySection.completed,
        ActionDaySection.completed,
      ]);
      expect(reader.queries.every((query) => query.date == _date), isTrue);
      expect(reader.queries.every((query) => query.pageSize == 50), isTrue);
    },
  );

  test(
    'нулевой целевой объём всё равно получает первую порцию обеих секций',
    () async {
      final reader = _PageReader();
      final assembly = _assemble(reader, incomplete: 0, completed: 0);
      reader.first(
        0,
        _items(1, 50),
        incompleteCount: 1000,
        completedCount: 1000,
        cursor: _Cursor(),
      );
      await pumpEventQueue();
      reader.first(
        1,
        _items(501, 50, isCompleted: true),
        incompleteCount: 1000,
        completedCount: 1000,
        cursor: _Cursor(),
      );

      final snapshot = (await assembly as ActionDayAssemblyReady).snapshot;
      expect(snapshot.incomplete.items, hasLength(50));
      expect(snapshot.completed.items, hasLength(50));
      expect(snapshot.hasTimedActions, isFalse);
      expect(reader.queries, hasLength(2));
    },
  );

  test(
    'исчерпанная и пустая секции завершаются раньше целевого объёма',
    () async {
      final reader = _PageReader();
      final assembly = _assemble(reader, incomplete: 100, completed: 100);
      reader.first(0, _items(1, 1), incompleteCount: 1, completedCount: 0);
      await pumpEventQueue();
      reader.first(1, [], incompleteCount: 1, completedCount: 0);

      final snapshot = (await assembly as ActionDayAssemblyReady).snapshot;
      expect(_ids(snapshot.incomplete), _idsOf(1, 1));
      expect(snapshot.completed.items, isEmpty);
      expect(snapshot.completed.totalCount, 0);
      expect(snapshot.incomplete.nextCursor, isNull);
      expect(snapshot.completed.nextCursor, isNull);
      expect(reader.queries, hasLength(2));
    },
  );

  test('несовпадение первых ревизий пересобирает пару без дублирования перенесённого действия', () async {
    final reader = _PageReader();
    final assembly = _assemble(reader);
    reader.first(0, _items(1, 1), incompleteCount: 1, completedCount: 0);
    await pumpEventQueue();
    reader.first(
      1,
      _items(1, 1, isCompleted: true),
      incompleteCount: 0,
      completedCount: 1,
      revision: 2,
    );
    await pumpEventQueue();
    reader.first(
      2,
      _items(2, 1),
      incompleteCount: 1,
      completedCount: 1,
      revision: 2,
    );
    await pumpEventQueue();
    reader.first(
      3,
      _items(1, 1, isCompleted: true),
      incompleteCount: 1,
      completedCount: 1,
      revision: 2,
    );

    final snapshot = (await assembly as ActionDayAssemblyReady).snapshot;
    expect(_ids(snapshot.incomplete), _idsOf(2, 1));
    expect(_ids(snapshot.completed), _idsOf(1, 1));
    expect(
      snapshot.revision.compareTo(const _Revision(2)),
      GraphRevisionOrder.same,
    );
    expect(reader.queries.every((query) => query.cursor == null), isTrue);
  });

  test('устаревшее продолжение отбрасывает обе части и восстанавливает нужный объём', () async {
    final reader = _PageReader();
    final assembly = _assemble(reader, incomplete: 101);
    final oldCursor = _Cursor();
    final expiredCursor = _Cursor();
    reader.first(
      0,
      _items(1, 50),
      incompleteCount: 200,
      completedCount: 0,
      cursor: oldCursor,
    );
    await pumpEventQueue();
    reader.first(1, [], incompleteCount: 200, completedCount: 0);
    await pumpEventQueue();
    reader.more(2, _items(51, 50), cursor: expiredCursor);
    await pumpEventQueue();
    reader.fail(3, const ActionDaySnapshotExpired());
    await pumpEventQueue();
    final newCursor = _Cursor();
    reader.first(
      4,
      _items(2, 50),
      incompleteCount: 199,
      completedCount: 1,
      cursor: newCursor,
      revision: 2,
    );
    await pumpEventQueue();
    reader.first(
      5,
      _items(1, 1, isCompleted: true),
      incompleteCount: 199,
      completedCount: 1,
      revision: 2,
    );
    await pumpEventQueue();
    reader.more(6, _items(52, 50), cursor: _Cursor(), revision: 2);
    await pumpEventQueue();
    reader.more(7, _items(102, 50), cursor: _Cursor(), revision: 2);

    final snapshot = (await assembly as ActionDayAssemblyReady).snapshot;
    expect(_ids(snapshot.incomplete), _idsOf(2, 150));
    expect(snapshot.incomplete.totalCount, 199);
    expect(_ids(snapshot.completed), _idsOf(1, 1));
    expect(snapshot.completed.totalCount, 1);
    expect(reader.queries[2].cursor, oldCursor);
    expect(reader.queries[3].cursor, expiredCursor);
    expect(reader.queries[4].cursor, isNull);
    expect(reader.queries[5].cursor, isNull);
    expect(reader.queries[6].cursor, newCursor);
    expect(reader.queries, hasLength(8));
  });

  test('отказ первой порции одной секции не возвращает частичную пару и не повторяется', () async {
    final reader = _PageReader();
    final assembly = _assemble(reader);
    reader.first(0, _items(1, 1), incompleteCount: 1, completedCount: 0);
    await pumpEventQueue();
    reader.fail(1, const ActionDayUnavailableFailure());

    final result = await assembly as ActionDayAssemblyFailed;
    expect(result.failure, isA<ActionDayUnavailableFailure>());
    expect(reader.queries, hasLength(2));
  });

  test('отказ продолжения сохраняет категорию и не возвращает готовые первые порции', () async {
    final reader = _PageReader();
    final assembly = _assemble(reader, incomplete: 51);
    reader.first(
      0,
      _items(1, 50),
      incompleteCount: 100,
      completedCount: 0,
      cursor: _Cursor(),
    );
    await pumpEventQueue();
    reader.first(1, [], incompleteCount: 100, completedCount: 0);
    await pumpEventQueue();
    reader.fail(2, const ActionDayCorruptionFailure());

    final result = await assembly as ActionDayAssemblyFailed;
    expect(result.failure, isA<ActionDayCorruptionFailure>());
    expect(reader.queries, hasLength(3));
  });

  test('непрерывная смена ревизии ограничена восемью попытками', () async {
    var reads = 0;
    final result = await assembleActionDaySnapshot(
      date: _date,
      incompleteItemCount: 0,
      completedItemCount: 0,
      isCurrent: () => true,
      acceptsRevision: (_) => true,
      readPage: (query) async => ActionDayPageSuccess(
        ActionDayFirstPage(
          items: [],
          incompleteCount: 0,
          completedCount: 0,
          hasTimedActions: false,
          nextCursor: null,
          revision: _Revision(++reads),
        ),
      ),
    );

    expect(
      (result as ActionDayAssemblyFailed).failure,
      isA<ActionDayUnavailableFailure>(),
    );
    expect(reads, 16);
  });

  test(
    'исключение чтения становится типизированным непредвиденным отказом',
    () async {
      final result = await assembleActionDaySnapshot(
        date: _date,
        incompleteItemCount: 0,
        completedItemCount: 0,
        isCurrent: () => true,
        acceptsRevision: (_) => true,
        readPage: (_) async => throw StateError('Сбой чтения'),
      );

      expect(
        (result as ActionDayAssemblyFailed).failure,
        isA<ActionDayUnexpectedFailure>(),
      );
    },
  );

  test('отменённый до запуска запрос ничего не читает', () async {
    final reader = _PageReader();
    final result = await _assemble(reader, isCurrent: () => false);
    expect(result, isA<ActionDayAssemblyCancelled>());
    expect(reader.queries, isEmpty);
  });

  test(
    'смена поколения отбрасывает поздний ответ и прекращает следующие чтения',
    () async {
      final reader = _PageReader();
      var generation = 1;
      final assembly = _assemble(reader, isCurrent: () => generation == 1);
      generation++;
      reader.first(0, _items(1, 1), incompleteCount: 1, completedCount: 0);

      expect(await assembly, isA<ActionDayAssemblyCancelled>());
      expect(reader.queries, hasLength(1));
    },
  );

  test(
    'закрытие экземпляра во время продолжения отменяет сборку вместо повтора',
    () async {
      final reader = _PageReader();
      var mounted = true;
      final assembly = _assemble(
        reader,
        incomplete: 100,
        isCurrent: () => mounted,
      );
      reader.first(
        0,
        _items(1, 50),
        incompleteCount: 200,
        completedCount: 0,
        cursor: _Cursor(),
      );
      await pumpEventQueue();
      reader.first(1, [], incompleteCount: 200, completedCount: 0);
      await pumpEventQueue();
      mounted = false;
      reader.fail(2, const ActionDaySnapshotExpired());

      expect(await assembly, isA<ActionDayAssemblyCancelled>());
      expect(reader.queries, hasLength(3));
    },
  );

  test(
    'подтверждённая новая ревизия не допускает согласованную, но прежнюю пару',
    () async {
      final reader = _PageReader();
      var minimumRevision = 1;
      final assembly = _assemble(
        reader,
        acceptsRevision: (revision) =>
            revision.compareTo(_Revision(minimumRevision)) !=
            GraphRevisionOrder.older,
      );
      reader.first(0, _items(1, 1), incompleteCount: 1, completedCount: 0);
      await pumpEventQueue();
      minimumRevision = 2;
      reader.first(1, [], incompleteCount: 1, completedCount: 0);
      await pumpEventQueue();
      reader.first(2, [], incompleteCount: 0, completedCount: 1, revision: 2);
      await pumpEventQueue();
      reader.first(
        3,
        _items(1, 1, isCompleted: true),
        incompleteCount: 0,
        completedCount: 1,
        revision: 2,
      );

      final snapshot = (await assembly as ActionDayAssemblyReady).snapshot;
      expect(snapshot.incomplete.items, isEmpty);
      expect(_ids(snapshot.completed), _idsOf(1, 1));
    },
  );
}

final _date = CalendarDate.fromParts(2026, 10, 16);

Future<ActionDayAssemblyResult> _assemble(
  _PageReader reader, {
  int incomplete = 0,
  int completed = 0,
  bool Function()? isCurrent,
  bool Function(GraphRevision)? acceptsRevision,
}) => assembleActionDaySnapshot(
  date: _date,
  incompleteItemCount: incomplete,
  completedItemCount: completed,
  readPage: reader.read,
  isCurrent: isCurrent ?? () => true,
  acceptsRevision: acceptsRevision ?? (_) => true,
);

final class _PageReader {
  final queries = <ActionDayQuery>[];
  final _responses = <Completer<ActionDayPageResult>>[];

  Future<ActionDayPageResult> read(ActionDayQuery query) {
    queries.add(query);
    final response = Completer<ActionDayPageResult>();
    _responses.add(response);
    return response.future;
  }

  /// Первая порция любой секции несёт числа обеих секций дня и признак
  /// времени во всём дне.
  void first(
    int index,
    List<ActionListItem> items, {
    required int incompleteCount,
    required int completedCount,
    bool hasTimedActions = false,
    ActionDayCursor? cursor,
    int revision = 1,
  }) => _responses[index].complete(
    ActionDayPageSuccess(
      ActionDayFirstPage(
        items: items,
        incompleteCount: incompleteCount,
        completedCount: completedCount,
        hasTimedActions: hasTimedActions,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );

  void more(
    int index,
    List<ActionListItem> items, {
    ActionDayCursor? cursor,
    int revision = 1,
  }) => _responses[index].complete(
    ActionDayPageSuccess(
      ActionDayContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );

  void fail(int index, ActionDayReadFailure failure) =>
      _responses[index].complete(ActionDayPageError(failure));
}

final class _Cursor implements ActionDayCursor {}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision) return GraphRevisionOrder.differentEpoch;
    if (value < other.value) return GraphRevisionOrder.older;
    if (value > other.value) return GraphRevisionOrder.newer;
    return GraphRevisionOrder.same;
  }
}

List<ActionId> _ids(ActionDaySectionSnapshot section) =>
    section.items.map((item) => item.id).toList();

List<ActionId> _idsOf(int start, int count) => [
  for (var i = start; i < start + count; i++)
    switch (ActionId.decode(
      '018f1400-0000-7000-8000-${i.toString().padLeft(12, '0')}',
    )) {
      ActionIdDecodingSuccess(:final id) => id,
      InvalidActionIdDecoding() => throw StateError(
        'Неверный идентификатор фикстуры',
      ),
    },
];

List<ActionListItem> _items(int start, int count, {bool isCompleted = false}) =>
    [
      for (final id in _idsOf(start, count))
        ActionListItem(
          id: id,
          title: ActionTitle('Пройти пешком до парка'),
          description: null,
          date: _date,
          schedule: const ActionAllDay(),
          priority: ActionPriority.p4,
          isCompleted: isCompleted,
          rootIntentionId: _rootIntentionId,
          rootTitle: 'Быть здоровым',
          pathIntentionCount: 2,
        ),
    ];

final _rootIntentionId = switch (IntentionId.decode(
  '018f1200-0000-7000-8000-000000000001',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Неверный идентификатор фикстуры',
  ),
};
