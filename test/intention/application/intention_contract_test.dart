import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('контракт каталога намерений', () {
    test(
      'нормализует фильтр, ограничивает порцию и применяет scope с фильтром',
      () {
        final query = IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: '  БЫТЬ ЗДОРОВЫМ  ',
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        );
        final active = _summary(
          id: '00000000-0000-4000-8000-000000000001',
          title: 'Быть здоровым',
        );
        final archived = _summary(
          id: '00000000-0000-4000-8000-000000000002',
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
        );

        expect(query.titleFilter, 'БЫТЬ ЗДОРОВЫМ');
        expect(query.pageSize, 1);
        expect(query.includes(active), isTrue);
        expect(query.includes(archived), isFalse);
        expect(
          IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: '  \n\t ',
            order: IntentionCatalogOrder.createdAtDescending,
            pageSize: 100,
          ).titleFilter,
          isNull,
        );
      },
    );

    test('принимает границы page size и фильтра из 255 графем', () {
      final titleFilter = List.filled(255, '👩🏽‍💻').join();

      expect(
        () => IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: titleFilter,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        ),
        returnsNormally,
      );
      expect(
        () => IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: titleFilter,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 100,
        ),
        returnsNormally,
      );
    });

    test('отклоняет выходящие за границы размер порции и фильтр', () {
      expect(
        () => _query(pageSize: 0),
        _throwsQueryFailure(
          IntentionCatalogQueryValidationFailure.pageSizeOutOfRange,
        ),
      );
      expect(
        () => _query(pageSize: 101),
        _throwsQueryFailure(
          IntentionCatalogQueryValidationFailure.pageSizeOutOfRange,
        ),
      );
      expect(
        () => _query(titleFilter: List.filled(256, '👩🏽‍💻').join()),
        _throwsQueryFailure(
          IntentionCatalogQueryValidationFailure.titleFilterTooLong,
        ),
      );
    });

    test('сравнивает summaries полным порядком времени и идентификатора', () {
      final query = _query();
      final newer = _summary(
        id: '00000000-0000-4000-8000-000000000002',
        createdAt: DateTime.utc(2026, 8, 30, 13),
      );
      final older = _summary(
        id: '00000000-0000-4000-8000-000000000001',
        createdAt: DateTime.utc(2026, 8, 30, 12),
      );
      final sameTimeLaterId = _summary(
        id: '00000000-0000-4000-8000-000000000003',
        createdAt: DateTime.utc(2026, 8, 30, 13),
      );

      expect(query.compare(newer, older), isNegative);
      expect(query.compare(newer, sameTimeLaterId), isNegative);
      expect(query.compare(sameTimeLaterId, newer), isPositive);
    });

    test('выражает три scope и четыре сочетания поля с направлением', () {
      final active = _summary(
        id: '00000000-0000-4000-8000-000000000001',
        createdAt: DateTime.utc(2026, 8, 30, 12),
        updatedAt: DateTime.utc(2026, 8, 30, 14),
      );
      final archived = _summary(
        id: '00000000-0000-4000-8000-000000000002',
        archiveState: IntentionArchiveState.archived,
        createdAt: DateTime.utc(2026, 8, 30, 13),
        updatedAt: DateTime.utc(2026, 8, 30, 13),
      );

      expect(_queryForScope(IntentionScope.active).includes(active), isTrue);
      expect(_queryForScope(IntentionScope.active).includes(archived), isFalse);
      expect(_queryForScope(IntentionScope.archived).includes(active), isFalse);
      expect(
        _queryForScope(IntentionScope.archived).includes(archived),
        isTrue,
      );
      expect(_queryForScope(IntentionScope.all).includes(active), isTrue);
      expect(_queryForScope(IntentionScope.all).includes(archived), isTrue);

      expect(
        _order(
          IntentionCatalogSortField.createdAt,
          IntentionCatalogSortDirection.ascending,
        ).compare(active, archived),
        isNegative,
      );
      expect(
        _order(
          IntentionCatalogSortField.createdAt,
          IntentionCatalogSortDirection.descending,
        ).compare(active, archived),
        isPositive,
      );
      expect(
        _order(
          IntentionCatalogSortField.updatedAt,
          IntentionCatalogSortDirection.ascending,
        ).compare(active, archived),
        isPositive,
      );
      expect(
        _order(
          IntentionCatalogSortField.updatedAt,
          IntentionCatalogSortDirection.descending,
        ).compare(active, archived),
        isNegative,
      );
    });

    test('передаёт opaque cursor без раскрытия его реализации', () {
      const cursor = _TestCatalogCursor();

      final continuation = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'здоровье',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
        cursor: cursor,
      );

      expect(continuation.cursor, same(cursor));
    });

    test(
      'различает sealed первую и последующую страницы без nullable count',
      () {
        final summary = _summary(id: '00000000-0000-4000-8000-000000000001');
        const cursor = _TestCatalogCursor();
        final pages = <IntentionCatalogPage>[
          IntentionCatalogFirstPage(
            items: [summary],
            totalCount: 2,
            nextCursor: cursor,
          ),
          IntentionCatalogContinuationPage(items: const [], nextCursor: null),
        ];

        expect(pages.map(_pageDescription), ['first:2', 'continuation']);
      },
    );

    test('первая страница отклоняет недопустимый total count в release', () {
      final summary = _summary(id: '00000000-0000-4000-8000-000000000001');

      expect(
        () => IntentionCatalogFirstPage(
          items: [summary],
          totalCount: 0,
          nextCursor: null,
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
      );
      expect(
        () => IntentionCatalogFirstPage(
          items: const [],
          totalCount: -1,
          nextCursor: null,
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
      );
    });

    test('summary отклоняет изменение раньше создания', () {
      expect(
        () => _summary(
          id: '00000000-0000-4000-8000-000000000001',
          createdAt: DateTime.utc(2026, 8, 30, 12),
          updatedAt: DateTime.utc(2026, 8, 30, 11),
        ),
        throwsA(isA<IntentionTimestampOrderException>()),
      );
    });
  });

  group('commands и результаты намерений', () {
    test(
      'закрытый набор commands несёт только необходимые предметные данные',
      () {
        final id = _intentionId('00000000-0000-4000-8000-000000000001');
        final commands = <IntentionCommand>[
          const CreateIntention(title: 'Здоровье', description: null),
          UpdateIntention(
            id: id,
            title: 'Быть здоровым',
            description: 'Каждый день',
          ),
          EnableIntentionReadiness(id),
          DisableIntentionReadiness(id),
          ArchiveIntention(id),
          RestoreIntention(id),
          DeleteIntention(id),
        ];

        expect(commands.map(_commandDescription), [
          'create',
          'update',
          'enableReadiness',
          'disableReadiness',
          'archive',
          'restore',
          'delete',
        ]);
      },
    );

    test('saved, deleted и failures имеют исчерпывающие типы', () {
      final intention = _intention();
      final results = <Result<IntentionCommandSuccess>>[
        ResultSuccess(IntentionSaved(intention)),
        ResultSuccess(IntentionDeleted(intention.id)),
        const ResultFailure(IntentionValidationFailure()),
        const ResultFailure(IntentionNotFoundFailure()),
        const ResultFailure(IntentionConflictFailure()),
        const ResultFailure(IntentionUnavailableFailure()),
        const ResultFailure(IntentionCorruptionFailure()),
      ];

      expect(
        results.whereType<ResultSuccess<IntentionCommandSuccess>>(),
        hasLength(2),
      );
      expect(
        results.whereType<ResultFailure<IntentionCommandSuccess>>(),
        hasLength(5),
      );
      expect(_resultSuccessDescription(results[0]), 'saved');
      expect(_resultSuccessDescription(results[1]), 'deleted');
      expect(results.skip(2).map(_resultFailureDescription), [
        'validation',
        'notFound',
        'conflict',
        'unavailable',
        'corruption',
      ]);
    });

    test(
      'watchById сигнализирует typed failure и повторяется новой подпиской',
      () async {
        final repository = _FailingRepository();
        final id = _intentionId('00000000-0000-4000-8000-000000000001');

        final expected = emitsInOrder(<Object?>[
          isA<ResultFailure<Intention?>>().having(
            (result) => result.failure,
            'failure',
            isA<IntentionUnavailableFailure>(),
          ),
          emitsDone,
        ]);

        await expectLater(repository.watchById(id), expected);
        await expectLater(repository.watchById(id), expected);

        expect(repository.watchSubscriptions, 2);
      },
    );
  });
}

