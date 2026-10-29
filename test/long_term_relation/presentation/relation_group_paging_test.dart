import 'dart:async';

import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, page) in [
    ('преждевременный конец', _first([1], totalCount: 2)),
    ('строк больше полного количества', _first([1, 2], totalCount: 1)),
    (
      'продолжение после полного количества',
      _first([1, 2], totalCount: 2, nextCursor: const _Cursor(2)),
    ),
    ('порция больше запрошенного размера', _first([1, 2, 3], totalCount: 3)),
    ('чужая строка', _first([-1], totalCount: 1)),
  ]) {
    test('первая порция отклоняется: $name', () async {
      final paging = RelationGroupPaging();
      final source = _source((_) async => GraphResultSuccess(page));

      final result = await paging.readFirst(source, _request(paging));

      expect(result, _unexpectedFailure);
    });
  }

  test('подгрузка присоединяет строки без повторов', () async {
    final paging = RelationGroupPaging();
    final source = _source(
      (cursor) async => GraphResultSuccess(
        cursor == null
            ? _first([1, 2], totalCount: 3, nextCursor: const _Cursor(2))
            : _continuation([2, 3, 3]),
      ),
      pageSize: 3,
    );
    final request = _request(paging);
    final confirmed = _data(await paging.readFirst(source, request));

    final result = _data(await paging.loadMore(source, confirmed, request));

    expect(result.items, [1, 2, 3]);
    expect(result.totalCount, 3);
    expect(result.counts, _counts(3));
    expect(result.nextCursor, isNull);
  });

  test('конец продолжения сверяется со всей загруженной частью', () async {
    final paging = RelationGroupPaging();
    final source = _source(
      (cursor) async => GraphResultSuccess(
        cursor == null
            ? _first([1], totalCount: 3, nextCursor: const _Cursor(1))
            : _continuation([2]),
      ),
    );
    final request = _request(paging);
    final confirmed = _data(await paging.readFirst(source, request));

    final result = await paging.loadMore(source, confirmed, request);

    expect(result, _unexpectedFailure);
  });

  test('порция другой ревизии не смешивается с загруженной частью', () async {
    final paging = RelationGroupPaging();
    final source = _source(
      (cursor) async => GraphResultSuccess(
        cursor == null
            ? _first([1, 2], totalCount: 3, nextCursor: const _Cursor(2))
            : _continuation([3], revision: const _Revision(9)),
      ),
    );
    final request = _request(paging);
    final confirmed = _data(await paging.readFirst(source, request));

    final result = await paging.loadMore(source, confirmed, request);

    expect(result, isNull);
  });

  test('устаревший снимок первой порции даёт безопасный отказ', () async {
    final paging = RelationGroupPaging();
    final source = _source(
      (_) async => const GraphResultFailure(RelationGroupSnapshotExpired()),
    );

    expect(
      await paging.readFirst(source, _request(paging)),
      _unexpectedFailure,
    );
  });

  for (final refresh in [false, true]) {
    test(
      'поздняя ${refresh ? 'сборка' : 'первая порция'} прежнего поколения отбрасывается',
      () async {
        final paging = RelationGroupPaging();
        final pendingPage = Completer<RelationPagingPageResult<int>>();
        final source = _source((_) => pendingPage.future);
        final request = _request(paging);
        final pending = refresh
            ? paging.refresh(
                source,
                request,
                loadedCount: 1,
                includeRequestedPage: false,
              )
            : paging.readFirst(source, request);

        paging.nextGeneration();
        final replacement = _data(
          await paging.readFirst(
            _source(
              (_) async => GraphResultSuccess(_first([9], totalCount: 1)),
            ),
            _request(paging),
          ),
        );
        pendingPage.complete(GraphResultSuccess(_first([1], totalCount: 1)));

        expect(await pending, isNull);
        expect(replacement.items, [9]);
      },
    );

    test(
      '${refresh ? 'сборка' : 'первое чтение'} перечитывает основу до требуемой ревизии',
      () async {
        final paging = RelationGroupPaging();
        var reads = 0;
        final source = _source((_) async {
          reads += 1;
          return GraphResultSuccess(
            reads == 1
                ? _first([1], totalCount: 1)
                : _first([9], totalCount: 1, revision: const _Revision(9)),
          );
        });
        paging.requireRevision(const _Revision(9));
        final request = _request(paging);

        final result = _data(
          await (refresh
              ? paging.refresh(
                  source,
                  request,
                  loadedCount: 1,
                  includeRequestedPage: false,
                )
              : paging.readFirst(source, request)),
        );

        expect(result.items, [9]);
      },
    );
  }

  test('позднее продолжение прежнего поколения отбрасывается', () async {
    final paging = RelationGroupPaging();
    final pendingPage = Completer<RelationPagingPageResult<int>>();
    final source = _source(
      (cursor) async => cursor == null
          ? GraphResultSuccess(
              _first([1, 2], totalCount: 3, nextCursor: const _Cursor(2)),
            )
          : await pendingPage.future,
    );
    final request = _request(paging);
    final confirmed = _data(await paging.readFirst(source, request));
    final pending = paging.loadMore(source, confirmed, request);

    paging.nextGeneration();
    final replacement = _data(
      await paging.readFirst(
        _source((_) async => GraphResultSuccess(_first([9], totalCount: 1))),
        _request(paging),
      ),
    );
    pendingPage.complete(GraphResultSuccess(_continuation([3])));

    expect(await pending, isNull);
    expect(replacement.items, [9]);
  });

  for (final snapshotExpired in [false, true]) {
    test(
      '${snapshotExpired ? 'устаревшее продолжение' : 'другая ревизия продолжения'} '
      'повторяет сборку с первой порции',
      () async {
        final paging = RelationGroupPaging();
        var firstReads = 0;
        final source = _source((cursor) async {
          if (cursor == null) {
            firstReads += 1;
            return GraphResultSuccess(
              firstReads == 1
                  ? _first([1, 2], totalCount: 4, nextCursor: const _Cursor(2))
                  : _first([7, 8], totalCount: 2, revision: const _Revision(9)),
            );
          }
          if (snapshotExpired) {
            return const GraphResultFailure(RelationGroupSnapshotExpired());
          }
          return GraphResultSuccess(
            _continuation([3, 4], revision: const _Revision(9)),
          );
        });

        final result = _data(
          await paging.refresh(
            source,
            _request(paging),
            loadedCount: 2,
            includeRequestedPage: true,
          ),
        );

        expect(result.items, [7, 8]);
        expect(result.counts, _counts(2));
        expect(result.nextCursor, isNull);
      },
    );
  }

  test(
    'новая ревизия прерывает сборку до чтения следующего продолжения',
    () async {
      final paging = RelationGroupPaging();
      final continuationRequested = Completer<void>();
      final pendingPage = Completer<RelationPagingPageResult<int>>();
      var firstReads = 0;
      final source = _source((cursor) async {
        if (cursor == null) {
          firstReads += 1;
          return GraphResultSuccess(
            firstReads == 1
                ? _first([1, 2], totalCount: 6, nextCursor: const _Cursor(2))
                : _first([9], totalCount: 1, revision: const _Revision(11)),
          );
        }
        expect(cursor, const _Cursor(2));
        continuationRequested.complete();
        return pendingPage.future;
      });
      final pending = paging.refresh(
        source,
        _request(paging),
        loadedCount: 4,
        includeRequestedPage: true,
      );
      await continuationRequested.future;

      paging.requireRevision(const _Revision(11));
      pendingPage.complete(
        GraphResultSuccess(_continuation([3, 4], nextCursor: const _Cursor(4))),
      );

      final result = _data(await pending);
      expect(result.items, [9]);
      expect(result.counts, _counts(1));
      expect(result.nextCursor, isNull);
    },
  );

  test(
    'исчерпание повторов устаревшего продолжения возвращает недоступность',
    () async {
      final paging = RelationGroupPaging();
      var attempts = 0;
      final source = _source((cursor) async {
        if (cursor != null) {
          return const GraphResultFailure(RelationGroupSnapshotExpired());
        }
        attempts += 1;
        if (attempts > 8) fail('Сборка не ограничила число повторов.');
        return GraphResultSuccess(
          _first([1, 2], totalCount: 3, nextCursor: const _Cursor(2)),
        );
      });

      final result = await paging.refresh(
        source,
        _request(paging),
        loadedCount: 2,
        includeRequestedPage: true,
      );

      expect(
        result,
        isA<
              GraphResultFailure<
                RelationPagingData<int>,
                RelationGroupReadFailure
              >
            >()
            .having(
              (result) => result.failure,
              'причина',
              isA<RelationGroupUnavailableFailure>(),
            ),
      );
    },
  );

  for (final includeRequestedPage in [false, true]) {
    test('сборка ограничена загруженной частью'
        '${includeRequestedPage ? ' и запрошенной порцией' : ''}', () async {
      final paging = RelationGroupPaging();
      var readCount = 0;
      final source = _source((cursor) async {
        readCount += 1;
        return GraphResultSuccess(switch (cursor) {
          null => _first([1, 2], totalCount: 7, nextCursor: const _Cursor(2)),
          _Cursor(offset: 2) => _continuation([
            3,
            4,
          ], nextCursor: const _Cursor(4)),
          _Cursor(offset: 4) => _continuation([
            5,
            6,
          ], nextCursor: const _Cursor(6)),
          _ => throw StateError('Незагруженный остаток читать не нужно.'),
        });
      });

      final result = _data(
        await paging.refresh(
          source,
          _request(paging),
          loadedCount: 4,
          includeRequestedPage: includeRequestedPage,
        ),
      );

      expect(
        result.items,
        includeRequestedPage ? [1, 2, 3, 4, 5, 6] : [1, 2, 3, 4],
      );
      expect(result.totalCount, 7);
      expect(result.nextCursor, isNotNull);
      expect(readCount, includeRequestedPage ? 3 : 2);
    });
  }

  for (final (name, previous, replacement, visibleId, expectedId, expectedIndex)
      in [
        ('сохранившаяся строка', [1, 2, 3], [3, 1], 3, 3, 0),
        (
          'следующая при равном расстоянии',
          [1, 2, 3, 4],
          [1, 2, 4, 5],
          3,
          4,
          2,
        ),
        ('ближайшая предыдущая', [1, 2, 3, 4, 5], [1, 2, 5], 3, 2, 1),
        ('полная замена с укорочением', [1, 2, 3, 4], [5, 6], 3, 6, 1),
      ]) {
    test('привязка после замены: $name', () {
      final anchor = RelationGroupPaging().chooseAnchor(
        previous: previous,
        replacement: replacement,
        visibleId: visibleId,
        identify: (row) => row,
      );

      expect(anchor?.id, expectedId);
      expect(anchor?.index, expectedIndex);
    });
  }

  test('привязки нет без видимой строки или после удаления всех строк', () {
    final paging = RelationGroupPaging();
    for (final (replacement, visibleId) in <(List<int>, int?)>[
      ([1, 2], null),
      ([], 2),
    ]) {
      expect(
        paging.chooseAnchor(
          previous: [1, 2],
          replacement: replacement,
          visibleId: visibleId,
          identify: (row) => row,
        ),
        isNull,
      );
    }
  });
}

