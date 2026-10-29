import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/add_row.dart';
import 'package:doable/src/design_system/components/count_tiles.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/relation_row.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/application/relation_group_page.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/long_term_relation/presentation/intention_relations/intention_relations_sliver.dart';
import 'package:doable/src/long_term_relation/presentation/relation_group_paging_policy.dart';
import 'package:doable/src/shared/domain/text_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../neighborhood/neighborhood_test_support.dart';

void main() {
  const revision = TestGraphRevision(2);

  for (final locale in _locales) {
    final l10n = lookupAppLocalizations(locale);
    final names = {
      IntentionRelationGroup.needs: l10n.detailsRelationsGroupNeeds,
      IntentionRelationGroup.canUse: l10n.detailsRelationsGroupCanUse,
      IntentionRelationGroup.neededFor: l10n.detailsRelationsGroupNeededFor,
      IntentionRelationGroup.canBeUsedFor:
          l10n.detailsRelationsGroupCanBeUsedFor,
    };

    testWidgets('[${locale.languageCode}] плитки показывают числа групп по '
        'направлению и архив только своей группы до получения её строк', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // Две исходящие и три входящие активные связи «нужно», архивированные
      // связи есть только среди входящих «можно».
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        counts: testRelationCounts(
          activeNeedOutgoing: 2,
          activeNeedIncoming: 3,
          archivedCanIncoming: 2,
        ),
      );

      expect(harness.repository.requestCount, 1);
      final tiles = _tiles(tester);
      expect(tiles.columns, CountTileColumns.two);
      expect(tiles.value, IntentionRelationGroup.needs);
      expect(tiles.label, l10n.detailsRelationsGroupsLabel);
      expect(
        [for (final tile in tiles.tiles) tile.id],
        [
          IntentionRelationGroup.needs,
          IntentionRelationGroup.canUse,
          IntentionRelationGroup.neededFor,
          IntentionRelationGroup.canBeUsedFor,
        ],
      );
      expect([for (final tile in tiles.tiles) tile.count], [2, 0, 3, 0]);
      expect(
        [for (final tile in tiles.tiles) tile.archived],
        [false, false, false, true],
      );
      expect(
        [for (final tile in tiles.tiles) tile.name],
        [for (final group in IntentionRelationGroup.values) names[group]],
      );
      expect(
        [
          for (final tile in tiles.tiles)
            (tile.glyph!.kind, tile.glyph!.direction),
        ],
        [
          (CountTileGlyphKind.need, CountTileGlyphDirection.fromIntention),
          (CountTileGlyphKind.can, CountTileGlyphDirection.fromIntention),
          (CountTileGlyphKind.need, CountTileGlyphDirection.toIntention),
          (CountTileGlyphKind.can, CountTileGlyphDirection.toIntention),
        ],
      );

      // Исходящие группы стоят в верхнем ряду, входящие — под ними.
      final needs = tester.getRect(_tileFinder(IntentionRelationGroup.needs));
      final canUse = tester.getRect(_tileFinder(IntentionRelationGroup.canUse));
      final neededFor = tester.getRect(
        _tileFinder(IntentionRelationGroup.neededFor),
      );
      expect(canUse.top, needs.top);
      expect(canUse.left, greaterThan(needs.right));
      expect(neededFor.left, needs.left);
      expect(neededFor.top, greaterThan(needs.bottom));
      // Плитки стоят в 8 под вкладками.
      expect(needs.top, tester.getBottomLeft(find.byKey(_tabsKey)).dy + 8);

      expect(
        find.bySemanticsLabel(
          l10n.detailsRelationsGroupTileSemantic(
            names[IntentionRelationGroup.neededFor]!,
            3,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          l10n.detailsRelationsGroupTileArchivedSemantic(
            names[IntentionRelationGroup.canBeUsedFor]!,
            0,
          ),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(l10n.detailsRelationsGroupsLabel), findsOne);

      // Опубликованное состояние модели заменяет сводку подробных данных.
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 4),
          counts: testRelationCounts(
            activeNeedOutgoing: 4,
            activeNeedIncoming: 3,
            archivedCanIncoming: 2,
          ),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        [for (final tile in _tiles(tester).tiles) tile.count],
        [4, 0, 3, 0],
      );
      semantics.dispose();
    });

    testWidgets('[${locale.languageCode}] строка связи показывает соседа и '
        'описание и открывает связь или соседа на той же группе', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final ownerId = testIntentionId(1);
      final neighborId = testIntentionId(2);
      final description = [
        'Разминка, присед, тяга и жим.',
        'Три подхода по восемь повторений.',
        'Отдых между подходами две минуты.',
        'Заминка и растяжка.',
      ].join('\n');
      final entry = RelationGroupEntry(
        relation: LongTermRelation(
          id: testRelationId(1),
          sourceIntentionId: ownerId,
          relatedIntentionId: neighborId,
          type: LongTermRelationType.need,
          priority: RelationPriority.p1,
          scope: RelationScope.active,
          creationSequence: RelationCreationSequence(1),
        ),
        neighbor: RelationNeighbor(
          id: neighborId,
          title: 'Сделать силовую тренировку',
          archiveState: IntentionArchiveState.active,
          readiness: IntentionReadiness.ready,
        ),
        descriptionPreview: TextPreview.fromText(description),
      );
      final counts = testRelationCounts(activeNeedOutgoing: 1);
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        ownerTitle: 'Быть здоровым',
        counts: counts,
        viewportHeight: 900,
      );
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: [entry],
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      final note = TextPreview.fromText(description).text;
      final row = _relationRow(tester, 1);
      expect(row.kind, RelationRowKind.need);
      expect(row.priority, RelationRowPriority.p1);
      expect(row.label, l10n.detailsRelationsRowNeed('P1'));
      expect(row.name, 'Сделать силовую тренировку');
      expect(row.note, note);
      expect(row.action, isTrue);
      expect(row.archived, isFalse);
      expect(row.intentionArchived, isFalse);
      expect(find.text(l10n.detailsRelationsRowNeed('P1')), findsOneWidget);
      expect(find.text('Сделать силовую тренировку'), findsOneWidget);
      expect(find.text(note), findsOneWidget);

      final rowLabel = [
        l10n.relationNeighborhoodNeedPhrase(
          'Быть здоровым',
          'Сделать силовую тренировку',
        ),
        l10n.relationNeighborhoodPriority('P1'),
        note,
      ].join('. ');
      expect(row.semanticLabel, rowLabel);
      final walkLabel = l10n.detailsRelationsWalkAction(
        'Сделать силовую тренировку',
      );
      expect(row.walkLabel, walkLabel);

      await tester.tap(find.bySemanticsLabel(rowLabel));
      expect(harness.opened, [testRelationId(1)]);
      expect(harness.walks, isEmpty);

      await tester.tap(find.bySemanticsLabel(walkLabel));
      expect(harness.walks, [(neighborId, IntentionRelationGroup.needs)]);
      expect(harness.opened, hasLength(1));
      semantics.dispose();
    });

    testWidgets('[${locale.languageCode}] входящая строка сохраняет '
        'направление формулировки и называет архивированного соседа', (
      tester,
    ) async {
      final counts = testRelationCounts(activeCanIncoming: 1);
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        ownerTitle: 'Много ходить',
        counts: counts,
        target: const RelationsTarget(IntentionRelationGroup.canBeUsedFor),
      );
      final base = testGroupRow(
        ownerId: harness.ownerId,
        index: 1,
        type: LongTermRelationType.can,
        direction: RelationDirection.incoming,
        neighborTitle: 'Быть здоровым',
      );
      final entry = RelationGroupEntry(
        relation: base.relation,
        neighbor: RelationNeighbor(
          id: base.neighbor.id,
          title: base.neighbor.title,
          archiveState: IntentionArchiveState.archived,
          readiness: IntentionReadiness.notReady,
        ),
      );
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: [entry],
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      final row = _relationRow(tester, 1);
      expect(row.kind, RelationRowKind.can);
      expect(row.label, l10n.detailsRelationsRowCan('P2'));
      expect(row.action, isFalse);
      expect(row.intentionArchived, isTrue);
      expect(row.note, isNull);
      expect(
        row.semanticLabel,
        [
          l10n.relationNeighborhoodCanPhrase('Быть здоровым', 'Много ходить'),
          l10n.relationNeighborhoodPriority('P2'),
          l10n.detailsRelationsNeighborArchived('Быть здоровым'),
        ].join('. '),
      );
      expect(
        row.walkLabel,
        l10n.detailsRelationsWalkIntention('Быть здоровым'),
      );

      row.onWalk();
      expect(harness.walks, [
        (entry.neighbor.id, IntentionRelationGroup.canBeUsedFor),
      ]);
    });

    testWidgets('[${locale.languageCode}] выбор плитки читает первую порцию '
        'только выбранной группы', (tester) async {
      final counts = testRelationCounts(
        activeNeedOutgoing: 1,
        activeCanIncoming: 1,
      );
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        counts: counts,
      );
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(_rowFinder(1), findsOneWidget);

      await tester.tap(_tileFinder(IntentionRelationGroup.canBeUsedFor));
      await tester.pump();

      expect(harness.repository.requestCount, 2);
      final query = harness.repository.queryAt(1);
      expect(query.intentionId, harness.ownerId);
      expect(query.type, LongTermRelationType.can);
      expect(query.direction, RelationDirection.incoming);
      expect(query.scope, RelationScope.active);
      expect(query.cursor, isNull);
      expect(_tiles(tester).value, IntentionRelationGroup.canBeUsedFor);
      expect(
        harness.pageInstance.relations?.group,
        IntentionRelationGroup.canBeUsedFor,
      );
      expect(_rowFinder(1), findsNothing);
      expect(find.text(l10n.relationNeighborhoodSummaryLoading), findsOne);

      harness.repository.completePage(
        1,
        RelationGroupFirstPage(
          items: testGroupRows(
            ownerId: harness.ownerId,
            from: 2,
            count: 1,
            type: LongTermRelationType.can,
            direction: RelationDirection.incoming,
          ),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(_rowFinder(2), findsOneWidget);
    });

    testWidgets('[${locale.languageCode}] подгружает активную часть у её '
        'конца и показывает статусы подгрузки и конца', (tester) async {
      final counts = testRelationCounts(activeNeedOutgoing: 11);
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        counts: counts,
        policy: RelationGroupPagingPolicy(pageSize: 10, prefetchRemaining: 2),
      );
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 10),
          counts: counts,
          nextCursor: const TestRelationGroupCursor(10),
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      // Начало списка ещё далеко от конца загруженной части.
      expect(harness.repository.requestCount, 1);

      await _scrollTo(tester, _rowFinder(8), settle: false);
      await _pumpUntilRequestCount(tester, harness.repository, 2);
      final continuation = harness.repository.queryAt(1);
      expect(continuation.cursor, const TestRelationGroupCursor(10));
      expect(continuation.scope, RelationScope.active);
      await _scrollTo(
        tester,
        find.text(l10n.relationNeighborhoodLoadingMore),
        settle: false,
      );

      harness.repository.failRead(1, const RelationGroupUnavailableFailure());
      await tester.pumpAndSettle();
      await _scrollTo(
        tester,
        find.text(l10n.relationNeighborhoodLoadMoreUnavailable),
      );
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(harness.repository.requestCount, 3);
      expect(
        harness.repository.queryAt(2).cursor,
        const TestRelationGroupCursor(10),
      );

      harness.repository.completePage(
        2,
        RelationGroupContinuationPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 11, count: 1),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      await _scrollTo(tester, find.text(l10n.relationNeighborhoodConfirmedEnd));
      expect(_rowFinder(11), findsOneWidget);
    });

    testWidgets('[${locale.languageCode}] показывает первое чтение и его '
        'отказ с повтором только при недоступности', (tester) async {
      final harness = await _Harness.pump(tester, locale: locale);
      expect(find.text(l10n.relationNeighborhoodSummaryLoading), findsOne);

      harness.repository.failRead(0, const RelationGroupUnavailableFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.relationNeighborhoodInitialUnavailable), findsOne);
      await _scrollTo(tester, find.text(l10n.commonRetry));
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(harness.repository.requestCount, 2);
      expect(harness.repository.queryAt(1).cursor, isNull);

      harness.repository.failRead(1, const RelationGroupCorruptionFailure());
      await tester.pumpAndSettle();
      expect(find.text(l10n.relationNeighborhoodInitialCorruption), findsOne);
      expect(find.text(l10n.commonRetry), findsNothing);
    });

    testWidgets('[${locale.languageCode}] отличает пустую группу от '
        'загрузки', (tester) async {
      final harness = await _Harness.pump(tester, locale: locale);
      expect(find.byType(EmptyState), findsNothing);

      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: const [],
          counts: testRelationCounts(),
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.relationNeighborhoodSummaryLoading), findsNothing);
      expect(find.byType(EmptyState), findsOne);
    });

    testWidgets('[${locale.languageCode}] под плитками стоит подсказка о '
        'смысле выбранной группы, а «Добавить» передаёт группу странице', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final harness = await _Harness.pump(tester, locale: locale);
      final hints = {
        IntentionRelationGroup.needs: l10n.detailsRelationsNeedsHint,
        IntentionRelationGroup.canUse: l10n.detailsRelationsCanUseHint,
        IntentionRelationGroup.neededFor: l10n.detailsRelationsNeededForHint,
        IntentionRelationGroup.canBeUsedFor:
            l10n.detailsRelationsCanBeUsedForHint,
      };
      final addLabels = {
        IntentionRelationGroup.needs: l10n.detailsRelationsAddNeedsLabel,
        IntentionRelationGroup.canUse: l10n.detailsRelationsAddCanUseLabel,
        IntentionRelationGroup.neededFor:
            l10n.detailsRelationsAddNeededForLabel,
        IntentionRelationGroup.canBeUsedFor:
            l10n.detailsRelationsAddCanBeUsedForLabel,
      };

      for (final group in IntentionRelationGroup.values) {
        if (group != IntentionRelationGroup.needs) {
          await tester.tap(_tileFinder(group));
          await tester.pump();
        }
        for (final entry in hints.entries) {
          expect(
            find.text(entry.value),
            entry.key == group ? findsOneWidget : findsNothing,
          );
        }
        expect(find.text(l10n.detailsRelationsAdd), findsOneWidget);
        await tester.tap(find.bySemanticsLabel(addLabels[group]!));
        expect(harness.adds.last, group);
      }
      expect(harness.adds, IntentionRelationGroup.values);
      semantics.dispose();
    });

    testWidgets('[${locale.languageCode}] строка «Добавить» стоит в 4 под '
        'плитками, а список следует за ней сразу', (tester) async {
      final counts = testRelationCounts(activeNeedOutgoing: 1);
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        counts: counts,
      );
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester.getRect(
        find.byType(CountTiles<IntentionRelationGroup>),
      );
      final addRow = tester.getRect(find.byType(AddRow));
      expect(addRow.top, tiles.bottom + 4);
      expect(tester.getTopLeft(_rowFinder(1)).dy, addRow.bottom);
    });

    testWidgets('[${locale.languageCode}] у архивированного намерения строка '
        'держит только подсказку', (tester) async {
      await _Harness.pump(
        tester,
        locale: locale,
        archiveState: IntentionArchiveState.archived,
      );

      expect(find.text(l10n.detailsRelationsNeedsHint), findsOneWidget);
      expect(find.byKey(_addKey), findsNothing);
      expect(find.text(l10n.detailsRelationsAdd), findsNothing);
    });

    testWidgets('[${locale.languageCode}] пустая группа объясняет, какие '
        'связи в ней появятся, без значка и «Добавить» не пропадает', (
      tester,
    ) async {
      final harness = await _Harness.pump(tester, locale: locale);
      final titles = {
        IntentionRelationGroup.needs: l10n.detailsRelationsEmptyNeedsTitle,
        IntentionRelationGroup.canUse: l10n.detailsRelationsEmptyCanUseTitle,
        IntentionRelationGroup.neededFor:
            l10n.detailsRelationsEmptyNeededForTitle,
        IntentionRelationGroup.canBeUsedFor:
            l10n.detailsRelationsEmptyCanBeUsedForTitle,
      };
      final texts = {
        IntentionRelationGroup.needs:
            l10n.detailsRelationsEmptyNeedsIntentionText,
        IntentionRelationGroup.canUse: l10n.detailsRelationsEmptyCanUseText,
        IntentionRelationGroup.neededFor:
            l10n.detailsRelationsEmptyNeededForText,
        IntentionRelationGroup.canBeUsedFor:
            l10n.detailsRelationsEmptyCanBeUsedForText,
      };

      for (final (index, group) in IntentionRelationGroup.values.indexed) {
        if (group != IntentionRelationGroup.needs) {
          await tester.tap(_tileFinder(group));
          await tester.pump();
        }
        harness.repository.completePage(index, _emptyPage(revision));
        await tester.pumpAndSettle();

        final empty = tester.widget<EmptyState>(find.byType(EmptyState));
        expect(empty.title, titles[group]);
        expect(empty.text, texts[group]);
        expect(empty.icon, isNull);
        expect(empty.action, isNull);
        expect(empty.textMaxWidth, 270);
        expect(empty.pretty, isTrue);
        expect(empty.spaceAbove, 24);
        expect(empty.spaceBelow, 24);
        expect(find.byType(AddRow), findsOneWidget);
        expect(find.byKey(_addKey), findsOneWidget);
        expect(find.byType(CountTiles<IntentionRelationGroup>), findsOneWidget);
      }
    });

    testWidgets('[${locale.languageCode}] пустая группа «Нужно» действия '
        'напоминает, что действие может обходиться без других', (tester) async {
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        readiness: IntentionReadiness.ready,
        target: const RelationsTarget(IntentionRelationGroup.needs),
      );
      harness.repository.completePage(0, _emptyPage(revision));
      await tester.pumpAndSettle();

      final empty = tester.widget<EmptyState>(find.byType(EmptyState));
      expect(empty.title, l10n.detailsRelationsEmptyNeedsTitle);
      expect(empty.text, l10n.detailsRelationsEmptyNeedsActionText);
      expect(empty.pretty, isTrue);
    });

    testWidgets('[${locale.languageCode}] пустая группа архивированного '
        'намерения просит восстановить его, а плитки и подсказка остаются', (
      tester,
    ) async {
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        archiveState: IntentionArchiveState.archived,
      );
      final titles = {
        IntentionRelationGroup.needs: l10n.detailsRelationsEmptyNeedsTitle,
        IntentionRelationGroup.canUse: l10n.detailsRelationsEmptyCanUseTitle,
        IntentionRelationGroup.neededFor:
            l10n.detailsRelationsEmptyNeededForTitle,
        IntentionRelationGroup.canBeUsedFor:
            l10n.detailsRelationsEmptyCanBeUsedForTitle,
      };

      for (final (index, group) in IntentionRelationGroup.values.indexed) {
        if (group != IntentionRelationGroup.needs) {
          await tester.tap(_tileFinder(group));
          await tester.pump();
        }
        // Активная и архивная части группы читаются парой запросов.
        harness.repository.completePage(index * 2, _emptyPage(revision));
        harness.repository.completePage(index * 2 + 1, _emptyPage(revision));
        await tester.pumpAndSettle();

        final empty = tester.widget<EmptyState>(find.byType(EmptyState));
        expect(empty.title, titles[group]);
        expect(empty.text, l10n.detailsRelationsEmptyArchivedText);
        expect(empty.icon, isNull);
        expect(empty.textMaxWidth, 270);
        expect(empty.pretty, isTrue);
        expect(empty.spaceAbove, 24);
        expect(empty.spaceBelow, 24);
        expect(_tiles(tester).value, group);
        expect(find.byKey(_addKey), findsNothing);
      }
    });

    testWidgets('[${locale.languageCode}] пустая группа не снимает отметку '
        'архива другой группы', (tester) async {
      final harness = await _Harness.pump(tester, locale: locale);
      harness.repository.completePage(
        0,
        _emptyPage(
          revision,
          counts: testRelationCounts(archivedCanIncoming: 2),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(
        [for (final tile in _tiles(tester).tiles) tile.archived],
        [false, false, false, true],
      );
    });

    testWidgets('[${locale.languageCode}] группа только с архивированными '
        'связями не считается пустой', (tester) async {
      final harness = await _Harness.pump(tester, locale: locale);
      harness.repository.completePage(
        0,
        _emptyPage(
          revision,
          counts: testRelationCounts(archivedNeedOutgoing: 2),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsNothing);
      expect(find.byKey(_addKey), findsOneWidget);
      expect(_tiles(tester).tiles.first.archived, isTrue);
    });

    testWidgets('[${locale.languageCode}] отказ обновления пустой группы '
        'остаётся виден рядом с пустым состоянием', (tester) async {
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        viewportHeight: 900,
      );
      harness.repository.completePage(0, _emptyPage(revision));
      await tester.pumpAndSettle();

      harness.repository.emitIntention(
        testNeighborhoodIntention(id: harness.ownerId),
        counts: testRelationCounts(),
        revision: const TestGraphRevision(3),
      );
      await _pumpUntilRequestCount(tester, harness.repository, 2);
      harness.repository.failRead(1, const RelationGroupUnavailableFailure());
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text(l10n.relationNeighborhoodRefreshFailed), findsOne);
      expect(find.text(l10n.commonRetry), findsOne);
    });

    testWidgets('[${locale.languageCode}] показывает обновление и его отказ '
        'под прежними строками', (tester) async {
      final counts = testRelationCounts(activeNeedOutgoing: 1);
      final harness = await _Harness.pump(
        tester,
        locale: locale,
        counts: counts,
        viewportHeight: 900,
      );
      harness.repository.completePage(
        0,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 1),
          counts: counts,
          nextCursor: null,
          revision: revision,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10n.relationNeighborhoodConfirmedEnd), findsOne);

      final refreshed = testRelationCounts(activeNeedOutgoing: 2);
      harness.repository.emitIntention(
        testNeighborhoodIntention(id: harness.ownerId),
        counts: refreshed,
        revision: const TestGraphRevision(3),
      );
      await _pumpUntilRequestCount(tester, harness.repository, 2);
      await tester.pump();
      expect(_rowFinder(1), findsOneWidget);
      expect(find.text(l10n.relationNeighborhoodRefreshing), findsOne);

      harness.repository.failRead(1, const RelationGroupUnavailableFailure());
      await tester.pumpAndSettle();
      expect(_rowFinder(1), findsOneWidget);
      expect(find.text(l10n.relationNeighborhoodRefreshFailed), findsOne);
      await _scrollTo(tester, find.text(l10n.commonRetry));
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pump();
      expect(harness.repository.requestCount, 3);

      harness.repository.completePage(
        2,
        RelationGroupFirstPage(
          items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 2),
          counts: refreshed,
          nextCursor: null,
          revision: const TestGraphRevision(3),
        ),
      );
      await tester.pumpAndSettle();
      expect(_rowFinder(2), findsOneWidget);
      expect(find.text(l10n.relationNeighborhoodConfirmedEnd), findsOne);
    });
  }

  testWidgets('пустое состояние стоит в оставшейся высоте под строкой '
      '«Добавить» с полями 24 сверху и снизу', (tester) async {
    final harness = await _Harness.pump(tester, viewportHeight: 1600);
    harness.repository.completePage(0, _emptyPage(revision));
    await tester.pumpAndSettle();

    final addRowBottom = tester.getRect(find.byType(AddRow)).bottom;
    final empty = tester.widget<EmptyState>(find.byType(EmptyState));
    final title = tester.getRect(find.text(empty.title));
    final text = tester.getRect(find.text(empty.text));
    // Блок стоит посередине между строкой «Добавить» и низом области
    // прокрутки, а над ним и под ним остаётся не меньше 24.
    expect(
      (title.top + text.bottom) / 2,
      closeTo((addRowBottom + 1600) / 2, 1),
    );
    expect(title.top - addRowBottom, greaterThanOrEqualTo(24));
    expect(1600 - text.bottom, greaterThanOrEqualTo(24));
  });

  testWidgets('после пересборки возвращает видимую строку под закреплённые '
      'вкладки', (tester) async {
    final counts = testRelationCounts(activeNeedOutgoing: 20);
    final harness = await _Harness.pump(tester, counts: counts);
    harness.repository.completePage(
      0,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 1, count: 20),
        counts: counts,
        nextCursor: null,
        revision: revision,
      ),
    );
    await tester.pumpAndSettle();

    // Восьмая строка начинается сразу под вкладками, а седьмая целиком
    // скрыта под ними.
    await _scrollTo(tester, _rowFinder(8));
    final position = _position(tester);
    final tabsBottom = tester.getBottomLeft(find.byKey(_tabsKey)).dy;
    await position.animateTo(
      position.pixels + tester.getTopLeft(_rowFinder(8)).dy - tabsBottom,
      duration: const Duration(milliseconds: 100),
      curve: Curves.linear,
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(_rowFinder(8)).dy, closeTo(tabsBottom, 0.01));

    // Новая ревизия убирает три первые связи: без якоря восьмая строка
    // ушла бы вверх под вкладки.
    final refreshed = testRelationCounts(activeNeedOutgoing: 17);
    harness.repository.emitIntention(
      testNeighborhoodIntention(id: harness.ownerId),
      counts: refreshed,
      revision: const TestGraphRevision(3),
    );
    await _pumpUntilRequestCount(tester, harness.repository, 2);
    harness.repository.completePage(
      1,
      RelationGroupFirstPage(
        items: testGroupRows(ownerId: harness.ownerId, from: 4, count: 17),
        counts: refreshed,
        nextCursor: null,
        revision: const TestGraphRevision(3),
      ),
    );
    await tester.pumpAndSettle();

    expect(_rowFinder(1), findsNothing);
    expect(
      tester.getTopLeft(_rowFinder(8)).dy,
      closeTo(tester.getBottomLeft(find.byKey(_tabsKey)).dy, 0.01),
    );
  });
}

