import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../intention/presentation/catalog/catalog_reconciliation_test_support.dart';
import '../../intention/presentation/catalog/catalog_test_support.dart';
import '../../support/app_root_pages.dart';
import '../../intention/presentation/catalog/intention_picker_session_test_support.dart';
import '../../support/tag_positions.dart';
import '../../support/tag_condition_cycles.dart';

/// Страница выбора намерения для дневного выбора и её ограничения поиска.
///
/// Поиск действия и поиск исходного намерения подключают одни и те же общие
/// элементы поиска по тегам; различаются только назначение, допустимая
/// готовность и подписи страницы.
final class DailyChoicePickerTagSearchCase {
  const DailyChoicePickerTagSearchCase({
    required this.route,
    required this.keyPrefix,
    required this.readinessFilter,
    required this.rowReadiness,
    required this.header,
    required this.unavailableMessage,
  });

  final PageRouteInfo route;

  /// Общее начало ключей поля названия, списка и отмены страницы.
  final String keyPrefix;
  final IntentionReadinessFilter readinessFilter;

  /// Готовность строк выдачи, допустимая ограничением страницы.
  final List<IntentionReadiness> rowReadiness;

  /// Заголовок подтверждённой выдачи.
  final String header;

  /// Сообщение устранимого отказа первой порции.
  final String unavailableMessage;
}

/// Проверки подключения поиска по тегам к странице выбора намерения.
void defineDailyChoicePickerTagSearchTests(
  DailyChoicePickerTagSearchCase page,
) {
  defineIntentionPickerSessionTests(
    route: page.route,
    filterKey: '${page.keyPrefix}-filter',
    listKey: '${page.keyPrefix}-list',
    readinessFilter: page.readinessFilter,
  );
  testWidgets('кнопка фильтра открывает панель тегов, где условие '
      'добавляется, переключается и снимается с ограничениями страницы, а '
      'отмена ничего не меняет', (tester) async {
    final repository = ControlledCatalogRepository();
    final sport = _tag(2, 'Спорт');
    repository.tagCatalogItems = [_tag(1, 'Здоровье'), sport];
    final opened = await _openPicker(tester, repository, page);
    repository.complete(1, _firstPage(_summaries(page, const [], count: 3)));
    await tester.pumpAndSettle();

    await tester.tap(_filterButton);
    await tester.pumpAndSettle();
    expect(find.text('Filter by tags'), findsOneWidget);
    // Первое нажатие требует тег, второе исключает его.
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 3);
    _expectPickerQuery(
      page,
      repository.queryAt(2),
      IntentionTagFilter(requiredTagIds: [sport.id]),
    );
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 4);
    _expectPickerQuery(
      page,
      repository.queryAt(3),
      IntentionTagFilter(excludedTagIds: [sport.id]),
    );
    repository.complete(3, _firstPage(_summaries(page, const [], count: 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(opened.router.current.name, page.route.routeName);
    expect(tester.widget<FilterButton>(_filterButton).count, 1);
    expect(_rows, findsNWidgets(2));

    // Третье нажатие снимает условие.
    await tester.tap(_filterButton);
    await tester.pumpAndSettle();
    await tester.tap(_panelRow(sport));
    await _pumpUntilQueries(tester, repository, 5);
    _expectPickerQuery(page, repository.queryAt(4), IntentionTagFilter.empty);
    repository.complete(4, _firstPage(_summaries(page, const [], count: 3)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterButton>(_filterButton).count, 0);
    expect(_rows, findsNWidgets(3));

    await tester.tap(find.byKey(ValueKey('${page.keyPrefix}-cancel')));
    await tester.pumpAndSettle();
    expect(await opened.selection, isNull);
    _expectNoCommands(repository);
  });

  testWidgets('отказ новой выдачи после удаления исключённого тега показан '
      'отказом первой порции, а повтор показывает выдачу без его условия с '
      'прежними ограничениями', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final remaining = IntentionTagFilter(requiredTagIds: [health.id]);
    final opened = await _openPicker(tester, repository, page);
    await _applyConditions(tester, opened.container, repository, page, [
      (health, IntentionTagRequirement.mustBePresent),
      (rest, IntentionTagRequirement.mustBeAbsent),
    ], _firstPage(_summaries(page, [health], count: 3), revision: 1));
    final restarted = repository.queries.length;

    final accepted = acceptTagCommand(
      opened.container,
      repository,
      DeleteTag(rest.id),
      tagDeletionSuccess(
        tagId: rest.id,
        revision: const TestCatalogRevision(2),
      ),
    );
    await accepted.future;
    await _pumpUntilQueries(tester, repository, restarted + 1);
    _expectPickerQuery(page, repository.queryAt(restarted), remaining);
    repository.complete(
      restarted,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    expect(find.text(page.unavailableMessage), findsOneWidget);
    expect(_rows, findsNothing);

    await tester.tap(find.text('Try again'));
    await _pumpUntilQueries(tester, repository, restarted + 2);
    _expectPickerQuery(page, repository.queryAt(restarted + 1), remaining);
    repository.complete(
      restarted + 1,
      _firstPage(_summaries(page, [health], count: 4), revision: 2),
    );
    await tester.pumpAndSettle();

    expect(find.text(page.unavailableMessage), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CatalogHeader &&
            widget.title == page.header &&
            widget.count == 4,
      ),
      findsOneWidget,
    );
    expect(_rows, findsNWidgets(4));
    _expectNoCommands(repository, tagCommands: 1);
  });
}

typedef _OpenedPicker = ({
  ProviderContainer container,
  AppRouter router,
  Future<IntentionId?> selection,
});

/// Открывает страницу выбора поверх каталога; запрос 0 принадлежит каталогу,
/// запрос 1 — первой порции страницы выбора.
Future<_OpenedPicker> _openPicker(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  DailyChoicePickerTagSearchCase page,
) async {
  final container = reconciliationCatalogContainer(repository);
  final router = AppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: doableTheme(Brightness.light),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router.config(),
      ),
    ),
  );
  await tester.pump();
  await openIntentionGraph(tester);
  repository.complete(0, _firstPage(const []));
  await tester.pumpAndSettle();
  final selection = router.push<IntentionId>(page.route);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return (container: container, router: router, selection: selection);
}