IntentionCatalogQuery _query({int pageSize = 100, String? titleFilter}) =>
    IntentionCatalogQuery(
      scope: IntentionScope.active,
      titleFilter: titleFilter,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: pageSize,
    );

IntentionCatalogQuery _queryForScope(IntentionScope scope) =>
    IntentionCatalogQuery(
      scope: scope,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: 100,
    );

IntentionCatalogQuery _order(
  IntentionCatalogSortField field,
  IntentionCatalogSortDirection direction,
) => IntentionCatalogQuery(
  scope: IntentionScope.all,
  titleFilter: null,
  order: IntentionCatalogOrder(field: field, direction: direction),
  pageSize: 100,
);

IntentionSummary _summary({
  required String id,
  String title = 'Здоровье',
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = IntentionTimestamp(
    createdAt ?? DateTime.utc(2026, 8, 30, 12),
  );
  return IntentionSummary(
    id: _intentionId(id),
    title: title,
    hasDescription: false,
    readiness: IntentionReadiness.notReady,
    archiveState: archiveState,
    createdAt: created,
    updatedAt: IntentionTimestamp(updatedAt ?? created.value),
  );
}

Intention _intention() {
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 8, 30, 12));
  return Intention(
    id: _intentionId('00000000-0000-4000-8000-000000000001'),
    title: 'Здоровье',
    description: null,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

String _pageDescription(IntentionCatalogPage page) => switch (page) {
  IntentionCatalogFirstPage(:final totalCount) => 'first:$totalCount',
  IntentionCatalogContinuationPage() => 'continuation',
};

String _successDescription(IntentionCommandSuccess success) =>
    switch (success) {
      IntentionSaved() => 'saved',
      IntentionDeleted() => 'deleted',
    };

String _commandDescription(IntentionCommand command) => switch (command) {
  CreateIntention() => 'create',
  UpdateIntention() => 'update',
  EnableIntentionReadiness() => 'enableReadiness',
  DisableIntentionReadiness() => 'disableReadiness',
  ArchiveIntention() => 'archive',
  RestoreIntention() => 'restore',
  DeleteIntention() => 'delete',
};

String _failureDescription(IntentionFailure failure) => switch (failure) {
  IntentionValidationFailure() => 'validation',
  IntentionNotFoundFailure() => 'notFound',
  IntentionConflictFailure() => 'conflict',
  IntentionUnavailableFailure() => 'unavailable',
  IntentionCorruptionFailure() => 'corruption',
};

String _resultSuccessDescription(Result<IntentionCommandSuccess> result) =>
    switch (result) {
      ResultSuccess(:final value) => _successDescription(value),
      ResultFailure() => throw StateError('Ожидался успешный результат.'),
    };

String _resultFailureDescription(Result<IntentionCommandSuccess> result) =>
    switch (result) {
      ResultSuccess() => throw StateError('Ожидался неуспешный результат.'),
      ResultFailure(:final failure) => _failureDescription(failure),
    };

Matcher _throwsQueryFailure(IntentionCatalogQueryValidationFailure failure) =>
    throwsA(
      isA<IntentionCatalogQueryValidationException>().having(
        (exception) => exception.failure,
        'failure',
        failure,
      ),
    );

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Ожидался корректный UUID.'),
};

final class _FailingRepository implements IntentionRepository {
  var watchSubscriptions = 0;

  @override
  Future<Result<IntentionCommandSuccess>> execute(
    IntentionCommand command,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Stream<Result<Intention?>> watchById(IntentionId id) {
    watchSubscriptions++;
    return Stream.value(const ResultFailure(IntentionUnavailableFailure()));
  }
}

final class _TestCatalogCursor implements IntentionCatalogCursor {
  const _TestCatalogCursor();
}
