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
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/order_button.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/presentation/catalog/intention_catalog_page.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_row.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_root_pages.dart';
import 'tag_condition_cycles.dart';

/// Параметры поиска, которые показывает каталог намерений.
typedef ShownIntentionCatalogParameters = ({
  IntentionScope scope,
  IntentionTypeChoice type,
  IntentionCatalogOrder order,
  String titleFilter,
  int tagConditions,
});

/// Строка, которую показывает выдача каталога намерений: название, подпись
/// тегов в виде `intentionSummaryTags` или `intentionSummaryNoTags` и
/// прямоугольник на экране.
typedef ShownIntentionCatalogRow = ({String title, String tags, Rect rect});

final _page = find.byType(IntentionCatalogPage);
final _header = find.descendant(
  of: _page,
  matching: find.byType(CatalogHeader),
);
final _sheet = find.byType(Sheet);

/// Заголовок страницы каталога намерений.
Finder intentionCatalogHeading(WidgetTester tester) => find.descendant(
  of: _page,
  matching: find.text(
    AppLocalizations.of(tester.element(_page)).appDestinationIntentionGraph,
  ),
);

/// Поле, в которое человек вводит название для поиска в каталоге намерений.
///
/// Для проверок его размещения и доступности: видимости, фокуса и соседства с
/// другими элементами. Вводить название и читать его надо шагами
/// [enterIntentionCatalogTitle] и [shownIntentionCatalogParameters].
final intentionCatalogTitleField = find.descendant(
  of: find.byKey(const ValueKey('intention-catalog-filter')),
  matching: find.byType(TextField),
);

/// Доступная подпись поля названия каталога.
///
/// Берётся из локализации по элементу поля, а не из семантики: под панелью
/// создания поле скрыто от семантики.
String intentionCatalogTitleFieldLabel(WidgetTester tester) =>
    AppLocalizations.of(tester.element(intentionCatalogTitleField))
        .intentionPickerSearchPlaceholder;

/// Кнопка фильтра, которой человек открывает панель условий по тегам каталога
/// намерений.
///
/// Для проверок её размещения и для сценариев, которые открывают панель
/// фильтра сами. Добавлять условие надо шагом
/// [addIntentionCatalogTagCondition].
final intentionCatalogTagFilterControl = find.descendant(
  of: _page,
  matching: find.byType(FilterButton),
);

/// Прокручиваемый список выдачи открытого каталога намерений.
///
/// Для проверок его размещения и жестов по списку. Прокрутку читают шаги
/// [intentionCatalogListPosition] и [shownIntentionCatalogOffsets].
final intentionCatalogList = find.byKey(
  const PageStorageKey<String>('intention-catalog-list'),
);

/// Строки выдачи открытого каталога намерений.
final intentionCatalogRows = find.descendant(
  of: _page,
  matching: find.byType(IntentionCatalogRow),
);

/// Построенные строки выдачи открытого каталога намерений сверху вниз.
///
/// Строки за краем видимой части, которые список уже построил, тоже входят.
List<ShownIntentionCatalogRow> shownIntentionCatalogRows(WidgetTester tester) {
  final texts = AppLocalizations.of(tester.element(_page));
  return [
    for (final row in tester.widgetList<IntentionCatalogRow>(
      intentionCatalogRows,
    ))
      (
        title: row.summary.title,
        tags: _shownTags(row, texts),
        rect: tester.getRect(find.byWidget(row)),
      ),
  ];
}

/// Строка выдачи открытого каталога намерений с названием [title].
Finder intentionCatalogRow(String title) => find.descendant(
  of: _page,
  matching: find.widgetWithText(IntentionCatalogRow, title),
);

/// Точное количество [count] совпадений подтверждённой выдачи.
Finder intentionCatalogTotal(int count) =>
    find.descendant(of: _header, matching: find.text('$count'));

/// Выбирает охват [scope] в листе «Показать и упорядочить» и закрывает лист.
/// [tap] — нажатие сценария; по умолчанию [tapWhenFound].
Future<void> selectIntentionCatalogScope(
  WidgetTester tester,
  IntentionScope scope, {
  RootPageTap tap = tapWhenFound,
}) async {
  final texts = AppLocalizations.of(tester.element(_page));
  await _openShowAndSort(tester, tap);
  await _choose(
    tester,
    texts.intentionPickerScopeCaption,
    _scopeLabels(texts)[scope]!,
  );
  await _closeShowAndSort(tester);
}