/// Передаёт модели условий выбор так же, как его возвращает экран поиска
/// тега. Каждое условие сразу начинает новую выдачу; [result] отвечает на
/// последнюю.
Future<void> _applyConditions(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  DailyChoicePickerTagSearchCase page,
  List<(Tag, IntentionTagRequirement)> conditions,
  Result<IntentionCatalogFirstPage> result,
) async {
  final model = container.read(
    intentionTagConditionsViewModelProvider(
      tester
          .widget<IntentionPickerView>(find.byType(IntentionPickerView))
          .purpose,
    ).notifier,
  );
  var expectedQueries = repository.queries.length;
  for (final (tag, requirement) in conditions) {
    for (var i = 0; i < tagConditionCycles(requirement); i++) {
      model.cycle(tag, snapshotRevision: const TestCatalogRevision(0));
      expectedQueries++;
      await tester.pump();
    }
  }
  await _pumpUntilQueries(tester, repository, expectedQueries);
  repository.complete(expectedQueries - 1, result);
  await tester.pumpAndSettle();
}

/// Запрос страницы выбора сохраняет её ограничения при любых условиях.
void _expectPickerQuery(
  DailyChoicePickerTagSearchCase page,
  IntentionCatalogQuery query,
  IntentionTagFilter tagFilter,
) {
  expect(query.scope, IntentionScope.active);
  expect(query.readinessFilter, page.readinessFilter);
  expect(query.tagFilter, tagFilter);
  expect(query.cursor, isNull);
}

/// Поиск и изменение условий не выполняют команд графа.
void _expectNoCommands(
  ControlledCatalogRepository repository, {
  int tagCommands = 0,
}) {
  expect(repository.tagCommands, hasLength(tagCommands));
  expect(repository.commands, isEmpty);
  expect(repository.relationCommands, isEmpty);
  expect(repository.dailyChoiceCommands, isEmpty);
}

final _filterButton = find.byType(FilterButton);

final _rows = find.byType(PickerRow);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

Result<IntentionCatalogFirstPage> _firstPage(
  List<IntentionSummary> items, {
  int revision = 0,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: items.length,
    nextCursor: null,
    revision: TestCatalogRevision(revision),
  ),
);

IntentionSummary _summary(
  DailyChoicePickerTagSearchCase page,
  int index, {
  required String title,
  List<Tag> tags = const [],
}) => testSummary(
  index: index,
  title: title,
  readiness: page.rowReadiness[index % page.rowReadiness.length],
  tags: tags,
);

List<IntentionSummary> _summaries(
  DailyChoicePickerTagSearchCase page,
  List<Tag> tags, {
  required int count,
}) => [
  for (var index = count; index >= 1; index--)
    _summary(page, index, title: 'Намерение $index', tags: tags),
];

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

Future<void> _pumpUntilQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    await tester.pump(const Duration(milliseconds: 1));
    if (repository.queries.length >= count) {
      return;
    }
  }
  fail('Не дождались $count запросов каталога.');
}
