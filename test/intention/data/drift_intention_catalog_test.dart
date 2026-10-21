import 'dart:async';
import 'dart:math';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/tag_storage_fixture.dart';

void main() {
  late AppDatabase database;
  late InMemoryDiagnosticsSink diagnostics;
  late DriftPersonalGraphRepository repository;
  late _SelectTrace trace;
  late Database raw;

  setUp(() async {
    trace = _SelectTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (connection) => raw = connection),
        trace,
      ),
    );
    await database.open();
    diagnostics = InMemoryDiagnosticsSink();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 2),
      diagnostics,
    );
  });

  tearDown(() => database.close());

  group('Совместный запрос каталога', () {
    final originalFilter = IntentionTagFilter(
      requiredTagIds: [_tagId(firstTagNumber)],
      excludedTagIds: [_tagId(lastTagNumber)],
    );
    test('продолжает выдачу при другом порядке и повторах тех же условий', () async {
      seedTagStorageFixture(raw);
      seedRawGraph(raw, () {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          _uuid(303),
          'Отдых',
        ]);
        for (final number in [1, 2]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [_uuid(303), _uuid(number)],
          );
        }
      });
      final first = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [_tagId(firstTagNumber), _tagId(303)],
              excludedTagIds: [_tagId(lastTagNumber), _tagId(304)],
            ),
            excludedIntentionId: _id(_uuid(3)),
          ),
        ),
      );
      expect(first.totalCount, 2);
      expect(first.items.single.id, _id(_uuid(1)));
      expect(first.nextCursor, isNotNull);

      final next = _continuationPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [
                _tagId(303),
                _tagId(firstTagNumber),
                _tagId(303),
              ],
              excludedTagIds: [_tagId(304), _tagId(lastTagNumber), _tagId(304)],
            ),
            excludedIntentionId: _id(_uuid(3)),
            cursor: first.nextCursor,
          ),
        ),
      );
      expect(next.items.single.id, _id(_uuid(2)));
      expect(next.nextCursor, isNull);
    });

    test(
      'переименование выбранного тега сохраняет совместимость курсора',
      () async {
        seedTagStorageFixture(raw);
        final first = _firstPage(
          await repository.getCatalogPage(_tagQuery(tagFilter: originalFilter)),
        );
        expect(first.nextCursor, isNotNull);
        expect(
          await repository.execute(
            UpdateTag(
              tagId: _tagId(firstTagNumber),
              name: TagName.fromInput('Семья'),
              color: null,
            ),
          ),
          isA<GraphCommandSucceeded>(),
        );

        final next = _continuationPage(
          await repository.getCatalogPage(
            _tagQuery(tagFilter: originalFilter, cursor: first.nextCursor),
          ),
        );
        expect(next.items.single.id, _id(_uuid(2)));
        expect(next.items.single.tags.single.id, _tagId(firstTagNumber));
        expect(next.items.single.tags.single.name.value, 'Семья');
        expect(next.nextCursor, isNull);
      },
    );

    // Порядок задаёт поле и направление; убывающее создание и возрастающее
    // обновление проходят каждое поле и направление, а ожидаемая выдача у них
    // отличается от порядка вставки.
    for (final (label, order, expectedNumbers) in [
      (
        'по созданию по убыванию',
        IntentionCatalogOrder.createdAtDescending,
        [
          for (var number = 121; number <= 235; number++) number,
          for (var number = 1; number <= 120; number++) number,
        ],
      ),
      (
        'по обновлению по возрастанию',
        IntentionCatalogOrder.updatedAtAscending,
        [
          for (var number = 161; number <= 235; number++) number,
          for (var number = 81; number <= 160; number++) number,
          for (var number = 1; number <= 80; number++) number,
        ],
      ),
    ]) {
      test('235 совместных совпадений ровно один раз: $label', () async {
        _seedJointCatalogPagingFixture(raw);
        final filter = IntentionTagFilter(
          requiredTagIds: [_tagId(1001), _tagId(1002)],
          excludedTagIds: [_tagId(1003), _tagId(1004)],
        );
        IntentionCatalogQuery query(IntentionCatalogCursor? cursor) =>
            IntentionCatalogQuery(
              scope: IntentionScope.active,
              readinessFilter: IntentionReadinessFilter.readyOnly,
              titleFilter: 'гулять',
              tagFilter: filter,
              excludedIntentionId: _id(_uuid(236)),
              order: order,
              pageSize: 100,
              cursor: cursor,
            );
        final first = _firstPage(await repository.getCatalogPage(query(null)));
        expect(first.totalCount, 235);
        expect(first.items, hasLength(100));
        expect(first.nextCursor, isNotNull);

        final items = [...first.items];
        final pageLengths = [first.items.length];
        var cursor = first.nextCursor;
        while (cursor != null) {
          final next = _continuationPage(
            await repository.getCatalogPage(query(cursor)),
          );
          expect(
            next.revision.compareTo(first.revision),
            GraphRevisionOrder.same,
          );
          items.addAll(next.items);
          pageLengths.add(next.items.length);
          cursor = next.nextCursor;
        }

        expect(pageLengths, [100, 100, 35]);
        expect(items.map((item) => item.id), [
          for (final number in expectedNumbers) _id(_uuid(number)),
        ]);
        expect(items.map((item) => item.id).toSet(), hasLength(235));
        expect(items.every(query(null).includes), isTrue);
        expect(
          items.every(
            (item) =>
                item.tags.length == 2 &&
                item.tags
                    .map((tag) => tag.id)
                    .toSet()
                    .containsAll(filter.requiredTagIds),
          ),
          isTrue,
        );
      });
    }

    test('находит совпадение за пределами прежних ста строк', () async {
      raw.execute('BEGIN');
      seedRawGraph(raw, () {
        for (var number = 1; number <= 120; number++) {
          raw.execute(
            'INSERT INTO intentions (id, title, created_at, updated_at) VALUES (?, ?, ?, ?)',
            [_uuid(number), 'Гулять $number', number, number],
          );
        }
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          _uuid(1000),
          'Здоровье',
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(1000), _uuid(110)],
        );
      });
      raw.execute('COMMIT');
      final oldPage = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(tagFilter: IntentionTagFilter.empty, pageSize: 100),
        ),
      );
      expect(oldPage.totalCount, 120);
      expect(oldPage.items, hasLength(100));
      expect(
        oldPage.items.map((item) => item.id),
        isNot(contains(_id(_uuid(110)))),
      );

      final page = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [_tagId(1000)],
              excludedTagIds: [_tagId(1001)],
            ),
            titleFilter: 'гулять',
            pageSize: 100,
          ),
        ),
      );
      expect(page.totalCount, 1);
      expect(page.items.single.id, _id(_uuid(110)));
      expect(page.nextCursor, isNull);
    });

    test('1203 обязательных и 1203 исключённых условий не ограничены порцией или SQL-параметрами', () async {
      seedLargeTagReadFixture(raw, includeDenseRecipients: true);
      trace.parameterLimit = 400;
      final required = [
        for (var number = 10000; number < 11203; number++) _tagId(number),
      ];
      final excluded = [
        for (var number = 40000; number < 41203; number++) _tagId(number),
      ];
      final page = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: required,
              excludedTagIds: excluded,
            ),
          ),
        ),
      );
      // Все теги фикстуры назначены второму и четвёртому намерениям.
      expect(page.totalCount, 2);
      expect(page.items.single.id, _id(_uuid(2)));
      expect(page.items.single.tags, hasLength(1203));
      final continuation = _continuationPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: required,
              excludedTagIds: excluded,
            ),
            cursor: page.nextCursor,
          ),
        ),
      );
      expect(continuation.items.single.id, _id(_uuid(4)));
      expect(continuation.items.single.tags, hasLength(1203));
      expect(continuation.nextCursor, isNull);

      final missingLastRequired = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [...required, _tagId(90000)],
            ),
          ),
        ),
      );
      expect(missingLastRequired.totalCount, 0);
      expect(missingLastRequired.items, isEmpty);
      final lastExclusion = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              excludedTagIds: [...excluded, required.last],
            ),
          ),
        ),
      );
      expect(lastExclusion.totalCount, 1);
      expect(lastExclusion.items.single.id, _id(_uuid(3)));
    });

    test('сохраняет все охваты, готовность и исключает одноимённого участника до порции', () async {
      for (var number = 1; number <= 6; number++) {
        await _insertIntention(
          database,
          id: _uuid(number),
          title: 'Гулять',
          isActionReady: number.isOdd || number == 6,
          isArchived: number == 3 || number == 4,
          createdAt: DateTime.utc(2026, 9, 2, number),
        );
      }
      seedRawGraph(raw, () {
        for (final (number, name) in [(101, 'Здоровье'), (102, 'Спорт')]) {
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            _uuid(number),
            name,
          ]);
        }
        for (var number = 1; number <= 6; number++) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [_uuid(101), _uuid(number)],
          );
        }
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(102), _uuid(6)],
        );
      });
      final filter = IntentionTagFilter(
        requiredTagIds: [_tagId(101)],
        excludedTagIds: [_tagId(102)],
      );
      for (final (scope, readiness, numbers) in [
        (IntentionScope.active, IntentionReadinessFilter.all, [1, 2]),
        (IntentionScope.archived, IntentionReadinessFilter.all, [3, 4]),
        (IntentionScope.all, IntentionReadinessFilter.all, [1, 2, 3, 4]),
        (IntentionScope.active, IntentionReadinessFilter.readyOnly, [1]),
        (IntentionScope.archived, IntentionReadinessFilter.readyOnly, [3]),
        (IntentionScope.all, IntentionReadinessFilter.readyOnly, [1, 3]),
      ]) {
        IntentionCatalogQuery query(IntentionCatalogCursor? cursor) =>
            _tagQuery(
              tagFilter: filter,
              scope: scope,
              readinessFilter: readiness,
              excludedIntentionId: _id(_uuid(5)),
              titleFilter: 'гулять',
              cursor: cursor,
            );
        final first = _firstPage(await repository.getCatalogPage(query(null)));
        expect(first.totalCount, numbers.length);
        final items = [...first.items];
        var cursor = first.nextCursor;
        while (cursor != null) {
          final page = _continuationPage(
            await repository.getCatalogPage(query(cursor)),
          );
          items.addAll(page.items);
          cursor = page.nextCursor;
        }
        expect(
          items.map((item) => item.id),
          numbers.map((number) => _id(_uuid(number))),
        );
        expect(items.every(query(null).includes), isTrue);
      }
      final otherSameTitle = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: filter,
            scope: IntentionScope.active,
            excludedIntentionId: _id(_uuid(1)),
          ),
        ),
      );
      expect(otherSameTitle.totalCount, 2);
      expect(otherSameTitle.items.single.id, _id(_uuid(2)));
    });

    test('принадлежность снимка команды учитывает собственные теги и исключённого участника', () async {
      seedTagStorageFixture(raw);
      final saved = await repository.execute(
        UpdateIntention(
          id: _id(_uuid(1)),
          title: 'Новое намерение',
          description: null,
        ),
      );
      expect(
        saved,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      final mutation =
          (saved
                  as ResultSuccess<
                    ConfirmedGraphResult<IntentionCommandSuccess>
                  >)
              .value
              .value
              .catalogMutation;
      for (final snapshot in [mutation.before!, mutation.after!]) {
        final required = _tagQuery(
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tagId(firstTagNumber)],
            excludedTagIds: [_tagId(lastTagNumber)],
          ),
          scope: IntentionScope.active,
          readinessFilter: IntentionReadinessFilter.readyOnly,
          titleFilter: 'намерение',
        );
        expect(snapshot.matches(required), isTrue);
        expect(
          snapshot.matches(
            _tagQuery(
              tagFilter: IntentionTagFilter(
                requiredTagIds: [_tagId(lastTagNumber)],
              ),
            ),
          ),
          isFalse,
        );
        expect(
          snapshot.matches(
            _tagQuery(
              tagFilter: IntentionTagFilter(
                excludedTagIds: [_tagId(firstTagNumber)],
              ),
            ),
          ),
          isFalse,
        );
        expect(
          snapshot.matches(
            _tagQuery(
              tagFilter: required.tagFilter,
              excludedIntentionId: snapshot.summary.id,
            ),
          ),
          isFalse,
        );
      }
    });

    test('чистые исключения допускают отсутствие тегов, пересечение даёт ноль', () async {
      for (var number = 1; number <= 4; number++) {
        await _insertIntention(
          database,
          id: _uuid(number),
          title: 'Намерение $number',
          createdAt: DateTime.utc(2026, 9, 2, number),
        );
      }
      seedRawGraph(raw, () {
        for (final (number, name, intention) in [
          (101, 'Здоровье', 2),
          (102, 'Спорт', 3),
          (103, 'Работа', 4),
        ]) {
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            _uuid(number),
            name,
          ]);
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [_uuid(number), _uuid(intention)],
          );
        }
      });

      final exclusions = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              excludedTagIds: [_tagId(102), _tagId(103)],
            ),
            pageSize: 100,
          ),
        ),
      );
      expect(exclusions.totalCount, 2);
      expect(exclusions.items.map((item) => item.id), [
        _id(_uuid(1)),
        _id(_uuid(2)),
      ]);
      expect(exclusions.items.first.tags, isEmpty);
      final impossible = _firstPage(
        await repository.getCatalogPage(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [_tagId(101)],
              excludedTagIds: [_tagId(101)],
            ),
          ),
        ),
      );
      expect(impossible.totalCount, 0);
      expect(impossible.items, isEmpty);
      expect(impossible.nextCursor, isNull);
    });

    test('удалённые идентификаторы сохраняют смысл после создания одноимённого тега', () async {
      seedTagStorageFixture(raw);
      final required = _tagQuery(
        tagFilter: IntentionTagFilter(requiredTagIds: [_tagId(firstTagNumber)]),
      );
      final excluded = _tagQuery(
        tagFilter: IntentionTagFilter(excludedTagIds: [_tagId(firstTagNumber)]),
        pageSize: 100,
      );
      expect(
        _firstPage(await repository.getCatalogPage(required)).totalCount,
        2,
      );
      expect(
        _firstPage(await repository.getCatalogPage(excluded)).totalCount,
        1,
      );
      expect(
        await repository.execute(DeleteTag(_tagId(firstTagNumber))),
        isA<GraphCommandSucceeded>(),
      );
      seedRawGraph(raw, () {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          _uuid(9000),
          'Дом',
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(9000), _uuid(1)],
        );
      });

      final missingRequired = _firstPage(
        await repository.getCatalogPage(required),
      );
      final missingExcluded = _firstPage(
        await repository.getCatalogPage(excluded),
      );
      expect(missingRequired.totalCount, 0);
      expect(missingRequired.items, isEmpty);
      expect(missingRequired.nextCursor, isNull);
      expect(missingExcluded.totalCount, 3);
      expect(missingExcluded.items.map((item) => item.id), [
        _id(_uuid(1)),
        _id(_uuid(2)),
        _id(_uuid(3)),
      ]);
      expect(missingExcluded.items.first.tags.map((tag) => tag.id), [
        _tagId(9000),
      ]);
      expect(required.tagFilter.requiredTagIds, {_tagId(firstTagNumber)});
      expect(excluded.tagFilter.excludedTagIds, {_tagId(firstTagNumber)});
    });

    test(
      'применяет название и все собственные теги до количества и порции',
      () async {
        for (final (number, title) in [
          (1, 'Ходить в парк'),
          (2, 'Ходить до магазина'),
          (3, 'Ходить в зал'),
          (4, 'Читать в тишине'),
          (5, 'Ходить с семьёй'),
          (6, 'Ходить на работу'),
        ]) {
          await _insertIntention(
            database,
            id: _uuid(number),
            title: title,
            createdAt: DateTime.utc(2026, 9, 2, number),
          );
        }
        seedRawGraph(raw, () {
          for (final (number, name) in [
            (101, 'Здоровье'),
            (102, 'Отдых'),
            (103, 'Спорт'),
            (104, 'Работа'),
          ]) {
            raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
              _uuid(number),
              name,
            ]);
          }
          for (final (intention, tags) in [
            (1, [101, 102]),
            (2, [101]),
            (3, [101, 102, 103]),
            (4, [101, 102]),
            (6, [101, 102, 104]),
          ]) {
            for (final tag in tags) {
              raw.execute(
                'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
                [_uuid(tag), _uuid(intention)],
              );
            }
          }
          raw.execute(
            'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, ?)',
            [_uuid(500), _uuid(1), _uuid(5), 'need', 2],
          );
        });
        final filter = IntentionTagFilter(
          requiredTagIds: [_tagId(101), _tagId(102)],
          excludedTagIds: [_tagId(103), _tagId(104)],
        );
        final before = raw
            .select('SELECT * FROM intentions ORDER BY id')
            .map((row) => Map.of(row))
            .toList();
        final revision = _firstPage(
          await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: IntentionScope.all,
              titleFilter: null,
              order: IntentionCatalogOrder.createdAtAscending,
              pageSize: 1,
            ),
          ),
        ).revision;

        final page = _firstPage(
          await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: IntentionScope.all,
              titleFilter: '  ХОДИТЬ  ',
              tagFilter: filter,
              order: IntentionCatalogOrder.createdAtAscending,
              pageSize: 1,
            ),
          ),
        );

        expect(page.totalCount, 1);
        expect(page.items.map((item) => item.id), [_id(_uuid(1))]);
        expect(page.items.single.tags.map((tag) => tag.id), [
          _tagId(101),
          _tagId(102),
        ]);
        expect(page.nextCursor, isNull);
        final tagsOnlyQuery = IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: null,
          tagFilter: filter,
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
        );
        final tagsOnly = _firstPage(
          await repository.getCatalogPage(tagsOnlyQuery),
        );
        expect(tagsOnly.totalCount, 2);
        expect(tagsOnly.items.map((item) => item.id), [_id(_uuid(1))]);
        final continuation = _continuationPage(
          await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: tagsOnlyQuery.scope,
              titleFilter: null,
              tagFilter: filter,
              order: tagsOnlyQuery.order,
              pageSize: 1,
              cursor: tagsOnly.nextCursor,
            ),
          ),
        );
        expect(continuation.items.map((item) => item.id), [_id(_uuid(4))]);
        expect(continuation.nextCursor, isNull);
        expect(page.revision.compareTo(revision), GraphRevisionOrder.same);
        expect(
          raw
              .select('SELECT * FROM intentions ORDER BY id')
              .map((row) => Map.of(row)),
          before,
        );
      },
    );

    test('отбирает по собственным назначениям без влияния тегов связанных намерений', () async {
      // Номер намерения → (название, в архиве, собственные теги).
      const intentions = <int, (String, bool, Set<int>)>{
        1: ('Ходить в парк', false, {101, 102}),
        2: ('Ходить в зал', false, {101}),
        3: ('Читать книгу', false, {102, 103}),
        4: ('Ходить на работу', false, {}),
        5: ('Ходить к морю', true, {101, 102}),
        6: ('Читать письма', true, {103}),
        7: ('Ходить в горы', true, {101}),
        8: ('Читать стихи', true, {}),
      };
      for (final MapEntry(key: number, value: (title, archived, _))
          in intentions.entries) {
        await _insertIntention(
          database,
          id: _uuid(number),
          title: title,
          isArchived: archived,
          createdAt: DateTime.utc(2026, 9, 2, number),
        );
      }
      seedRawGraph(raw, () {
        for (final (number, name) in [
          (101, 'Здоровье'),
          (102, 'Отдых'),
          (103, 'Работа'),
        ]) {
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            _uuid(number),
            name,
          ]);
        }
        for (final MapEntry(key: number, value: (_, _, tags))
            in intentions.entries) {
          for (final tag in tags) {
            raw.execute(
              'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
              [_uuid(tag), _uuid(number)],
            );
          }
        }
        // Связи с помеченными соседями не дают намерению собственных назначений.
        for (final (relation, source, related, archived) in [
          (500, 4, 1, 0),
          (501, 2, 3, 0),
          (502, 8, 7, 1),
        ]) {
          raw.execute(
            'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
            [
              _uuid(relation),
              _uuid(source),
              _uuid(related),
              'need',
              2,
              archived,
            ],
          );
        }
      });
      // Тег 900 никогда не существовал либо физически удалён вместе с
      // назначениями: хранилище не содержит ни его, ни ссылок на него.
      final filters = [
        (<int>[], [103]),
        (<int>[], [101, 102, 103]),
        (<int>[], [900]),
        ([101, 102], <int>[]),
        ([102], <int>[]),
        ([900], <int>[]),
        ([101, 900], <int>[]),
        ([101], [103]),
        ([101], [900]),
        ([102], [102]),
        ([101, 102], [103, 900]),
      ];
      // Охват и фильтр названия не зависят от условий по тегам: две пары
      // проходят каждое значение обоих измерений.
      for (final (required, excluded) in filters) {
        for (final (scope, titleFilter) in [
          (IntentionScope.active, null),
          (IntentionScope.archived, 'ходить'),
        ]) {
          final label =
              'обязательные $required, исключённые $excluded, '
              '$scope, название $titleFilter';
          final expected = [
            for (final MapEntry(key: number, value: (title, archived, tags))
                in intentions.entries)
              if (archived == (scope == IntentionScope.archived) &&
                  (titleFilter == null ||
                      title.toLowerCase().contains(titleFilter)) &&
                  tags.containsAll(required) &&
                  !excluded.any(tags.contains))
                _id(_uuid(number)),
          ];
          final query = _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [for (final tag in required) _tagId(tag)],
              excludedTagIds: [for (final tag in excluded) _tagId(tag)],
            ),
            scope: scope,
            titleFilter: titleFilter,
          );

          final first = _firstPage(await repository.getCatalogPage(query));
          final loaded = [...first.items.map((item) => item.id)];
          var cursor = first.nextCursor;
          while (cursor != null) {
            final next = _continuationPage(
              await repository.getCatalogPage(
                _tagQuery(
                  tagFilter: query.tagFilter,
                  scope: scope,
                  titleFilter: titleFilter,
                  cursor: cursor,
                ),
              ),
            );
            loaded.addAll(next.items.map((item) => item.id));
            cursor = next.nextCursor;
          }

          expect(first.totalCount, expected.length, reason: label);
          expect(loaded, expected, reason: label);
        }
      }
    });

    test('порция и продолжение с обязательными тегами отдают выдачу по порядку и читают только порцию', () async {
      // 50 000 намерений: чётные активны, нечётные в архиве. Обязательный
      // тег назначен всем, исключённый — каждому десятому.
      const requiredTag = 1001;
      const excludedTag = 1002;
      const pageSize = 100;
      seedRawGraph(raw, () {
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?), (?, ?)', [
          _uuid(requiredTag),
          'Обязательный',
          _uuid(excludedTag),
          'Исключённый',
        ]);
        raw.execute('''
        WITH RECURSIVE ids(n) AS (
          VALUES(1) UNION ALL SELECT n + 1 FROM ids WHERE n < 50000
        )
        INSERT INTO intentions
          (id, title, is_action_ready, is_archived, created_at, updated_at)
        SELECT printf('018f0b5d-6b2e-7c80-8000-%012x', n),
               'Запись ' || n, 0, n % 2, n, n FROM ids
      ''');
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) '
          'SELECT ?, id FROM intentions',
          [_uuid(requiredTag)],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) '
          'SELECT ?, id FROM intentions WHERE created_at % 10 = 0',
          [_uuid(excludedTag)],
        );
      });

      // Вид условий по тегам, охват и режим фильтра названия независимы:
      // три случая проходят каждое значение каждого измерения. Двухсимвольный
      // фильтр отбирается без полнотекстового индекса.
      for (final (filterLabel, required, excluded, scope, titleFilter) in [
        ('обязательный', [requiredTag], <int>[], IntentionScope.all, null),
        (
          'совместный',
          [requiredTag],
          [excludedTag],
          IntentionScope.active,
          'за',
        ),
        (
          'только исключённый',
          <int>[],
          [excludedTag],
          IntentionScope.archived,
          null,
        ),
      ]) {
        final label = '$filterLabel, $scope, название $titleFilter';
        bool inScope(int number) => switch (scope) {
          IntentionScope.active => number.isEven,
          IntentionScope.archived => number.isOdd,
          IntentionScope.all => true,
        };
        final expected = [
          for (var number = 50000; number >= 1; number--)
            if (inScope(number) && (excluded.isEmpty || number % 10 != 0))
              _id(_uuid(number)),
        ];
        final tagFilter = IntentionTagFilter(
          requiredTagIds: [for (final tag in required) _tagId(tag)],
          excludedTagIds: [for (final tag in excluded) _tagId(tag)],
        );
        IntentionCatalogQuery query({IntentionCatalogCursor? cursor}) =>
            IntentionCatalogQuery(
              scope: scope,
              titleFilter: titleFilter,
              tagFilter: tagFilter,
              order: IntentionCatalogOrder.createdAtDescending,
              pageSize: pageSize,
              cursor: cursor,
            );

        trace.measured.clear();
        final first = _firstPage(await repository.getCatalogPage(query()));
        _expectReadsBoundedByPage(trace, first.items, pageSize);
        trace.measured.clear();
        final next = _continuationPage(
          await repository.getCatalogPage(query(cursor: first.nextCursor)),
        );
        _expectReadsBoundedByPage(trace, next.items, pageSize);

        expect(first.totalCount, expected.length, reason: label);
        expect(
          first.items.map((item) => item.id),
          expected.take(pageSize),
          reason: label,
        );
        expect(
          next.items.map((item) => item.id),
          expected.skip(pageSize).take(pageSize),
          reason: label,
        );
      }
    });
  });

  group('Порция каталога — собственные теги', () {
    test('показывает собственные теги возвращаемых одноимённых намерений', () async {
      for (var number = 1; number <= 4; number++) {
        await _insertIntention(
          database,
          id: _uuid(number),
          title: 'Гулять',
          createdAt: DateTime.utc(2026, 9, 2, number),
        );
      }
      seedRawGraph(raw, () {
        for (final (number, name) in [
          (110, 'Здоровье'),
          (109, 'Отдых'),
          (108, 'Семья'),
        ]) {
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            _uuid(number),
            name,
          ]);
        }
        for (final (tag, intention) in [(109, 1), (110, 1), (108, 2)]) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [_uuid(tag), _uuid(intention)],
          );
        }
        raw.execute(
          'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority) VALUES (?, ?, ?, ?, ?)',
          [_uuid(500), _uuid(1), _uuid(3), 'need', 2],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(109), _uuid(4)],
        );
      });

      final page = _firstPage(
        await repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: null,
            order: IntentionCatalogOrder.createdAtAscending,
            pageSize: 3,
          ),
        ),
      );

      expect(page.totalCount, 4);
      expect(page.nextCursor, isNotNull);
      expect(page.items.map((item) => item.id), [
        _id(_uuid(1)),
        _id(_uuid(2)),
        _id(_uuid(3)),
      ]);
      expect(page.items.map((item) => item.tags.map((tag) => tag.name.value)), [
        ['Здоровье', 'Отдых'],
        ['Семья'],
        <String>[],
      ]);
      expect(page.items.first.activeRelationCount, 1);
      final assignments = (await repository.getTagAssignments(
        page.items.first.id,
      ) as TagAssignmentsSuccess).value;
      expect(
        page.items.first.tags.map((tag) => tag.id),
        assignments.items.map((tag) => tag.id),
      );
      expect(
        page.revision.compareTo(assignments.revision),
        GraphRevisionOrder.same,
      );
    });

    test(
      'продолжение получает все 1203 назначения независимо от размера порции',
      () async {
        seedLargeTagReadFixture(raw, includeDenseRecipients: true);
        var cursor = _firstPage(
          await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: IntentionScope.all,
              titleFilter: null,
              order: IntentionCatalogOrder.createdAtAscending,
              pageSize: 1,
            ),
          ),
        ).nextCursor;

        final dense = _continuationPage(
          await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: IntentionScope.all,
              titleFilter: null,
              order: IntentionCatalogOrder.createdAtAscending,
              pageSize: 1,
              cursor: cursor,
            ),
          ),
        );

        expect(dense.items.single.id, _id(_uuid(2)));
        expect(
          dense.items.single.tags.map((tag) => tag.id.toCanonicalString()),
          [for (var index = 0; index < 1203; index++) _uuid(10000 + index)],
        );
        cursor = dense.nextCursor;
        // Третье намерение получает каждый третий тег, четвёртое — все.
        for (final (number, indexes) in [
          (3, [for (var index = 0; index < 1203; index += 3) index]),
          (4, [for (var index = 0; index < 1203; index++) index]),
        ]) {
          final next = _continuationPage(
            await repository.getCatalogPage(
              IntentionCatalogQuery(
                scope: IntentionScope.all,
                titleFilter: null,
                order: IntentionCatalogOrder.createdAtAscending,
                pageSize: 1,
                cursor: cursor,
              ),
            ),
          );
          expect(next.items.single.id, _id(_uuid(number)));
          expect(
            next.items.single.tags.map((tag) => tag.id.toCanonicalString()),
            [for (final index in indexes) _uuid(10000 + index)],
          );
          cursor = next.nextCursor;
        }
        expect(cursor, isNull);
      },
    );

    // Один случай на разбор идентификатора: прочие варианты проходят ту же
    // проверку.
    test('отклоняет всю порцию: неверный идентификатор тега после сотого назначения', () async {
      seedTagStorageFixture(raw);
      seedRawGraph(raw, () {
        for (var number = 303; number <= 439; number++) {
          raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            _uuid(number),
            'Тег $number',
          ]);
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [_uuid(number), _uuid(1)],
          );
        }
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          'некорректный идентификатор',
          'Последний тег',
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          ['некорректный идентификатор', _uuid(1)],
        );
      });

      expect(
        await repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: null,
            order: IntentionCatalogOrder.createdAtAscending,
            pageSize: 3,
          ),
        ),
        isA<ResultFailure<IntentionCatalogPage>>().having(
          (result) => result.failure,
          'причина',
          isA<IntentionCorruptionFailure>(),
        ),
      );
      expect(
        await repository.getTagAssignments(_id(_uuid(1))),
        isA<TagAssignmentsError>().having(
          (result) => result.failure,
          'причина',
          isA<TagAssignmentsCorruptionFailure>(),
        ),
      );
    });
  });

  test('отбирает действия до порции и считает только совпадения', () async {
    for (var index = 1; index <= 60; index++) {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-${index.toRadixString(16).padLeft(12, '0')}',
        title: 'Действие %_ без готовности',
        createdAt: DateTime.utc(2026, 9, 2, 11, index),
      );
    }
    for (final (suffix, createdHour, updatedHour) in [
      ('101', 8, 12),
      ('102', 9, 10),
      ('103', 10, 11),
    ]) {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000$suffix',
        title: 'Действие %_ с одинаковым названием',
        isActionReady: true,
        createdAt: DateTime.utc(2026, 9, 2, createdHour),
        updatedAt: DateTime.utc(2026, 9, 2, updatedHour),
      );
    }
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000104',
      title: 'Действие %_ в архиве',
      isActionReady: true,
      isArchived: true,
      createdAt: DateTime.utc(2026, 9, 2, 13),
    );

    final cases = <(IntentionCatalogOrder, List<String>)>[
      (IntentionCatalogOrder.createdAtAscending, ['101', '102', '103']),
      (IntentionCatalogOrder.createdAtDescending, ['103', '102', '101']),
      (IntentionCatalogOrder.updatedAtAscending, ['102', '103', '101']),
      (IntentionCatalogOrder.updatedAtDescending, ['101', '103', '102']),
    ];
    for (final (order, expectedSuffixes) in cases) {
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        readinessFilter: IntentionReadinessFilter.readyOnly,
        titleFilter: '%_',
        order: order,
        pageSize: 1,
      );
      final first = _firstPage(await repository.getCatalogPage(query));
      expect(first.totalCount, 3);
      expect(first.items, hasLength(1));
      final ids = [first.items.single.id.toCanonicalString()];
      var cursor = first.nextCursor;
      while (cursor != null) {
        final page = _continuationPage(
          await repository.getCatalogPage(
            IntentionCatalogQuery(
              scope: query.scope,
              readinessFilter: query.readinessFilter,
              titleFilter: '%_',
              order: query.order,
              pageSize: query.pageSize,
              cursor: cursor,
            ),
          ),
        );
        ids.addAll(page.items.map((item) => item.id.toCanonicalString()));
        cursor = page.nextCursor;
      }
      expect(
        ids,
        expectedSuffixes.map(
          (suffix) => '018f0b5d-6b2e-7c80-8000-000000000$suffix',
        ),
      );
    }
  });

  test('читает только порцию и количество при редкой готовности в большом каталоге', () async {
    await seedGraph(
      database,
      () => database.customStatement('''
      WITH RECURSIVE ids(n) AS (
        VALUES(1) UNION ALL SELECT n + 1 FROM ids WHERE n < 3000
      )
      INSERT INTO intentions
        (id, title, is_action_ready, is_archived, created_at, updated_at)
      SELECT printf('018f0b5d-6b2e-7c80-8000-%012x', n),
             'Действие %_ ' || n, n % 1000 = 0, 0, n, n FROM ids
    '''),
    );
    final query = IntentionCatalogQuery(
      scope: IntentionScope.active,
      readinessFilter: IntentionReadinessFilter.readyOnly,
      titleFilter: '%_',
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: 2,
    );
    trace.measured.clear();
    final first = _firstPage(await repository.getCatalogPage(query));
    expect(first.totalCount, 3);
    expect(first.items.map((item) => item.id), [
      _id(_uuid(3000)),
      _id(_uuid(2000)),
    ]);
    // Порция из двух намерений и одна строка сверх неё: ни одно чтение не
    // возвращает остальные 2997 намерений без готовности.
    expect(
      trace.measured.map((entry) => entry.rows),
      everyElement(lessThanOrEqualTo(3)),
    );

    trace.measured.clear();
    final next = _continuationPage(
      await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: query.scope,
          readinessFilter: query.readinessFilter,
          titleFilter: '%_',
          order: query.order,
          pageSize: query.pageSize,
          cursor: first.nextCursor,
        ),
      ),
    );
    expect(next.items.map((item) => item.id), [_id(_uuid(1000))]);
    expect(
      trace.measured.map((entry) => entry.rows),
      everyElement(lessThanOrEqualTo(1)),
    );
  });

  test(
    'снимки изменения готовности сохраняют точную принадлежность каталогу',
    () async {
      const id = '018f0b5d-6b2e-7c80-8000-000000000301';
      await _insertIntention(
        database,
        id: id,
        title: 'Пройти по Straße',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        readinessFilter: IntentionReadinessFilter.readyOnly,
        titleFilter: 'STRASSE',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      );
      expect(_firstPage(await repository.getCatalogPage(query)).totalCount, 0);

      final result = await repository.execute(
        EnableIntentionReadiness(_id(id)),
      );
      expect(
        result,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      final mutation =
          (result
                  as ResultSuccess<
                    ConfirmedGraphResult<IntentionCommandSuccess>
                  >)
              .value
              .value
              .catalogMutation;
      expect(mutation.before!.matches(query), isFalse);
      expect(mutation.after!.matches(query), isTrue);
      expect(_firstPage(await repository.getCatalogPage(query)).totalCount, 1);
    },
  );

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

    // Охват и порядок независимы: все четыре порядка проверены для охвата
    // «все», а активные и архивные намерения — каждое одним порядком.
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

  test('применяет фильтр названия к количеству и порции', () async {
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
  });

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
          seedGraph(
            database,
            () => database.customStatement(
              'UPDATE intentions SET description = ? WHERE id = ?',
              [description, id],
            ),
          ),
          throwsA(isA<SqliteException>()),
        );
      }
    },
  );

  test('не публикует каталог с предметно недопустимым сохранённым описанием', () async {
    final maximumLengthDescription = List.filled(4096, 'а').join();
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000071',
      title: 'Описание предельной длины',
      description: maximumLengthDescription,
      createdAt: DateTime.utc(2026, 9, 2, 10),
    );
    await _insertIntention(
      database,
      id: '018f0b5d-6b2e-7c80-8000-000000000072',
      title: 'Многострочное описание',
      description: 'Первая строка\nВторая строка',
      createdAt: DateTime.utc(2026, 9, 2, 11),
    );

    final validPage = _firstPage(
      await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 2,
        ),
      ),
    );
    expect(validPage.items, hasLength(2));
    expect(
      validPage.items.map((summary) => summary.hasDescription),
      everyElement(isTrue),
    );

    // Схема пропускает все три значения: описание она проверяет только на NUL
    // и на отсутствие одних ASCII-пробелов, а длину не ограничивает.
    final invalidDescriptions = [
      '\u00a0',
      '\ufeff',
      List.filled(4097, 'а').join(),
    ];
    for (final (index, description) in invalidDescriptions.indexed) {
      final id =
          '018f0b5d-6b2e-7c80-8000-${(0x73 + index).toRadixString(16).padLeft(12, '0')}';
      await _insertIntention(
        database,
        id: id,
        title: 'Повреждённое описание $index',
        description: description,
        createdAt: DateTime.utc(2026, 9, 3, index),
      );

      final result = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 10,
        ),
      );

      expect(
        result,
        isA<ResultFailure<IntentionCatalogPage>>().having(
          (result) => result.failure,
          'failure',
          isA<IntentionCorruptionFailure>(),
        ),
        reason: 'описание $index',
      );
      expect(
        diagnostics.events.last,
        isA<CatalogPageReadDiagnosticsEvent>().having(
          (event) => event.status,
          'status',
          isA<DiagnosticsFailed>().having(
            (status) => status.code,
            'code',
            DiagnosticsFailureCode.corruption,
          ),
        ),
        reason: 'описание $index',
      );
      expect(
        diagnostics.events.toString(),
        isNot(contains(description)),
        reason: 'описание $index',
      );
      await seedGraph(
        database,
        () => database.customStatement('DELETE FROM intentions WHERE id = ?', [
          id,
        ]),
      );
    }
  });

  test(
    'не публикует первую страницу с BLOB-описанием до typed Drift mapping',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000079',
        title: 'Первая допустимая строка',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertRawIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000080',
        title: 'Строка с BLOB-описанием',
        description: Uint8List.fromList([1]),
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );

      final result = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: null,
          order: const IntentionCatalogOrder(
            field: IntentionCatalogSortField.createdAt,
            direction: IntentionCatalogSortDirection.ascending,
          ),
          pageSize: 1,
        ),
      );

      expect(result, isA<ResultFailure<IntentionCatalogPage>>());
      expect(
        (result as ResultFailure<IntentionCatalogPage>).failure,
        isA<IntentionCorruptionFailure>(),
      );
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
      await seedGraph(
        database,
        () =>
            (database.delete(database.intentions)..where(
                  (row) =>
                      row.id.equals('018f0b5d-6b2e-7c80-8000-000000000062'),
                ))
                .go(),
      );
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
    },
  );

  test(
    'не допускает commit между полным чтением страницы и её revision',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000091',
        title: 'Первое',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000092',
        title: 'Второе',
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
      final firstPage = _firstPage(await repository.getCatalogPage(firstQuery));
      final continuationQuery = IntentionCatalogQuery(
        scope: firstQuery.scope,
        titleFilter: null,
        order: firstQuery.order,
        pageSize: firstQuery.pageSize,
        cursor: firstPage.nextCursor,
      );
      trace.blockNextSelect();

      final pageFuture = repository.getCatalogPage(continuationQuery);
      await trace.selectBlocked;
      var commandCompleted = false;
      final commandFuture = repository
          .execute(
            const CreateIntention(
              title: 'Создано после страницы',
              description: null,
            ),
          )
          .whenComplete(() => commandCompleted = true);
      await pumpEventQueue(times: 20);
      final completedBeforePageRead = commandCompleted;
      trace.releaseSelect();

      final page = _continuationPage(await pageFuture);
      final commandResult = await commandFuture;
      expect(completedBeforePageRead, isFalse);
      expect(
        commandResult,
        isA<ResultSuccess<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
      final mutation =
          (commandResult
                  as ResultSuccess<
                    ConfirmedGraphResult<IntentionCommandSuccess>
                  >)
              .value
              .value
              .catalogMutation;
      expect(
        page.revision.compareTo(mutation.revision),
        GraphRevisionOrder.older,
      );
    },
  );

  group('Чтение согласования каталога', () {
    final excludedTag = _tagId(1101);
    final keptTag = _tagId(1102);
    IntentionCatalogQuery excludingQuery({int pageSize = 2}) => _tagQuery(
      tagFilter: IntentionTagFilter(excludedTagIds: [excludedTag]),
      pageSize: pageSize,
    );
    int connectionChanges() =>
        raw.select('SELECT total_changes() AS count').single['count'] as int;

    Future<List<IntentionSummary>> loadWholeCatalog(
      IntentionCatalogQuery Function() query,
    ) async {
      final rows = <IntentionSummary>[];
      IntentionCatalogCursor? cursor;
      do {
        final page = (await repository.getCatalogPage(
          cursor == null ? query() : query().withCursorForTest(cursor),
        ) as ResultSuccess<IntentionCatalogPage>).value;
        rows.addAll(page.items);
        cursor = page.nextCursor;
      } while (cursor != null);
      return rows;
    }

    test(
      'частичный префикс читает недостающие совпадения окнами до границы',
      () async {
        _seedReconciliationFixture(raw);
        final query = excludingQuery();
        final first = _firstPage(await repository.getCatalogPage(query));
        final second = _continuationPage(
          await repository.getCatalogPage(
            excludingQuery().withCursorForTest(first.nextCursor!),
          ),
        );
        final stored = [...first.items, ...second.items];
        expect(stored.map((item) => item.id), [
          for (final n in [1, 3, 5, 7]) _id(_uuid(n)),
        ]);
        expect(second.nextCursor, isNotNull);
        expect(
          await repository.execute(DeleteTag(excludedTag)),
          isA<GraphCommandSucceeded>(),
        );
        final changesBefore = connectionChanges();
        trace.measured.clear();
        final boundary = IntentionCatalogPartialPrefixBoundary(
          second.nextCursor!,
        );

        final firstPortion = _reconciliationFirstPortion(
          await repository.getCatalogReconciliationPortion(
            IntentionCatalogReconciliationQuery(
              catalogQuery: query,
              boundary: boundary,
              window: IntentionCatalogInnerReconciliationWindow(stored.take(2)),
            ),
          ),
        );

        // Количество абсолютно: оно учитывает совпадения после границы (8–10)
        // и сохранённые строки, а не только недостающие в окне.
        expect(firstPortion.totalCount, 10);
        // Незаполненная порция внутреннего окна останавливается на его
        // верхнем крае: совпадение 4 после края относится к следующему окну.
        expect(firstPortion.items.map((item) => item.id), [_id(_uuid(2))]);
        expect(firstPortion.items.single.tags.map((tag) => tag.id), [keptTag]);
        expect(firstPortion.nextCursor, isNotNull);

        final continuation = _reconciliationContinuationPortion(
          await repository.getCatalogReconciliationPortion(
            IntentionCatalogReconciliationQuery(
              catalogQuery: query,
              boundary: boundary,
              window: IntentionCatalogFinalReconciliationWindow(stored.skip(2)),
              cursor: firstPortion.nextCursor,
            ),
          ),
        );
        // Совпадения сразу после края прежнего окна и перед границей области.
        expect(continuation.items.map((item) => item.id), [
          _id(_uuid(4)),
          _id(_uuid(6)),
        ]);
        expect(
          continuation.items.map((item) => item.tags.map((tag) => tag.id)),
          [
            [_tagId(1103)],
            [_tagId(1103)],
          ],
        );
        expect(continuation.nextCursor, isNull);
        expect(
          continuation.revision.compareTo(firstPortion.revision),
          GraphRevisionOrder.same,
        );

        // Сохранённые строки не перечитываются: ни одно чтение не возвращает
        // больше строк, чем порция с одной строкой сверх неё.
        expect(
          trace.measured.map((select) => select.rows),
          everyElement(lessThanOrEqualTo(3)),
        );
        expect(connectionChanges(), changesBefore);

        final regular = _continuationPage(
          await repository.getCatalogPage(
            excludingQuery().withCursorForTest(second.nextCursor!),
          ),
        );
        expect(regular.items.map((item) => item.id), [
          _id(_uuid(8)),
          _id(_uuid(9)),
        ]);
      },
    );

    test('заполненная порция продолжается с последней строки и оставляет '
        'строки окна после неё следующему окну', () async {
      _seedReconciliationFixture(raw);
      final query = excludingQuery();
      final all = await loadWholeCatalog(
        () => _tagQuery(tagFilter: IntentionTagFilter.empty, pageSize: 2),
      );
      IntentionSummary row(int number) =>
          all.singleWhere((item) => item.id == _id(_uuid(number)));
      expect(
        await repository.execute(DeleteTag(excludedTag)),
        isA<GraphCommandSucceeded>(),
      );
      const boundary = IntentionCatalogCompletedBoundary();

      final firstPortion = _reconciliationFirstPortion(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: IntentionCatalogInnerReconciliationWindow([row(1), row(7)]),
          ),
        ),
      );
      expect(firstPortion.totalCount, 10);
      expect(firstPortion.items.map((item) => item.id), [
        _id(_uuid(2)),
        _id(_uuid(3)),
      ]);
      expect(firstPortion.nextCursor, isNotNull);

      final continuation = _reconciliationContinuationPortion(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: IntentionCatalogFinalReconciliationWindow([row(7), row(9)]),
            cursor: firstPortion.nextCursor,
          ),
        ),
      );
      expect(continuation.items.map((item) => item.id), [
        _id(_uuid(4)),
        _id(_uuid(5)),
      ]);
      expect(continuation.nextCursor, isNotNull);
    });

    test('граница префикса учитывает убывающий порядок изменения', () async {
      _seedReconciliationFixture(raw);
      final query = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: null,
        tagFilter: IntentionTagFilter(excludedTagIds: [excludedTag]),
        order: IntentionCatalogOrder.updatedAtDescending,
        pageSize: 2,
      );
      final first = _firstPage(await repository.getCatalogPage(query));
      expect(first.items.map((item) => item.id), [
        _id(_uuid(9)),
        _id(_uuid(7)),
      ]);
      expect(
        await repository.execute(DeleteTag(excludedTag)),
        isA<GraphCommandSucceeded>(),
      );

      final portion = _reconciliationFirstPortion(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: IntentionCatalogPartialPrefixBoundary(first.nextCursor!),
            window: IntentionCatalogFinalReconciliationWindow(first.items),
          ),
        ),
      );

      expect(portion.totalCount, 10);
      expect(portion.items.map((item) => item.id), [
        _id(_uuid(10)),
        _id(_uuid(8)),
      ]);
      expect(portion.nextCursor, isNull);
    });

    test('ранее завершённая выдача в несколько окон читает недостающие '
        'совпадения до нового конца', () async {
      _seedReconciliationFixture(raw);
      final stored = await loadWholeCatalog(excludingQuery);
      expect(stored.map((item) => item.id), [
        for (final n in [1, 3, 5, 7, 9]) _id(_uuid(n)),
      ]);
      expect(
        await repository.execute(DeleteTag(excludedTag)),
        isA<GraphCommandSucceeded>(),
      );

      final missing = await _readWholeReconciliation(
        repository,
        excludingQuery(),
        const IntentionCatalogCompletedBoundary(),
        stored,
      );

      expect(missing.totalCount, 10);
      expect(
        missing.portions.map((portion) => portion.map((item) => item.id)),
        [
          [_id(_uuid(2))],
          [_id(_uuid(4)), _id(_uuid(6))],
          [_id(_uuid(8)), _id(_uuid(10))],
        ],
      );
      expect(missing.windows, [
        [_id(_uuid(1)), _id(_uuid(3))],
        [_id(_uuid(5)), _id(_uuid(7))],
        [_id(_uuid(7)), _id(_uuid(9))],
      ]);
    });

    test(
      'пустая завершённая выдача получает все новые совпадения порциями',
      () async {
        _seedReconciliationFixture(raw);
        final query = _tagQuery(
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tagId(1103)],
            excludedTagIds: [excludedTag],
          ),
          pageSize: 2,
        );
        final empty = _firstPage(await repository.getCatalogPage(query));
        expect(empty.totalCount, 0);
        expect(empty.nextCursor, isNull);
        expect(
          await repository.execute(DeleteTag(excludedTag)),
          isA<GraphCommandSucceeded>(),
        );

        final missing = await _readWholeReconciliation(
          repository,
          query,
          const IntentionCatalogCompletedBoundary(),
          const [],
        );

        expect(missing.totalCount, 3);
        expect(
          missing.portions.map((portion) => portion.map((item) => item.id)),
          [
            [_id(_uuid(4)), _id(_uuid(6))],
            [_id(_uuid(8))],
          ],
        );
        expect(missing.windows, [<IntentionId>[], <IntentionId>[]]);
        expect(
          missing.portions
              .expand((portion) => portion)
              .map((item) => item.tags.map((tag) => tag.id)),
          everyElement([_tagId(1103)]),
        );
      },
    );

    test(
      'новая ревизия между порциями требует повторить согласование',
      () async {
        _seedReconciliationFixture(raw);
        final query = excludingQuery();
        final firstStored = (await loadWholeCatalog(excludingQuery)).first;
        expect(firstStored.id, _id(_uuid(1)));
        expect(
          await repository.execute(DeleteTag(excludedTag)),
          isA<GraphCommandSucceeded>(),
        );
        final firstPortion = _reconciliationFirstPortion(
          await repository.getCatalogReconciliationPortion(
            IntentionCatalogReconciliationQuery(
              catalogQuery: query,
              boundary: const IntentionCatalogCompletedBoundary(),
              window: IntentionCatalogFinalReconciliationWindow([firstStored]),
            ),
          ),
        );
        expect(firstPortion.nextCursor, isNotNull);
        expect(
          await repository.execute(
            AssignTag(tagId: keptTag, intentionId: _id(_uuid(9))),
          ),
          isA<GraphCommandSucceeded>(),
        );
        final changesBefore = connectionChanges();

        final retried = await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: const IntentionCatalogCompletedBoundary(),
            window: IntentionCatalogFinalReconciliationWindow(const []),
            cursor: firstPortion.nextCursor,
          ),
        );

        expect(
          retried,
          isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>().having(
            (result) => result.value,
            'исход',
            isA<IntentionCatalogReconciliationRetry>(),
          ),
        );
        expect(connectionChanges(), changesBefore);
        final restarted = _reconciliationFirstPortion(
          await repository.getCatalogReconciliationPortion(
            IntentionCatalogReconciliationQuery(
              catalogQuery: query,
              boundary: const IntentionCatalogCompletedBoundary(),
              window: IntentionCatalogFinalReconciliationWindow([firstStored]),
            ),
          ),
        );
        expect(
          restarted.revision.compareTo(firstPortion.revision),
          GraphRevisionOrder.newer,
        );
        expect(restarted.items.map((item) => item.id), [
          _id(_uuid(2)),
          _id(_uuid(3)),
        ]);
      },
    );

    test('отклоняет недопустимое окно, чужие границу и продолжение', () async {
      _seedReconciliationFixture(raw);
      final query = excludingQuery();
      final first = _firstPage(await repository.getCatalogPage(query));
      final second = _continuationPage(
        await repository.getCatalogPage(
          excludingQuery().withCursorForTest(first.nextCursor!),
        ),
      );
      final all = await loadWholeCatalog(
        () => _tagQuery(tagFilter: IntentionTagFilter.empty, pageSize: 2),
      );
      IntentionSummary row(int number) =>
          all.singleWhere((item) => item.id == _id(_uuid(number)));
      expect(
        await repository.execute(DeleteTag(excludedTag)),
        isA<GraphCommandSucceeded>(),
      );
      final stored = [...first.items, ...second.items];
      final boundary = IntentionCatalogPartialPrefixBoundary(
        second.nextCursor!,
      );
      final firstWindow = IntentionCatalogInnerReconciliationWindow(
        stored.take(2),
      );
      final nextWindow = IntentionCatalogFinalReconciliationWindow(
        stored.skip(2),
      );
      final firstPortion = _reconciliationFirstPortion(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: firstWindow,
          ),
        ),
      );
      // Заполненные порции оставляют строки окна после своей последней
      // строки: внутреннее окно — следующему окну, последнее окно — ровно
      // им же.
      final fullInnerPortion = _reconciliationFirstPortion(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: const IntentionCatalogCompletedBoundary(),
            window: IntentionCatalogInnerReconciliationWindow([row(1), row(7)]),
          ),
        ),
      );
      final fullFinalPortion = _reconciliationFirstPortion(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: const IntentionCatalogCompletedBoundary(),
            window: IntentionCatalogFinalReconciliationWindow([row(1), row(7)]),
          ),
        ),
      );
      // Для сравнения: подходящие продолжения принимаются.
      for (final valid in [
        IntentionCatalogReconciliationQuery(
          catalogQuery: query,
          boundary: boundary,
          window: nextWindow,
          cursor: firstPortion.nextCursor,
        ),
        IntentionCatalogReconciliationQuery(
          catalogQuery: query,
          boundary: const IntentionCatalogCompletedBoundary(),
          window: IntentionCatalogFinalReconciliationWindow([row(7), row(9)]),
          cursor: fullInnerPortion.nextCursor,
        ),
        IntentionCatalogReconciliationQuery(
          catalogQuery: query,
          boundary: const IntentionCatalogCompletedBoundary(),
          window: IntentionCatalogFinalReconciliationWindow([row(7)]),
          cursor: fullFinalPortion.nextCursor,
        ),
      ]) {
        expect(
          await repository.getCatalogReconciliationPortion(valid),
          isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>(),
        );
      }

      for (final (label, invalid) in [
        (
          'окно больше размера порции',
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: IntentionCatalogInnerReconciliationWindow(stored.take(3)),
          ),
        ),
        (
          'окно не в действующем порядке',
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: IntentionCatalogInnerReconciliationWindow(
              stored.take(2).toList().reversed,
            ),
          ),
        ),
        (
          'окно с повтором строки',
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: IntentionCatalogInnerReconciliationWindow([
              stored.first,
              stored.first,
            ]),
          ),
        ),
        (
          'окно за границей частичного префикса',
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: IntentionCatalogPartialPrefixBoundary(first.nextCursor!),
            window: nextWindow,
          ),
        ),
        (
          'продолжение с окном, не следующим за курсором',
          IntentionCatalogReconciliationQuery(
            catalogQuery: query,
            boundary: boundary,
            window: IntentionCatalogFinalReconciliationWindow(
              stored.skip(1).take(2),
            ),
            cursor: firstPortion.nextCursor,
          ),
        ),
        (
          'запрос выдачи с курсором обычного продолжения',
          IntentionCatalogReconciliationQuery(
            catalogQuery: excludingQuery().withCursorForTest(first.nextCursor!),
            boundary: const IntentionCatalogCompletedBoundary(),
            window: firstWindow,
          ),
        ),
      ]) {
        final result = await repository.getCatalogReconciliationPortion(
          invalid,
        );

        expect(
          result,
          isA<ResultFailure<IntentionCatalogReconciliationOutcome>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionGenericValidationFailure>(),
          ),
          reason: label,
        );
      }
    });
  });
}

