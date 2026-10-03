import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/graph/application/selected_relations.dart';

import 'dart:io';

import 'package:doable/src/daily_choice/application/choice_path_continuations.dart';
import 'package:doable/src/daily_choice/application/choice_path_suggestions.dart';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/favorite_read_contract_test_fallback.dart';
import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  group('поисковый ключ названия намерения', () {
    test('использует полный Unicode Default Case Folding 17.0.0', () {
      expect(unicodeDefaultCaseFoldingVersion, '17.0.0');
      expect(titleSearchKey('КУПИТЬ МОЛОКО'), 'купить молоко');
      expect(titleSearchKey('Straße'), 'strasse');
      expect(titleSearchKey('K'), 'k');
      expect(titleSearchKey('Σςσ'), 'σσσ');
      expect(titleSearchKey('ꭰᎠ'), 'ᎠᎠ');
      expect(titleSearchKey('𐐀'), '𐐨');
      expect(titleSearchKey('İ'), 'i̇');
      expect(titleSearchKey('Istanbul'), 'istanbul');
      expect(titleSearchKey('ışık'), 'ışık');
      expect(titleSearchKey('еé'), 'еé');
    });

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

    test(
      'повторяет весь закреплённый corpus Unicode Default Case Folding',
      () async {
        final lines = await File('test/fixtures/unicode/CaseFolding-17.0.0.txt')
            .readAsLines();
        var mappingCount = 0;

        for (final line in lines) {
          if (line.isEmpty || line.startsWith('#')) {
            continue;
          }
          final fields = line.split(';');
          final status = fields[1].trim();
          if (status != 'C' && status != 'F') {
            continue;
          }

          final input = int.parse(fields[0].trim(), radix: 16);
          final expected = String.fromCharCodes(
            fields[2]
                .trim()
                .split(RegExp(r'\s+'))
                .map((codePoint) => int.parse(codePoint, radix: 16)),
          );

          expect(
            titleSearchKey(String.fromCharCode(input)),
            expected,
            reason: 'U+${input.toRadixString(16).toUpperCase()}',
          );
          mappingCount++;
        }

        expect(mappingCount, 1585);
      },
    );
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
      expect(filter.hashCode, IntentionTagFilter.empty.hashCode);
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

    test('повторы и порядок не меняют равенство, хеш и смысл условий', () {
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
      expect(first.hashCode, reordered.hashCode);
      expect({first, reordered}, hasLength(1));
      for (final ownTagIds in <Set<TagId>>[
        {},
        {health},
        {health, rest},
        {health, rest, sport},
      ]) {
        expect(first.matches(ownTagIds), reordered.matches(ownTagIds));
      }
    });

    test('состав и роль каждого набора различают условия', () {
      final filter = IntentionTagFilter(
        requiredTagIds: [health],
        excludedTagIds: [sport],
      );

      expect(
        filter ==
            IntentionTagFilter(requiredTagIds: [rest], excludedTagIds: [sport]),
        isFalse,
      );
      expect(
        filter ==
            IntentionTagFilter(
              requiredTagIds: [health],
              excludedTagIds: [work],
            ),
        isFalse,
      );
      expect(
        filter ==
            IntentionTagFilter(
              requiredTagIds: [sport],
              excludedTagIds: [health],
            ),
        isFalse,
      );
      expect(filter == IntentionTagFilter(requiredTagIds: [health]), isFalse);
      expect(filter == IntentionTagFilter(excludedTagIds: [sport]), isFalse);
      expect(filter == Object(), isFalse);
    });

    test('копирует входные наборы и запрещает изменение своих условий', () {
      final requiredTagIds = [health, rest];
      final excludedTagIds = {sport, work};
      final filter = IntentionTagFilter(
        requiredTagIds: requiredTagIds,
        excludedTagIds: excludedTagIds,
      );
      final originalHashCode = filter.hashCode;
      requiredTagIds.clear();
      excludedTagIds
        ..clear()
        ..add(health);

      expect(filter.requiredTagIds, {health, rest});
      expect(filter.excludedTagIds, {sport, work});
      expect(() => filter.requiredTagIds.add(work), throwsUnsupportedError);
      expect(
        () => filter.requiredTagIds.remove(health),
        throwsUnsupportedError,
      );
      expect(() => filter.excludedTagIds.add(health), throwsUnsupportedError);
      expect(() => filter.excludedTagIds.clear(), throwsUnsupportedError);
      expect(filter.matches({health, rest}), isTrue);
      expect(filter.hashCode, originalHashCode);
    });

    test(
      'переименование и одноимённый новый тег не подменяют идентичность',
      () {
        final original = Tag(id: health, name: TagName.fromInput('Здоровье'));
        final renamed = Tag(
          id: health,
          name: TagName.fromInput('Самочувствие'),
        );
        final sameName = Tag(id: rest, name: TagName.fromInput('Здоровье'));
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
      );
      final rest = Tag(
        id: _tagId('00000000-0000-4000-8000-000000000102'),
        name: TagName.fromStored('Отдых'),
      );
      final sport = Tag(
        id: _tagId('00000000-0000-4000-8000-000000000103'),
        name: TagName.fromStored('Спорт'),
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

    test('замена счётчика связей сохраняет теги и остальные данные сводки', () {
      final suppliedTags = [
        Tag(
          id: _tagId('00000000-0000-4000-8000-000000000002'),
          name: TagName.fromStored('Первый тег'),
        ),
        Tag(
          id: _tagId('00000000-0000-4000-8000-000000000001'),
          name: TagName.fromStored('Второй тег'),
        ),
      ];
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        hasDescription: true,
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        activeRelationCount: 2,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        favoriteMark: FavoriteMark.favorite,
        tags: suppliedTags,
      );

      final copy = summary.withActiveRelationCount(7);

      expect(copy.activeRelationCount, 7);
      expect(summary.activeRelationCount, 2);
      expect(copy.id, summary.id);
      expect(copy.title, summary.title);
      expect(copy.hasDescription, summary.hasDescription);
      expect(copy.readiness, summary.readiness);
      expect(copy.archiveState, summary.archiveState);
      expect(copy.createdAt, summary.createdAt);
      expect(copy.updatedAt, summary.updatedAt);
      expect(copy.favoriteMark, FavoriteMark.favorite);
      expect(copy.tags, suppliedTags);
      suppliedTags.clear();
      expect(copy.tags, summary.tags);
      expect(copy.tags.map((tag) => tag.name.value), [
        'Первый тег',
        'Второй тег',
      ]);
      expect(() => copy.tags.clear(), throwsUnsupportedError);
    });

    test('переименование тега заменяет только его название в сводке', () {
      final firstId = _tagId('00000000-0000-4000-8000-000000000002');
      final secondId = _tagId('00000000-0000-4000-8000-000000000001');
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        hasDescription: true,
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        activeRelationCount: 2,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        favoriteMark: FavoriteMark.favorite,
        tags: [
          Tag(id: firstId, name: TagName.fromStored('Первый тег')),
          Tag(id: secondId, name: TagName.fromStored('Второй тег')),
        ],
      );

      final copy = summary.withRenamedTag(
        Tag(id: secondId, name: TagName.fromStored('Переименованный')),
      );

      expect(copy.tags.map((tag) => tag.id), [firstId, secondId]);
      expect(copy.tags.map((tag) => tag.name.value), [
        'Первый тег',
        'Переименованный',
      ]);
      expect(summary.tags.last.name.value, 'Второй тег');
      expect(copy.id, summary.id);
      expect(copy.title, summary.title);
      expect(copy.hasDescription, summary.hasDescription);
      expect(copy.readiness, summary.readiness);
      expect(copy.archiveState, summary.archiveState);
      expect(copy.activeRelationCount, summary.activeRelationCount);
      expect(copy.createdAt, summary.createdAt);
      expect(copy.favoriteMark, FavoriteMark.favorite);
      expect(copy.updatedAt, summary.updatedAt);
      expect(() => copy.tags.clear(), throwsUnsupportedError);
    });

    test('переименование неназначенного тега возвращает ту же сводку', () {
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        hasDescription: false,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        activeRelationCount: 0,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        tags: [
          Tag(
            id: _tagId('00000000-0000-4000-8000-000000000001'),
            name: TagName.fromStored('Здоровье'),
          ),
        ],
        favoriteMark: FavoriteMark.notFavorite,
      );

      final copy = summary.withRenamedTag(
        Tag(
          id: _tagId('00000000-0000-4000-8000-000000000002'),
          name: TagName.fromStored('Здоровье'),
        ),
      );

      expect(copy, same(summary));
    });

    test('удаление тега убирает только его назначение из сводки', () {
      final firstId = _tagId('00000000-0000-4000-8000-000000000002');
      final secondId = _tagId('00000000-0000-4000-8000-000000000001');
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        hasDescription: true,
        readiness: IntentionReadiness.ready,
        archiveState: IntentionArchiveState.archived,
        activeRelationCount: 2,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 2)),
        favoriteMark: FavoriteMark.favorite,
        tags: [
          Tag(id: firstId, name: TagName.fromStored('Первый тег')),
          Tag(id: secondId, name: TagName.fromStored('Второй тег')),
        ],
      );

      final copy = summary.withoutTag(firstId);

      expect(copy.tags.map((tag) => tag.id), [secondId]);
      expect(copy.tags.single.name.value, 'Второй тег');
      expect(summary.tags.map((tag) => tag.id), [firstId, secondId]);
      expect(copy.id, summary.id);
      expect(copy.title, summary.title);
      expect(copy.hasDescription, summary.hasDescription);
      expect(copy.readiness, summary.readiness);
      expect(copy.archiveState, summary.archiveState);
      expect(copy.activeRelationCount, summary.activeRelationCount);
      expect(copy.createdAt, summary.createdAt);
      expect(copy.favoriteMark, FavoriteMark.favorite);
      expect(copy.updatedAt, summary.updatedAt);
      expect(() => copy.tags.clear(), throwsUnsupportedError);
    });

    test('удаление неназначенного тега возвращает ту же сводку', () {
      final summary = IntentionSummary(
        id: _intentionId('00000000-0000-4000-8000-000000000003'),
        title: 'Гулять',
        hasDescription: false,
        readiness: IntentionReadiness.notReady,
        archiveState: IntentionArchiveState.active,
        activeRelationCount: 0,
        createdAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        updatedAt: IntentionTimestamp(DateTime.utc(2026, 9, 1)),
        tags: [
          Tag(
            id: _tagId('00000000-0000-4000-8000-000000000001'),
            name: TagName.fromStored('Здоровье'),
          ),
        ],
        favoriteMark: FavoriteMark.notFavorite,
      );

      final copy = summary.withoutTag(
        _tagId('00000000-0000-4000-8000-000000000002'),
      );

      expect(copy, same(summary));
    });

    test('отметка избранного — подтверждённое состояние из двух значений', () {
      String describe(FavoriteMark mark) => switch (mark) {
        FavoriteMark.notFavorite => 'без отметки',
        FavoriteMark.favorite => 'избранное',
      };

      expect(FavoriteMark.values, [
        FavoriteMark.notFavorite,
        FavoriteMark.favorite,
      ]);
      expect(FavoriteMark.values.map(describe), ['без отметки', 'избранное']);
    });

    test('подробные данные несут отметку своего намерения', () {
      final intention = _intention();
      final counts = RelationCounts(
        activeNeedIncoming: 0,
        activeNeedOutgoing: 0,
        activeCanIncoming: 0,
        activeCanOutgoing: 0,
        archivedNeedIncoming: 0,
        archivedNeedOutgoing: 0,
        archivedCanIncoming: 0,
        archivedCanOutgoing: 0,
      );

      final favorite = IntentionDetails(
        intention: intention,
        relationCounts: counts,
        favoriteMark: FavoriteMark.favorite,
      );
      final notFavorite = IntentionDetails(
        intention: intention,
        relationCounts: counts,
        favoriteMark: FavoriteMark.notFavorite,
      );

      expect(favorite.favoriteMark, FavoriteMark.favorite);
      expect(notFavorite.favoriteMark, FavoriteMark.notFavorite);
      expect(favorite.intention, same(intention));
    });

    test(
      'сводки одноимённых намерений несут отметку своего идентификатора',
      () {
        final favorite = _summary(
          id: '00000000-0000-4000-8000-000000000001',
          title: 'Гулять',
          favoriteMark: FavoriteMark.favorite,
        );
        final notFavorite = _summary(
          id: '00000000-0000-4000-8000-000000000002',
          title: 'Гулять',
          favoriteMark: FavoriteMark.notFavorite,
        );

        expect(favorite.title, notFavorite.title);
        expect(favorite.favoriteMark, FavoriteMark.favorite);
        expect(notFavorite.favoriteMark, FavoriteMark.notFavorite);
      },
    );

    test('копии сводки сохраняют отсутствие отметки', () {
      final tag = Tag(
        id: _tagId('00000000-0000-4000-8000-000000000101'),
        name: TagName.fromStored('Здоровье'),
      );
      final summary = _summary(
        id: '00000000-0000-4000-8000-000000000001',
        tags: [tag],
        favoriteMark: FavoriteMark.notFavorite,
      );

      expect(
        summary.withActiveRelationCount(3).favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(
        summary
            .withRenamedTag(Tag(id: tag.id, name: TagName.fromStored('Отдых')))
            .favoriteMark,
        FavoriteMark.notFavorite,
      );
      expect(summary.withoutTag(tag.id).favoriteMark, FavoriteMark.notFavorite);
    });

    test('отметка не меняет принадлежность запросу ни в одном охвате', () {
      for (final scope in IntentionScope.values) {
        for (final archiveState in IntentionArchiveState.values) {
          for (final readinessFilter in IntentionReadinessFilter.values) {
            final query = IntentionCatalogQuery(
              scope: scope,
              readinessFilter: readinessFilter,
              titleFilter: 'гулять',
              order: IntentionCatalogOrder.createdAtDescending,
              pageSize: 100,
            );
            for (final title in ['Гулять', 'Читать']) {
              final membership = {
                for (final mark in FavoriteMark.values)
                  query.includes(
                    _summary(
                      id: '00000000-0000-4000-8000-000000000001',
                      title: title,
                      archiveState: archiveState,
                      favoriteMark: mark,
                    ),
                  ),
              };

              expect(
                membership,
                hasLength(1),
                reason: '$scope, $archiveState, $readinessFilter, $title',
              );
            }
          }
        }
      }
    });

    test('отметка не участвует в сравнении порядка', () {
      const firstId = '00000000-0000-4000-8000-000000000001';
      const secondId = '00000000-0000-4000-8000-000000000002';
      for (final field in IntentionCatalogSortField.values) {
        for (final direction in IntentionCatalogSortDirection.values) {
          final query = _order(field, direction);
          for (final (earlier, later) in [
            (DateTime.utc(2026, 8, 30, 12), DateTime.utc(2026, 8, 30, 13)),
            (DateTime.utc(2026, 8, 30, 12), DateTime.utc(2026, 8, 30, 12)),
          ]) {
            final comparisons = {
              for (final leftMark in FavoriteMark.values)
                for (final rightMark in FavoriteMark.values)
                  query
                      .compare(
                        _summary(
                          id: firstId,
                          createdAt: earlier,
                          favoriteMark: leftMark,
                        ),
                        _summary(
                          id: secondId,
                          createdAt: later,
                          favoriteMark: rightMark,
                        ),
                      )
                      .sign,
            };

            expect(comparisons, hasLength(1), reason: '$field, $direction');
          }
        }
      }
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
        const revision = _TestGraphRevision(epoch: 'первая', sequence: 0);
        final pages = <IntentionCatalogPage>[
          IntentionCatalogFirstPage(
            items: [summary],
            totalCount: 2,
            nextCursor: cursor,
            revision: revision,
          ),
          IntentionCatalogContinuationPage(
            items: const [],
            nextCursor: null,
            revision: revision,
          ),
        ];

        expect(pages.map(_pageDescription), ['first:2', 'continuation']);
        expect(pages.map((page) => page.revision), everyElement(revision));
      },
    );

    test('сравнимая revision различает порядок и process-local эпоху', () {
      const first = _TestGraphRevision(epoch: 'первая', sequence: 0);
      const second = _TestGraphRevision(epoch: 'первая', sequence: 1);
      const anotherEpoch = _TestGraphRevision(epoch: 'вторая', sequence: 0);

      expect(first.compareTo(second), GraphRevisionOrder.older);
      expect(second.compareTo(first), GraphRevisionOrder.newer);
      expect(second.compareTo(second), GraphRevisionOrder.same);
      expect(first.compareTo(anotherEpoch), GraphRevisionOrder.differentEpoch);
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

    test(
      'summary сохраняет показание изменения после перевода часов назад',
      () {
        final summary = _summary(
          id: '00000000-0000-4000-8000-000000000001',
          createdAt: DateTime.utc(2026, 8, 30, 12),
          updatedAt: DateTime.utc(2026, 8, 30, 11),
        );

        expect(summary.createdAt.value, DateTime.utc(2026, 8, 30, 12));
        expect(summary.updatedAt.value, DateTime.utc(2026, 8, 30, 11));
      },
    );
  });

  group('контракт чтения согласования каталога', () {
    test('запрос несёт фильтр, границу, курсор и окно сохранённых строк', () {
      final query = _query(pageSize: 2);
      final second = _summary(id: '00000000-0000-4000-8000-000000000002');
      final first = _summary(id: '00000000-0000-4000-8000-000000000001');
      final stored = [second, first];
      const continuation = _TestCatalogCursor();
      const cursor = _TestReconciliationCursor();

      final reconciliation = IntentionCatalogReconciliationQuery(
        catalogQuery: query,
        boundary: const IntentionCatalogPartialPrefixBoundary(continuation),
        window: IntentionCatalogInnerReconciliationWindow(stored),
        cursor: cursor,
      );
      stored.clear();

      expect(reconciliation.catalogQuery, same(query));
      expect(reconciliation.cursor, same(cursor));
      final window =
          reconciliation.window as IntentionCatalogInnerReconciliationWindow;
      expect(window.storedIntentionIds, [second.id, first.id]);
      expect(window.upperEdgeRow, same(first));
      expect(() => window.storedRows.add(first), throwsUnsupportedError);
      expect(switch (reconciliation.boundary) {
        IntentionCatalogPartialPrefixBoundary(:final continuation) =>
          continuation,
        IntentionCatalogCompletedBoundary() => null,
      }, same(continuation));
    });

    test('внутреннее окно без сохранённых строк не создаётся', () {
      expect(
        () => IntentionCatalogInnerReconciliationWindow(const []),
        throwsArgumentError,
      );
    });

    test('ранее завершённая выдача, включая пустую, — отдельная граница, '
        'а окно с последней строкой области может быть пустым', () {
      final reconciliation = IntentionCatalogReconciliationQuery(
        catalogQuery: _query(),
        boundary: const IntentionCatalogCompletedBoundary(),
        window: IntentionCatalogFinalReconciliationWindow(const []),
      );

      expect(_boundaryDescription(reconciliation.boundary), 'completed');
      expect(_windowDescription(reconciliation.window), 'final');
      expect(reconciliation.window.storedIntentionIds, isEmpty);
      expect(reconciliation.cursor, isNull);
    });

    test('исходы различают первую порцию, продолжение и повтор', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
      const cursor = _TestReconciliationCursor();
      final summary = _summary(id: '00000000-0000-4000-8000-000000000003');
      final outcomes = <IntentionCatalogReconciliationOutcome>[
        IntentionCatalogReconciliationFirstPortion(
          items: [summary],
          totalCount: 7,
          nextCursor: cursor,
          revision: revision,
        ),
        IntentionCatalogReconciliationContinuationPortion(
          items: const [],
          nextCursor: null,
          revision: revision,
        ),
        const IntentionCatalogReconciliationRetry(),
      ];

      expect(outcomes.map(_reconciliationDescription), [
        'first:7',
        'continuation',
        'retry',
      ]);
      final first = outcomes.first as IntentionCatalogReconciliationPortion;
      expect(first.items.single, same(summary));
      expect(first.nextCursor, same(cursor));
      expect(first.revision, same(revision));
      expect(() => first.items.add(summary), throwsUnsupportedError);
    });

    test('первая порция отклоняет количество меньше своих строк', () {
      final summary = _summary(id: '00000000-0000-4000-8000-000000000001');

      expect(
        () => IntentionCatalogReconciliationFirstPortion(
          items: [summary],
          totalCount: 0,
          nextCursor: null,
          revision: const _TestGraphRevision(epoch: 'первая', sequence: 0),
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
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
          MarkIntentionFavorite(id),
          UnmarkIntentionFavorite(id),
        ];

        expect(commands.map(_commandDescription), [
          'create',
          'update',
          'enableReadiness',
          'disableReadiness',
          'archive',
          'restore',
          'delete',
          'markFavorite',
          'unmarkFavorite',
        ]);
        expect(
          commands.whereType<ExistingIntentionCommand>().map(
            (command) => command.id,
          ),
          everyElement(id),
        );
        expect(commands.skip(7), everyElement(isA<ExistingIntentionCommand>()));
      },
    );

    test('saved, deleted и failures имеют исчерпывающие типы', () {
      final intention = _intention();
      final entry = _TestCatalogEntrySnapshot(
        _summary(id: intention.id.toCanonicalString()),
      );
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 1);
      final results = <Result<IntentionCommandSuccess>>[
        ResultSuccess(
          IntentionSaved(
            intention,
            catalogMutation: IntentionCatalogCreated(
              revision: revision,
              entry: entry,
            ),
          ),
        ),
        ResultSuccess(
          IntentionDeleted(
            intention.id,
            catalogMutation: IntentionCatalogDeleted(
              revision: revision,
              entry: entry,
            ),
          ),
        ),
        const ResultFailure(IntentionGenericValidationFailure()),
        const ResultFailure(IntentionNotFoundFailure()),
        const ResultFailure(IntentionConflictFailure()),
        ResultFailure(IntentionHasBlockingRelationsFailure(intention.id)),
        const ResultFailure(IntentionUnavailableFailure()),
        const ResultFailure(IntentionCorruptionFailure()),
        const ResultFailure(IntentionUnexpectedFailure()),
      ];

      expect(
        results.whereType<ResultSuccess<IntentionCommandSuccess>>(),
        hasLength(2),
      );
      expect(
        results.whereType<ResultFailure<IntentionCommandSuccess>>(),
        hasLength(7),
      );
      expect(_resultSuccessDescription(results[0]), 'saved');
      expect(_resultSuccessDescription(results[1]), 'deleted');
      expect(results.skip(2).map(_resultFailureDescription), [
        'validation',
        'notFound',
        'conflict',
        'blockingRelations',
        'unavailable',
        'corruption',
        'unexpected',
      ]);
      expect(
        const IntentionUnexpectedFailure().code,
        IntentionFailureCode.unexpected,
      );
    });

    test('sealed catalog mutations выражают допустимые before и after', () {
      final before = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );
      final after = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 1);
      final mutations = <IntentionCatalogMutation>[
        IntentionCatalogCreated(revision: revision, entry: after),
        IntentionCatalogUpdated(
          revision: revision,
          before: before,
          after: after,
        ),
        IntentionCatalogDeleted(revision: revision, entry: before),
        IntentionCatalogUnchanged(revision: revision, entry: before),
      ];

      expect(mutations.map(_mutationDescription), [
        'created',
        'updated',
        'deleted',
        'unchanged',
      ]);
      expect(mutations[0].before, isNull);
      expect(mutations[0].after, same(after));
      expect(mutations[1].before, same(before));
      expect(mutations[1].after, same(after));
      expect(mutations[2].before, same(before));
      expect(mutations[2].after, isNull);
      expect(mutations[3].before, same(before));
      expect(mutations[3].after, same(before));
    });
  });

  group('общая граница личного графа', () {
    test('выражает чтения намерений и их счётчиков', () async {
      final PersonalGraphRepository repository =
          _FailingPersonalGraphRepository();
      final id = _intentionId('00000000-0000-4000-8000-000000000001');

      expect(
        await repository.getCatalogPage(_query()),
        isA<ResultFailure<IntentionCatalogPage>>(),
      );
      expect(
        await repository.getCatalogReconciliationPortion(
          IntentionCatalogReconciliationQuery(
            catalogQuery: _query(),
            boundary: const IntentionCatalogCompletedBoundary(),
            window: IntentionCatalogFinalReconciliationWindow([
              _summary(id: '00000000-0000-4000-8000-000000000001'),
            ]),
          ),
        ),
        isA<ResultFailure<IntentionCatalogReconciliationOutcome>>(),
      );
      expect(
        await repository.getRelationCounts(id),
        isA<ResultFailure<GraphSnapshot<RelationCounts>>>(),
      );
      await expectLater(
        repository.watchIntention(id),
        emits(
          isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
            (result) => result.failure,
            'failure',
            isA<IntentionUnavailableFailure>(),
          ),
        ),
      );
      expect(
        await repository.execute(
          const CreateIntention(title: 'Здоровье', description: null),
        ),
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
    });

    test('снимок связывает подтверждённое значение с одной ревизией', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 3);
      final intention = _intention();
      final snapshot = GraphSnapshot(value: intention, revision: revision);

      expect(snapshot.value, same(intention));
      expect(snapshot.revision, same(revision));
    });

    test('пакет результата неизменно объединяет снимки одной ревизии', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
      final before = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );
      final after = _TestCatalogEntrySnapshot(
        _summary(
          id: '00000000-0000-4000-8000-000000000001',
          title: 'Быть здоровым',
        ),
      );
      final mutation = IntentionCatalogUpdated(
        revision: revision,
        before: before,
        after: after,
      );
      final success = IntentionSaved(_intention(), catalogMutation: mutation);
      final result = ConfirmedGraphResult(revision: revision, value: success);

      expect(result.revision, same(revision));
      expect(result.value, same(success));
      expect(result.changes, hasLength(1));
      expect(
        () => result.changes.add(
          IntentionCatalogUnchanged(revision: revision, entry: after),
        ),
        throwsUnsupportedError,
      );
    });

    test('пакет намерения включает неизменяемые абсолютные счётчики', () {
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
      expect(
        () => success.additionalChanges.add(mutation),
        throwsUnsupportedError,
      );
    });

    test('пакет результата отклоняет изменение другой ревизии', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
      const newerRevision = _TestGraphRevision(epoch: 'первая', sequence: 5);
      final entry = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );

      expect(
        () => ConfirmedGraphResult(
          revision: revision,
          value: IntentionSaved(
            _intention(),
            catalogMutation: IntentionCatalogCreated(
              revision: newerRevision,
              entry: entry,
            ),
          ),
        ),
        throwsA(isA<ConfirmedGraphResultValidationException>()),
      );
    });

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
  FavoriteMark favoriteMark = FavoriteMark.notFavorite,
}) {
  final created = IntentionTimestamp(
    createdAt ?? DateTime.utc(2026, 8, 30, 12),
  );
  return IntentionSummary(
    id: _intentionId(id),
    title: title,
    hasDescription: false,
    readiness: readiness,
    archiveState: archiveState,
    activeRelationCount: 0,
    createdAt: created,
    updatedAt: IntentionTimestamp(updatedAt ?? created.value),
    tags: tags,
    favoriteMark: favoriteMark,
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

String _boundaryDescription(IntentionCatalogReconciliationBoundary boundary) =>
    switch (boundary) {
      IntentionCatalogPartialPrefixBoundary() => 'partial',
      IntentionCatalogCompletedBoundary() => 'completed',
    };

String _windowDescription(IntentionCatalogReconciliationWindow window) =>
    switch (window) {
      IntentionCatalogInnerReconciliationWindow() => 'inner',
      IntentionCatalogFinalReconciliationWindow() => 'final',
    };

String _reconciliationDescription(
  IntentionCatalogReconciliationOutcome outcome,
) => switch (outcome) {
  IntentionCatalogReconciliationFirstPortion(:final totalCount) =>
    'first:$totalCount',
  IntentionCatalogReconciliationContinuationPortion() => 'continuation',
  IntentionCatalogReconciliationRetry() => 'retry',
};

String _successDescription(IntentionCommandSuccess success) =>
    switch (success) {
      IntentionSaved() => 'saved',
      IntentionDeleted() => 'deleted',
    };

String _mutationDescription(IntentionCatalogMutation mutation) =>
    switch (mutation) {
      IntentionCatalogCreated() => 'created',
      IntentionCatalogUpdated() => 'updated',
      IntentionCatalogDeleted() => 'deleted',
      IntentionCatalogUnchanged() => 'unchanged',
    };

String _commandDescription(IntentionCommand command) => switch (command) {
  CreateIntention() => 'create',
  UpdateIntention() => 'update',
  EnableIntentionReadiness() => 'enableReadiness',
  DisableIntentionReadiness() => 'disableReadiness',
  ArchiveIntention() => 'archive',
  RestoreIntention() => 'restore',
  DeleteIntention() => 'delete',
  MarkIntentionFavorite() => 'markFavorite',
  UnmarkIntentionFavorite() => 'unmarkFavorite',
};

String _failureDescription(IntentionFailure failure) => switch (failure) {
  IntentionValidationFailure() => 'validation',
  IntentionNotFoundFailure() => 'notFound',
  IntentionConflictFailure() => 'conflict',
  IntentionHasBlockingRelationsFailure() => 'blockingRelations',
  IntentionUnavailableFailure() => 'unavailable',
  IntentionCorruptionFailure() => 'corruption',
  IntentionUnexpectedFailure() => 'unexpected',
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

final class _FailingPersonalGraphRepository
    with
        TagReadContractTestFallback,
        FavoriteReadContractTestFallback,
        CatalogReconciliationTestFallback
    implements PersonalGraphRepository {
  @override
  Future<ChoicePathSuggestionsResult> getChoicePathSuggestions(
    ChoicePathSuggestionsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<ChoicePathContinuationResult> getChoicePathContinuations(
    ChoicePathContinuationQuery query,
  ) => throw UnimplementedError();

  @override
  Future<DailyChoiceReadResult> getDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Чтение дневного выбора не используется этим тестом.',
      );

  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) =>
      throw UnsupportedError(
        'Наблюдение дневного выбора не используется этим тестом.',
      );

  @override
  Future<SelectedRelationsReadResult> getSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Чтение выбранных связей не используется в этом тесте.',
  );

  @override
  Stream<SelectedRelationsReadResult> watchSelectedRelations(
    SelectedRelationsQuery query,
  ) => throw UnsupportedError(
    'Наблюдение выбранных связей не используется в этом тесте.',
  );

  @override
  Future<GraphCommandResult<TSuccess, TFailure>> execute<
    TSuccess extends GraphCommandOutcome,
    TFailure extends GraphCommandFailure
  >(GraphCommand<TSuccess, TFailure> command) async {
    if (command is! IntentionCommand) {
      throw UnsupportedError('Команды связей не используются в этих тестах.');
    }
    return const ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>(
      IntentionUnavailableFailure(),
    ) as GraphCommandResult<TSuccess, TFailure>;
  }

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) => throw UnsupportedError(
    'Каталог дневных выборов не используется в этом тесте.',
  );

  @override
  Future<RelationGroupPageResult> getRelationGroupPage(
    RelationGroupPageQuery query,
  ) async => const RelationGroupPageFailure(RelationGroupUnavailableFailure());

  @override
  Stream<LongTermRelationReadResult> watchRelation(LongTermRelationId id) =>
      Stream.value(
        const LongTermRelationReadError(
          LongTermRelationReadUnavailableFailure(),
        ),
      );

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => Stream.value(const ResultFailure(IntentionUnavailableFailure()));
}

final class _EmptyGraphCommandOutcome implements GraphCommandOutcome {
  const _EmptyGraphCommandOutcome();

  @override
  Iterable<GraphChange> get changes => const [];
}

final class _TestCatalogCursor implements IntentionCatalogCursor {
  const _TestCatalogCursor();
}

final class _TestReconciliationCursor
    implements IntentionCatalogReconciliationCursor {
  const _TestReconciliationCursor();
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
