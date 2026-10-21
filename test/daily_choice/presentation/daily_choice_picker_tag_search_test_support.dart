import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
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
import '../../support/inline_text.dart';
import '../../intention/presentation/catalog/intention_picker_session_test_support.dart';

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
    required this.totalCountLabel,
    required this.emptyScopeMessage,
  });

  final PageRouteInfo route;

  /// Общее начало ключей поля названия, списка и отмены страницы.
  final String keyPrefix;
  final IntentionReadinessFilter readinessFilter;

  /// Готовность строк выдачи, допустимая ограничением страницы.
  final List<IntentionReadiness> rowReadiness;
  final String Function(int count) totalCountLabel;

  /// Сообщение о пустом допустимом охвате.
  final String emptyScopeMessage;
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
  testWidgets('условие добавляется через экран поиска тега, переключается и '
      'снимается, а отмена ничего не меняет', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    repository.tagCatalogItems = [health, sport];
    final opened = await _openPicker(tester, repository, page);
    repository.complete(1, _firstPage(_summaries(page, const [], count: 3)));
    await tester.pumpAndSettle();

    await tester.tap(_addCondition);
    await tester.pumpAndSettle();
    expect(opened.router.current.name, TagConditionPickerRoute.name);
    await tester.tap(
      _pickerAction(sport, IntentionTagRequirement.mustBeAbsent),
    );
    await _pumpUntilQueries(tester, repository, 3);
    _expectPickerQuery(
      page,
      repository.queryAt(2),
      IntentionTagFilter(excludedTagIds: [sport.id]),
    );
    repository.complete(2, _firstPage(_summaries(page, [health], count: 2)));
    await tester.pumpAndSettle();

    expect(opened.router.current.name, page.route.routeName);
    expect(_shownConditions(tester), ['not Спорт']);
    expect(findTextIgnoringInlineWidgets('Tags: Здоровье'), findsNWidgets(2));

    await tester.tap(_conditionToggle(sport));
    await _pumpUntilQueries(tester, repository, 4);
    _expectPickerQuery(
      page,
      repository.queryAt(3),
      IntentionTagFilter(requiredTagIds: [sport.id]),
    );
    repository.complete(3, _firstPage(_summaries(page, [sport], count: 1)));
    await tester.pumpAndSettle();
    expect(_shownConditions(tester), ['Спорт']);
    expect(findTextIgnoringInlineWidgets('Tags: Спорт'), findsOneWidget);

    await tester.tap(_conditionRemove(sport));
    await _pumpUntilQueries(tester, repository, 5);
    _expectPickerQuery(page, repository.queryAt(4), IntentionTagFilter.empty);
    repository.complete(4, _firstPage(_summaries(page, const [], count: 3)));
    await tester.pumpAndSettle();
    expect(_shownConditions(tester), isEmpty);
    expect(find.text('No tags'), findsNWidgets(3));

    await tester.tap(find.byKey(ValueKey('${page.keyPrefix}-cancel')));
    await tester.pumpAndSettle();
    expect(await opened.selection, isNull);
    _expectNoCommands(repository);
  });

  testWidgets('пустая выдача при условиях по тегам сообщает об отсутствии '
      'совпадений по условиям, а не о пустом охвате', (tester) async {
    final repository = ControlledCatalogRepository();
    const byConditions = 'No intentions match the tag conditions.';
    final byScope = page.emptyScopeMessage;
    final opened = await _openPicker(tester, repository, page);
    repository.complete(1, _firstPage(const []));
    await tester.pumpAndSettle();
    expect(find.text(byScope), findsOneWidget);
    expect(find.text(byConditions), findsNothing);

    await _applyConditions(tester, opened.container, repository, page, [
      (_tag(1, 'Здоровье'), IntentionTagRequirement.mustBePresent),
    ], _firstPage(const []));

    expect(find.text(byConditions), findsOneWidget);
    expect(find.text(byScope), findsNothing);
  });

  testWidgets('отказ обновления из-за недоступности показан над сохранённым '
      'списком, а повтор согласует выдачу с прежними ограничениями', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final items = _summaries(page, [health], count: 3);
    final filter = IntentionTagFilter(
      requiredTagIds: [health.id],
      excludedTagIds: [rest.id],
    );
    final opened = await _openPicker(tester, repository, page);
    await _failRefresh(
      tester,
      opened.container,
      repository,
      page,
      required: health,
      deletedExcluded: rest,
      items: items,
      failure: const IntentionUnavailableFailure(),
    );

    final message = find.text(
      'The intention list isn’t up to date: changes couldn’t be loaded.',
    );
    expect(message, findsOneWidget);
    expect(find.text(page.totalCountLabel(3)), findsOneWidget);
    expect(find.byType(IntentionSummaryView), findsNWidgets(3));
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
    // Отказ не закрывает первую строку: она остаётся достижимой.
    expect(
      find.byType(IntentionSummaryView).first.hitTestable(),
      findsOneWidget,
    );
    _expectPickerQuery(
      page,
      repository.reconciliationQueryAt(0).catalogQuery,
      filter,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await _pumpUntilReconciliationQueries(tester, repository, 2);
    _expectPickerQuery(
      page,
      repository.reconciliationQueryAt(1).catalogQuery,
      filter,
    );
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(
        [
          _summary(page, 4, title: 'Намерение 4', tags: [health]),
        ],
        totalCount: 4,
        revision: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(message, findsNothing);
    expect(find.text(page.totalCountLabel(4)), findsOneWidget);
    expect(find.byType(IntentionSummaryView), findsNWidgets(4));
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
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
  final expectedQueries = repository.queries.length + conditions.length;
  for (final (tag, requirement) in conditions) {
    container
        .read(
          intentionTagConditionsViewModelProvider(
            tester
                .widget<IntentionTagConditionsSection>(
                  find.byType(IntentionTagConditionsSection),
                )
                .purpose,
          ).notifier,
        )
        .applySelection(
          IntentionTagConditionSelection(
            tag: tag,
            requirement: requirement,
            snapshotRevision: const TestCatalogRevision(0),
          ),
        );
    await tester.pump();
  }
  await _pumpUntilQueries(tester, repository, expectedQueries);
  repository.complete(expectedQueries - 1, result);
  await tester.pumpAndSettle();
}

/// Доводит страницу выбора до отказа обновления после удаления исключённого
/// тега.
Future<void> _failRefresh(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  DailyChoicePickerTagSearchCase page, {
  required Tag required,
  required Tag deletedExcluded,
  required List<IntentionSummary> items,
  required IntentionFailure failure,
}) async {
  await _applyConditions(tester, container, repository, page, [
    (required, IntentionTagRequirement.mustBePresent),
    (deletedExcluded, IntentionTagRequirement.mustBeAbsent),
  ], _firstPage(items, revision: 1));
  final accepted = acceptTagCommand(
    container,
    repository,
    DeleteTag(deletedExcluded.id),
    tagDeletionSuccess(
      tagId: deletedExcluded.id,
      revision: const TestCatalogRevision(2),
    ),
  );
  await accepted.future;
  await tester.pump();
  await tester.pump();
  await _pumpUntilReconciliationQueries(tester, repository, 1);
  repository.completeReconciliation(0, ResultFailure(failure));
  await tester.pump();
  await tester.pump();
  await tester.pump();
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

final _addCondition = find.byKey(
  const ValueKey('intention-tag-conditions-add'),
);

Finder _conditionToggle(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-toggle-${tag.id.toCanonicalString()}'),
);

Finder _conditionRemove(Tag tag) => find.byKey(
  ValueKey('intention-tag-condition-remove-${tag.id.toCanonicalString()}'),
);

Finder _pickerAction(Tag tag, IntentionTagRequirement requirement) =>
    find.byKey(
      ValueKey(
        'tag-condition-picker-${requirement.name}-'
        '${tag.id.toCanonicalString()}',
      ),
    );

/// Тексты чипов раздела условий в порядке показа.
List<String> _shownConditions(WidgetTester tester) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byType(IntentionTagConditionsSection),
      matching: find.byKey(const ValueKey('intention-tag-condition-label')),
    ),
  ))
    textIgnoringInlineWidgets(text),
];

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
);

Future<void> _pumpUntilReconciliationQueries(
  WidgetTester tester,
  ControlledCatalogRepository repository,
  int count,
) async {
  for (var attempt = 0; attempt < 1000; attempt++) {
    if (repository.reconciliationQueries.length >= count) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 1));
  }
  fail('Не дождались $count чтений согласования.');
}

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
