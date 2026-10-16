import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_catalog_snapshot_assembly.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'собирает разные объёмы секций порциями, сохраняя сводки и остаток',
    () async {
      final reader = _PageReader();
      final assembly = _assemble(reader, incomplete: 75, completed: 125);
      final incompleteCursor = _Cursor();
      final completedCursor = _Cursor();

      reader.first(0, _items(1, 50), total: 400, cursor: _Cursor());
      await pumpEventQueue();
      // Обе первые порции нужны до восстановления загруженного объёма.
      reader.first(
        1,
        _items(501, 50, isCompleted: true),
        total: 700,
        hasTimedChoices: true,
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

      final snapshot =
          (await assembly as DailyChoiceCatalogAssemblyReady).snapshot;
      expect(_ids(snapshot.incomplete), _idsOf(1, 100));
      expect(_ids(snapshot.completed), _idsOf(501, 150));
      expect(snapshot.incomplete.totalCount, 400);
      expect(snapshot.incomplete.hasTimedChoices, isFalse);
      expect(snapshot.incomplete.nextCursor, incompleteCursor);
      expect(snapshot.completed.totalCount, 700);
      expect(snapshot.completed.hasTimedChoices, isTrue);
      expect(snapshot.completed.nextCursor, completedCursor);
      expect(reader.queries.map((query) => query.isCompleted), [
        false,
        true,
        false,
        true,
        true,
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
      reader.first(0, _items(1, 50), total: 1000, cursor: _Cursor());
      await pumpEventQueue();
      reader.first(
        1,
        _items(501, 50, isCompleted: true),
        total: 1000,
        cursor: _Cursor(),
      );

      final snapshot =
          (await assembly as DailyChoiceCatalogAssemblyReady).snapshot;
      expect(snapshot.incomplete.items, hasLength(50));
      expect(snapshot.completed.items, hasLength(50));
      expect(reader.queries, hasLength(2));
    },
  );

  test(
    'исчерпанная и пустая секции завершаются раньше целевого объёма',
    () async {
      final reader = _PageReader();
      final assembly = _assemble(reader, incomplete: 100, completed: 100);
      reader.first(0, _items(1, 1), total: 1);
      await pumpEventQueue();
      reader.first(1, [], total: 0);

      final snapshot =
          (await assembly as DailyChoiceCatalogAssemblyReady).snapshot;
      expect(_ids(snapshot.incomplete), _idsOf(1, 1));
      expect(snapshot.completed.items, isEmpty);
      expect(snapshot.completed.totalCount, 0);
      expect(snapshot.incomplete.nextCursor, isNull);
      expect(snapshot.completed.nextCursor, isNull);
      expect(reader.queries, hasLength(2));
    },
  );

  test('несовпадение первых ревизий пересобирает пару без дублирования перенесённого выбора', () async {
    final reader = _PageReader();
    final assembly = _assemble(reader);
    reader.first(0, _items(1, 1), total: 1);
    await pumpEventQueue();
    reader.first(1, _items(1, 1, isCompleted: true), total: 1, revision: 2);
    await pumpEventQueue();
    reader.first(2, _items(2, 1), total: 1, revision: 2);
    await pumpEventQueue();
    reader.first(3, _items(1, 1, isCompleted: true), total: 1, revision: 2);

    final snapshot =
        (await assembly as DailyChoiceCatalogAssemblyReady).snapshot;
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
    reader.first(0, _items(1, 50), total: 200, cursor: oldCursor);
    await pumpEventQueue();
    reader.first(1, [], total: 0);
    await pumpEventQueue();
    reader.more(2, _items(51, 50), cursor: expiredCursor);
    await pumpEventQueue();
    reader.fail(3, const DailyChoiceCatalogSnapshotExpired());
    await pumpEventQueue();
    final newCursor = _Cursor();
    reader.first(4, _items(2, 50), total: 199, cursor: newCursor, revision: 2);
    await pumpEventQueue();
    reader.first(5, _items(1, 1, isCompleted: true), total: 1, revision: 2);
    await pumpEventQueue();
    reader.more(6, _items(52, 50), cursor: _Cursor(), revision: 2);
    await pumpEventQueue();
    reader.more(7, _items(102, 50), cursor: _Cursor(), revision: 2);

    final snapshot =
        (await assembly as DailyChoiceCatalogAssemblyReady).snapshot;
    expect(_ids(snapshot.incomplete), _idsOf(2, 150));
    expect(snapshot.incomplete.totalCount, 199);
    expect(_ids(snapshot.completed), _idsOf(1, 1));
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
    reader.first(0, _items(1, 1), total: 1);
    await pumpEventQueue();
    reader.fail(1, const DailyChoiceCatalogUnavailableFailure());

    final result = await assembly as DailyChoiceCatalogAssemblyFailed;
    expect(result.failure, isA<DailyChoiceCatalogUnavailableFailure>());
    expect(reader.queries, hasLength(2));
  });

  test('отказ продолжения сохраняет категорию и не возвращает готовые первые порции', () async {
    final reader = _PageReader();
    final assembly = _assemble(reader, incomplete: 51);
    reader.first(0, _items(1, 50), total: 100, cursor: _Cursor());
    await pumpEventQueue();
    reader.first(1, [], total: 0);
    await pumpEventQueue();
    reader.fail(2, const DailyChoiceCatalogCorruptionFailure());

    final result = await assembly as DailyChoiceCatalogAssemblyFailed;
    expect(result.failure, isA<DailyChoiceCatalogCorruptionFailure>());
    expect(reader.queries, hasLength(3));
  });

  test('непрерывная смена ревизии ограничена восемью попытками', () async {
    var reads = 0;
    final result = await assembleDailyChoiceCatalogSnapshot(
      date: _date,
      incompleteItemCount: 0,
      completedItemCount: 0,
      isCurrent: () => true,
      acceptsRevision: (_) => true,
      readPage: (query) async => DailyChoiceCatalogPageSuccess(
        DailyChoiceCatalogFirstPage(
          items: [],
          totalCount: 0,
          hasTimedChoices: false,
          nextCursor: null,
          revision: _Revision(++reads),
        ),
      ),
    );

    expect(
      (result as DailyChoiceCatalogAssemblyFailed).failure,
      isA<DailyChoiceCatalogUnavailableFailure>(),
    );
    expect(reads, 16);
  });

  test(
    'исключение чтения становится типизированным непредвиденным отказом',
    () async {
      final result = await assembleDailyChoiceCatalogSnapshot(
        date: _date,
        incompleteItemCount: 0,
        completedItemCount: 0,
        isCurrent: () => true,
        acceptsRevision: (_) => true,
        readPage: (_) async => throw StateError('Сбой чтения'),
      );

      expect(
        (result as DailyChoiceCatalogAssemblyFailed).failure,
        isA<DailyChoiceCatalogUnexpectedFailure>(),
      );
    },
  );

  test('отменённый до запуска запрос ничего не читает', () async {
    final reader = _PageReader();
    final result = await _assemble(reader, isCurrent: () => false);
    expect(result, isA<DailyChoiceCatalogAssemblyCancelled>());
    expect(reader.queries, isEmpty);
  });

  test(
    'смена поколения отбрасывает поздний ответ и прекращает следующие чтения',
    () async {
      final reader = _PageReader();
      var generation = 1;
      final assembly = _assemble(reader, isCurrent: () => generation == 1);
      generation++;
      reader.first(0, _items(1, 1), total: 1);

      expect(await assembly, isA<DailyChoiceCatalogAssemblyCancelled>());
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
      reader.first(0, _items(1, 50), total: 200, cursor: _Cursor());
      await pumpEventQueue();
      reader.first(1, [], total: 0);
      await pumpEventQueue();
      mounted = false;
      reader.fail(2, const DailyChoiceCatalogSnapshotExpired());

      expect(await assembly, isA<DailyChoiceCatalogAssemblyCancelled>());
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
      reader.first(0, _items(1, 1), total: 1);
      await pumpEventQueue();
      minimumRevision = 2;
      reader.first(1, [], total: 0);
      await pumpEventQueue();
      reader.first(2, [], total: 0, revision: 2);
      await pumpEventQueue();
      reader.first(3, _items(1, 1, isCompleted: true), total: 1, revision: 2);

      final snapshot =
          (await assembly as DailyChoiceCatalogAssemblyReady).snapshot;
      expect(snapshot.incomplete.items, isEmpty);
      expect(_ids(snapshot.completed), _idsOf(1, 1));
    },
  );
}

final _date = CalendarDate.fromParts(2026, 10, 16);

Future<DailyChoiceCatalogAssemblyResult> _assemble(
  _PageReader reader, {
  int incomplete = 0,
  int completed = 0,
  bool Function()? isCurrent,
  bool Function(GraphRevision)? acceptsRevision,
}) => assembleDailyChoiceCatalogSnapshot(
  date: _date,
  incompleteItemCount: incomplete,
  completedItemCount: completed,
  readPage: reader.read,
  isCurrent: isCurrent ?? () => true,
  acceptsRevision: acceptsRevision ?? (_) => true,
);

final class _PageReader {
  final queries = <DailyChoiceCatalogQuery>[];
  final _responses = <Completer<DailyChoiceCatalogPageResult>>[];

  Future<DailyChoiceCatalogPageResult> read(DailyChoiceCatalogQuery query) {
    queries.add(query);
    final response = Completer<DailyChoiceCatalogPageResult>();
    _responses.add(response);
    return response.future;
  }

  void first(
    int index,
    List<DailyChoiceCatalogItem> items, {
    required int total,
    DailyChoiceCatalogCursor? cursor,
    bool hasTimedChoices = false,
    int revision = 1,
  }) => _responses[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogFirstPage(
        items: items,
        totalCount: total,
        hasTimedChoices: hasTimedChoices,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );

  void more(
    int index,
    List<DailyChoiceCatalogItem> items, {
    DailyChoiceCatalogCursor? cursor,
    int revision = 1,
  }) => _responses[index].complete(
    DailyChoiceCatalogPageSuccess(
      DailyChoiceCatalogContinuationPage(
        items: items,
        nextCursor: cursor,
        revision: _Revision(revision),
      ),
    ),
  );

  void fail(int index, DailyChoiceCatalogReadFailure failure) =>
      _responses[index].complete(DailyChoiceCatalogPageError(failure));
}

final class _Cursor implements DailyChoiceCatalogCursor {}

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

List<DailyChoiceId> _ids(DailyChoiceCatalogSectionSnapshot section) =>
    section.items.map((item) => item.id).toList();

List<DailyChoiceId> _idsOf(int start, int count) => [
  for (var i = start; i < start + count; i++)
    switch (DailyChoiceId.decode(
      '018f1400-0000-7000-8000-${i.toString().padLeft(12, '0')}',
    )) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      InvalidDailyChoiceIdDecoding() => throw StateError(
        'Неверный идентификатор фикстуры',
      ),
    },
];

List<DailyChoiceCatalogItem> _items(
  int start,
  int count, {
  bool isCompleted = false,
}) => [
  for (final id in _idsOf(start, count))
    DailyChoiceCatalogItem(
      id: id,
      source: DailyChoiceCatalogParticipant(
        id: _intentionId(1),
        title: 'Быть здоровым',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.notReady,
      ),
      selected: DailyChoiceCatalogParticipant(
        id: _intentionId(2),
        title: 'Пройти пешком до парка',
        archiveState: IntentionArchiveState.active,
        readiness: IntentionReadiness.ready,
      ),
      date: _date,
      isCompleted: isCompleted,
      schedule: const DailyChoiceAllDay(),
      priority: DailyChoicePriority.p4,
      description: null,
      pathIntentionCount: 2,
    ),
];

IntentionId _intentionId(int value) => switch (IntentionId.decode(
  '018f1200-0000-7000-8000-${value.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError(
    'Неверный идентификатор фикстуры',
  ),
};