/// Выбирает тип [type] в листе «Показать и упорядочить» и закрывает лист.
/// [tap] — нажатие сценария; по умолчанию [tapWhenFound].
Future<void> selectIntentionCatalogType(
  WidgetTester tester,
  IntentionTypeChoice type, {
  RootPageTap tap = tapWhenFound,
}) async {
  final texts = AppLocalizations.of(tester.element(_page));
  await _openShowAndSort(tester, tap);
  await _choose(
    tester,
    texts.intentionPickerTypeCaption,
    _typeLabels(texts)[type]!,
  );
  await _closeShowAndSort(tester);
}

/// Выбирает порядок [order] в листе «Показать и упорядочить» и закрывает лист:
/// поле — в меню сортировки, направление — кнопкой рядом с ним. [tap] —
/// нажатие сценария; по умолчанию [tapWhenFound].
Future<void> selectIntentionCatalogOrder(
  WidgetTester tester,
  IntentionCatalogOrder order, {
  RootPageTap tap = tapWhenFound,
}) async {
  final texts = AppLocalizations.of(tester.element(_page));
  await _openShowAndSort(tester, tap);
  await _choose(
    tester,
    texts.intentionPickerSortCaption,
    _sortFieldLabels(texts)[order.field]!,
  );
  final direction = find.descendant(
    of: _sheet,
    matching: find.byType(OrderButton),
  );
  if (tester.widget<OrderButton>(direction).direction.name !=
      order.direction.name) {
    await tester.tap(direction);
    await tester.pump();
  }
  await _closeShowAndSort(tester);
}

/// Вводит [title] фильтром названия.
Future<void> enterIntentionCatalogTitle(WidgetTester tester, String title) =>
    tester.enterText(intentionCatalogTitleField, title);

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
}) => _cycleTagCondition(
  tester,
  tag,
  tagConditionCycles(requirement),
  tap: tap,
  waitFor: waitFor,
);

/// Снимает условие [requirement] по тегу [tag] в панели фильтра и закрывает
/// её, не дожидаясь выдачи без него.
///
/// [tap] и [waitFor] — нажатие и ожидание сценария; по умолчанию
/// [tapWhenFound] и [pumpUntilFound].
Future<void> removeIntentionCatalogTagCondition(
  WidgetTester tester,
  TagId tag,
  IntentionTagRequirement requirement, {
  RootPageTap tap = tapWhenFound,
  RootPageWait waitFor = pumpUntilFound,
}) => _cycleTagCondition(
  tester,
  tag,
  _tagConditionCircle - tagConditionCycles(requirement),
  tap: tap,
  waitFor: waitFor,
);

/// Параметры поиска открытого каталога. Каталог, который показывает другие
/// значения, проваливает проверку.
ShownIntentionCatalogParameters shownIntentionCatalogParameters(
  WidgetTester tester,
) {
  final texts = AppLocalizations.of(tester.element(_page));
  final header = tester.widget<CatalogHeader>(_header);
  final shown = [
    for (final scope in IntentionScope.values)
      for (final type in IntentionTypeChoice.values)
        if (texts.intentionPickerScopeHeader(scope.name, type.name) ==
            header.title)
          (scope: scope, type: type),
  ].single;
  return (
    scope: shown.scope,
    type: shown.type,
    order: _orderSummaries(texts).entries
        .singleWhere((order) => order.value == header.summary)
        .key,
    titleFilter: tester
        .widget<TextField>(intentionCatalogTitleField)
        .controller!
        .text,
    tagConditions: tester
        .widget<FilterButton>(intentionCatalogTagFilterControl)
        .count,
  );
}

/// Прокрутка списка выдачи открытого каталога.
ScrollPosition intentionCatalogListPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: intentionCatalogList,
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

/// Смещения всех прокруток страницы каталога, включая список выдачи.
List<double> shownIntentionCatalogOffsets(WidgetTester tester) => [
  for (final position in _pagePositions(tester)) position.pixels,
];

/// Открытие и закрытие меню и панели короче этого времени.
///
/// Индикатор загрузки выдачи может не дать дождаться покоя всех анимаций,
/// поэтому шаг продвигает время сам.
const _transition = Duration(seconds: 1);