/// Ни одно чтение запроса порции не возвращает больше строк, чем порция с
/// одной строкой сверх неё или собственные теги её намерений.
void _expectReadsBoundedByPage(
  _SelectTrace trace,
  List<IntentionSummary> items,
  int pageSize,
) {
  final tagRows = items.fold(0, (sum, item) => sum + item.tags.length);
  expect(
    trace.measured.map((select) => select.rows),
    everyElement(
      lessThanOrEqualTo(tagRows > pageSize + 1 ? tagRows : pageSize + 1),
    ),
  );
}

void _seedJointCatalogPagingFixture(Database database) {
  database.execute('BEGIN');
  seedRawGraph(database, () {
    for (final (number, name) in [
      (1001, 'Здоровье'),
      (1002, 'Отдых'),
      (1003, 'Спорт'),
      (1004, 'Работа'),
    ]) {
      database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _uuid(number),
        name,
      ]);
    }
    for (var number = 1; number <= 285; number++) {
      database.execute(
        'INSERT INTO intentions '
        '(id, title, is_action_ready, is_archived, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?)',
        [
          _uuid(number),
          number >= 256 && number <= 265 ? 'Читать' : 'Гулять',
          number < 276 ? 1 : 0,
          number >= 266 && number <= 275 ? 1 : 0,
          100 + (number - 1) ~/ 120,
          300 - (number - 1) ~/ 80,
        ],
      );
      for (final tag in [
        1001,
        if (number < 246 || number > 255) 1002,
        if (number >= 237 && number <= 245) number.isOdd ? 1003 : 1004,
      ]) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(tag), _uuid(number)],
        );
      }
    }
  });
  database.execute('COMMIT');
}

