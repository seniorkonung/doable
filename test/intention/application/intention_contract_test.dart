import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_positions.dart';
import '../../support/intention_title_order_key.dart';

import 'package:doable/src/intention/application/intention_description_preview.dart';

void main() {
  group('поисковый ключ названия намерения', () {
    test('сопоставляет фильтр с названием через единый поисковый ключ', () {
      final filter = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: 'STRASSE',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ).titleFilter!;

      expect(filter.matchesTitle('Прогуляться по Straße'), isTrue);
      expect(filter.matchesTitle('Istanbul'), isFalse);
      expect(
        IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: 'ı',
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        ).titleFilter!.matchesTitle('ışık'),
        isTrue,
      );
    });
  });

  group('ключ порядка названия намерения', () {
    IntentionTitleOrderKey key(String searchProjection) =>
        IntentionTitleOrderKey.fromSearchProjection(searchProjection);

    test('сравнивает ключи по кодовым точкам, а не по единицам UTF-16', () {
      // В UTF-16 суррогатная пара U+1F600 начинается с 0xD83D < 0xE000.
      expect(key('\u{E000}').compareTo(key('\u{1F600}')), isNegative);
      expect(key('\u{1F600}').compareTo(key('\u{E000}')), isPositive);
      expect(key('a\u{FFFD}').compareTo(key('a\u{10000}')), isNegative);
    });

    test('ставит ключ раньше его продолжения и равняет одинаковые', () {
      expect(key('стр').compareTo(key('строка')), isNegative);
      expect(key('строка').compareTo(key('стр')), isPositive);
      expect(key('\u{1F600}я').compareTo(key('\u{1F600}я')), 0);
    });
  });

  group('условия собственных тегов намерения', () {
    final health = _tagId('00000000-0000-4000-8000-000000000001');
    final rest = _tagId('00000000-0000-4000-8000-000000000002');
    final sport = _tagId('00000000-0000-4000-8000-000000000003');
    final work = _tagId('00000000-0000-4000-8000-000000000004');

    test('пустые условия допускают намерения с тегами и без них', () {
      final filter = IntentionTagFilter();

      expect(filter.requiredTagIds, isEmpty);
      expect(filter.excludedTagIds, isEmpty);
      expect(filter.matches({}), isTrue);
      expect(filter.matches({health, sport}), isTrue);
      expect(filter, IntentionTagFilter.empty);
    });

    test('требует каждый обязательный тег и допускает дополнительные', () {
      final filter = IntentionTagFilter(requiredTagIds: [health, rest]);

      expect(filter.matches({health, rest}), isTrue);
      expect(filter.matches({health, rest, sport}), isTrue);
      expect(filter.matches({health}), isFalse);
      expect(filter.matches({rest}), isFalse);
      expect(filter.matches({}), isFalse);
    });

    test('исключает любой запрещённый тег и допускает отсутствие тегов', () {
      final filter = IntentionTagFilter(excludedTagIds: [sport, work]);

      expect(filter.matches({}), isTrue);
      expect(filter.matches({health}), isTrue);
      expect(filter.matches({sport}), isFalse);
      expect(filter.matches({work}), isFalse);
      expect(filter.matches({health, sport, work}), isFalse);
    });

    test('соединяет обязательные и исключённые условия через «И»', () {
      final filter = IntentionTagFilter(
        requiredTagIds: [health, rest],
        excludedTagIds: [sport, work],
      );
      final ownTagIds = {health, rest};

      expect(filter.matches(ownTagIds), isTrue);
      expect(filter.matches({health}), isFalse);
      expect(filter.matches({health, rest, sport}), isFalse);
      expect(filter.matches({health, rest, work}), isFalse);
      expect(filter.matches({}), isFalse);
      expect(ownTagIds, {health, rest});
    });

    test('сохраняет противоречивые условия и не допускает совпадений', () {
      final filter = IntentionTagFilter(
        requiredTagIds: [health, rest],
        excludedTagIds: [rest, sport],
      );

      expect(filter.requiredTagIds, {health, rest});
      expect(filter.excludedTagIds, {rest, sport});
      expect(filter.matches({}), isFalse);
      expect(filter.matches({health}), isFalse);
      expect(filter.matches({health, rest}), isFalse);
      expect(filter.matches({health, rest, sport, work}), isFalse);
    });

    test('повторы и порядок не меняют равенство и смысл условий', () {
      final first = IntentionTagFilter(
        requiredTagIds: [health, rest, health],
        excludedTagIds: [sport, work, sport],
      );
      final reordered = IntentionTagFilter(
        requiredTagIds: [rest, _tagId(health.toCanonicalString())],
        excludedTagIds: [work, sport],
      );

      expect(first.requiredTagIds, {health, rest});
      expect(first.excludedTagIds, {sport, work});
      expect(first == reordered, isTrue);
      expect(reordered == first, isTrue);
      for (final ownTagIds in <Set<TagId>>[
        {},
        {health},
        {health, rest},
        {health, rest, sport},
      ]) {
        expect(first.matches(ownTagIds), reordered.matches(ownTagIds));
      }
    });

    test('копирует входные наборы условий', () {
      final requiredTagIds = [health, rest];
      final excludedTagIds = {sport, work};
      final filter = IntentionTagFilter(
        requiredTagIds: requiredTagIds,
        excludedTagIds: excludedTagIds,
      );
      requiredTagIds.clear();
      excludedTagIds
        ..clear()
        ..add(health);

      expect(filter.requiredTagIds, {health, rest});
      expect(filter.excludedTagIds, {sport, work});
      expect(filter.matches({health, rest}), isTrue);
    });

    test(
      'переименование и одноимённый новый тег не подменяют идентичность',
      () {
        final original = Tag(
          id: health,
          name: TagName.fromInput('Здоровье'),
          color: null,
          position: tagPositionAt(1000),
        );
        final renamed = Tag(
          id: health,
          name: TagName.fromInput('Самочувствие'),
          color: original.color,
          position: original.position,
        );
        final sameName = Tag(
          id: rest,
          name: TagName.fromInput('Здоровье'),
          color: null,
          position: tagPositionAt(1001),
        );
        final required = IntentionTagFilter(requiredTagIds: [original.id]);
        final excluded = IntentionTagFilter(excludedTagIds: [original.id]);

        expect(original.name, sameName.name);
        expect(required.matches({renamed.id}), isTrue);
        expect(required.matches({sameName.id}), isFalse);
        expect(excluded.matches({renamed.id}), isFalse);
        expect(excluded.matches({sameName.id}), isTrue);
      },
    );

    test('сохраняет идентификатор после удаления тега из назначений', () {
      final required = IntentionTagFilter(requiredTagIds: [health]);
      final excluded = IntentionTagFilter(excludedTagIds: [health]);
      final ownTagIds = {health, rest};

      expect(required.matches(ownTagIds), isTrue);
      expect(excluded.matches(ownTagIds), isFalse);
      ownTagIds.remove(health);

      expect(required.matches(ownTagIds), isFalse);
      expect(excluded.matches(ownTagIds), isTrue);
      expect(required.requiredTagIds, {health});
      expect(excluded.excludedTagIds, {health});
    });
  });

  group('контракт каталога намерений', () {
    test('соединяет название, теги и ограничения допустимости через «И»', () {
      final health = Tag(
        id: _tagId('00000000-0000-4000-8000-000000000101'),
        name: TagName.fromStored('Здоровье'),
        color: null,
        position: tagPositionAt(1002),
      );
      final rest = Tag(
        id: _tagId('00000000-0000-4000-8000-000000000102'),
        name: TagName.fromStored('Отдых'),
        color: null,
        position: tagPositionAt(1003),
      );
      final sport = Tag(
        id: _tagId('00000000-0000-4000-8000-000000000103'),
        name: TagName.fromStored('Спорт'),
        color: null,
        position: tagPositionAt(1004),
      );
      const candidateId = '00000000-0000-4000-8000-000000000001';
      final otherParticipant = _intentionId(
        '00000000-0000-4000-8000-000000000002',
      );
      final filter = IntentionTagFilter(
        requiredTagIds: [health.id, rest.id],
        excludedTagIds: [sport.id],
      );
      final query = IntentionCatalogQuery(
        scope: IntentionScope.active,
        readinessFilter: IntentionReadinessFilter.readyOnly,
        titleFilter: 'ХОДИТЬ',
        tagFilter: filter,
        excludedIntentionId: otherParticipant,
        order: IntentionCatalogOrder.createdAtAscending,
        pageSize: 1,
      );

      expect(query.tagFilter, filter);
      expect(query.excludedIntentionId, otherParticipant);
      for (final (id, title, tags, readiness, archiveState, expected) in [
        (
          candidateId,
          'Ходить в парк',
          [health, rest],
          IntentionReadiness.ready,
          IntentionArchiveState.active,
          true,
        ),
        (
          candidateId,
          'Читать',
          [health, rest],
          IntentionReadiness.ready,
          IntentionArchiveState.active,
          false,
        ),
        (
          candidateId,
          'Ходить в парк',
          [health],
          IntentionReadiness.ready,
          IntentionArchiveState.active,
          false,
        ),
        (
          candidateId,
          'Ходить в парк',
          [health, rest, sport],
          IntentionReadiness.ready,
          IntentionArchiveState.active,
          false,
        ),
        (
          candidateId,
          'Ходить в парк',
          [health, rest],
          IntentionReadiness.notReady,
          IntentionArchiveState.active,
          false,
        ),
        (
          candidateId,
          'Ходить в парк',
          [health, rest],
          IntentionReadiness.ready,
          IntentionArchiveState.archived,
          false,
        ),
        (
          otherParticipant.toCanonicalString(),
          'Ходить в парк',
          [health, rest],
          IntentionReadiness.ready,
          IntentionArchiveState.active,
          false,
        ),
      ]) {
        expect(
          query.includes(
            _summary(
              id: id,
              title: title,
              tags: tags,
              readiness: readiness,
              archiveState: archiveState,
            ),
          ),
          expected,
        );
      }
      expect(_query().tagFilter, IntentionTagFilter.empty);
      expect(_query().excludedIntentionId, isNull);
    });

    test('условие готовности допускает оба типа, только действия или только намерения без готовности', () {
      for (final (filter, acceptsReady, acceptsNotReady) in [
        (IntentionReadinessFilter.all, true, true),
        (IntentionReadinessFilter.readyOnly, true, false),
        (IntentionReadinessFilter.notReadyOnly, false, true),
      ]) {
        final query = IntentionCatalogQuery(
          scope: IntentionScope.active,
          readinessFilter: filter,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtAscending,
          pageSize: 1,
        );
        expect(
          query.includes(
            _summary(
              id: '00000000-0000-4000-8000-000000000001',
              readiness: IntentionReadiness.ready,
            ),
          ),
          acceptsReady,
        );
        expect(
          query.includes(
            _summary(
              id: '00000000-0000-4000-8000-000000000001',
              readiness: IntentionReadiness.notReady,
            ),
          ),
          acceptsNotReady,
        );
      }
    });

    test('изменение только цвета тега заменяет его состояние в сводке', () {
      final firstId = _tagId('00000000-0000-4000-8000-000000000002');
      final secondId = _tagId('00000000-0000-4000-8000-000000000001');
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        descriptionPreview: IntentionDescriptionPreview.fromDescription(
          'Описание',
        ),
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        titleOrderKey: testTitleOrderKey('Гулять'),
        tags: [
          Tag(
            id: firstId,
            name: TagName.fromStored('Первый тег'),
            color: null,
            position: tagPositionAt(1007),
          ),
          Tag(
            id: secondId,
            name: TagName.fromStored('Второй тег'),
            color: null,
            position: tagPositionAt(1008),
          ),
        ],
      );

      final copy = summary.withUpdatedTag(
        Tag(
          id: secondId,
          name: TagName.fromStored('Второй тег'),
          color: TagColor.blue,
          position: tagPositionAt(1008),
        ),
      );

      expect(copy.tags.map((tag) => tag.id), [firstId, secondId]);
      expect(copy.tags.map((tag) => tag.name.value), [
        'Первый тег',
        'Второй тег',
      ]);
      expect(copy.tags.map((tag) => tag.color), [null, TagColor.blue]);
      expect(summary.tags.last.color, isNull);
      expect(copy.id, summary.id);
      expect(copy.title, summary.title);
      expect(copy.descriptionPreview?.text, summary.descriptionPreview?.text);
      expect(copy.readiness, summary.readiness);
      expect(copy.archiveState, summary.archiveState);
      expect(copy.createdAt, summary.createdAt);
      expect(copy.updatedAt, summary.updatedAt);
    });

    test('изменение только места тега переставляет его в сводке', () {
      final firstId = _tagId('00000000-0000-4000-8000-000000000002');
      final secondId = _tagId('00000000-0000-4000-8000-000000000001');
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        descriptionPreview: IntentionDescriptionPreview.fromDescription(
          'Описание',
        ),
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        titleOrderKey: testTitleOrderKey('Гулять'),
        tags: [
          Tag(
            id: firstId,
            name: TagName.fromStored('Первый тег'),
            color: null,
            position: tagPositionAt(1015),
          ),
          Tag(
            id: secondId,
            name: TagName.fromStored('Второй тег'),
            color: TagColor.blue,
            position: tagPositionAt(1016),
          ),
        ],
      );

      final copy = summary.withUpdatedTag(
        Tag(
          id: secondId,
          name: TagName.fromStored('Второй тег'),
          color: TagColor.blue,
          position: tagPositionAt(1014),
        ),
      );

      expect(copy.tags.map((tag) => (tag.id, tag.position)), [
        (secondId, tagPositionAt(1014)),
        (firstId, tagPositionAt(1015)),
      ]);
      expect(summary.tags.map((tag) => tag.id), [firstId, secondId]);
      expect(copy.id, summary.id);
      expect(copy.title, summary.title);
      expect(copy.descriptionPreview?.text, summary.descriptionPreview?.text);
      expect(copy.readiness, summary.readiness);
      expect(copy.archiveState, summary.archiveState);
      expect(copy.createdAt, summary.createdAt);
      expect(copy.updatedAt, summary.updatedAt);
    });

    test('изменение неназначенного тега не меняет сводку', () {
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        descriptionPreview: null,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        titleOrderKey: testTitleOrderKey('Гулять'),
        tags: [
          Tag(
            id: _tagId('00000000-0000-4000-8000-000000000001'),
            name: TagName.fromStored('Здоровье'),
            color: null,
            position: tagPositionAt(1010),
          ),
        ],
      );

      final copy = summary.withUpdatedTag(
        Tag(
          id: _tagId('00000000-0000-4000-8000-000000000002'),
          name: TagName.fromStored('Здоровье'),
          color: TagColor.blue,
          position: tagPositionAt(1011),
        ),
      );

      expect(copy.tags.map((tag) => (tag.name.value, tag.color)), [
        ('Здоровье', null),
      ]);
      expect(copy.title, 'Гулять');
    });

    test('удаление тега убирает только его назначение из сводки', () {
      final firstId = _tagId('00000000-0000-4000-8000-000000000002');
      final secondId = _tagId('00000000-0000-4000-8000-000000000001');
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        descriptionPreview: IntentionDescriptionPreview.fromDescription(
          'Описание',
        ),
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        titleOrderKey: testTitleOrderKey('Гулять'),
        tags: [
          Tag(
            id: firstId,
            name: TagName.fromStored('Первый тег'),
            color: null,
            position: tagPositionAt(1012),
          ),
          Tag(
            id: secondId,
            name: TagName.fromStored('Второй тег'),
            color: null,
            position: tagPositionAt(1013),
          ),
        ],
      );

      final copy = summary.withoutTag(firstId);

      expect(copy.tags.map((tag) => tag.id), [secondId]);
      expect(copy.tags.single.name.value, 'Второй тег');
      expect(summary.tags.map((tag) => tag.id), [firstId, secondId]);
      expect(copy.id, summary.id);
      expect(copy.title, summary.title);
      expect(copy.descriptionPreview?.text, summary.descriptionPreview?.text);
      expect(copy.readiness, summary.readiness);
      expect(copy.archiveState, summary.archiveState);
      expect(copy.createdAt, summary.createdAt);
      expect(copy.updatedAt, summary.updatedAt);
    });

    test('удаление неназначенного тега не меняет сводку', () {
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        descriptionPreview: null,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        titleOrderKey: testTitleOrderKey('Гулять'),
        tags: [
          Tag(
            id: _tagId('00000000-0000-4000-8000-000000000001'),
            name: TagName.fromStored('Здоровье'),
            color: null,
            position: tagPositionAt(1014),
          ),
        ],
      );

      final copy = summary.withoutTag(
        _tagId('00000000-0000-4000-8000-000000000002'),
      );

      expect(copy.tags.map((tag) => tag.name.value), ['Здоровье']);
      expect(copy.title, 'Гулять');
    });

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

        expect(query.titleFilter, isA<IntentionTitleFilter>());
        expect(query.titleFilter!.matchesTitle('Быть здоровым'), isTrue);
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

    test(
      'по умолчанию охватывает любую готовность и отбирает только действия',
      () {
        final action = _summary(
          id: '00000000-0000-4000-8000-000000000011',
          readiness: IntentionReadiness.ready,
        );
        final ordinary = _summary(id: '00000000-0000-4000-8000-000000000012');
        final archivedAction = _summary(
          id: '00000000-0000-4000-8000-000000000013',
          readiness: IntentionReadiness.ready,
          archiveState: IntentionArchiveState.archived,
        );
        final usualQuery = _query();
        final actionQuery = IntentionCatalogQuery(
          scope: IntentionScope.active,
          readinessFilter: IntentionReadinessFilter.readyOnly,
          titleFilter: null,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        );

        expect(usualQuery.readinessFilter, IntentionReadinessFilter.all);
        expect(usualQuery.includes(ordinary), isTrue);
        expect(actionQuery.includes(action), isTrue);
        expect(actionQuery.includes(ordinary), isFalse);
        expect(actionQuery.includes(archivedAction), isFalse);
      },
    );

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

    test('отклоняет некорректный Unicode фильтра до поиска', () {
      final invalidValues = [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => _query(titleFilter: 'до$invalidValueпосле'),
          _throwsInvalidUnicodeFilter(),
        );
      }
    });

    test('отклоняет некорректное название до case folding', () {
      final filter = _query(titleFilter: 'здоровье').titleFilter!;

      expect(
        () => filter.matchesTitle('Здоровье\u0000'),
        throwsA(
          isA<IntentionTextValidationException>()
              .having(
                (exception) => exception.failure.field,
                'field',
                IntentionTextField.title,
              )
              .having(
                (exception) => exception.failure.reason,
                'reason',
                IntentionTextValidationReason.invalidUnicodeRepertoire,
              ),
        ),
      );
    });

    test('сохраняет корректный Unicode фильтра без нормализации', () {
      const filter = 'е\u0301\t👩🏽‍💻\nтекст';
      final query = _query(titleFilter: filter);

      expect(query.titleFilter!.map((value) => value), filter);
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

    test('порядок по названию сравнивает ключи сводок, при равенстве — идентификаторы', () {
      final lower = _summary(
        id: '00000000-0000-4000-8000-000000000002',
        title: 'strauss',
        createdAt: DateTime.utc(2026, 8, 30, 12),
      );
      final upperSameKey = _summary(
        id: '00000000-0000-4000-8000-000000000001',
        title: 'STRAUSS',
        createdAt: DateTime.utc(2026, 8, 30, 14),
      );
      final folded = _summary(
        id: '00000000-0000-4000-8000-000000000003',
        title: 'Straßenbahn',
        createdAt: DateTime.utc(2026, 8, 30, 10),
      );
      final privateUse = _summary(
        id: '00000000-0000-4000-8000-000000000004',
        title: '\u{E000}',
      );
      final astral = _summary(
        id: '00000000-0000-4000-8000-000000000005',
        title: '\u{1F600}',
      );
      final ascending = _order(
        IntentionCatalogSortField.title,
        IntentionCatalogSortDirection.ascending,
      );
      final descending = _order(
        IntentionCatalogSortField.title,
        IntentionCatalogSortDirection.descending,
      );

      expect(ascending.compare(folded, lower), isNegative);
      expect(descending.compare(folded, lower), isPositive);
      expect(ascending.compare(privateUse, astral), isNegative);
      expect(descending.compare(privateUse, astral), isPositive);
      // Равные ключи в обоих направлениях упорядочивает возрастающий идентификатор.
      expect(ascending.compare(upperSameKey, lower), isNegative);
      expect(descending.compare(upperSameKey, lower), isNegative);
      expect(ascending.compare(lower, lower), isZero);
    });

    test('первая страница отклоняет недопустимый total count в release', () {
      final summary = _summary(id: '00000000-0000-4000-8000-000000000001');

      expect(
        () => IntentionCatalogFirstPage(
          items: [summary],
          totalCount: 0,
          nextCursor: null,
          revision: const _TestGraphRevision(epoch: 'первая', sequence: 0),
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
      );
      expect(
        () => IntentionCatalogFirstPage(
          items: const [],
          totalCount: -1,
          nextCursor: null,
          revision: const _TestGraphRevision(epoch: 'первая', sequence: 0),
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
      );
    });
  });

  group('полное начальное состояние создания намерения', () {
    final home = _tagId('00000000-0000-4000-8000-000000000001');
    final weekend = _tagId('00000000-0000-4000-8000-000000000002');
    final sport = _tagId('00000000-0000-4000-8000-000000000003');

    test('повторные идентификаторы тега не размножают назначения', () {
      final command = CreateIntention.withInitialState(
        title: 'Прогулка',
        description: null,
        readiness: IntentionReadiness.notReady,
        tagIds: [home, weekend, _tagId(home.toCanonicalString()), home],
      );

      expect(command.tagIds, hasLength(2));
      expect(command.tagIds, {home, weekend});
    });

    test('отказ фиксирует копию набора отсутствующих тегов без повторов', () {
      final missing = [home, weekend, _tagId(home.toCanonicalString())];
      final failure = IntentionCreationTagsMissingFailure(missing);
      missing
        ..clear()
        ..add(sport);

      expect(failure.missingTagIds, {home, weekend});
      expect(failure.missingTagIds, hasLength(2));
    });

    test('отказ отсутствующих тегов не создаётся с пустым набором', () {
      expect(
        () => IntentionCreationTagsMissingFailure(const <TagId>[]),
        throwsArgumentError,
      );
      expect(
        () => IntentionCreationTagsMissingFailure(<TagId>{}),
        throwsArgumentError,
      );
    });
  });

  group('общая граница личного графа', () {
    test(
      'пакет намерения объединяет каталожное и дополнительные изменения',
      () {
        const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
        final intention = _intention();
        final entry = _TestCatalogEntrySnapshot(
          _summary(id: intention.id.toCanonicalString()),
        );
        final mutation = IntentionCatalogUpdated(
          revision: revision,
          before: entry,
          after: entry,
        );
        final countChange = IntentionRelationCountsChanged(
          revision: revision,
          intentionId: intention.id,
          counts: RelationCounts(
            activeNeedIncoming: 0,
            activeNeedOutgoing: 0,
            activeCanIncoming: 0,
            activeCanOutgoing: 0,
            archivedNeedIncoming: 1,
            archivedNeedOutgoing: 0,
            archivedCanIncoming: 0,
            archivedCanOutgoing: 0,
          ),
        );
        final success = IntentionSaved(
          intention,
          catalogMutation: mutation,
          additionalChanges: [countChange],
        );
        final result = ConfirmedGraphResult(revision: revision, value: success);

        expect(result.changes, [mutation, countChange]);
      },
    );

    test('пакет подтверждённого результата не бывает пустым', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);

      expect(
        () => ConfirmedGraphResult(
          revision: revision,
          value: const _EmptyGraphCommandOutcome(),
        ),
        throwsA(
          isA<ConfirmedGraphResultValidationException>().having(
            (exception) => exception.failure,
            'failure',
            ConfirmedGraphResultValidationFailure.emptyChanges,
          ),
        ),
      );
    });
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
  IntentionReadiness readiness = IntentionReadiness.notReady,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  DateTime? createdAt,
  DateTime? updatedAt,
  List<Tag> tags = const [],
}) {
  final created = IntentionTimestamp(
    createdAt ?? DateTime.utc(2026, 8, 30, 12),
  );
  return IntentionSummary(
    id: _intentionId(id),
    title: title,
    descriptionPreview: null,
    readiness: readiness,
    archiveState: archiveState,
    createdAt: created,
    updatedAt: IntentionTimestamp(updatedAt ?? created.value),
    titleOrderKey: testTitleOrderKey(title),
    tags: tags,
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

Matcher _throwsQueryFailure(IntentionCatalogQueryValidationFailure failure) =>
    throwsA(
      isA<IntentionCatalogQueryValidationException>().having(
        (exception) => exception.failure,
        'failure',
        failure,
      ),
    );

Matcher _throwsInvalidUnicodeFilter() => throwsA(
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
);

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Ожидался корректный UUID.'),
};

TagId _tagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Ожидался корректный UUID тега.'),
};

final class _EmptyGraphCommandOutcome implements GraphCommandOutcome {
  const _EmptyGraphCommandOutcome();

  @override
  Iterable<GraphChange> get changes => const [];
}

final class _TestGraphRevision implements GraphRevision {
  const _TestGraphRevision({required this.epoch, required this.sequence});

  final String epoch;
  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _TestGraphRevision || other.epoch != epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    return switch (sequence.compareTo(other.sequence)) {
      < 0 => GraphRevisionOrder.older,
      > 0 => GraphRevisionOrder.newer,
      _ => GraphRevisionOrder.same,
    };
  }
}

final class _TestCatalogEntrySnapshot implements IntentionCatalogEntrySnapshot {
  const _TestCatalogEntrySnapshot(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}