/// Число нажатий, которыми строка панели фильтра проходит круг надобности и
/// возвращается к тегу без условия.
const _tagConditionCircle = 3;

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

/// Подпись всех тегов строки [row], включая не поместившиеся в линию, в
/// ручном порядке сводки: порядок показа с обязательными тегами впереди
/// закрепляет проверка содержания строки.
String _shownTags(IntentionCatalogRow row, AppLocalizations texts) {
  final tags = row.summary.tags;
  return tags.isEmpty
      ? texts.intentionSummaryNoTags
      : texts.intentionSummaryTags(
          tags.map((tag) => tag.name.value).join(', '),
        );
}

/// Открывает панель фильтра, нажимает строку тега [tag] [cycles] раз и
/// закрывает панель.
Future<void> _cycleTagCondition(
  WidgetTester tester,
  TagId tag,
  int cycles, {
  required RootPageTap tap,
  required RootPageWait waitFor,
}) async {
  await tap(tester, intentionCatalogTagFilterControl);
  await tester.pump(_transition);
  final row = find.byKey(ValueKey('tags-panel-row-${tag.toCanonicalString()}'));
  for (var cycle = 0; cycle < cycles; cycle++) {
    await tap(tester, row);
  }
  // Панель фильтра применяет условие сразу, а «назад» только закрывает её.
  await tester.binding.handlePopRoute();
  await waitFor(tester, intentionCatalogTagFilterControl.hitTestable());
}

/// Открывает заголовком списка лист «Показать и упорядочить».
Future<void> _openShowAndSort(WidgetTester tester, RootPageTap tap) async {
  await tap(tester, _header);
  await tester.pump(_transition);
}

/// Закрывает лист: выбор уже применён, а «назад» только закрывает лист.
Future<void> _closeShowAndSort(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
  await tester.pump(_transition);
}

/// Открывает меню строки листа [row] и выбирает в нём вариант [label].
///
/// Лист уже открыт, а выдача за ним может получаться: нажатия не ждут покоя
/// анимаций.
Future<void> _choose(WidgetTester tester, String row, String label) async {
  await tester.tap(
    find.descendant(of: _sheet, matching: find.widgetWithText(InkWell, row)),
  );
  await tester.pump();
  await tester.pump(_transition);
  await tester.tap(
    find.ancestor(of: find.text(label), matching: find.byType(MenuItemButton)),
  );
  await tester.pump();
  await tester.pump(_transition);
}

Map<IntentionScope, String> _scopeLabels(AppLocalizations texts) => {
  IntentionScope.active: texts.intentionPickerScopeActive,
  IntentionScope.archived: texts.intentionPickerScopeArchived,
  IntentionScope.all: texts.intentionPickerScopeAll,
};

Map<IntentionTypeChoice, String> _typeLabels(AppLocalizations texts) => {
  IntentionTypeChoice.all: texts.intentionPickerTypeAll,
  IntentionTypeChoice.intentions: texts.intentionPickerTypeIntentionsOnly,
  IntentionTypeChoice.actions: texts.intentionPickerTypeActionsOnly,
};

Map<IntentionCatalogSortField, String> _sortFieldLabels(
  AppLocalizations texts,
) => {
  IntentionCatalogSortField.createdAt: texts.intentionPickerSortCreated,
  IntentionCatalogSortField.updatedAt: texts.intentionPickerSortChanged,
  IntentionCatalogSortField.title: texts.intentionPickerSortName,
};

Map<IntentionCatalogOrder, String> _orderSummaries(AppLocalizations texts) => {
  IntentionCatalogOrder.createdAtDescending:
      texts.intentionPickerOrderCreatedNewest,
  IntentionCatalogOrder.createdAtAscending:
      texts.intentionPickerOrderCreatedOldest,
  IntentionCatalogOrder.updatedAtDescending:
      texts.intentionPickerOrderUpdatedNewest,
  IntentionCatalogOrder.updatedAtAscending:
      texts.intentionPickerOrderUpdatedOldest,
  IntentionCatalogOrder.titleAscending:
      texts.intentionPickerOrderTitleAscending,
  IntentionCatalogOrder.titleDescending:
      texts.intentionPickerOrderTitleDescending,
};