Future<void> _insertIntention(
  AppDatabase database, {
  required String id,
  required String title,
  String? description,
  bool isActionReady = false,
  bool isArchived = false,
  required DateTime createdAt,
  DateTime? updatedAt,
}) => seedGraph(
  database,
  () => database
      .into(database.intentions)
      .insert(
        IntentionsCompanion.insert(
          id: id,
          title: title,
          description: Value(description),
          isActionReady: Value(isActionReady),
          isArchived: Value(isArchived),
          createdAt: createdAt.microsecondsSinceEpoch,
          updatedAt: (updatedAt ?? createdAt).microsecondsSinceEpoch,
        ),
      ),
);

Future<void> _insertRawIntention(
  AppDatabase database, {
  required String id,
  required String title,
  required Object description,
  required DateTime createdAt,
}) => seedGraph(
  database,
  () => database.customStatement(
    '''
    INSERT INTO intentions (id, title, description, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?)
  ''',
    [
      id,
      title,
      description,
      createdAt.microsecondsSinceEpoch,
      createdAt.microsecondsSinceEpoch,
    ],
  ),
);

IntentionId _id(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw ArgumentError.value(value, 'value'),
};

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';

TagId _tagId(int number) => switch (TagId.decode(_uuid(number))) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw ArgumentError.value(number, 'number'),
};

