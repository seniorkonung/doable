import 'dart:async';
import 'dart:convert';

import 'package:doable/src/data/local/app_database.dart' hide Intention;
import 'package:doable/src/data/local/sqlite_tag_functions.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/shared/diagnostics/developer_diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_assignments.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

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
    trace.statements.clear();
  });

  tearDown(() => database.close());

  group('Совместный запрос каталога', () {
    final originalFilter = IntentionTagFilter(
      requiredTagIds: [_tagId(firstTagNumber)],
      excludedTagIds: [_tagId(lastTagNumber)],
    );
    for (final (label, filter, originalExcluded, excluded) in [
      (
        'заменён обязательный тег при том же числе условий',
        IntentionTagFilter(
          requiredTagIds: [_tagId(lastTagNumber)],
          excludedTagIds: [_tagId(lastTagNumber)],
        ),
        null,
        null,
      ),
      (
        'заменён исключённый тег при том же числе условий',
        IntentionTagFilter(
          requiredTagIds: [_tagId(firstTagNumber)],
          excludedTagIds: [_tagId(firstTagNumber)],
        ),
        null,
        null,
      ),
      (
        'обязательный и исключённый теги поменялись местами',
        IntentionTagFilter(
          requiredTagIds: [_tagId(lastTagNumber)],
          excludedTagIds: [_tagId(firstTagNumber)],
        ),
        null,
        null,
      ),
      ('сняты условия по тегам', IntentionTagFilter.empty, null, null),
      ('добавлен исключённый участник', originalFilter, null, _id(_uuid(3))),
      ('удалён исключённый участник', originalFilter, _id(_uuid(3)), null),
      (
        'заменён исключённый участник',
        originalFilter,
        _id(_uuid(3)),
        _id(_uuid(1)),
      ),
    ]) {
      test('отклоняет несовместимый курсор до SQL: $label', () async {
        seedTagStorageFixture(raw);
        final first = _firstPage(
          await repository.getCatalogPage(
            _tagQuery(
              tagFilter: originalFilter,
              excludedIntentionId: originalExcluded,
            ),
          ),
        );
        expect(first.nextCursor, isNotNull);
        trace.statements.clear();

        final result = await repository.getCatalogPage(
          _tagQuery(
            tagFilter: filter,
            excludedIntentionId: excluded,
            cursor: first.nextCursor,
          ),
        );

        expect(
          result,
          isA<ResultFailure<IntentionCatalogPage>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionGenericValidationFailure>(),
          ),
        );
        expect(trace.statements, isEmpty);
      });
    }

    test(
      'продолжает выдачу при другом порядке и повторах тех же условий',
      () async {
        seedTagStorageFixture(raw);
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
                excludedTagIds: [
                  _tagId(304),
                  _tagId(lastTagNumber),
                  _tagId(304),
                ],
              ),
              excludedIntentionId: _id(_uuid(3)),
              cursor: first.nextCursor,
            ),
          ),
        );
        expect(next.items.single.id, _id(_uuid(2)));
        expect(next.nextCursor, isNull);
      },
    );

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
            RenameTag(
              tagId: _tagId(firstTagNumber),
              name: TagName.fromInput('Семья'),
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

    for (final (label, order, expectedNumbers) in [
      (
        'по созданию по возрастанию',
        IntentionCatalogOrder.createdAtAscending,
        [for (var number = 1; number <= 235; number++) number],
      ),
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
      (
        'по обновлению по убыванию',
        IntentionCatalogOrder.updatedAtDescending,
        [for (var number = 1; number <= 235; number++) number],
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
        trace.statements.clear();
        final first = _firstPage(await repository.getCatalogPage(query(null)));
        expect(first.totalCount, 235);
        expect(first.items, hasLength(100));
        expect(first.nextCursor, isNotNull);
        expect(trace.statements.where(_isCatalogCountStatement), hasLength(1));
        trace.statements.clear();

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
        expect(trace.statements.where(_isCatalogCountStatement), isEmpty);
        expect(trace.statements, isNot(anyElement(contains('OFFSET'))));
      });
    }

    test(
      'изолирует параллельные чтения, продолжение и запрос после отказа',
      () async {
        seedTagStorageFixture(raw);
        final firstFilter = IntentionTagFilter(
          requiredTagIds: [_tagId(firstTagNumber)],
          excludedTagIds: [_tagId(lastTagNumber)],
        );
        final otherQuery = _tagQuery(
          tagFilter: IntentionTagFilter(
            requiredTagIds: [_tagId(lastTagNumber)],
            excludedTagIds: [_tagId(firstTagNumber)],
          ),
        );
        trace.blockNextSelect();
        final firstFuture = repository.getCatalogPage(
          _tagQuery(tagFilter: firstFilter),
        );
        await trace.selectBlocked;
        var otherCompleted = false;
        final otherFuture = repository
            .getCatalogPage(otherQuery)
            .whenComplete(() => otherCompleted = true);
        await pumpEventQueue();
        final completedBeforeRead = otherCompleted;
        trace.releaseSelect();
        final first = _firstPage(await firstFuture);
        final other = _firstPage(await otherFuture);
        expect(completedBeforeRead, isFalse);
        expect(first.totalCount, 2);
        expect(first.items.single.id, _id(_uuid(1)));
        expect(other.totalCount, 1);
        expect(other.items.single.id, _id(_uuid(3)));
        expect(other.nextCursor, isNull);
        final continuation = _continuationPage(
          await repository.getCatalogPage(
            _tagQuery(tagFilter: firstFilter, cursor: first.nextCursor),
          ),
        );
        expect(continuation.items.single.id, _id(_uuid(2)));
        expect(continuation.nextCursor, isNull);

        trace.failure = SqliteException(
          extendedResultCode: SqlError.SQLITE_BUSY,
          message: 'Отказ чтения',
        );
        expect(
          await repository.getCatalogPage(otherQuery),
          isA<ResultFailure<IntentionCatalogPage>>().having(
            (result) => result.failure,
            'причина',
            isA<IntentionUnavailableFailure>(),
          ),
        );
        trace.failure = null;
        final recovered = _firstPage(
          await repository.getCatalogPage(_tagQuery(tagFilter: firstFilter)),
        );
        expect(recovered.totalCount, 2);
        expect(recovered.items.single.id, _id(_uuid(1)));
        final noTags = _firstPage(
          await repository.getCatalogPage(
            _tagQuery(tagFilter: IntentionTagFilter.empty, pageSize: 100),
          ),
        );
        expect(noTags.totalCount, 3);
        expect(noTags.items.map((item) => item.id), [
          _id(_uuid(1)),
          _id(_uuid(2)),
          _id(_uuid(3)),
        ]);
      },
    );

    test('находит совпадение за пределами прежних ста строк', () async {
      raw.execute('BEGIN');
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

    test('1203 обязательных и 35000 исключённых условий не ограничены порцией или SQL-параметрами', () async {
      seedLargeTagReadFixture(raw, includeDenseRecipients: true);
      trace.parameterLimit = 400;
      final required = [
        for (var number = 10000; number < 11203; number++) _tagId(number),
      ];
      final excluded = [
        for (var number = 40000; number < 75000; number++) _tagId(number),
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
      expect(page.totalCount, 1);
      expect(page.items.single.id, _id(_uuid(2)));
      expect(page.items.single.tags, hasLength(1203));
      expect(page.nextCursor, isNull);

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

    test(
      'чистые исключения допускают отсутствие тегов, пересечение даёт ноль',
      () async {
        for (var number = 1; number <= 4; number++) {
          await _insertIntention(
            database,
            id: _uuid(number),
            title: 'Намерение $number',
            createdAt: DateTime.utc(2026, 9, 2, number),
          );
        }
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
      },
    );

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
      raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
        _uuid(9000),
        'Дом',
      ]);
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
        [_uuid(9000), _uuid(1)],
      );

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

    test('применяет название и все собственные теги до количества и порции', () async {
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
      raw.execute(
        'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
        [_uuid(102), _uuid(500)],
      );
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
    });

    test('отбирает по собственным назначениям без влияния назначений связям', () async {
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
      // Связи несут те же теги, но их назначения не являются собственными
      // назначениями намерений и не содержат `intention_id`.
      for (final (relation, source, related, archived, tags) in [
        (500, 4, 1, 0, [101, 102, 103]),
        (501, 2, 3, 0, [102, 103]),
        (502, 8, 7, 1, [101, 102, 103]),
      ]) {
        raw.execute(
          'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, ?, ?)',
          [_uuid(relation), _uuid(source), _uuid(related), 'need', 2, archived],
        );
        for (final tag in tags) {
          raw.execute(
            'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
            [_uuid(tag), _uuid(relation)],
          );
        }
      }
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
      for (final (required, excluded) in filters) {
        for (final scope in [IntentionScope.active, IntentionScope.archived]) {
          for (final titleFilter in [null, 'ходить']) {
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
      }
    });

    test('порция и продолжение с обязательными тегами идут по индексу порядка охвата', () async {
      // 50 000 намерений: чётные активны, нечётные в архиве. Обязательный
      // тег назначен всем, исключённый — каждому десятому.
      const requiredTag = 1001;
      const excludedTag = 1002;
      const pageSize = 100;
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

      for (final (filterLabel, required, excluded) in [
        ('обязательный', [requiredTag], <int>[]),
        ('совместный', [requiredTag], [excludedTag]),
        ('только исключённый', <int>[], [excludedTag]),
      ]) {
        for (final scope in IntentionScope.values) {
          // Двухсимвольный фильтр отбирается без полнотекстового индекса.
          for (final titleFilter in [null, 'за']) {
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
            final firstWatch = Stopwatch()..start();
            final first = _firstPage(await repository.getCatalogPage(query()));
            firstWatch.stop();
            final firstRead = trace.measured.singleWhere(
              (select) => select.sql.contains('LIMIT'),
            );
            trace.measured.clear();
            final nextWatch = Stopwatch()..start();
            final next = _continuationPage(
              await repository.getCatalogPage(query(cursor: first.nextCursor)),
            );
            nextWatch.stop();
            final nextRead = trace.measured.singleWhere(
              (select) => select.sql.contains('LIMIT'),
            );

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
            String planOf(_MeasuredSelect read) => raw
                .select('EXPLAIN QUERY PLAN ${read.sql}', read.arguments)
                .map((row) => row['detail'] as String)
                .join('\n');
            final firstPlan = planOf(firstRead);
            final nextPlan = planOf(nextRead);
            // Измерение характеризует фикстуру и не служит порогом.
            // ignore: avoid_print
            print(
              'Порядок каталога ($label): 50000 намерений, '
              '${expected.length} совпадений, порция $pageSize; '
              'первая=${firstWatch.elapsedMicroseconds} мкс '
              '(SELECT=${firstRead.elapsed.inMicroseconds} мкс), '
              'продолжение=${nextWatch.elapsedMicroseconds} мкс '
              '(SELECT=${nextRead.elapsed.inMicroseconds} мкс); '
              'план первой=${firstPlan.replaceAll('\n', ' | ')}; '
              'план продолжения=${nextPlan.replaceAll('\n', ' | ')}',
            );
            for (final (read, plan) in [
              (firstRead, firstPlan),
              (nextRead, nextPlan),
            ]) {
              expect(
                plan,
                contains('intentions_${scope.name}_created_at_desc_id_asc'),
                reason: '$label:\n$plan',
              );
              expect(
                plan,
                isNot(contains('USE TEMP B-TREE FOR ORDER BY')),
                reason: '$label:\n$plan',
              );
              expect(
                plan,
                isNot(
                  contains(
                    'SEARCH intentions USING INDEX '
                    'sqlite_autoindex_intentions_1 (id=?)',
                  ),
                ),
                reason: '$label:\n$plan',
              );
              expect(read.rows, pageSize + 1, reason: label);
            }
          }
        }
      }
    });
  });

  group('Порция каталога — собственные теги', () {
    test(
      'пакетно получает теги только возвращаемых одноимённых намерений',
      () async {
        for (var number = 1; number <= 4; number++) {
          await _insertIntention(
            database,
            id: _uuid(number),
            title: 'Гулять',
            createdAt: DateTime.utc(2026, 9, 2, number),
          );
        }
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
          'INSERT INTO tag_assignments (tag_id, long_term_relation_id) VALUES (?, ?)',
          [_uuid(108), _uuid(500)],
        );
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(109), _uuid(4)],
        );
        raw.execute('PRAGMA foreign_keys = OFF');
        raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
          _uuid(111),
          'Недоступный тег за границей порции',
        ]);
        raw.execute(
          'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
          [_uuid(111), _uuid(4)],
        );
        raw.execute('DELETE FROM tags WHERE id = ?', [_uuid(111)]);
        trace.measured.clear();

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
        expect(
          page.items.map((item) => item.tags.map((tag) => tag.name.value)),
          [
            ['Здоровье', 'Отдых'],
            ['Семья'],
            <String>[],
          ],
        );
        expect(page.items.first.activeRelationCount, 1);
        expect(() => page.items.first.tags.clear(), throwsUnsupportedError);
        final suppliedTags = List.of(page.items.first.tags);
        final original = page.items.first;
        final summary = IntentionSummary(
          id: original.id,
          title: original.title,
          hasDescription: original.hasDescription,
          readiness: original.readiness,
          archiveState: original.archiveState,
          activeRelationCount: original.activeRelationCount,
          createdAt: original.createdAt,
          updatedAt: original.updatedAt,
          tags: suppliedTags,
        );
        suppliedTags.clear();
        expect(summary.tags, original.tags);
        final assignmentRead = trace.measured
            .where((read) => read.sql.contains('FROM tag_assignments'))
            .single;
        expect(assignmentRead.rows, 3);
        expect(assignmentRead.arguments, [_uuid(1), _uuid(2), _uuid(3)]);
        final assignments = (await repository.getTagAssignments(
          IntentionTagTarget(page.items.first.id),
        ) as TagAssignmentsSuccess).value;
        expect(
          page.items.first.tags.map((tag) => tag.id),
          assignments.items.map((tag) => tag.id),
        );
        expect(
          page.revision.compareTo(assignments.revision),
          GraphRevisionOrder.same,
        );
      },
    );

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
        trace.measured.clear();

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
        final read = trace.measured
            .where((read) => read.sql.contains('FROM tag_assignments'))
            .single;
        expect(read.rows, 1203);
        expect(read.arguments, [_uuid(2)]);
        cursor = dense.nextCursor;
        final empty = _continuationPage(
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
        expect(empty.items.single.id, _id(_uuid(3)));
        expect(empty.items.single.tags, isEmpty);
        expect(empty.nextCursor, isNull);
      },
    );

    test(
      'состав тегов и ревизия порции предшествуют ожидающей команде',
      () async {
        seedTagStorageFixture(raw);
        trace.blockNextSelect(containing: 'FROM tag_assignments');
        final pageFuture = repository.getCatalogPage(
          IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: null,
            order: IntentionCatalogOrder.createdAtAscending,
            pageSize: 1,
          ),
        );
        await trace.selectBlocked;
        var commandCompleted = false;
        final commandFuture = repository
            .execute(
              RenameTag(
                tagId: (TagId.decode(
                  _uuid(firstTagNumber),
                ) as TagIdDecodingSuccess).id,
                name: TagName.fromInput('Новое название'),
              ),
            )
            .whenComplete(() => commandCompleted = true);
        await pumpEventQueue();
        final completedBeforeRead = commandCompleted;
        trace.releaseSelect();

        final page = _firstPage(await pageFuture);
        final command = await commandFuture;
        expect(completedBeforeRead, isFalse);
        expect(page.items.single.tags.single.name.value, 'Дом');
        expect(command, isA<GraphCommandSucceeded>());
        expect(
          page.revision.compareTo(
            (command as GraphCommandSucceeded).value.revision,
          ),
          GraphRevisionOrder.older,
        );
      },
    );

    for (final (label, corrupt) in <(String, void Function(Database))>[
      (
        'начальный BOM в идентификаторе тега',
        (connection) {
          final tagId = '\ufeff${_uuid(440)}';
          connection.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            tagId,
            'Тег с повреждённым идентификатором',
          ]);
          connection.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            [tagId, _uuid(1)],
          );
        },
      ),
      (
        'неверный идентификатор тега после сотого назначения',
        (connection) {
          for (var number = 303; number <= 439; number++) {
            connection.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
              _uuid(number),
              'Тег $number',
            ]);
            connection.execute(
              'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
              [_uuid(number), _uuid(1)],
            );
          }
          connection.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
            'некорректный идентификатор',
            'Последний тег',
          ]);
          connection.execute(
            'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
            ['некорректный идентификатор', _uuid(1)],
          );
        },
      ),
      for (final (reason, invalidName) in <(String, Object)>[
        ('окружающие пробелы', ' Дом '),
        ('символ NUL', 'Дом\u0000'),
        ('начальный BOM', '\ufeffДом'),
        ('двоичные данные', <int>[1, 2, 3]),
      ])
        (
          'недопустимое название: $reason',
          (connection) {
            connection.execute('PRAGMA ignore_check_constraints = ON');
            connection.createFunction(
              functionName: tagNameKeyFunctionName,
              argumentCount: const AllowedArgumentCount(1),
              deterministic: true,
              directOnly: false,
              function: (_) => 'повреждённый ключ',
            );
            connection.execute('UPDATE tags SET name = ? WHERE id = ?', [
              invalidName,
              _uuid(firstTagNumber),
            ]);
          },
        ),
      for (final order in <Object>[0, 1000, 'не число'])
        (
          'несогласованный порядок назначения $order',
          (connection) {
            connection.execute(
              'DROP TRIGGER tag_assignments_valid_tag_order_update',
            );
            connection.execute(
              'UPDATE tag_assignments SET tag_creation_sequence = ? WHERE intention_id = ?',
              [order, _uuid(1)],
            );
          },
        ),
    ]) {
      test('отклоняет всю порцию: $label', () async {
        seedTagStorageFixture(raw);
        corrupt(raw);

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
          await repository.getTagAssignments(IntentionTagTarget(_id(_uuid(1)))),
          isA<TagAssignmentsError>().having(
            (result) => result.failure,
            'причина',
            isA<TagAssignmentsCorruptionFailure>(),
          ),
        );
      });
    }
  });

  test('отбирает действия в SQL до порции и считает только совпадения', () async {
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
      trace.statements.clear();
      final first = _firstPage(await repository.getCatalogPage(query));
      expect(first.totalCount, 3);
      expect(first.items, hasLength(1));
      expect(trace.statements.where(_isCatalogCountStatement), hasLength(1));
      expect(
        trace.statements.where(_isCatalogCountStatement).single,
        contains('is_action_ready'),
      );
      expect(
        trace.statements.where((sql) => sql.contains('LIMIT')).single,
        contains('is_action_ready'),
      );
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

  test(
    'измеряет вход от действия при редкой готовности в большом каталоге',
    () async {
      await database.customStatement('''
      WITH RECURSIVE ids(n) AS (
        VALUES(1) UNION ALL SELECT n + 1 FROM ids WHERE n < 3000
      )
      INSERT INTO intentions
        (id, title, is_action_ready, is_archived, created_at, updated_at)
      SELECT printf('018f0b5d-6b2e-7c80-8000-%012x', n),
             'Действие %_ ' || n, n % 1000 = 0, 0, n, n FROM ids
    ''');
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        readinessFilter: IntentionReadinessFilter.readyOnly,
        titleFilter: '%_',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 2,
      );
      trace.measured.clear();
      final firstWatch = Stopwatch()..start();
      final first = _firstPage(await repository.getCatalogPage(query));
      firstWatch.stop();
      expect(first.totalCount, 3);
      expect(first.items.map((item) => item.id), [
        _id(_uuid(3000)),
        _id(_uuid(2000)),
      ]);
      final firstQueries = List<_MeasuredSelect>.of(trace.measured);
      expect(
        firstQueries.map((entry) => entry.rows),
        everyElement(lessThanOrEqualTo(3)),
      );
      final count = firstQueries
          .where((entry) => _isCatalogCountStatement(entry.sql))
          .single;
      final page = firstQueries
          .where((entry) => entry.sql.contains('LIMIT'))
          .single;
      expect(count.rows, 1);
      expect(page.rows, 3);
      expect(count.sql, contains('is_action_ready'));
      expect(page.sql, contains('is_action_ready'));
      expect(page.sql, isNot(contains('OFFSET')));
      final countPlan = raw.select(
        'EXPLAIN QUERY PLAN ${count.sql}',
        count.arguments,
      );
      final pagePlan = raw.select(
        'EXPLAIN QUERY PLAN ${page.sql}',
        page.arguments,
      );

      trace.measured.clear();
      final nextWatch = Stopwatch()..start();
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
      nextWatch.stop();
      expect(next.items.map((item) => item.id), [_id(_uuid(1000))]);
      expect(
        trace.measured.where((entry) => _isCatalogCountStatement(entry.sql)),
        isEmpty,
      );
      expect(
        trace.measured
            .where((entry) => entry.sql.contains('LIMIT'))
            .single
            .rows,
        1,
      );
      // ignore: avoid_print
      print(
        'Вход от действия: 3000 намерений, 3 готовых, фильтр, порция 2; '
        'первая=${firstWatch.elapsedMicroseconds} мкс, '
        'продолжение=${nextWatch.elapsedMicroseconds} мкс, '
        'COUNT=${count.elapsed.inMicroseconds} мкс, '
        'SELECT=${page.elapsed.inMicroseconds} мкс; '
        'план COUNT=${countPlan.map((row) => row['detail']).join(' | ')}; '
        'план SELECT=${pagePlan.map((row) => row['detail']).join(' | ')}',
      );
    },
  );

  test('курсор привязан к готовности до SQL', () async {
    for (final suffix in ['201', '202']) {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000$suffix',
        title: 'Действие $suffix',
        isActionReady: true,
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
    }
    final cursor = _firstPage(
      await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: IntentionScope.active,
          readinessFilter: IntentionReadinessFilter.readyOnly,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
        ),
      ),
    ).nextCursor!;
    trace.statements.clear();

    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: 1,
        cursor: cursor,
      ),
    );

    expect(result, isA<ResultFailure<IntentionCatalogPage>>());
    expect(
      (result as ResultFailure<IntentionCatalogPage>).failure,
      isA<IntentionValidationFailure>(),
    );
    expect(trace.statements, isEmpty);
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

  test('не запрашивает SQLite для недопустимого Unicode фильтра', () {
    expect(
      () => IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'молоко\u0000',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ),
      throwsA(
        isA<IntentionCatalogQueryValidationException>()
            .having(
              (exception) => exception.failure,
              'failure',
              IntentionCatalogQueryValidationFailure.invalidUnicodeRepertoire,
            )
            .having(
              (exception) => exception.textFailure?.field,
              'field',
              IntentionTextField.titleFilter,
            )
            .having(
              (exception) => exception.textFailure?.reason,
              'reason',
              IntentionTextValidationReason.invalidUnicodeRepertoire,
            ),
      ),
    );

    expect(trace.statements, isEmpty);
    expect(diagnostics.events, isEmpty);
  });

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
      expect(trace.statements.where(_isCatalogCountStatement), hasLength(1));
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

    final invalidDescriptions = [
      'недопустимый\u0000NUL',
      '',
      ' \t\r\n ',
      '\u00a0',
      '\ufeff',
      List.filled(4097, 'а').join(),
    ];
    await database.customStatement('PRAGMA ignore_check_constraints = ON');
    for (var index = 0; index < invalidDescriptions.length; index++) {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-${(0x73 + index).toRadixString(16).padLeft(12, '0')}',
        title: 'Повреждённое описание $index',
        description: invalidDescriptions[index],
        createdAt: DateTime.utc(2026, 9, 3, index),
      );
    }
    await database.customStatement('PRAGMA ignore_check_constraints = OFF');

    trace.statements.clear();
    final result = await repository.getCatalogPage(
      IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: null,
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 10,
      ),
    );

    expect(result, isA<ResultFailure<IntentionCatalogPage>>());
    expect(
      (result as ResultFailure<IntentionCatalogPage>).failure,
      isA<IntentionCorruptionFailure>(),
    );
    expect(trace.statements.where(_isCatalogCountStatement), hasLength(1));
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
    );
    expect(
      diagnostics.events.toString(),
      isNot(contains('недопустимый\u0000NUL')),
    );
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
    'не публикует следующую страницу с BLOB-описанием до typed Drift mapping',
    () async {
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000081',
        title: 'Первая допустимая строка',
        createdAt: DateTime.utc(2026, 9, 2, 10),
      );
      await _insertIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000082',
        title: 'Вторая допустимая строка',
        createdAt: DateTime.utc(2026, 9, 2, 11),
      );
      await _insertRawIntention(
        database,
        id: '018f0b5d-6b2e-7c80-8000-000000000083',
        title: 'Строка с BLOB-описанием',
        description: Uint8List.fromList([1]),
        createdAt: DateTime.utc(2026, 9, 2, 12),
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

      trace.statements.clear();
      final result = await repository.getCatalogPage(
        IntentionCatalogQuery(
          scope: firstQuery.scope,
          titleFilter: null,
          order: firstQuery.order,
          pageSize: firstQuery.pageSize,
          cursor: cursor,
        ),
      );

      expect(result, isA<ResultFailure<IntentionCatalogPage>>());
      expect(
        (result as ResultFailure<IntentionCatalogPage>).failure,
        isA<IntentionCorruptionFailure>(),
      );
      expect(trace.statements.where(_isCatalogCountStatement), isEmpty);
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
        expect(trace.statements.where(_isCatalogCountStatement), isEmpty);
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
      final sharedDatabaseRepository = DriftPersonalGraphRepository(
        database,
        UuidV7IntentionIdGenerator(),
        () => DateTime.utc(2026, 9, 2),
        diagnostics,
      );
      final recreatedRepository = DriftPersonalGraphRepository(
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
      final foreignDatabaseRepository = DriftPersonalGraphRepository(
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

  test('создаёт несравнимую revision после пересоздания repository', () async {
    final query = IntentionCatalogQuery(
      scope: IntentionScope.all,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: 1,
    );
    final originalRevision = _firstPage(await repository.getCatalogPage(query))
        .revision;
    final recreatedRepository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 2),
      diagnostics,
    );
    final recreatedRevision = _firstPage(
      await recreatedRepository.getCatalogPage(query),
    ).revision;

    expect(
      originalRevision.compareTo(recreatedRevision),
      GraphRevisionOrder.differentEpoch,
    );
    expect(
      recreatedRevision.compareTo(originalRevision),
      GraphRevisionOrder.differentEpoch,
    );
  });

  for (final (sinkFails, description) in [
    (
      false,
      'диагностика совместного поиска сообщает только безопасный исход и длительность',
    ),
    (true, 'отказ диагностики не меняет исходы совместного поиска'),
  ]) {
    test(description, () async {
      seedTagStorageFixture(raw);
      raw.execute('UPDATE intentions SET title = ?', [
        'CANARY-название-совместного-поиска',
      ]);
      raw.execute('UPDATE tags SET name = ? WHERE id = ?', [
        'CANARY-название-обязательного-тега',
        _uuid(firstTagNumber),
      ]);
      if (sinkFails) {
        repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 2),
          _ThrowingCatalogDiagnosticsSink(diagnostics),
        );
      }
      Future<Result<IntentionCatalogPage>> read(
        IntentionCatalogQuery query, {
        DiagnosticsFailureCode? failureCode,
      }) async {
        final offset = diagnostics.events.length;
        final result = await repository.getCatalogPage(query);
        _expectSafeJointDiagnostics(
          diagnostics.events.skip(offset).toList(),
          pageSize: query.pageSize,
          failureCode: failureCode,
        );
        return result;
      }

      final filter = IntentionTagFilter(
        requiredTagIds: [_tagId(firstTagNumber)],
        excludedTagIds: [_tagId(lastTagNumber)],
      );
      IntentionCatalogQuery query({IntentionCatalogCursor? cursor}) =>
          _tagQuery(
            tagFilter: filter,
            titleFilter: 'CANARY-название',
            excludedIntentionId: _id(_uuid(3)),
            cursor: cursor,
          );
      final first = _firstPage(await read(query()));
      expect(first.totalCount, 2);
      expect(first.items.single.id, _id(_uuid(1)));
      expect(first.items.single.tags.single.id, _tagId(firstTagNumber));
      final next = _continuationPage(
        await read(query(cursor: first.nextCursor)),
      );
      expect(next.items.single.id, _id(_uuid(2)));
      expect(next.items.single.tags.single.id, _tagId(firstTagNumber));
      expect(next.nextCursor, isNull);
      final empty = _firstPage(
        await read(
          _tagQuery(
            tagFilter: IntentionTagFilter(
              requiredTagIds: [_tagId(9999)],
              excludedTagIds: filter.excludedTagIds,
            ),
            titleFilter: 'CANARY-название',
          ),
        ),
      );
      expect(empty.totalCount, 0);
      expect(empty.items, isEmpty);
      expect(empty.nextCursor, isNull);

      for (final (error, expected, code)
          in <(Object, Matcher, DiagnosticsFailureCode)>[
            (
              SqliteException(
                extendedResultCode: SqlError.SQLITE_BUSY,
                message: 'CANARY-ошибка-SQL-параметр ${_uuid(firstTagNumber)}',
              ),
              isA<IntentionUnavailableFailure>(),
              DiagnosticsFailureCode.unavailable,
            ),
            (
              SqliteException(
                extendedResultCode: SqlError.SQLITE_CORRUPT,
                message: 'CANARY-повреждение ${_uuid(1)}',
              ),
              isA<IntentionCorruptionFailure>(),
              DiagnosticsFailureCode.corruption,
            ),
            (
              StateError('CANARY-неожиданный-отказ'),
              isA<IntentionUnexpectedFailure>(),
              DiagnosticsFailureCode.unexpected,
            ),
          ]) {
        trace.failure = error;
        for (final cursor in [null, first.nextCursor]) {
          final result = await read(query(cursor: cursor), failureCode: code);
          expect(result, isA<ResultFailure<IntentionCatalogPage>>());
          expect(
            (result as ResultFailure<IntentionCatalogPage>).failure,
            expected,
          );
        }
        trace.failure = null;
      }
      final recovered = _firstPage(await read(query()));
      expect(recovered.totalCount, first.totalCount);
      expect(
        recovered.items.single.tags.map((tag) => (tag.id, tag.name)),
        first.items.single.tags.map((tag) => (tag.id, tag.name)),
      );
    });
  }

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

