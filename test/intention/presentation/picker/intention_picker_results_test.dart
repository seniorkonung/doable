import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_results.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';
import '../../../support/tag_positions.dart';

const _emptyScopeRu = 'Доступных активных действий нет.';

final _list = find.byKey(
  const PageStorageKey<String>('daily-choice-action-list'),
);

void main() {
  group('состояния без строк', () {
    testWidgets('загрузка первой порции и пауза ввода показаны загрузкой', (
      tester,
    ) async {
      final h = await _open(tester);
      expect(_loading('Загружаем действия…'), findsOneWidget);

      h.repository.complete(0, _firstPage(_actions(3)));
      await _settle(tester);
      h.notifier.changeTitleFilter('бег');
      await _settle(tester);

      expect(_loading('Загружаем действия…'), findsOneWidget);
      expect(find.byType(CatalogHeader), findsNothing);
    });

    testWidgets('устранимый отказ первой порции повторяет её чтение', (
      tester,
    ) async {
      final h = await _open(tester);

      h.repository.complete(
        0,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(tester);
      expect(
        find.text('Не удалось загрузить действия. Повторите попытку.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Повторить'));
      await _settle(tester);

      expect(h.repository.queries, hasLength(2));
      expect(_loading('Загружаем действия…'), findsOneWidget);
    });

    testWidgets('повреждение первой порции показано отказом без повтора', (
      tester,
    ) async {
      final h = await _open(tester);

      h.repository.complete(
        0,
        const ResultFailure(IntentionCorruptionFailure()),
      );
      await _settle(tester);

      expect(
        find.text(
          'Сохранённые данные действий повреждены и не могут быть показаны.',
        ),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsNothing);
    });

    testWidgets('недопустимый фильтр названия не показывает ни состояния, '
        'ни заголовка выдачи', (tester) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(3)));
      await _settle(tester);

      h.notifier.changeTitleFilter('\uD800');
      await tester.pump(const Duration(milliseconds: 300));
      await _settle(tester);

      expect(h.notifier.selection.filterValidationFailure, isNotNull);
      expect(_listState, findsNothing);
      expect(find.byType(CatalogHeader), findsNothing);
    });

    testWidgets('поиск исходного намерения называет выдачу «Намерения»', (
      tester,
    ) async {
      final h = await _open(
        tester,
        purpose: SelectDailyChoiceSource(session: IntentionSearchSession()),
      );

      h.repository.complete(0, _firstPage(const []));
      await _settle(tester);

      expect(_header('Намерения', 0), findsOneWidget);
    });
  });

  group('загруженная выдача', () {
    testWidgets('заголовок показывает точное количество совпадений, '
        'а не число загруженных строк', (tester) async {
      final h = await _open(tester, pageSize: 3);

      h.repository.complete(0, _firstPage(_actions(3), totalCount: 13));
      await _settle(tester);

      expect(_header('Действия', 13), findsOneWidget);
      expect(_list, findsOneWidget);
      expect(
        find.byKey(
          ValueKey(
            'daily-choice-action-${_actions(3).first.id.toCanonicalString()}',
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('построенные строки подгружают порции, а кольцо подгрузки '
        'стоит в конце, только пока есть следующая порция', (tester) async {
      final h = await _open(tester, pageSize: 2);
      final all = _actions(5);

      h.repository.complete(0, _firstPage(all.sublist(0, 2), totalCount: 5));
      await _settle(tester);
      expect(_more, findsOneWidget);
      await _waitForQueries(tester, h, 2);
      h.repository.complete(1, _continuationPage(all.sublist(2, 4)));
      await _settle(tester);
      expect(_more, findsOneWidget);
      await _waitForQueries(tester, h, 3);
      h.repository.complete(
        2,
        _continuationPage(all.sublist(4), hasMore: false),
      );
      await _settle(tester);

      for (final summary in all) {
        expect(find.text(summary.title), findsOneWidget);
      }
      expect(_more, findsNothing);
      expect(h.repository.queries, hasLength(3));
    });

    testWidgets('кольцо подгрузки не строится, пока конец выдачи далеко '
        'от экрана', (tester) async {
      final h = await _open(tester, pageSize: 30);
      h.repository.complete(0, _firstPage(_actions(30), totalCount: 60));
      await _settle(tester);

      // Иначе анимация кольца вне экрана требовала бы кадров непрерывно.
      expect(_more, findsNothing);
      await tester.pumpAndSettle();
      h.position.jumpTo(h.position.maxScrollExtent);
      await _settle(tester);
      expect(_more, findsOneWidget);
    });

    testWidgets('устранимый отказ продолжения стоит в конце списка и '
        'повторяет подгрузку', (tester) async {
      final h = await _open(tester, pageSize: 2);
      final all = _actions(3);
      h.repository.complete(0, _firstPage(all.sublist(0, 2), totalCount: 3));
      await _settle(tester);
      await _waitForQueries(tester, h, 2);

      h.repository.complete(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await _settle(tester);
      expect(
        find.text('Не удалось загрузить следующие намерения.'),
        findsOneWidget,
      );
      expect(_more, findsNothing);
      await tester.tap(find.text('Повторить'));
      await _settle(tester);
      h.repository.complete(
        2,
        _continuationPage(all.sublist(2), hasMore: false),
      );
      await _settle(tester);

      expect(find.text(all.last.title), findsOneWidget);
      expect(
        find.text('Не удалось загрузить следующие намерения.'),
        findsNothing,
      );
    });

    testWidgets('выдача нового запроса открывается с начала списка', (
      tester,
    ) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      h.position.jumpTo(600);
      await _settle(tester);

      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await _waitForQueries(tester, h, 2);
      h.repository.complete(1, _firstPage(_actions(30)));
      await _settle(tester);

      expect(h.position.pixels, 0);
      expect(_header('Действия', 30), findsOneWidget);
    });
  });

  group('выбор и стрелка', () {
    testWidgets('выбор передаёт сводку строки с ревизией выдачи, из которой '
        'строка построена, а стрелка — идентификатор', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _open(tester);
      final renamed = Tag(
        id: _sport.id,
        name: TagName.fromInput('Бег'),
        color: _sport.color,
        position: _sport.position,
      );
      final summary = testSummary(
        index: 1,
        title: 'Бегать по утрам',
        readiness: IntentionReadiness.ready,
        tags: [_sport],
      );
      h.repository.complete(0, _firstPage([summary]));
      await _settle(tester);

      await acceptTagCommand(
        h.container,
        h.repository,
        UpdateTag(tagId: _sport.id, name: renamed.name, color: renamed.color),
        tagRenameSuccess(
          before: _sport,
          after: renamed,
          revision: const TestCatalogRevision(2),
        ),
      ).future;
      await _settle(tester);
      await tester.tap(find.text('Бегать по утрам'));
      await tester.tap(find.bySemanticsLabel(RegExp('Открыть страницу')));

      final pick = h.picks.single;
      expect(pick.value.id, summary.id);
      expect(pick.value.tags.single.name.value, 'Бег');
      expect(
        pick.revision.compareTo(const TestCatalogRevision(2)),
        GraphRevisionOrder.same,
      );
      expect(h.openedDetails, [summary.id]);
      semantics.dispose();
    });
  });
}

final _sport = Tag(
  id: switch (TagId.decode('00000000-0000-4000-8000-000000000001')) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Некорректный идентификатор тега в тесте.',
    ),
  },
  name: TagName.fromInput('Спорт'),
  color: null,
  position: tagPositionAt(1),
);

/// Кольцо подгрузки: видимого текста у него нет, только доступное название.
final _more = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics &&
      widget.properties.label == 'Загружаем ещё действия',
);