IntentionCatalogQuery _tagQuery({
  required IntentionTagFilter tagFilter,
  IntentionScope scope = IntentionScope.all,
  IntentionReadinessFilter readinessFilter = IntentionReadinessFilter.all,
  String? titleFilter,
  IntentionId? excludedIntentionId,
  int pageSize = 1,
  IntentionCatalogCursor? cursor,
}) => IntentionCatalogQuery(
  scope: scope,
  readinessFilter: readinessFilter,
  titleFilter: titleFilter,
  tagFilter: tagFilter,
  excludedIntentionId: excludedIntentionId,
  order: IntentionCatalogOrder.createdAtAscending,
  pageSize: pageSize,
  cursor: cursor,
);

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

/// Намерения 1–10 упорядочены созданием. Исключаемый тег 1101 назначен
/// чётным, сохраняемый 1102 — второму и третьему, а 1103 — четвёртому,
/// шестому и восьмому, у которых есть и исключаемый тег.
void _seedReconciliationFixture(Database database) {
  database.execute('BEGIN');
  seedRawGraph(database, () {
    for (final (number, name) in [
      (1101, 'Спорт'),
      (1102, 'Здоровье'),
      (1103, 'Отдых'),
    ]) {
      database.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _uuid(number),
        name,
      ]);
    }
    for (var number = 1; number <= 10; number++) {
      database.execute(
        'INSERT INTO intentions (id, title, created_at, updated_at) '
        'VALUES (?, ?, ?, ?)',
        [_uuid(number), 'Намерение $number', 100 + number, 200 + number],
      );
      for (final tag in [
        if (number.isEven) 1101,
        if (number == 2 || number == 3) 1102,
        if (number == 4 || number == 6 || number == 8) 1103,
      ]) {
        database.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(tag), _uuid(number)],
        );
      }
    }
  });
  database.execute('COMMIT');
}

