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
import 'package:doable/src/tag/application/tag_read_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
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
part 'tag_navigation_terminal_page_scenarios.dart';
part 'tag_navigation_late_page_widget_scenarios.dart';

void main() {
  _registerNavigationSemanticsScenarios();
  _registerTerminalNavigationScenarios();
  _registerLatePageWidgetScenarios();
  for (final (archived, number) in [(false, 1), (false, 4), (true, 2)]) {
    testWidgets('точный переход к намерению $number и возврат к охвату', (
      tester,
    ) async {
      final h = await _pumpStoredPage(tester);
      if (archived) {
        await tester.tap(_scope(TaggedIntentionsScope.archived));
        await tester.pumpAndSettle();
      }
      final item = _intention(number, archived: archived);
      expect(_row(_intention(3)), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(archived ? 1 : 2));
      expect(find.textContaining('Чтобы'), findsNothing);
      await tester.tap(_row(item));
      await tester.pumpAndSettle();
      expect(h.router.current.name, IntentionDetailsRoute.name);
      expect(
        h.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        item.id,
      );
      expect(find.text('Общее название'), findsOneWidget);
      h.router.pop();
      await tester.pumpAndSettle();
      expect(h.router.current.name, TagNavigationRoute.name);
      expect(h.router.current.argsAs<TagNavigationRouteArgs>().tagId, _tag.id);
      expect(
        tester
            .widget<ChoiceChip>(
              _scope(
                archived
                    ? TaggedIntentionsScope.archived
                    : TaggedIntentionsScope.active,
              ),
            )
            .selected,
        isTrue,
      );
      expect(_row(item), findsOneWidget);
      if (!archived) expect(find.text('Общее название'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'удалённое перед переходом намерение не подменяется прежними данными',
    (tester) async {
      final reads = _Reads();
      addTearDown(reads.dispose);
      final h = await _pumpStoredPage(tester, reads: reads);
      final item = _intention(4);
      reads.page(0, [item]);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TagNavigationPage)),
      );
      // Навигация удерживает снимок при задержанном сигнале;
      // подробности читают актуальные данные реального репозитория.
      expect(
        await h.repository.execute(DeleteIntention(item.id)),
        isA<GraphResultSuccess>(),
      );
      await tester.tap(_row(item));
      await tester.pumpAndSettle();
      expect(find.text(l10n.detailsNotFound), findsOneWidget);
      expect(h.router.current.name, IntentionDetailsRoute.name);
      expect(tester.takeException(), isNull);
    },
  );

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
          find.text(
            russian ? 'Показать ещё намерения' : 'Show more intentions',
          ),
          findsNothing,
        );
        reads.fail(1, const TaggedIntentionsUnavailableFailure());
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

    testWidgets(
      'длинный текст, охваты, подгрузка и повтор доступны на $locale',
      (tester) async {
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
          await _scrollTo(tester, _scope(TaggedIntentionsScope.archived));
          await tester.tap(_scope(TaggedIntentionsScope.archived));
          await tester.pump();
          final intention = _intention(
            2,
            archived: true,
            title: 'Очень длинное намерение ' * 10,
          );
          final second = _intention(
            103,
            archived: true,
            title: 'Ещё одно длинное намерение ' * 7,
          );
          reads.page(1, [intention, second], tag: tag, cursor: _Cursor());
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
          await _scrollTo(tester, _row(second));
          expect(
            tester.getSemantics(_row(second)).label,
            '${l10n.tagNavigationIntentionArchived}: ${second.title}',
          );
          final more = find.text(
            russian ? 'Показать ещё намерения' : 'Show more intentions',
          );
          await _scrollTo(tester, more);
          await tester.tap(more);
          await tester.pump();
          await _expectNavigationStatusSemantics(
            tester,
            l10n.tagNavigationLoadingMore,
          );
          reads.fail(2, const TaggedIntentionsUnavailableFailure());
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
          expect(reads.queries.last.scope, TaggedIntentionsScope.archived);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets('строки намерений тега не показывают отметку избранного на '
        '$locale', (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale);
        final active = _intention(1);
        reads.page(0, [active, _intention(101)]);
        await tester.pumpAndSettle();

        // Навигация по тегу — представление без поиска: строка намерения
        // тега отметку не несёт и не выводит её для избранных намерений.
        final markLabel = russian
            ? 'Избранное намерение'
            : 'Favorite intention';
        expect(find.text('Намерение 1'), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNothing);
        expect(find.byIcon(Icons.star_border), findsNothing);
        expect(find.text(markLabel), findsNothing);
        expect(
          tester.getSemantics(_row(active)).label,
          isNot(contains(markLabel)),
        );
        expect(find.bySemanticsLabel(RegExp(markLabel)), findsNothing);

        await tester.tap(_scope(TaggedIntentionsScope.archived));
        await tester.pump();
        final archived = _intention(2, archived: true);
        reads.page(1, [archived]);
        await tester.pumpAndSettle();
        expect(find.text('Намерение 2'), findsOneWidget);
        expect(find.byIcon(Icons.star), findsNothing);
        expect(
          tester.getSemantics(_row(archived)).label,
          isNot(contains(markLabel)),
        );
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('строки намерений, охват и семантика на $locale', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        final reads = _Reads();
        addTearDown(reads.dispose);
        await _pumpPage(tester, reads, locale: locale);
        expect(reads.queries.single.tagId, _tag.id);
        expect(reads.queries.single.scope, TaggedIntentionsScope.active);
        expect(
          find.text(
            russian
                ? 'Загружаем намерения с тегом…'
                : 'Loading tagged intentions…',
          ),
          findsOneWidget,
        );
        final intention = _intention(1);
        final need = _intention(101);
        final can = _intention(102);
        reads.page(0, [intention, need, can]);
        await tester.pumpAndSettle();

        expect(find.text(russian ? 'Тег: Дом' : 'Tag: Дом'), findsOneWidget);
        expect(find.text('Намерение 1'), findsOneWidget);
        expect(find.text('Намерение 101'), findsOneWidget);
        expect(find.text('Намерение 102'), findsOneWidget);
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
          contains(russian ? 'Намерение, активно' : 'Intention, active'),
        );
        expect(
          tester
              .getSemantics(_scope(TaggedIntentionsScope.active))
              .flagsCollection
              .isSelected,
          Tristate.isTrue,
        );

        await tester.tap(_scope(TaggedIntentionsScope.archived));
        await tester.pump();
        expect(find.text('Намерение 1'), findsNothing);
        reads.page(1, [
          _intention(2, archived: true),
          _intention(103, archived: true),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Намерение 2'), findsOneWidget);
        expect(
          tester.getSemantics(_row(_intention(2, archived: true))).label,
          contains(russian ? 'Намерение, в архиве' : 'Intention, archived'),
        );
        expect(
          tester.getSemantics(_row(_intention(103, archived: true))).label,
          contains(russian ? 'Намерение, в архиве' : 'Intention, archived'),
        );
        expect(
          tester
              .getSemantics(_scope(TaggedIntentionsScope.archived))
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
              ? 'С этим тегом нет активных намерений.'
              : 'No active intentions have this tag.',
        ),
        findsOneWidget,
      );
      await tester.tap(_scope(TaggedIntentionsScope.archived));
      await tester.pump();
      reads.page(1, []);
      await tester.pumpAndSettle();
      expect(
        find.text(
          russian
              ? 'С этим тегом нет архивированных намерений.'
              : 'No archived intentions have this tag.',
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
    await tester.tap(_scope(TaggedIntentionsScope.archived));
    await tester.pump();
    reads.page(1, [_intention(102, archived: true)]);
    await tester.pumpAndSettle();
    await _pumpPage(tester, reads, locale: 'en');
    await tester.pumpAndSettle();
    expect(reads.queries, hasLength(2));
    expect(find.text('Tag: Дом'), findsOneWidget);
    expect(find.text('Намерение 102'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(_scope(TaggedIntentionsScope.archived))
          .selected,
      isTrue,
    );
  });

  testWidgets('поздняя активная порция не возвращает прежний охват', (
    tester,
  ) async {
    final reads = _Reads();
    addTearDown(reads.dispose);
    await _pumpPage(tester, reads);
    await tester.tap(_scope(TaggedIntentionsScope.archived));
    await tester.pump();
    reads.page(0, [_intention(1)]);
    await tester.pump();
    expect(reads.queries.last.scope, TaggedIntentionsScope.archived);
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
      await tester.tap(find.text('Показать ещё намерения'));
      await tester.pump();
      expect(reads.queries, hasLength(2));
      expect(reads.queries.last.cursor, same(cursor));
      expect(find.text('Загружаем ещё намерения…'), findsOneWidget);
      expect(find.text('Намерение 1'), findsOneWidget);
      reads.fail(1, const TaggedIntentionsUnavailableFailure());
      await tester.pumpAndSettle();
      expect(
        find.text('Не удалось загрузить следующую порцию намерений.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expect(reads.queries.last.cursor, same(cursor));
      reads.page(2, [_intention(101)]);
      await tester.pumpAndSettle();
      expect(find.text('Намерение 1'), findsOneWidget);
      expect(_row(_intention(101)), findsOneWidget);
      expect(find.text('Все намерения показаны.'), findsOneWidget);
      expect(find.text('Показать ещё намерения'), findsNothing);
    },
  );

  for (final locale in ['ru', 'en']) {
    for (final (failure, russianMessage, englishMessage) in [
      (
        const TaggedIntentionsUnavailableFailure(),
        'Не удалось загрузить намерения с тегом. Повторите попытку.',
        'Could not load tagged intentions. Try again.',
      ),
      (
        const TaggedIntentionsCorruptionFailure(),
        'Сохранённые данные помеченных намерений повреждены и не могут быть показаны.',
        'Stored tagged intention data is damaged and cannot be shown.',
      ),
      (
        const TaggedIntentionsUnexpectedFailure(),
        'Не удалось загрузить намерения с тегом из-за непредвиденной ошибки.',
        'Could not load tagged intentions because of an unexpected error.',
      ),
      (
        const TaggedIntentionsInvalidCursor(),
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
        if (failure is TaggedIntentionsUnavailableFailure) {
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
        const TaggedIntentionsCorruptionFailure(),
        'Сохранённые данные повреждены; следующая порция намерений недоступна.',
        'Stored data is damaged; more intentions cannot be shown.',
        'Не удалось обновить выдачу: сохранённые данные повреждены. Показанные данные могут быть устаревшими.',
        'Could not refresh results: stored data is damaged. The displayed data may be out of date.',
      ),
      (
        const TaggedIntentionsUnexpectedFailure(),
        'Не удалось загрузить следующую порцию намерений из-за непредвиденной ошибки.',
        'Could not load more intentions because of an unexpected error.',
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
                      ? 'Показать ещё намерения'
                      : 'Show more intentions',
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

Finder _row(TaggedIntention item) => find.byKey(ValueKey(item.id));
Finder _scope(TaggedIntentionsScope scope) => find.byKey(ValueKey(scope));

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
  final queries = <TaggedIntentionsQuery>[];
  final pending = <Completer<TaggedIntentionsPageResult>>[];
  final watch = StreamController<TagReadResult>.broadcast(sync: true);

  @override
  Stream<TagReadResult> watchTag(TagId id) => watch.stream;

  @override
  Future<TaggedIntentionsPageResult> getTaggedIntentionsPage(
    TaggedIntentionsQuery query,
  ) {
    queries.add(query);
    final result = Completer<TaggedIntentionsPageResult>();
    pending.add(result);
    return result.future;
  }

  void page(
    int index,
    List<TaggedIntention> items, {
    TaggedIntentionsCursor? cursor,
    Tag? tag,
    int revision = 1,
  }) {
    final query = queries[index];
    pending[index].complete(
      TaggedIntentionsPageSuccess(
        TaggedIntentionsPage(
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

  void fail(int index, TaggedIntentionsReadFailure failure) =>
      pending[index].complete(TaggedIntentionsPageError(failure));

  void dispose() => unawaited(watch.close());
}

final class _Cursor implements TaggedIntentionsCursor {}

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
