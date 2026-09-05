import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_repository.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/data/drift_intention_repository.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/in_memory_diagnostics_sink.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftIntentionRepository repository;
  late _SelectTrace trace;

  setUp(() async {
    trace = _SelectTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        trace,
      ),
    );
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftIntentionRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 2),
      diagnostics,
    );
    trace.statements.clear();
  });

  tearDown(() => database.close());

  test('возвращает ограниченную первую страницу и точное количество', () async {
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000001',
      title: 'Первое',
      createdAt: DateTime.utc(2026, 9, 2, 10),
    );
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000002',
      title: 'Второе',
      createdAt: DateTime.utc(2026, 9, 2, 11),
    );
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000003',
      title: 'Третье',
      createdAt: DateTime.utc(2026, 9, 2, 12),
    );

    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ),
    );

    expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
    final page = (result as ResultSuccess<IntentionCatalogPage>).value;
    expect(page, isA<IntentionCatalogFirstPage>());
    final firstPage = page as IntentionCatalogFirstPage;
    expect(firstPage.totalCount, 3);
    expect(firstPage.items, hasLength(1));
    expect(
      firstPage.items.single.id,
      _id('018f0b5d-6b2e-7c80-8000-000000000003'),
    );
    expect(firstPage.nextCursor, isNotNull);
    expect(diagnostics.events, [
      isA<CatalogPageReadDiagnosticsEvent>().having(
        (event) => event.status,
        'status',
        isA<DiagnosticsStarted>(),
      ),
      isA<CatalogPageReadDiagnosticsEvent>()
          .having((event) => event.pageSize, 'pageSize', 1)
          .having(
            (event) => event.status,
            'status',
            isA<DiagnosticsSucceeded>(),
          ),
    ]);
  });

  test('применяет все охваты и четыре порядка с tie-breaker по ID', () async {
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000011',
      title: 'Активное первое',
      createdAt: DateTime.utc(2026, 9, 2, 10),
      updatedAt: DateTime.utc(2026, 9, 2, 14),
    );
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000012',
      title: 'Активное второе',
      createdAt: DateTime.utc(2026, 9, 2, 10),
      updatedAt: DateTime.utc(2026, 9, 2, 12),
    );
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000013',
      title: 'Архивное первое',
      isArchived: true,
      createdAt: DateTime.utc(2026, 9, 2, 8),
      updatedAt: DateTime.utc(2026, 9, 2, 9),
    );
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000014',
      title: 'Архивное второе',
      isArchived: true,
      createdAt: DateTime.utc(2026, 9, 2, 11),
      updatedAt: DateTime.utc(2026, 9, 2, 13),
    );

    final cases = <(IntentionScope, IntentionCatalogOrder, List<String>)>[
      (
        IntentionScope.active,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.createdAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000011',
          '018f0b5d-6b2e-7c80-8000-000000000012',
        ],
      ),
      (
        IntentionScope.active,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.updatedAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000012',
          '018f0b5d-6b2e-7c80-8000-000000000011',
        ],
      ),
      (
        IntentionScope.active,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.updatedAt,
          direction: IntentionCatalogSortDirection.descending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000011',
          '018f0b5d-6b2e-7c80-8000-000000000012',
        ],
      ),
      (
        IntentionScope.archived,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.createdAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000013',
          '018f0b5d-6b2e-7c80-8000-000000000014',
        ],
      ),
      (
        IntentionScope.archived,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.createdAt,
          direction: IntentionCatalogSortDirection.descending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000014',
          '018f0b5d-6b2e-7c80-8000-000000000013',
        ],
      ),
      (
        IntentionScope.archived,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.updatedAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000013',
          '018f0b5d-6b2e-7c80-8000-000000000014',
        ],
      ),
      (
        IntentionScope.archived,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.updatedAt,
          direction: IntentionCatalogSortDirection.descending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000014',
          '018f0b5d-6b2e-7c80-8000-000000000013',
        ],
      ),
      (
        IntentionScope.all,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.createdAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000013',
          '018f0b5d-6b2e-7c80-8000-000000000011',
          '018f0b5d-6b2e-7c80-8000-000000000012',
          '018f0b5d-6b2e-7c80-8000-000000000014',
        ],
      ),
      (
        IntentionScope.all,
        IntentionCatalogOrder.createdAtDescending,
        [
          '018f0b5d-6b2e-7c80-8000-000000000014',
          '018f0b5d-6b2e-7c80-8000-000000000011',
          '018f0b5d-6b2e-7c80-8000-000000000012',
          '018f0b5d-6b2e-7c80-8000-000000000013',
        ],
      ),
      (
        IntentionScope.all,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.updatedAt,
          direction: IntentionCatalogSortDirection.descending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000011',
          '018f0b5d-6b2e-7c80-8000-000000000014',
          '018f0b5d-6b2e-7c80-8000-000000000012',
          '018f0b5d-6b2e-7c80-8000-000000000013',
        ],
      ),
      (
        IntentionScope.all,
        const IntentionCatalogOrder(
          field: IntentionCatalogSortField.updatedAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        [
          '018f0b5d-6b2e-7c80-8000-000000000013',
          '018f0b5d-6b2e-7c80-8000-000000000012',
          '018f0b5d-6b2e-7c80-8000-000000000014',
          '018f0b5d-6b2e-7c80-8000-000000000011',
        ],
      ),
    ];

    for (final (scope, order, expectedIds) in cases) {
      final page = _firstPage(
        await repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: scope,
            titleFilter: null,
            order: order,
            pageSize: 100,
          ),
        ),
      );

      expect(page.totalCount, expectedIds.length);
      expect(
        page.items.map((summary) => summary.id.toCanonicalString()),
        expectedIds,
      );
      expect(page.nextCursor, isNull);
    }
  });

  test(
    'упорядочивает сохранённые убывающие timestamps с tie-breaker по ID',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000121',
        title: 'Первое',
        createdAt: DateTime.utc(2026, 9, 3, 12),
        updatedAt: DateTime.utc(2026, 9, 3, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000122',
        title: 'Второе',
        createdAt: DateTime.utc(2026, 9, 3, 11),
        updatedAt: DateTime.utc(2026, 9, 3, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000123',
        title: 'Третье',
        createdAt: DateTime.utc(2026, 9, 3, 10),
        updatedAt: DateTime.utc(2026, 9, 3, 9),
      );

      final page = _firstPage(
        await repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: null,
            order: const IntentionCatalogOrder(
              field: IntentionCatalogSortField.updatedAt,
              direction: IntentionCatalogSortDirection.descending,
            ),
            pageSize: 3,
          ),
        ),
      );

      expect(page.items.map((item) => item.id.toCanonicalString()), [
        '018f0b5d-6b2e-7c80-8000-000000000121',
        '018f0b5d-6b2e-7c80-8000-000000000122',
        '018f0b5d-6b2e-7c80-8000-000000000123',
      ]);
      expect(page.items.map((item) => item.updatedAt.value), [
        DateTime.utc(2026, 9, 3, 10),
        DateTime.utc(2026, 9, 3, 10),
        DateTime.utc(2026, 9, 3, 9),
      ]);
    },
  );

  test(
    'применяет FTS-фильтр к count и ограниченному чтению без OFFSET',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000021',
        title: 'Купить молоко',
        description: 'В фермерском магазине',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000022',
        title: 'Молоко в запас',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000023',
        title: 'Заварить чай',
        createdAt: DateTime.utc(2026, 9, 2, 12),
      );
      trace.statements.clear();

      final page = _firstPage(
        await repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: IntentionScope.active,
            titleFilter: '  МОЛО  ',
            order: IntentionCatalogOrder.createdAtDescending,
            pageSize: 100,
          ),
        ),
      );

      expect(page.totalCount, 2);
      expect(page.items.map((summary) => summary.title), [
        'Молоко в запас',
        'Купить молоко',
      ]);
      expect(page.items.last.hasDescription, isTrue);
      expect(
        trace.statements.where((statement) => statement.contains('COUNT(')),
        hasLength(1),
      );
      expect(
        trace.statements.where((statement) => statement.contains('MATCH')),
        hasLength(2),
      );
      expect(
        trace.statements.where((statement) => statement.contains('LIMIT')),
        hasLength(1),
      );
      expect(trace.statements, isNot(anyElement(contains('OFFSET'))));
    },
  );

  test('применяет полный Default Case Folding к фильтру названия', () async {
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000028',
      title: 'Прогуляться по Straße',
      createdAt: DateTime.utc(2026, 9, 2, 12),
    );

    final page = _firstPage(
      await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: 'STRASSE',
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        ),
      ),
    );

    expect(page.totalCount, 1);
    expect(page.items.single.title, 'Прогуляться по Straße');
  });

  test('сохраняет согласованный snapshot, когда запись отдельного search key отклонена', () async {
    const id = '018f0b5d-6b2e-7c80-8000-000000000024';
    await _insertIntention(
      database,
      id: id,
      title: 'Купить молоко',
      createdAt: DateTime.utc(2026, 9, 2, 10),
    );
    await expectLater(
      database.customStatement(
        'UPDATE intentions SET title_search_key = ? WHERE id = ?',
        ['посторонний ключ', id],
      ),
      throwsA(isA<Exception>()),
    );

    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'молоко',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ),
    );

    expect(_firstPage(result).items.single.id, _id(id));
  });

  test('не создаёт ложное совпадение, когда запись отдельного search key отклонена', () async {
    const id = '018f0b5d-6b2e-7c80-8000-000000000025';
    await _insertIntention(
      database,
      id: id,
      title: 'Купить молоко',
      createdAt: DateTime.utc(2026, 9, 2, 10),
    );
    await expectLater(
      database.customStatement(
        'UPDATE intentions SET title_search_key = ? WHERE id = ?',
        ['посторонний ключ', id],
      ),
      throwsA(isA<Exception>()),
    );

    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'посторонний',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ),
    );

    expect(_firstPage(result).items, isEmpty);
  });

  test('сохраняет первую страницу при отклонённой записи отдельного search key за её границей', () async {
    const visibleId = '018f0b5d-6b2e-7c80-8000-000000000026';
    const lookaheadId = '018f0b5d-6b2e-7c80-8000-000000000027';
    await _insertIntention(
      database,
      id: visibleId,
      title: 'Видимое намерение',
      createdAt: DateTime.utc(2026, 9, 2, 11),
    );
    await _insertIntention(
      database,
      id: lookaheadId,
      title: 'Намерение за границей',
      createdAt: DateTime.utc(2026, 9, 2, 10),
    );
    await expectLater(
      database.customStatement(
        'UPDATE intentions SET title_search_key = ? WHERE id = ?',
        ['повреждённый ключ', lookaheadId],
      ),
      throwsA(isA<Exception>()),
    );

    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ),
    );

    expect(_firstPage(result).items.single.id, _id(visibleId));
  });

  test(
    'сохраняет continuation page при отклонённой записи отдельного search key',
    () async {
      const firstId = '018f0b5d-6b2e-7c80-8000-000000000030';
      const corruptedId = '018f0b5d-6b2e-7c80-8000-000000000031';
      await _insertIntention(
        database,
        id: firstId,
        title: 'Первая строка',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: corruptedId,
        title: 'Строка продолжения',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      final firstQuery = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: const IntentionCatalogOrder(
          field: IntentionCatalogSortField.createdAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        pageSize: 1,
      );
      final cursor = _firstPage(await repository.getCatalogPage(firstQuery))
          .nextCursor!;
      await expectLater(
        database.customStatement(
          'UPDATE intentions SET title_search_key = ? WHERE id = ?',
          ['повреждённый ключ', corruptedId],
        ),
        throwsA(isA<Exception>()),
      );

      final result = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: firstQuery.scope,
          titleFilter: null,
          order: firstQuery.order,
          pageSize: firstQuery.pageSize,
          cursor: cursor,
        ),
      );

      expect(_continuationPage(result).items.single.id, _id(corruptedId));
    },
  );

  test(
    'хранилище не допускает пустое или полностью пробельное описание',
    () async {
      const id = '018f0b5d-6b2e-7c80-8000-000000000028';
      await _insertIntention(
        database,
        id: id,
        title: 'Намерение с описанием',
        description: 'Исходное описание',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );

      for (final description in const ['', ' \t\r\n ']) {
        await expectLater(
          database.customStatement(
            'UPDATE intentions SET description = ? WHERE id = ?',
            [description, id],
          ),
          throwsA(isA<SqliteException>()),
        );
      }
    },
  );

  test(
    'продолжает каталог keyset-порциями для всех порядков без повторного COUNT',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000041',
        title: 'Первое',
        createdAt: DateTime.utc(2026, 9, 2, 10),
        updatedAt: DateTime.utc(2026, 9, 2, 12),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000042',
        title: 'Второе',
        createdAt: DateTime.utc(2026, 9, 2, 10),
        updatedAt: DateTime.utc(2026, 9, 2, 12),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000043',
        title: 'Третье',
        createdAt: DateTime.utc(2026, 9, 2, 10),
        updatedAt: DateTime.utc(2026, 9, 2, 11),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000044',
        title: 'Четвёртое',
        createdAt: DateTime.utc(2026, 9, 2, 9),
        updatedAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000045',
        title: 'Пятое',
        createdAt: DateTime.utc(2026, 9, 2, 12),
        updatedAt: DateTime.utc(2026, 9, 2, 13),
      );

      final cases = <(IntentionCatalogOrder, List<String>)>[
        (
          const IntentionCatalogOrder(
            field: IntentionCatalogSortField.createdAt,
            direction: IntentionCatalogSortDirection.ascending,
          ),
          [
            '018f0b5d-6b2e-7c80-8000-000000000044',
            '018f0b5d-6b2e-7c80-8000-000000000041',
            '018f0b5d-6b2e-7c80-8000-000000000042',
            '018f0b5d-6b2e-7c80-8000-000000000043',
            '018f0b5d-6b2e-7c80-8000-000000000045',
          ],
        ),
        (
          IntentionCatalogOrder.createdAtDescending,
          [
            '018f0b5d-6b2e-7c80-8000-000000000045',
            '018f0b5d-6b2e-7c80-8000-000000000041',
            '018f0b5d-6b2e-7c80-8000-000000000042',
            '018f0b5d-6b2e-7c80-8000-000000000043',
            '018f0b5d-6b2e-7c80-8000-000000000044',
          ],
        ),
        (
          const IntentionCatalogOrder(
            field: IntentionCatalogSortField.updatedAt,
            direction: IntentionCatalogSortDirection.ascending,
          ),
          [
            '018f0b5d-6b2e-7c80-8000-000000000044',
            '018f0b5d-6b2e-7c80-8000-000000000043',
            '018f0b5d-6b2e-7c80-8000-000000000041',
            '018f0b5d-6b2e-7c80-8000-000000000042',
            '018f0b5d-6b2e-7c80-8000-000000000045',
          ],
        ),
        (
          const IntentionCatalogOrder(
            field: IntentionCatalogSortField.updatedAt,
            direction: IntentionCatalogSortDirection.descending,
          ),
          [
            '018f0b5d-6b2e-7c80-8000-000000000045',
            '018f0b5d-6b2e-7c80-8000-000000000041',
            '018f0b5d-6b2e-7c80-8000-000000000042',
            '018f0b5d-6b2e-7c80-8000-000000000043',
            '018f0b5d-6b2e-7c80-8000-000000000044',
          ],
        ),
      ];

      for (final (order, expectedIds) in cases) {
        final query = IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          order: order,
          pageSize: 2,
        );
        final firstPage = _firstPage(await repository.getCatalogPage(query));
        trace.statements.clear();

        final actualIds = [
          ...firstPage.items.map((summary) => summary.id.toCanonicalString()),
        ];
        var cursor = firstPage.nextCursor;
        while (cursor != null) {
          final continuation = _continuationPage(
            await repository.getCatalogPage(
              IntentionCatalogQuery(
                scope: query.scope,
                titleFilter: null,
                order: query.order,
                pageSize: query.pageSize,
                cursor: cursor,
              ),
            ),
          );
          actualIds.addAll(
            continuation.items.map((summary) => summary.id.toCanonicalString()),
          );
          cursor = continuation.nextCursor;
        }

        expect(actualIds, expectedIds);
        expect(
          trace.statements.where((statement) => statement.contains('COUNT(')),
          isEmpty,
        );
        expect(trace.statements, isNot(anyElement(contains('OFFSET'))));
      }
    },
  );

  test(
    'отклоняет cursor другого адаптера и cursor с другими параметрами до SQL',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000051',
        title: 'Первое',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000052',
        title: 'Первое дополнение',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'Первое',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      );
      final cursor = _firstPage(await repository.getCatalogPage(query))
          .nextCursor!;
      final invalidQueries = [
        IntentionCatalogQuery(
          scope: query.scope,
          titleFilter: 'Другое',
          order: query.order,
          pageSize: query.pageSize,
          cursor: cursor,
        ),
        IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: 'Первое',
          order: query.order,
          pageSize: query.pageSize,
          cursor: cursor,
        ),
        IntentionCatalogQuery(
          scope: query.scope,
          titleFilter: 'Первое',
          order: const IntentionCatalogOrder(
            field: IntentionCatalogSortField.updatedAt,
            direction: IntentionCatalogSortDirection.descending,
          ),
          pageSize: query.pageSize,
          cursor: cursor,
        ),
        IntentionCatalogQuery(
          scope: query.scope,
          titleFilter: 'Первое',
          order: query.order,
          pageSize: query.pageSize,
          cursor: const _ForeignCatalogCursor(),
        ),
      ];

      for (final invalidQuery in invalidQueries) {
        trace.statements.clear();

        final result = await repository.getCatalogPage(invalidQuery);

        expect(result, isA<ResultFailure<IntentionCatalogPage>>());
        expect(
          (result as ResultFailure<IntentionCatalogPage>).failure,
          isA<IntentionValidationFailure>(),
        );
        expect(trace.statements, isEmpty);
      }
    },
  );

  test(
    'отклоняет cursor другого экземпляра repository до обращения к SQLite',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000056',
        title: 'Первое',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000057',
        title: 'Второе',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      );
      final cursor = _firstPage(await repository.getCatalogPage(query))
          .nextCursor!;
      final sharedDatabaseRepository = DriftIntentionRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 2),
        diagnostics,
      );
      final recreatedRepository = DriftIntentionRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 2),
        diagnostics,
      );
      final foreignTrace = _SelectTrace();
      final previousMultipleDatabaseWarning =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousMultipleDatabaseWarning,
      );
      final foreignDatabase = AppDatabase(
        observeConfiguredLocalDatabaseConnection(
          openInMemoryLocalDatabase(),
          foreignTrace,
        ),
      );
      await foreignDatabase.open();
      addTearDown(foreignDatabase.close);
      final foreignDatabaseRepository = DriftIntentionRepository(
        foreignDatabase,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 2),
        diagnostics,
      );
      final continuationQuery = IntentionCatalogQuery(
        scope: query.scope,
        titleFilter: null,
        order: query.order,
        pageSize: query.pageSize,
        cursor: cursor,
      );

      for (final foreignRepository in [
        sharedDatabaseRepository,
        recreatedRepository,
        foreignDatabaseRepository,
      ]) {
        trace.statements.clear();
        foreignTrace.statements.clear();

        final result = await foreignRepository.getCatalogPage(
          continuationQuery,
        );

        expect(result, isA<ResultFailure<IntentionCatalogPage>>());
        expect(
          (result as ResultFailure<IntentionCatalogPage>).failure,
          isA<IntentionValidationFailure>(),
        );
        expect(trace.statements, isEmpty);
        expect(foreignTrace.statements, isEmpty);
      }
    },
  );

  test('продолжает независимые цепочки одного repository вперемешку', () async {
    for (final (id, title, createdAt) in [
      (
        '018f0b5d-6b2e-7c80-8000-000000000058',
        'Первое',
        DateTime.utc(2026, 9, 2, 10),
      ),
      (
        '018f0b5d-6b2e-7c80-8000-000000000059',
        'Второе',
        DateTime.utc(2026, 9, 2, 11),
      ),
      (
        '018f0b5d-6b2e-7c80-8000-00000000005a',
        'Третье',
        DateTime.utc(2026, 9, 2, 12),
      ),
    ]) {
      await _insertIntention(
        database,
        id: id,
        title: title,
        createdAt: createdAt,
      );
    }
    final ascendingQuery = IntentionCatalogQuery(
      scope: IntentionScope.active,
      titleFilter: null,
      order: const IntentionCatalogOrder(
        field: IntentionCatalogSortField.createdAt,
        direction: IntentionCatalogSortDirection.ascending,
      ),
      pageSize: 1,
    );
    final descendingQuery = IntentionCatalogQuery(
      scope: ascendingQuery.scope,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: ascendingQuery.pageSize,
    );
    final ascendingCursor = _firstPage(
      await repository.getCatalogPage(ascendingQuery),
    ).nextCursor!;
    final descendingCursor = _firstPage(
      await repository.getCatalogPage(descendingQuery),
    ).nextCursor!;

    final ascendingContinuation = _continuationPage(
      await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: ascendingQuery.scope,
          titleFilter: null,
          order: ascendingQuery.order,
          pageSize: ascendingQuery.pageSize,
          cursor: ascendingCursor,
        ),
      ),
    );
    final descendingContinuation = _continuationPage(
      await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: descendingQuery.scope,
          titleFilter: null,
          order: descendingQuery.order,
          pageSize: descendingQuery.pageSize,
          cursor: descendingCursor,
        ),
      ),
    );

    expect(
      ascendingContinuation.items.single.id,
      _id('018f0b5d-6b2e-7c80-8000-000000000059'),
    );
    expect(
      descendingContinuation.items.single.id,
      _id('018f0b5d-6b2e-7c80-8000-000000000059'),
    );
  });

  test(
    'использует value boundary после удаления и вставок вокруг cursor',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000061',
        title: 'Первое',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000062',
        title: 'Второе',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000064',
        title: 'Четвёртое',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000065',
        title: 'Пятое',
        createdAt: DateTime.utc(2026, 9, 2, 12),
      );
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: const IntentionCatalogOrder(
          field: IntentionCatalogSortField.createdAt,
          direction: IntentionCatalogSortDirection.ascending,
        ),
        pageSize: 2,
      );
      final cursor = _firstPage(await repository.getCatalogPage(query))
          .nextCursor!;
      await (database.delete(database.intentions)..where(
            (row) => row.id.equals('018f0b5d-6b2e-7c80-8000-000000000062'),
          ))
          .go();
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000060',
        title: 'До границы',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000063',
        title: 'После границы',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );

      final continuation = _continuationPage(
        await repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: query.scope,
            titleFilter: null,
            order: query.order,
            pageSize: query.pageSize,
            cursor: cursor,
          ),
        ),
      );

      expect(
        continuation.items.map((summary) => summary.id.toCanonicalString()),
        [
          '018f0b5d-6b2e-7c80-8000-000000000063',
          '018f0b5d-6b2e-7c80-8000-000000000064',
        ],
      );
      expect(continuation.nextCursor, isNotNull);
      expect(trace.statements, isNot(anyElement(contains('OFFSET'))));
    },
  );

  test('диагностирует typed failure чтения первой страницы без пользовательских данных', () async {
    trace.failure = SqliteException(
      extendedResultCode: SqlError.SQLITE_BUSY,
      message: 'CANARY-исключение-личные-данные',
    );

    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'CANARY-фильтр-личные-данные',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ),
    );

    expect(result, isA<ResultFailure<IntentionCatalogPage>>());
    expect(
      (result as ResultFailure<IntentionCatalogPage>).failure,
      isA<IntentionUnavailableFailure>(),
    );
    expect(diagnostics.events, [
      isA<CatalogPageReadDiagnosticsEvent>().having(
        (event) => event.status,
        'status',
        isA<DiagnosticsStarted>(),
      ),
      isA<CatalogPageReadDiagnosticsEvent>()
          .having((event) => event.pageSize, 'pageSize', 1)
          .having(
            (event) => event.status,
            'status',
            isA<DiagnosticsFailed>().having(
              (status) => status.code,
              'code',
              DiagnosticsFailureCode.unavailable,
            ),
          ),
    ]);
    expect(
      diagnostics.events.toString(),
      isNot(contains('CANARY-исключение-личные-данные')),
    );
    expect(
      diagnostics.events.toString(),
      isNot(contains('CANARY-фильтр-личные-данные')),
    );
  });
}

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isArchived = false,
  required DateTime createdAt,
  DateTime? updatedAt,
}) => database
    .into(database.intentions)
    .insert(
      IntentionsCompanion.insert(
        id: id,
        title: title,
        description: Value(description),
        isArchived: Value(isArchived),
        createdAt: createdAt.microsecondsSinceEpoch,
        updatedAt: (updatedAt ?? createdAt).microsecondsSinceEpoch,
      ),
    );

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

IntentionCatalogFirstPage _firstPage(Result<IntentionCatalogPage> result) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  final page = (result as ResultSuccess<IntentionCatalogPage>).value;
  expect(page, isA<IntentionCatalogFirstPage>());
  return page as IntentionCatalogFirstPage;
}

IntentionCatalogContinuationPage _continuationPage(
  Result<IntentionCatalogPage> result,
) {
  expect(result, isA<ResultSuccess<IntentionCatalogPage>>());
  final page = (result as ResultSuccess<IntentionCatalogPage>).value;
  expect(page, isA<IntentionCatalogContinuationPage>());
  return page as IntentionCatalogContinuationPage;
}

final class _ForeignCatalogCursor implements IntentionCatalogCursor {
  const _ForeignCatalogCursor();
}

final class _SelectTrace extends LocalDatabaseConnectionObserver {
  final List<String> statements = [];
  Object? failure;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    statements.add(statement.statements.single);
    final failure = this.failure;
    if (failure != null) throw failure;
  }
}