extension on IntentionCatalogQuery {
  IntentionCatalogQuery withCursorForTest(IntentionCatalogCursor cursor) =>
      IntentionCatalogQuery(
        scope: scope,
        readinessFilter: readinessFilter,
        titleFilter: titleFilter?.map((value) => value),
        tagFilter: tagFilter,
        excludedIntentionId: excludedIntentionId,
        order: order,
        pageSize: pageSize,
        cursor: cursor,
      );
}

IntentionCatalogReconciliationFirstPortion _reconciliationFirstPortion(
  Result<IntentionCatalogReconciliationOutcome> result,
) {
  expect(result, isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>());
  final outcome =
      (result as ResultSuccess<IntentionCatalogReconciliationOutcome>).value;
  expect(outcome, isA<IntentionCatalogReconciliationFirstPortion>());
  return outcome as IntentionCatalogReconciliationFirstPortion;
}

IntentionCatalogReconciliationContinuationPortion
_reconciliationContinuationPortion(
  Result<IntentionCatalogReconciliationOutcome> result,
) {
  expect(result, isA<ResultSuccess<IntentionCatalogReconciliationOutcome>>());
  final outcome =
      (result as ResultSuccess<IntentionCatalogReconciliationOutcome>).value;
  expect(outcome, isA<IntentionCatalogReconciliationContinuationPortion>());
  return outcome as IntentionCatalogReconciliationContinuationPortion;
}

