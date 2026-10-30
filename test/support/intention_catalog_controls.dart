/// Общие шаги управления каталогом намерений в сценариях приложения.
///
/// Сценарий называет только намерение человека — «выбрать охват», «ввести
/// название», «добавить условие по тегу», «какие параметры показывает каталог»
/// — и не знает, какими элементами страница это позволяет. Шаги действуют и
/// наблюдают через интерфейс каталога и не обращаются к его модели.
///
/// Действие не ждёт выдачи: её дожидается сам сценарий. Смена способа
/// управления каталогом меняет только этот файл, а не сценарии.
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';
import 'tag_condition_cycles.dart';

/// Параметры поиска, которые показывает каталог намерений.
typedef ShownIntentionCatalogParameters = ({
  IntentionScope scope,
  IntentionCatalogOrder order,
  String titleFilter,
  int tagConditions,
});

final _page = find.byType(IntentionCatalogPage);
final _scopeControl = find.byKey(const ValueKey('catalog-scope-control'));
final _orderControl = find.byKey(const ValueKey('catalog-order-control'));
final _titleField = find.byKey(const ValueKey('catalog-filter-field'));
final _tagConditionsAdd = find.byKey(
  const ValueKey('intention-tag-conditions-add'),
);

/// Строки выдачи открытого каталога намерений.
final intentionCatalogRows = find.descendant(
  of: _page,
  matching: find.byType(IntentionSummaryView),
);

/// Строка выдачи открытого каталога намерений с названием [title].
Finder intentionCatalogRow(String title) => find.descendant(
  of: _page,
  matching: find.widgetWithText(IntentionSummaryView, title),
);

/// Точное количество [count] совпадений подтверждённой выдачи.
Finder intentionCatalogTotal(int count) => find.descendant(
  of: _page,
  matching: find.byElementPredicate((element) {
    final widget = element.widget;
    return widget is Text &&
        widget.data == AppLocalizations.of(element).catalogTotalCount(count);
  }, description: 'количество совпадений каталога $count'),
);

/// Выбирает охват [scope]. [tap] — нажатие сценария; по умолчанию
/// [tapWhenFound].
Future<void> selectIntentionCatalogScope(
  WidgetTester tester,
  IntentionScope scope, {
  RootPageTap tap = tapWhenFound,
}) => _choose(
  tester,
  _scopeControl,
  _scopeLabels(AppLocalizations.of(tester.element(_page)))[scope]!,
  tap,
);

/// Выбирает порядок [order]. [tap] — нажатие сценария; по умолчанию
/// [tapWhenFound].
Future<void> selectIntentionCatalogOrder(
  WidgetTester tester,
  IntentionCatalogOrder order, {
  RootPageTap tap = tapWhenFound,
}) => _choose(
  tester,
  _orderControl,
  _orderLabels(AppLocalizations.of(tester.element(_page)))[order]!,
  tap,
);

/// Вводит [title] фильтром названия.
Future<void> enterIntentionCatalogTitle(WidgetTester tester, String title) =>
    tester.enterText(_titleField, title);

/// Добавляет условие [requirement] по тегу [tag] из панели фильтра и закрывает
/// её, не дожидаясь выдачи с этим условием.
///
/// [tap] и [waitFor] — нажатие и ожидание сценария; по умолчанию
/// [tapWhenFound] и [pumpUntilFound].
Future<void> addIntentionCatalogTagCondition(
  WidgetTester tester,
  TagId tag,
  IntentionTagRequirement requirement, {
  RootPageTap tap = tapWhenFound,
  RootPageWait waitFor = pumpUntilFound,
}) async {
  await tap(tester, _tagConditionsAdd);
  await tester.pump(_transition);
  final row = find.byKey(ValueKey('tags-panel-row-${tag.toCanonicalString()}'));
  for (var cycle = 0; cycle < tagConditionCycles(requirement); cycle++) {
    await tap(tester, row);
  }
  // Панель фильтра применяет условие сразу, а «назад» только закрывает её.
  await tester.binding.handlePopRoute();
  await waitFor(tester, _tagConditionsAdd.hitTestable());
}

/// Параметры поиска открытого каталога. Каталог, который показывает другие
/// значения, проваливает проверку.
ShownIntentionCatalogParameters shownIntentionCatalogParameters(
  WidgetTester tester,
) {
  final texts = AppLocalizations.of(tester.element(_page));
  return (
    scope: _shownChoice(_scopeControl, _scopeLabels(texts)),
    order: _shownChoice(_orderControl, _orderLabels(texts)),
    titleFilter: tester.widget<TextField>(_titleField).controller!.text,
    tagConditions: find
        .descendant(
          of: _page,
          matching: find.byKey(const ValueKey('intention-tag-condition-label')),
        )
        .evaluate()
        .length,
  );
}

/// Прокрутка списка выдачи открытого каталога.
ScrollPosition intentionCatalogListPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(
              const PageStorageKey<String>('intention-catalog-list'),
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// Ставит все прокрутки страницы каталога на долю [fraction] их длины.
void jumpIntentionCatalog(WidgetTester tester, double fraction) {
  for (final position in _pagePositions(tester)) {
    position.jumpTo(position.maxScrollExtent * fraction);
  }
}

/// Смещения всех прокруток страницы каталога в порядке дерева.
List<double> shownIntentionCatalogOffsets(WidgetTester tester) => [
  for (final position in _pagePositions(tester)) position.pixels,
];

/// Открытие и закрытие меню и панели короче этого времени.
///
/// Индикатор загрузки выдачи может не дать дождаться покоя всех анимаций,
/// поэтому шаг продвигает время сам.
const _transition = Duration(seconds: 1);

/// Вертикальные прокрутки страницы каталога: своя прокрутка есть и у поля.
List<ScrollPosition> _pagePositions(WidgetTester tester) {
  final scrollables = find.descendant(
    of: _page,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    ),
  );
  expect(scrollables, findsAtLeast(1));
  return [
    for (final state in tester.stateList<ScrollableState>(scrollables))
      state.position,
  ];
}

/// Выбирает вариант [label] в выпадающем списке [control].
Future<void> _choose(
  WidgetTester tester,
  Finder control,
  String label,
  RootPageTap tap,
) async {
  await tap(tester, control);
  await tester.pump(_transition);
  await tester.tap(find.text(label).last);
  await tester.pump();
  await tester.pump(_transition);
}

/// Вариант [labels], который показывает выпадающий список [control].
T _shownChoice<T>(Finder control, Map<T, String> labels) {
  final shown = [
    for (final element
        in find.descendant(of: control, matching: find.byType(Text)).evaluate())
      (element.widget as Text).data,
  ];
  return labels.keys.singleWhere((choice) => shown.contains(labels[choice]));
}

Map<IntentionScope, String> _scopeLabels(AppLocalizations texts) => {
  IntentionScope.active: texts.catalogScopeActive,
  IntentionScope.archived: texts.catalogScopeArchived,
  IntentionScope.all: texts.catalogScopeAll,
};

Map<IntentionCatalogOrder, String> _orderLabels(AppLocalizations texts) => {
  IntentionCatalogOrder.createdAtDescending: texts.catalogOrderCreatedNewest,
  IntentionCatalogOrder.createdAtAscending: texts.catalogOrderCreatedOldest,
  IntentionCatalogOrder.updatedAtDescending: texts.catalogOrderUpdatedNewest,
  IntentionCatalogOrder.updatedAtAscending: texts.catalogOrderUpdatedOldest,
};
