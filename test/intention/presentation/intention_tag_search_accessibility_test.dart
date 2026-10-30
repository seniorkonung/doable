import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/design_system/components/catalog_row.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/search_field.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import '../../support/intention_catalog_controls.dart';
import 'catalog/catalog_reconciliation_test_support.dart';
import 'catalog/catalog_test_support.dart';
import '../../support/tag_condition_cycles.dart';
import '../../support/tag_positions.dart';

/// Нижняя граница области над открытой клавиатурой: окно 900, inset 300.
const _keyboardTop = 600.0;

/// Теги каталога тегов с длинными названиями в порядке создания.
final _tags = [
  for (var index = 1; index <= 9; index++)
    _tag(index, 'Здоровье и долгие прогулки на свежем воздухе $index'),
];

/// Число условий, выбранных до открытия панели фильтра.
const _initialConditions = 6;

void main() {
  testWidgets('каталог намерений и панель фильтра по тегам доступны при '
      'открытой клавиатуре и многих условиях', (tester) async {
    const locale = Locale('ru');
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    final l10n = await AppLocalizations.delegate.load(locale);
    final repository = ControlledCatalogRepository()..tagCatalogItems = _tags;
    final container = reconciliationCatalogContainer(repository);
    final router = AppRouter();
    addTearDown(container.dispose);
    addTearDown(router.dispose);
    final list = find.byKey(
      const PageStorageKey<String>('intention-catalog-list'),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: doableTheme(Brightness.light),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router.config(),
        ),
      ),
    );
    await tester.pump();
    await openIntentionGraph(tester);
    repository.complete(0, _firstPage(const []));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    final conditionsProvider = intentionTagConditionsViewModelProvider(
      const BrowseIntentionCatalog(),
    );

    // Поле названия принимает ввод при открытой клавиатуре.
    final field = intentionCatalogTitleField;
    _expectTappable(tester, field);
    expect(
      find.bySemanticsLabel(
        RegExp(RegExp.escape(intentionCatalogTitleFieldLabel(tester))),
      ),
      findsWidgets,
    );
    await tester.tap(field);
    await tester.enterText(field, 'ход');
    await _pumpUntilQueries(tester, repository, repository.queries.length + 1);
    expect(repository.queries.last.titleFilter?.map((value) => value), 'ход');

    // Много условий с длинными названиями.
    final model = container.read(conditionsProvider.notifier);
    for (var index = 0; index < _initialConditions; index++) {
      final requirement = index.isEven
          ? IntentionTagRequirement.mustBePresent
          : IntentionTagRequirement.mustBeAbsent;
      for (var i = 0; i < tagConditionCycles(requirement); i++) {
        model.cycle(_tags[index].id);
        await tester.pump();
      }
    }
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    // Кнопка фильтра называет число условий и открывает панель тегов в
    // режиме фильтра.
    final filter = intentionCatalogTagFilterControl;
    _expectTappable(tester, filter);
    _expectFilterAnnounced(tester, l10n, _initialConditions);
    await tester.tap(filter);
    await _pumpFrames(tester);
    await _expectTagsPanelAccessible(tester, l10n);

    // Два нажатия на последний тег добавляют условие «должен
    // отсутствовать», а закрытие панели возвращает страницу поиска.
    final lastTagRow = _panelRow(_tags.last);
    await _reach(tester, lastTagRow, _panelList);
    _expectTappable(tester, lastTagRow);
    await tester.tap(lastTagRow);
    await tester.pump();
    await tester.tap(lastTagRow);
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.tagsPanelDone));
    await _pumpFrames(tester);
    expect(find.text(l10n.tagsPanelFilterTitle), findsNothing);
    expect(tester.takeException(), isNull);
    expectIntentionGraphRootPage(router);
    expect(container.read(conditionsProvider).conditions, [
      for (var index = 0; index < _initialConditions; index++)
        _condition(
          _tags[index],
          index.isEven
              ? IntentionTagRequirement.mustBePresent
              : IntentionTagRequirement.mustBeAbsent,
        ),
      _condition(_tags.last, IntentionTagRequirement.mustBeAbsent),
    ]);

    // Условия видны только по кнопке фильтра, а не под полем названия.
    expect(find.textContaining(_tags.first.name.value), findsNothing);
    _expectFilterAnnounced(tester, l10n, _initialConditions + 1);
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Надобность меняется и условие снимается нажатиями в панели.
    await tester.tap(filter);
    await _pumpFrames(tester);
    final firstTagRow = _panelRow(_tags.first);
    _expectTappable(tester, firstTagRow);
    await tester.tap(firstTagRow);
    await tester.pump();
    expect(
      container.read(conditionsProvider).conditions.first.requirement,
      IntentionTagRequirement.mustBeAbsent,
    );
    await _reach(tester, lastTagRow, _panelList);
    await tester.tap(lastTagRow);
    await _pumpFrames(tester);
    await tester.tap(find.text(l10n.tagsPanelDone));
    await _pumpFrames(tester);
    _expectFilterAnnounced(tester, l10n, _initialConditions);
    expect(tester.takeException(), isNull);

    // Выдача со строкой тегов у каждого результата и отказом продолжения.
    final rowTags = [_tags[0], _tags[2]];
    final items = [
      for (var index = 4; index >= 2; index--)
        testSummary(
          index: index,
          title: 'Долгая прогулка до дальнего парка $index',
          readiness: IntentionReadiness.ready,
          description: 'Описание',
          tags: index == 2 ? const [] : rowTags,
        ),
    ];
    await _pumpFrames(tester);
    final firstPageQuery = repository.queries.length - 1;
    expect(
      repository.queryAt(firstPageQuery).tagFilter,
      container.read(conditionsProvider).tagFilter,
    );
    repository.complete(
      firstPageQuery,
      ResultSuccess(
        IntentionCatalogFirstPage(
          items: items,
          totalCount: 4,
          nextCursor: const TestCatalogCursor(),
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await _pumpUntilQueries(tester, repository, firstPageQuery + 2);
    repository.complete(
      firstPageQuery + 1,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);

    // Первый тег в панели стал исключённым, и обязательным остался второй из
    // тегов строки: он называется впереди.
    final tagsLine = l10n.intentionSummaryTags(
      rowTags.reversed.map((tag) => tag.name.value).join(', '),
    );
    for (final summary in items) {
      final row = find.ancestor(
        of: find.text(summary.title),
        matching: find.byType(CatalogRow),
      );
      await _reach(tester, row, list);
      _expectTappable(tester, row);
      final line = summary.tags.isEmpty
          ? l10n.intentionSummaryNoTags
          : tagsLine;
      _expectNotTruncated(tester, find.text(summary.title));
      final rowNode = tester.getSemantics(find.text(summary.title));
      expect(rowNode.label, allOf(contains(summary.title), contains(line)));
      expect(rowNode, isSemantics(isButton: true, hasTapAction: true));
    }

    // Виды состояния списка — закрытые наследники ListState.
    final continuation = find.byWidgetPredicate(
      (widget) => widget is ListState,
    );
    final continuationRetry = find.descendant(
      of: continuation,
      matching: find.widgetWithText(InkWell, l10n.commonRetry),
    );
    await _reach(tester, continuationRetry, list);
    _expectTappable(tester, continuationRetry);
    expect(
      find.descendant(
        of: continuation,
        matching: find.text(l10n.catalogLoadMoreUnavailable),
      ),
      findsOneWidget,
    );
    // Поле поиска закреплено на экране, а область его крестика — 32 по
    // оформлению, поэтому размер цели проверяется у самого повтора.
    expect(
      tester.getSize(continuationRetry).height,
      greaterThanOrEqualTo(DoableMetrics.tapMin),
    );
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await tester.tap(continuationRetry);
    await _pumpUntilQueries(tester, repository, firstPageQuery + 3);
    final lastSummary = testSummary(
      index: 1,
      title: 'Долгая прогулка до дальнего парка 1',
      readiness: IntentionReadiness.ready,
      tags: rowTags,
    );
    repository.complete(
      firstPageQuery + 2,
      ResultSuccess(
        IntentionCatalogContinuationPage(
          items: [lastSummary],
          nextCursor: null,
          revision: const TestCatalogRevision(1),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    final lastRow = find.ancestor(
      of: find.text(lastSummary.title),
      matching: find.byType(CatalogRow),
    );
    await _reach(tester, lastRow, list);
    _expectTappable(tester, lastRow);

    // Поле названия закреплено и доступно и от конца выдачи.
    _expectTappable(tester, field);
    expect(tester.widget<TextField>(field).controller!.text, 'ход');

    // Удаление исключённого тега снимает его условие без сбоя раскладки.
    final deleted = _tags[1];
    final accepted = acceptTagCommand(
      container,
      repository,
      DeleteTag(deleted.id),
      tagDeletionSuccess(
        tagId: deleted.id,
        revision: const TestCatalogRevision(2),
      ),
    );
    await accepted.future;
    await _pumpFrames(tester);
    expect(
      shownIntentionCatalogParameters(tester).tagConditions,
      _initialConditions - 1,
    );

    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

/// Экранный диктор называет кнопку фильтра с числом условий [count], а
/// сама кнопка показывает это число.
void _expectFilterAnnounced(
  WidgetTester tester,
  AppLocalizations l10n,
  int count,
) {
  final filter = intentionCatalogTagFilterControl;
  expect(
    find.descendant(of: filter, matching: find.text('$count')),
    findsOneWidget,
  );
  expect(
    tester.getSemantics(filter),
    isSemantics(
      label: l10n.intentionPickerFilterLabel(count),
      isButton: true,
      hasTapAction: true,
    ),
  );
}

/// Проверяет открытую панель тегов в режиме фильтра: поле поиска и строки
/// тегов достижимы над клавиатурой, а строки объявляют надобность текущих
/// условий.
Future<void> _expectTagsPanelAccessible(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  expect(tester.takeException(), isNull);
  expect(find.text(l10n.tagsPanelFilterTitle), findsOneWidget);
  final search = find.descendant(
    of: find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(SearchField),
    ),
    matching: find.byType(TextField),
  );
  _expectTappable(tester, search);
  expect(
    find.bySemanticsLabel(RegExp(RegExp.escape(l10n.tagsPanelSearchLabel))),
    findsWidgets,
  );

  for (final (index, tag) in _tags.indexed) {
    final name = tag.name.value;
    final row = _panelRow(tag);
    await _reach(tester, row, _panelList);
    _expectTappable(tester, row);
    // Тег, уже входящий в условия, объявлен с текущей надобностью.
    expect(tester.getSemantics(row).label, switch (index) {
      >= _initialConditions => name,
      _ when index.isEven => l10n.tagsPanelFilterPresentLabel(name),
      _ => l10n.tagsPanelFilterAbsentLabel(name),
    });
  }
  // Цели касания панели из модуля основ не меньше 44 точек.
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

/// Список строк открытой панели тегов.
final _panelList = find.descendant(
  of: find.byType(BottomSheet),
  matching: find.byType(CustomScrollView),
);

/// Доводит лениво создаваемый элемент до видимой области списка [list]:
/// сначала находит его жестами на [delta], затем показывает.
Future<void> _reach(
  WidgetTester tester,
  Finder finder,
  Finder list, {
  double delta = 150,
}) async {
  final scrollable = find
      .descendant(of: list, matching: find.byType(Scrollable))
      .first;
  for (var attempt = 0; attempt < 200 && finder.evaluate().isEmpty; attempt++) {
    await tester.dragFrom(_visiblePoint(tester, scrollable), Offset(0, -delta));
    await tester.pump();
  }
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
  await tester.pump();
}

/// Точка списка над клавиатурой, не закрытая отказом обновления и кнопкой
/// создания: с неё пользователь прокручивает список жестом.
Offset _visiblePoint(WidgetTester tester, Finder scrollable) {
  final box = tester.renderObject<RenderBox>(scrollable);
  final rect = box.localToGlobal(Offset.zero) & box.size;
  final bottom = rect.bottom < _keyboardTop ? rect.bottom : _keyboardTop;
  for (var dy = bottom - 4; dy > rect.top && dy > 0; dy -= 8) {
    final point = Offset(rect.center.dx, dy);
    if (tester
        .hitTestOnBinding(point)
        .path
        .any((entry) => identical(entry.target, box))) {
      return point;
    }
  }
  fail('Список закрыт целиком: $scrollable');
}

/// Касание по видимой части элемента над клавиатурой приходится на него.
void _expectTappable(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  expect(
    _isTappable(tester, finder),
    isTrue,
    reason: 'Касание не достигает элемента над клавиатурой: $finder',
  );
}

/// Ищет точку касания на вертикальной оси элемента, начиная с его центра:
/// строка выше области просмотра видна и доступна только частью.
bool _isTappable(WidgetTester tester, Finder finder) {
  if (finder.evaluate().isEmpty) {
    return false;
  }
  final box = tester.renderObject<RenderBox>(finder);
  final rect = box.localToGlobal(Offset.zero) & box.size;
  bool hits(double dy) =>
      dy >= 0 &&
      dy < _keyboardTop &&
      tester
          .hitTestOnBinding(Offset(rect.center.dx, dy))
          .path
          .any((entry) => identical(entry.target, box));
  if (hits(rect.center.dy)) {
    return true;
  }
  for (var dy = rect.top + 4; dy < rect.bottom; dy += 8) {
    if (hits(dy)) {
      return true;
    }
  }
  return false;
}

/// Текст показан целиком: переносится, а не обрезается.
void _expectNotTruncated(WidgetTester tester, Finder finder) {
  expect(finder, findsOneWidget);
  final text = tester.widget<Text>(finder);
  expect(text.maxLines, isNull);
  expect(text.overflow, isNull);
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(of: finder, matching: find.byType(RichText)),
  );
  expect(paragraph.didExceedMaxLines, isFalse);
}

IntentionTagCondition _condition(
  Tag tag,
  IntentionTagRequirement requirement,
) => IntentionTagCondition(tagId: tag.id, requirement: requirement);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

Result<IntentionCatalogFirstPage> _firstPage(List<IntentionSummary> items) =>
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
        revision: const TestCatalogRevision(0),
      ),
    );

Tag _tag(int index, String name) => Tag(
  id: switch (TagId.decode(
    '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}',
  )) {
    TagIdDecodingSuccess(:final id) => id,
    InvalidTagIdDecoding() => throw StateError(
      'Некорректный идентификатор тега в тесте.',
    ),
  },
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(index),
);

/// Прокачивает кадры и переходы маршрутов без ожидания бесконечных
/// индикаторов загрузки.
Future<void> _pumpFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

Future<void> _pumpUntilQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.queries.length >= count) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count запросов каталога.');
}