/// Читает все порции одного согласования скользящим окном сохранённых строк
/// так же, как модель представления, и проверяет единую ревизию.
Future<
  ({
    int totalCount,
    List<List<IntentionSummary>> portions,
    List<List<IntentionId>> windows,
  })
>
_readWholeReconciliation(
  DriftPersonalGraphRepository repository,
  IntentionCatalogQuery query,
  IntentionCatalogReconciliationBoundary boundary,
  List<IntentionSummary> stored,
) async {
  final portions = <List<IntentionSummary>>[];
  final windows = <List<IntentionId>>[];
  IntentionCatalogReconciliationFirstPortion? first;
  IntentionCatalogReconciliationCursor? cursor;
  var windowStart = 0;
  do {
    final windowEnd = min(windowStart + query.pageSize, stored.length);
    final rows = stored.sublist(windowStart, windowEnd);
    final IntentionCatalogReconciliationWindow window =
        windowEnd < stored.length
        ? IntentionCatalogInnerReconciliationWindow(rows)
        : IntentionCatalogFinalReconciliationWindow(rows);
    windows.add(window.storedIntentionIds);
    final result = await repository.getCatalogReconciliationPortion(
      IntentionCatalogReconciliationQuery(
        catalogQuery: query,
        boundary: boundary,
        window: window,
        cursor: cursor,
      ),
    );
    final IntentionCatalogReconciliationPortion portion;
    if (first == null) {
      portion = first = _reconciliationFirstPortion(result);
    } else {
      portion = _reconciliationContinuationPortion(result);
      expect(
        portion.revision.compareTo(first.revision),
        GraphRevisionOrder.same,
      );
    }
    expect(portion.items.length, lessThanOrEqualTo(query.pageSize));
    portions.add(portion.items);
    cursor = portion.nextCursor;
    if (cursor != null) {
      final position = portion.items.length == query.pageSize
          ? portion.items.last
          : (window as IntentionCatalogInnerReconciliationWindow).upperEdgeRow;
      while (windowStart < stored.length &&
          query.compare(stored[windowStart], position) <= 0) {
        windowStart += 1;
      }
    }
  } while (cursor != null);
  return (totalCount: first.totalCount, portions: portions, windows: windows);
}