/// Виды состояния списка — закрытые наследники [ListState].
final _listState = find.byWidgetPredicate((widget) => widget is ListState);

Finder _loading(String text) =>
    find.descendant(of: _listState, matching: find.text(text));

Finder _header(String title, int count) => find.byWidgetPredicate(
  (widget) =>
      widget is CatalogHeader && widget.title == title && widget.count == count,
);

/// Готовые к действию сводки в порядке выдачи: от новых к старым.
List<IntentionSummary> _actions(int count) => [
  for (var index = count; index >= 1; index--)
    testSummary(
      index: index,
      title: 'Действие $index',
      readiness: IntentionReadiness.ready,
    ),
];

Result<IntentionCatalogPage> _firstPage(
  List<IntentionSummary> items, {
  int? totalCount,
}) {
  final total = totalCount ?? items.length;
  return ResultSuccess(
    IntentionCatalogFirstPage(
      items: items,
      totalCount: total,
      nextCursor: total > items.length ? const TestCatalogCursor() : null,
      revision: const TestCatalogRevision(1),
    ),
  );
}

Result<IntentionCatalogPage> _continuationPage(
  List<IntentionSummary> items, {
  bool hasMore = true,
}) => ResultSuccess(
  IntentionCatalogContinuationPage(
    items: items,
    nextCursor: hasMore ? const TestCatalogCursor() : null,
    revision: const TestCatalogRevision(1),
  ),
);

final class _Harness {
  _Harness(this._tester, this.container, this.repository, this.purpose);

  final WidgetTester _tester;
  final ProviderContainer container;
  final ControlledCatalogRepository repository;
  final IntentionPickerPurpose purpose;
  final picks = <GraphSnapshot<IntentionSummary>>[];
  final openedDetails = <IntentionId>[];

  IntentionCatalogViewModel get notifier =>
      container.read(intentionCatalogViewModelProvider(purpose).notifier);

  ScrollPosition get position => _tester
      .state<ScrollableState>(
        find.descendant(of: _list, matching: find.byType(Scrollable)),
      )
      .position;
}

Future<_Harness> _open(
  WidgetTester tester, {
  IntentionPickerPurpose? purpose,
  int pageSize = 100,
}) async {
  final repository = ControlledCatalogRepository();
  // Подгрузка начинается, когда построена последняя загруженная строка.
  final container = reconciliationCatalogContainer(
    repository,
    pageSize: pageSize,
    prefetchRemaining: 0,
  );
  addTearDown(container.dispose);
  final h = _Harness(
    tester,
    container,
    repository,
    purpose ?? SelectDailyChoiceAction(session: IntentionSearchSession()),
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: doableTheme(Brightness.light),
        locale: const Locale('ru'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: IntentionPickerResults(
            purpose: h.purpose,
            emptyScopeMessage: _emptyScopeRu,
            onResetFilters: () {},
            onPick: h.picks.add,
            onOpenDetails: h.openedDetails.add,
          ),
        ),
      ),
    ),
  );
  return h;
}

/// Ждёт чтения порции, которое модель начинает после кадра.
Future<void> _waitForQueries(WidgetTester tester, _Harness h, int count) async {
  for (var attempt = 0; h.repository.queries.length < count; attempt++) {
    if (attempt == 100) {
      fail('Не дождались $count запросов каталога.');
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
}

/// Завершённое чтение публикует состояние в микрозадаче, перестроение
/// приходит следующим кадром, а подгрузка запрашивается после кадра строки.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}
