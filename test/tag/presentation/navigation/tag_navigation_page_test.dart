import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tag;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_entities_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_read_contract_test_fallback.dart';
import '../../../support/tag_storage_fixture.dart';

part 'tag_navigation_semantics_scenarios.dart';

void main() {
  _registerNavigationSemanticsScenarios();
  for (final (relation, archived, number) in [
    (false, false, 4),
    (false, true, 2),
    (true, false, 101),
    (true, true, 102),
  ]) {
    testWidgets(
      'точный переход к ${relation ? 'связи' : 'намерению'} $number и возврат к охвату',
      (tester) async {
        final h = await _pumpStoredPage(tester);
        if (archived) {
          await tester.tap(_scope(TaggedEntitiesScope.archived));
          await tester.pumpAndSettle();
        }
        final item = relation
            ? _relation(number, archived: archived)
            : _intention(number, archived: archived);
        await tester.tap(_row(item));
        await tester.pumpAndSettle();
        if (relation) {
          expect(h.router.current.name, RelationDetailsRoute.name);
          expect(
            h.router.current.argsAs<RelationDetailsRouteArgs>().relationId,
            (item as TaggedLongTermRelation).id,
          );
          expect(
            find.byKey(const ValueKey('relation-details-phrase')),
            findsOneWidget,
          );
        } else {
          expect(h.router.current.name, IntentionDetailsRoute.name);
          expect(
            h.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
            (item as TaggedIntention).id,
          );
          expect(find.text('Общее название'), findsOneWidget);
        }
        h.router.pop();
        await tester.pumpAndSettle();
        expect(h.router.current.name, TagNavigationRoute.name);
        expect(
          h.router.current.argsAs<TagNavigationRouteArgs>().tagId,
          _tag.id,
        );
        expect(
          tester
              .widget<ChoiceChip>(
                _scope(
                  archived
                      ? TaggedEntitiesScope.archived
                      : TaggedEntitiesScope.active,
                ),
              )
              .selected,
          isTrue,
        );
        expect(_row(item), findsOneWidget);
        if (!archived && !relation) {
          expect(find.text('Общее название'), findsNWidgets(2));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final relation in [false, true]) {
    testWidgets(
      'удалённая перед переходом ${relation ? 'связь' : 'намерение'} не подменяется прежними данными',
      (tester) async {
        final reads = _Reads();
        addTearDown(reads.dispose);
        final h = await _pumpStoredPage(tester, reads: reads);
        final item = relation ? _relation(104) : _intention(4);
        reads.page(0, [item]);
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TagNavigationPage)),
        );
        // Навигация удерживает старый снимок, пока доставка её сигнала задержана.
        // Подробности получают актуальные данные из настоящего репозитория.
        if (item case TaggedIntention(:final id)) {
          expect(
            await h.repository.execute(DeleteIntention(id)),
            isA<GraphResultSuccess>(),
          );
        } else if (item case TaggedLongTermRelation(:final id)) {
          expect(
            await h.repository.execute(DeleteLongTermRelation(id)),
            isA<GraphResultSuccess>(),
          );
        }
        await tester.tap(_row(item));
        await tester.pumpAndSettle();
        expect(
          find.text(
            relation ? l10n.relationDetailsNotFound : l10n.detailsNotFound,
          ),
          findsOneWidget,
        );
        expect(
          h.router.current.name,
          relation ? RelationDetailsRoute.name : IntentionDetailsRoute.name,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final locale in ['ru', 'en']) {
    final russian = locale == 'ru';
    testWidgets('актуализация отключает прежние переходы на $locale', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale);
        final item = _intention(1);
        reads.page(0, [item], cursor: _Cursor());
        await tester.pumpAndSettle();
        final tile = find.descendant(
          of: _row(item),
          matching: find.byType(ListTile),
        );
        final oldCallback = tester.widget<ListTile>(tile).onTap!;
        reads.watch.add(
          TagReadSuccess(
            GraphSnapshot(value: _tag, revision: const _Revision(2)),
          ),
        );
        // Сигнал уже изменил ViewModel, а прежний кадр ещё не перестроен.
        oldCallback();
        expect(tester.takeException(), isNull);
        await tester.pump();
        expect(
          find.text(
            russian
                ? 'Обновляем выдачу. Показанные данные могут быть устаревшими.'
                : 'Refreshing results. The displayed data may be out of date.',
          ),
          findsOneWidget,
        );
        expect(tester.widget<ListTile>(tile).onTap, isNull);
        expect(
          tester
              .getSemantics(_row(item))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isFalse,
        );
        expect(
          find.text(russian ? 'Показать ещё сущности' : 'Show more entities'),
          findsNothing,
        );
        reads.fail(1, const TaggedEntitiesUnavailableFailure());
        await tester.pumpAndSettle();
        expect(
          find.text(
            russian
                ? 'Не удалось обновить выдачу. Показанные данные могут быть устаревшими. Повторите чтение.'
                : 'Could not refresh results. The displayed data may be out of date. Try loading again.',
          ),
          findsOneWidget,
        );
        expect(tester.widget<ListTile>(tile).onTap, isNull);
        await tester.tap(find.text(russian ? 'Повторить' : 'Try again'));
        await tester.pump();
        expect(reads.queries.last.cursor, isNull);
        reads.page(2, [_intention(2)], revision: 2);
        await tester.pumpAndSettle();
        expect(_row(item), findsNothing);
        expect(_row(_intention(2)), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('длинный текст, охваты, подгрузка и повтор доступны на $locale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      try {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale, textScale: 3);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TagNavigationPage)),
        );
        final tag = Tag(
          id: _tag.id,
          name: TagName.fromInput('Длинный тег ' * 20),
        );
        reads.page(0, [], tag: tag);
        await tester.pumpAndSettle();
        expect(
          find.text(
            russian ? 'Тег: ${tag.name.value}' : 'Tag: ${tag.name.value}',
          ),
          findsOneWidget,
        );
        await _scrollTo(tester, _scope(TaggedEntitiesScope.archived));
        await tester.tap(_scope(TaggedEntitiesScope.archived));
        await tester.pump();
        final intention = _intention(
          2,
          archived: true,
          title: 'Очень длинное намерение ' * 10,
        );
        final relation = TaggedLongTermRelation(
          id: _relation(103).id,
          type: LongTermRelationType.can,
          sourceTitle: 'Длинное исходное намерение ' * 9,
          relatedTitle: 'Длинное связанное намерение ' * 9,
          scope: RelationScope.archived,
        );
        reads.page(1, [intention, relation], tag: tag, cursor: _Cursor());
        await tester.pumpAndSettle();
        await _scrollTo(tester, _row(intention));
        expect(
          tester.getSemantics(_row(intention)).label,
          '${l10n.tagNavigationIntentionArchived}: ${intention.title}',
        );
        expect(
          tester
              .getSize(
                find
                    .descendant(
                      of: _row(intention),
                      matching: find.byType(Text),
                    )
                    .first,
              )
              .height,
          greaterThan(100),
        );
        await _scrollTo(tester, _row(relation));
        expect(
          tester.getSemantics(_row(relation)).label,
          '${l10n.tagNavigationRelationArchived}: ${l10n.relationNeighborhoodCanPhrase(relation.sourceTitle, relation.relatedTitle)}',
        );
        final more = find.text(
          russian ? 'Показать ещё сущности' : 'Show more entities',
        );
        await _scrollTo(tester, more);
        await tester.tap(more);
        await tester.pump();
        await _expectNavigationStatusSemantics(
          tester,
          l10n.tagNavigationLoadingMore,
        );
        reads.fail(2, const TaggedEntitiesUnavailableFailure());
        await tester.pumpAndSettle();
        await _expectNavigationStatusSemantics(
          tester,
          l10n.tagNavigationLoadMoreUnavailable,
        );
        final retry = find.text(russian ? 'Повторить' : 'Try again');
        await _scrollTo(tester, retry);
        final retrySemantics = tester.getSemantics(retry);
        expect(retrySemantics.flagsCollection.isButton, isTrue);
        expect(
          retrySemantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(retry);
        await tester.pump();
        reads.page(3, [_intention(3, archived: true)], tag: tag);
        await tester.pumpAndSettle();
        await _scrollTo(tester, _row(_intention(3, archived: true)));
        expect(_row(_intention(3, archived: true)), findsOneWidget);
        expect(reads.queries.last.scope, TaggedEntitiesScope.archived);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('смешанные строки, охват и семантика на $locale', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale);
        expect(reads.queries.single.tagId, _tag.id);
        expect(reads.queries.single.scope, TaggedEntitiesScope.active);
        expect(
          find.text(
            russian
                ? 'Загружаем сущности с тегом…'
                : 'Loading tagged entities…',
          ),
          findsOneWidget,
        );
        final intention = _intention(1);
        final need = _relation(101);
        final can = _relation(102, type: LongTermRelationType.can);
        reads.page(0, [intention, need, can]);
        await tester.pumpAndSettle();

        expect(find.text(russian ? 'Тег: Дом' : 'Tag: Дом'), findsOneWidget);
        expect(find.text('Намерение 1'), findsOneWidget);
        expect(
          find.text(
            russian
                ? 'Чтобы Источник, нужно Результат'
                : 'To Источник, you need Результат',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            russian
                ? 'Чтобы Источник, можно Результат'
                : 'To Источник, you can Результат',
          ),
          findsOneWidget,
        );
        final intentionSemantics = tester.getSemantics(_row(intention));
        expect(intentionSemantics.flagsCollection.isButton, isTrue);
        expect(
          intentionSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
        expect(
          intentionSemantics.label,
          contains(russian ? 'Намерение, активно' : 'Intention, active'),
        );
        expect(
          tester.getSemantics(_row(need)).label,
          contains(
            russian
                ? 'Долговременная связь, активна'
                : 'Long-term relation, active',
          ),
        );
        expect(
          tester
              .getSemantics(_scope(TaggedEntitiesScope.active))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );

        await tester.tap(_scope(TaggedEntitiesScope.archived));
        await tester.pump();
        expect(find.text('Намерение 1'), findsNothing);
        reads.page(1, [
          _intention(2, archived: true),
          _relation(103, archived: true),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Намерение 2'), findsOneWidget);
        expect(
          tester.getSemantics(_row(_intention(2, archived: true))).label,
          contains(russian ? 'Намерение, в архиве' : 'Intention, archived'),
        );
        expect(
          tester.getSemantics(_row(_relation(103, archived: true))).label,
          contains(
            russian
                ? 'Долговременная связь, в архиве'
                : 'Long-term relation, archived',
          ),
        );
        expect(
          tester
              .getSemantics(_scope(TaggedEntitiesScope.archived))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('пустой охват отличается от отсутствующего тега на $locale', (
      tester,
    ) async {
      final reads = _Reads();
      addTearDown(reads.dispose);
      await _pumpPage(tester, reads, locale: locale);
      reads.page(0, []);
      await tester.pumpAndSettle();
      expect(
        find.text(
          russian
              ? 'С этим тегом нет активных намерений и долговременных связей.'
              : 'No active intentions or long-term relations have this tag.',
        ),
        findsOneWidget,
      );
      await tester.tap(_scope(TaggedEntitiesScope.archived));
      await tester.pump();
      reads.page(1, []);
      await tester.pumpAndSettle();
      expect(
        find.text(
          russian
              ? 'С этим тегом нет архивных намерений и долговременных связей.'
              : 'No archived intentions or long-term relations have this tag.',
        ),
        findsOneWidget,
      );
      reads.watch.add(
        const TagReadSuccess(
          GraphSnapshot(value: null, revision: _Revision(2)),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TagNavigationPage)),
      );
      expect(find.text(l10n.tagNotFound), findsOneWidget);
      expect(find.text(russian ? 'Тег: Дом' : 'Tag: Дом'), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });
  }

  testWidgets('смена языка сохраняет тег, архивный охват и буквальный текст', (
    tester,
  ) async {
    final reads = _Reads();
    addTearDown(reads.dispose);
    await _pumpPage(tester, reads);
    reads.page(0, []);
    await tester.pumpAndSettle();
    await tester.tap(_scope(TaggedEntitiesScope.archived));
    await tester.pump();
    reads.page(1, [_relation(102, archived: true)]);
    await tester.pumpAndSettle();
    await _pumpPage(tester, reads, locale: 'en');
    await tester.pumpAndSettle();
    expect(reads.queries, hasLength(2));
    expect(find.text('Tag: Дом'), findsOneWidget);
    expect(find.text('To Источник, you need Результат'), findsOneWidget);
    expect(
      tester.widget<ChoiceChip>(_scope(TaggedEntitiesScope.archived)).selected,
      isTrue,
    );
  });

  testWidgets('поздняя активная порция не возвращает прежний охват', (
    tester,
  ) async {
    final reads = _Reads();
    addTearDown(reads.dispose);
    await _pumpPage(tester, reads);
    await tester.tap(_scope(TaggedEntitiesScope.archived));
    await tester.pump();
    reads.page(0, [_intention(1)]);
    await tester.pump();
    expect(reads.queries.last.scope, TaggedEntitiesScope.archived);
    expect(find.text('Намерение 1'), findsNothing);
    reads.page(1, [_intention(2, archived: true)]);
    await tester.pumpAndSettle();
    expect(find.text('Намерение 2'), findsOneWidget);
    expect(find.text('Намерение 1'), findsNothing);
  });

  testWidgets(
    'подгрузка сохраняет строки при отказе и повторяет только чтение',
    (tester) async {
      final reads = _Reads();
      addTearDown(reads.dispose);
      await _pumpPage(tester, reads);
      final cursor = _Cursor();
      reads.page(0, [_intention(1)], cursor: cursor);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Показать ещё сущности'));
      await tester.pump();
      expect(reads.queries, hasLength(2));
      expect(reads.queries.last.cursor, same(cursor));
      expect(find.text('Загружаем ещё сущности…'), findsOneWidget);
      expect(find.text('Намерение 1'), findsOneWidget);
      reads.fail(1, const TaggedEntitiesUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось загрузить следующую порцию сущностей.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(reads.queries.last.cursor, same(cursor));
      reads.page(2, [_relation(101)]);
      await tester.pumpAndSettle();
      expect(find.text('Намерение 1'), findsOneWidget);
      expect(_row(_relation(101)), findsOneWidget);
      expect(find.text('Все сущности показаны.'), findsOneWidget);
      expect(find.text('Показать ещё сущности'), findsNothing);
    },
  );

  for (final locale in ['ru', 'en']) {
    for (final (failure, russianMessage, englishMessage) in [
      (
        const TaggedEntitiesUnavailableFailure(),
        'Не удалось загрузить сущности с тегом. Повторите попытку.',
        'Could not load tagged entities. Try again.',
      ),
      (
        const TaggedEntitiesCorruptionFailure(),
        'Сохранённые данные помеченных сущностей повреждены и не могут быть показаны.',
        'Stored tagged entity data is damaged and cannot be shown.',
      ),
      (
        const TaggedEntitiesUnexpectedFailure(),
        'Не удалось загрузить сущности с тегом из-за непредвиденной ошибки.',
        'Could not load tagged entities because of an unexpected error.',
      ),
      (
        const TaggedEntitiesInvalidCursor(),
        'Продолжение выдачи недействительно. Откройте навигацию по тегу заново.',
        'This result continuation is invalid. Reopen tag navigation.',
      ),
    ]) {
      testWidgets('начальный отказ на $locale: $russianMessage', (
        tester,
      ) async {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale);
        reads.fail(0, failure);
        await tester.pumpAndSettle();
        expect(
          find.text(locale == 'ru' ? russianMessage : englishMessage),
          findsOneWidget,
        );
        final retry = find.text(locale == 'ru' ? 'Повторить' : 'Try again');
        if (failure is TaggedEntitiesUnavailableFailure) {
          expect(retry, findsOneWidget);
          await tester.tap(retry);
          await tester.pump();
          expect(reads.queries, hasLength(2));
          expect(reads.queries.last.cursor, isNull);
          reads.page(1, [_intention(1)]);
          await tester.pumpAndSettle();
          expect(find.text('Намерение 1'), findsOneWidget);
        } else {
          expect(retry, findsNothing);
          expect(reads.queries, hasLength(1));
        }
      });
    }
    for (final (failure, pageRu, pageEn, refreshRu, refreshEn) in [
      (
        const TaggedEntitiesCorruptionFailure(),
        'Сохранённые данные повреждены; следующая порция сущностей недоступна.',
        'Stored data is damaged; more entities cannot be shown.',
        'Не удалось обновить выдачу: сохранённые данные повреждены. Показанные данные могут быть устаревшими.',
        'Could not refresh results: stored data is damaged. The displayed data may be out of date.',
      ),
      (
        const TaggedEntitiesUnexpectedFailure(),
        'Не удалось загрузить следующую порцию сущностей из-за непредвиденной ошибки.',
        'Could not load more entities because of an unexpected error.',
        'Не удалось обновить выдачу из-за непредвиденной ошибки. Показанные данные могут быть устаревшими.',
        'Could not refresh results because of an unexpected error. The displayed data may be out of date.',
      ),
    ]) {
      for (final refresh in [false, true]) {
        testWidgets(
          'неустранимый отказ ${refresh ? 'актуализации' : 'подгрузки'} на $locale: $pageRu',
          (tester) async {
            final reads = _Reads();
            addTearDown(reads.dispose);
            await _pumpPage(tester, reads, locale: locale);
            final item = _intention(1);
            reads.page(0, [item], cursor: _Cursor());
            await tester.pumpAndSettle();
            if (refresh) {
              reads.watch.add(
                TagReadSuccess(
                  GraphSnapshot(value: _tag, revision: const _Revision(2)),
                ),
              );
            } else {
              await tester.tap(
                find.text(
                  locale == 'ru'
                      ? 'Показать ещё сущности'
                      : 'Show more entities',
                ),
              );
            }
            await tester.pump();
            reads.fail(1, failure);
            await tester.pumpAndSettle();
            expect(
              find.text(
                refresh
                    ? (locale == 'ru' ? refreshRu : refreshEn)
                    : (locale == 'ru' ? pageRu : pageEn),
              ),
              findsOneWidget,
            );
            expect(_row(item), findsOneWidget);
            expect(find.byType(OutlinedButton), findsNothing);
            expect(
              tester
                  .widget<ListTile>(
                    find.descendant(
                      of: _row(item),
                      matching: find.byType(ListTile),
                    ),
                  )
                  .onTap,
              refresh ? isNull : isNotNull,
            );
          },
        );
      }
    }
  }
}

final _tag = Tag(
  id: (TagId.decode(tagFixtureId(301)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput('Дом'),
);

TaggedIntention _intention(
  int number, {
  bool archived = false,
  String? title,
}) => TaggedIntention(
  id: (IntentionId.decode(
    tagFixtureId(number),
  ) as IntentionIdDecodingSuccess).id,
  title: title ?? 'Намерение $number',
  archiveState: archived
      ? IntentionArchiveState.archived
      : IntentionArchiveState.active,
);

TaggedLongTermRelation _relation(
  int number, {
  bool archived = false,
  LongTermRelationType type = LongTermRelationType.need,
}) => TaggedLongTermRelation(
  id: (LongTermRelationId.decode(
    tagFixtureId(number),
  ) as LongTermRelationIdDecodingSuccess).id,
  type: type,
  sourceTitle: 'Источник',
  relatedTitle: 'Результат',
  scope: archived ? RelationScope.archived : RelationScope.active,
);

Finder _row(TaggedEntity item) => find.byKey(ValueKey(item.target));
Finder _scope(TaggedEntitiesScope scope) => find.byKey(ValueKey(scope));

Future<void> _pumpPage(
  WidgetTester tester,
  _Reads reads, {
  String locale = 'ru',
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tagNavigationReaderProvider.overrideWithValue(reads),
        tagNavigationChangesProvider.overrideWithValue(const Stream.empty()),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: TagNavigationPage(tagId: _tag.id),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, maxScrolls: 100);
  await tester.pumpAndSettle();
}

Future<({AppRouter router, DriftPersonalGraphRepository repository})>
_pumpStoredPage(WidgetTester tester, {_Reads? reads}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late sqlite.Database raw;
  final database = AppDatabase(
    openInMemoryLocalDatabase(setup: (db) => raw = db),
  );
  await database.open();
  seedTagStorageFixture(raw);
  raw.execute('UPDATE intentions SET title = ?', ['Общее название']);
  raw.execute(
    'INSERT INTO intentions (id, title, is_action_ready, is_archived, created_at, updated_at) VALUES (?, ?, 0, 0, 1, 1)',
    [tagFixtureId(4), 'Общее название'],
  );
  raw.execute(
    'INSERT INTO long_term_relations (id, source_intention_id, related_intention_id, type, priority, is_archived) VALUES (?, ?, ?, ?, 2, 0)',
    [tagFixtureId(104), tagFixtureId(3), tagFixtureId(1), 'can'],
  );
  raw.execute(
    'INSERT INTO tag_assignments (tag_id, intention_id) VALUES (?, ?)',
    [tagFixtureId(firstTagNumber), tagFixtureId(4)],
  );
  final repository = DriftPersonalGraphRepository(
    database,
    UuidV7IntentionIdGenerator(),
    () => DateTime.utc(2026, 9, 28),
    InMemoryDiagnosticsSink(),
  );
  final router = AppRouter();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await database.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        if (reads != null) ...[
          tagNavigationReaderProvider.overrideWithValue(reads),
          tagNavigationChangesProvider.overrideWithValue(const Stream.empty()),
        ],
      ],
      child: MaterialApp.router(
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push(TagNavigationRoute(tagId: _tag.id)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  if (reads == null) await tester.pumpAndSettle();
  return (router: router, repository: repository);
}

final class _Reads with TagReadContractTestFallback implements TagReadContract {
  final queries = <TaggedEntitiesQuery>[];
  final pending = <Completer<TaggedEntitiesPageResult>>[];
  final watch = StreamController<TagReadResult>.broadcast(sync: true);

  @override
  Stream<TagReadResult> watchTag(TagId id) => watch.stream;

  @override
  Future<TaggedEntitiesPageResult> getTaggedEntitiesPage(
    TaggedEntitiesQuery query,
  ) {
    queries.add(query);
    final result = Completer<TaggedEntitiesPageResult>();
    pending.add(result);
    return result.future;
  }

  void page(
    int index,
    List<TaggedEntity> items, {
    TaggedEntitiesCursor? cursor,
    Tag? tag,
    int revision = 1,
  }) {
    final query = queries[index];
    pending[index].complete(
      TaggedEntitiesPageSuccess(
        TaggedEntitiesPage(
          tag: tag ?? _tag,
          scope: query.scope,
          items: items,
          pageSize: query.pageSize,
          nextCursor: cursor,
          revision: _Revision(revision),
        ),
      ),
    );
  }

  void fail(int index, TaggedEntitiesReadFailure failure) =>
      pending[index].complete(TaggedEntitiesPageError(failure));

  void dispose() => unawaited(watch.close());
}

final class _Cursor implements TaggedEntitiesCursor {}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is! _Revision
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}