const _locales = [Locale('ru'), Locale('en')];
const _headHeight = 300.0;
const _tabsHeight = 52.0;
const _tabsKey = ValueKey('test-pinned-tabs');
const _addKey = ValueKey('intention-relations-add');

/// Вкладка «Связи» под шапкой и закреплёнными вкладками, как на странице:
/// подробные данные намерения передаёт страница.
final class _Harness {
  _Harness._(this.repository, this.pageInstance);

  final ControlledNeighborhoodRepository repository;
  final IntentionPageInstance pageInstance;
  final IntentionId ownerId = testIntentionId(1);
  final opened = <LongTermRelationId>[];
  final walks = <(IntentionId, IntentionRelationGroup)>[];
  final adds = <IntentionRelationGroup>[];

  static Future<_Harness> pump(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    String ownerTitle = 'Намерение',
    IntentionReadiness readiness = IntentionReadiness.notReady,
    IntentionArchiveState archiveState = IntentionArchiveState.active,
    RelationCounts? counts,
    IntentionPageTarget target = const OverviewTarget(),
    RelationGroupPagingPolicy? policy,
    double? viewportHeight,
  }) async {
    if (viewportHeight != null) {
      tester.view
        ..physicalSize = Size(800, viewportHeight)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final repository = ControlledNeighborhoodRepository();
    addTearDown(repository.dispose);
    final harness = _Harness._(
      repository,
      IntentionPageInstance(target: target),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
          relationGroupPagingPolicyProvider.overrideWithValue(
            policy ??
                RelationGroupPagingPolicy(pageSize: 50, prefetchRemaining: 15),
          ),
        ],
        retry: (retryCount, error) => null,
        child: MaterialApp(
          theme: doableTheme(Brightness.light),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => CustomScrollView(
                slivers: [
                  const SliverToBoxAdapter(
                    child: SizedBox(height: _headHeight),
                  ),
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _PinnedTabs(),
                  ),
                  if (ref.watch(
                        intentionDetailsViewModelProvider(harness.ownerId),
                      )
                      case IntentionDetailsLoaded(:final details))
                    IntentionRelationsSliver(
                      details: details,
                      pageInstance: harness.pageInstance,
                      onOpenRelation: harness.opened.add,
                      onWalk: (neighborId, group) =>
                          harness.walks.add((neighborId, group)),
                      onAdd: harness.adds.add,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    repository.emitIntention(
      testNeighborhoodIntention(
        id: harness.ownerId,
        title: ownerTitle,
        readiness: readiness,
        archiveState: archiveState,
      ),
      counts: counts ?? testRelationCounts(),
      revision: const TestGraphRevision(1),
    );
    await _pumpUntilRequestCount(tester, repository, 1);
    return harness;
  }
}

final class _PinnedTabs extends SliverPersistentHeaderDelegate {
  const _PinnedTabs();

  @override
  double get minExtent => _tabsHeight;

  @override
  double get maxExtent => _tabsHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => const SizedBox.expand(
    key: _tabsKey,
    child: ColoredBox(color: Colors.white),
  );

  @override
  bool shouldRebuild(_PinnedTabs oldDelegate) => false;
}

RelationGroupFirstPage _emptyPage(
  TestGraphRevision revision, {
  RelationCounts? counts,
}) => RelationGroupFirstPage(
  items: const [],
  counts: counts ?? testRelationCounts(),
  nextCursor: null,
  revision: revision,
);

CountTiles<IntentionRelationGroup> _tiles(WidgetTester tester) =>
    tester.widget(find.byType(CountTiles<IntentionRelationGroup>));

RelationRow _relationRow(WidgetTester tester, int index) => tester.widget(
  find.descendant(of: _rowFinder(index), matching: find.byType(RelationRow)),
);

Finder _tileFinder(IntentionRelationGroup group) =>
    find.byKey(ValueKey('intention-relations-group-${group.name}'));

Finder _rowFinder(int index) => find.byKey(
  ValueKey(
    'intention-relations-row-${testRelationId(index).toCanonicalString()}',
  ),
);

ScrollPosition _position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

/// Индикатор подгрузки анимируется бесконечно, поэтому при нём прокрутка
/// не ждёт затихания кадров.
Future<void> _scrollTo(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _pumpUntilRequestCount(
  WidgetTester tester,
  ControlledNeighborhoodRepository repository,
  int expected,
) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (repository.requestCount >= expected) {
      return;
    }
    await tester.pump();
  }
  throw StateError('Ожидаемая порция группы не была запрошена.');
}
