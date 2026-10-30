import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/search/intention_search_list.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';
import '../../../support/tag_positions.dart';

/// Высота строки-образца выдачи.
const _rowExtent = 48.0;

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

    testWidgets('пауза ввода во время прокрутки выдачи сразу стоит сверху', (
      tester,
    ) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      await _flingDown(tester, h);

      h.notifier.changeTitleFilter('бег');
      await tester.pump();

      expect(_loading('Загружаем действия…'), findsOneWidget);
      expect(h.position.pixels, 0);
      expect(tester.getTopLeft(_listState).dy, tester.getTopLeft(_list).dy);
    });

    testWidgets('загрузка и отказ первой порции во время прокрутки выдачи '
        'сразу стоят сверху', (tester) async {
      final h = await _open(tester);
      h.repository.complete(0, _firstPage(_actions(30)));
      await _settle(tester);
      await _flingDown(tester, h);

      h.notifier.changeTagFilter(
        IntentionTagFilter(excludedTagIds: [_sport.id]),
      );
      await tester.pump();

      expect(_loading('Загружаем действия…'), findsOneWidget);
      expect(h.position.pixels, 0);
      expect(tester.getTopLeft(_listState).dy, tester.getTopLeft(_list).dy);

      await _waitForQueries(tester, h, 2);
      h.repository.complete(
        1,
        const ResultFailure(IntentionUnavailableFailure()),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Не удалось загрузить действия. Повторите попытку.'),
        findsOneWidget,
      );
      expect(h.position.pixels, 0);
      expect(tester.getTopLeft(_listState).dy, tester.getTopLeft(_list).dy);
    });
  });

  group('загруженная выдача', () {
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
    });
  });

  group('согласование выдачи без смены параметров', () {
    testWidgets('строка, добавленная перед видимой, оставляет видимую строку '
        'на месте', (tester) async {
      final h = await _openSportActions(tester);
      h.position.jumpTo(300);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 46');

      await _assignSportToAction59(tester, h);

      final confirmed = h.container
          .read(intentionCatalogViewModelProvider(h.purpose))
          .requireValue;
      expect((confirmed as IntentionCatalogLoaded).items, hasLength(31));
      expect(h.position.pixels, 300 + _rowExtent + DoableMetrics.space2);
      expect(_rowTop(tester, 'Действие 46'), visibleTop);
    });

    testWidgets('верх списка в промежутке между строками: первая видимая '
        'строка остаётся на месте', (tester) async {
      final h = await _openSportActions(tester);
      // Строка 5 занимает 280–328, строка 6 начинается с 336.
      h.position.jumpTo(332);
      await _settle(tester);
      final visibleTop = _rowTop(tester, 'Действие 48');

      await _assignSportToAction59(tester, h);

      expect(_rowTop(tester, 'Действие 48'), visibleTop);
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

IntentionSummary _action(int index, {List<Tag> tags = const []}) => testSummary(
  index: index,
  title: 'Действие $index',
  readiness: IntentionReadiness.ready,
  tags: tags,
);

/// Готовые к действию сводки в порядке выдачи: от новых к старым.
List<IntentionSummary> _actions(int count) => [
  for (var index = count; index >= 1; index--) _action(index),
];

double _rowTop(WidgetTester tester, String title) =>
    tester.getTopLeft(find.text(title)).dy;

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
          body: IntentionSearchList(
            purpose: h.purpose,
            rowBuilder: (context, results, summary) =>
                SizedBox(height: _rowExtent, child: Text(summary.title)),
            emptyScope: (_) => const EmptyState(
              title: 'Выбрать не из чего',
              text: 'Доступных активных действий нет.',
            ),
            onResetFilters: () {},
            bottomPadding: DoableMetrics.space10,
          ),
        ),
      ),
    ),
  );
  return h;
}

/// Открывает выдачу с обязательным тегом «Спорт»: 30 строк, чётные действия
/// от 60 до 2.
Future<_Harness> _openSportActions(WidgetTester tester) async {
  final h = await _open(tester);
  h.notifier.changeTagFilter(IntentionTagFilter(requiredTagIds: [_sport.id]));
  await _waitForQueries(tester, h, 2);
  h.repository.complete(
    1,
    _firstPage([
      for (var index = 60; index >= 1; index -= 2)
        _action(index, tags: [_sport]),
    ]),
  );
  await _settle(tester);
  return h;
}

/// Назначение обязательного тега добавляет строку перед видимой.
Future<void> _assignSportToAction59(WidgetTester tester, _Harness h) async {
  final (command, result) = intentionTagAssignment(
    state: TagAssignmentState.assigned,
    tagId: _sport.id,
    before: _action(59),
    after: _action(59, tags: [_sport]),
    revision: const TestCatalogRevision(2),
  );
  await acceptTagCommand(h.container, h.repository, command, result).future;
  await _settle(tester);
}

/// Бросает выдачу вниз и оставляет её прокручиваться по инерции: пока
/// прокрутка движется, смещение не прижимается к краю сжавшегося содержимого.
Future<void> _flingDown(WidgetTester tester, _Harness h) async {
  await tester.fling(_list, const Offset(0, -300), 2000);
  await tester.pump(const Duration(milliseconds: 50));
  expect(h.position.pixels, greaterThan(0));
  expect(h.position.activity!.velocity, isNot(0));
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