bool _isCatalogCountStatement(String statement) =>
    statement.startsWith('SELECT COUNT(') &&
    !statement.contains('doable_relation_count_aggregates');

void _expectSafeJointDiagnostics(
  List<DiagnosticsEvent> events, {
  required int pageSize,
  DiagnosticsFailureCode? failureCode,
}) {
  expect(events, hasLength(2));
  expect(events, everyElement(isA<CatalogPageReadDiagnosticsEvent>()));
  expect(events.first.status, isA<DiagnosticsStarted>());
  final duration = switch (events.last.status) {
    DiagnosticsSucceeded(:final duration) when failureCode == null => duration,
    DiagnosticsFailed(:final duration, :final code) when code == failureCode =>
      duration,
    _ => throw StateError('Неверный диагностический исход совместного поиска.'),
  };
  expect(duration, greaterThanOrEqualTo(Duration.zero));
  final messages = <String>[];
  final sink = DeveloperDiagnosticsSink(messages.add);
  for (final event in events) {
    sink.record(event);
  }
  expect(messages, hasLength(2));
  final outcome = failureCode == null ? 'succeeded' : 'failed';
  for (var index = 0; index < messages.length; index++) {
    final fields = switch (jsonDecode(messages[index])) {
      final Map<String, dynamic> fields => fields,
      _ => throw StateError('Диагностика не предоставила JSON-объект.'),
    };
    expect(fields, {
      'operation': 'catalogPageRead',
      'outcome': index == 0 ? 'started' : outcome,
      'pageSize': pageSize,
      if (index != 0) 'durationMicros': duration.inMicroseconds,
      if (index != 0 && failureCode != null) 'failureCode': failureCode.name,
    });
  }
  // Точное множество полей и значений запрещает условия, назначения, SQL
  // и другие данные даже при добавлении нового способа их сериализации.
  for (final canary in [
    'CANARY',
    'SELECT',
    _uuid(1),
    _uuid(2),
    _uuid(3),
    _uuid(firstTagNumber),
    _uuid(lastTagNumber),
    _uuid(9999),
  ]) {
    expect(messages.join(), isNot(contains(canary)));
  }
}