final class _SelectTrace extends LocalDatabaseConnectionObserver {
  final List<_MeasuredSelect> measured = [];
  int? parameterLimit;
  Completer<void>? _blockedSelectStarted;
  Completer<void>? _blockedSelectRelease;

  void blockNextSelect() {
    if (_blockedSelectStarted != null) {
      throw StateError('SELECT уже заблокирован.');
    }
    _blockedSelectStarted = Completer<void>();
    _blockedSelectRelease = Completer<void>();
  }

  Future<void> get selectBlocked {
    final started = _blockedSelectStarted;
    if (started == null) throw StateError('SELECT не был заблокирован.');
    return started.future;
  }

  void releaseSelect() {
    final release = _blockedSelectRelease;
    if (release == null) throw StateError('SELECT не был заблокирован.');
    release.complete();
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    final limit = parameterLimit;
    if (limit != null && statement.arguments.length > limit) {
      throw StateError('Превышено число параметров одного SQL-выражения.');
    }
    if (statement.operation != LocalDatabaseSqlOperation.select) return;
    final started = _blockedSelectStarted;
    if (started == null || started.isCompleted) return;
    final release = _blockedSelectRelease!;
    started.complete();
    await release.future;
    _blockedSelectStarted = null;
    _blockedSelectRelease = null;
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    measured.add(_MeasuredSelect(rows.length));
    return rows;
  }
}

/// Число строк одного чтения.
final class _MeasuredSelect {
  const _MeasuredSelect(this.rows);

  final int rows;
}