final _unexpectedFailure =
    isA<GraphResultFailure<RelationPagingData<int>, RelationGroupReadFailure>>()
        .having(
          (result) => result.failure,
          'причина',
          isA<RelationGroupUnexpectedFailure>(),
        );

RelationPagingRequest _request(RelationGroupPaging paging) =>
    paging.startRequest(paging.generation);

RelationPagingSource<int, int> _source(
  Future<RelationPagingPageResult<int>> Function(RelationGroupCursor?) read, {
  int pageSize = 2,
}) => RelationPagingSource(
  readPage: read,
  pageSize: pageSize,
  identify: (row) => row > 0 ? row : null,
);

RelationPagingFirstPage<int> _first(
  List<int> items, {
  required int totalCount,
  RelationGroupCursor? nextCursor,
  GraphRevision revision = const _Revision(4),
}) => RelationPagingFirstPage(
  items: items,
  counts: _counts(totalCount),
  totalCount: totalCount,
  revision: revision,
  nextCursor: nextCursor,
);

RelationPagingContinuationPage<int> _continuation(
  List<int> items, {
  RelationGroupCursor? nextCursor,
  GraphRevision revision = const _Revision(4),
}) => RelationPagingContinuationPage(
  items: items,
  revision: revision,
  nextCursor: nextCursor,
);

RelationPagingData<int> _data(RelationPagingResult<int>? result) {
  return switch (result) {
    GraphResultSuccess(:final value) => value,
    _ => throw StateError('Ожидалась успешная сборка, получено $result.'),
  };
}

RelationCounts _counts(int count) => RelationCounts(
  activeNeedIncoming: 0,
  activeNeedOutgoing: count,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
);

final class _Cursor implements RelationGroupCursor {
  const _Cursor(this.offset);

  final int offset;
}

final class _Revision implements GraphRevision {
  const _Revision(this.sequence);

  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _Revision) return GraphRevisionOrder.differentEpoch;
    return switch (sequence.compareTo(other.sequence)) {
      < 0 => GraphRevisionOrder.older,
      > 0 => GraphRevisionOrder.newer,
      _ => GraphRevisionOrder.same,
    };
  }
}