final class _ThrowingCatalogDiagnosticsSink implements DiagnosticsSink {
  const _ThrowingCatalogDiagnosticsSink(this.attempted);

  final InMemoryDiagnosticsSink attempted;

  @override
  void record(DiagnosticsEvent event) {
    attempted.record(event);
    throw StateError('CANARY-отказ-приёмника-диагностики');
  }
}

void _seedJointCatalogPagingFixture(Database database) {
  database.execute('BEGIN');
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
}) => database
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
    );

Future<void> _insertRawIntention(
  AppDatabase database, {
  required String id,
  required String title,
  required Object description,
  required DateTime createdAt,
}) => database.customStatement(
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

final class _ForeignCatalogCursor implements IntentionCatalogCursor {
  const _ForeignCatalogCursor();
}

final class _SelectTrace extends LocalDatabaseConnectionObserver {
  final List<String> statements = [];
  final List<_MeasuredSelect> measured = [];
  final Map<LocalDatabaseSqlStatement, Stopwatch> _started = {};
  Object? failure;
  int? parameterLimit;
  Completer<void>? _blockedSelectStarted;
  Completer<void>? _blockedSelectRelease;
  String? _blockedSelectPattern;

  void blockNextSelect({String? containing}) {
    if (_blockedSelectStarted != null) {
      throw StateError('SELECT уже заблокирован.');
    }
    _blockedSelectStarted = Completer<void>();
    _blockedSelectRelease = Completer<void>();
    _blockedSelectPattern = containing;
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
    statements.add(statement.statements.single);
    _started[statement] = Stopwatch()..start();
    final failure = this.failure;
    if (failure != null) throw failure;
    final started = _blockedSelectStarted;
    if (started == null || started.isCompleted) return;
    final pattern = _blockedSelectPattern;
    if (pattern != null && !statement.statements.single.contains(pattern)) {
      return;
    }
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
    final watch = _started.remove(statement)!..stop();
    measured.add(
      _MeasuredSelect(
        statement.statements.single,
        statement.arguments,
        rows.length,
        watch.elapsed,
      ),
    );
    return rows;
  }
}

final class _MeasuredSelect {
  const _MeasuredSelect(this.sql, this.arguments, this.rows, this.elapsed);

  final String sql;
  final List<Object?> arguments;
  final int rows;
  final Duration elapsed;
}
