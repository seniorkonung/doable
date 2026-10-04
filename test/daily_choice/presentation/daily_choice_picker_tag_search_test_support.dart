import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
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

/// Страница выбора намерения для дневного выбора и её ограничения поиска.
///
/// Поиск действия и поиск исходного намерения подключают одни и те же общие
/// элементы поиска по тегам; различаются только назначение, допустимая
/// готовность и подписи страницы.
final class DailyChoicePickerTagSearchCase {
  const DailyChoicePickerTagSearchCase({
    required this.route,
    required this.purpose,
    required this.keyPrefix,
    required this.readinessFilter,
    required this.rowReadiness,
    required this.totalCountLabel,
    required this.emptyScopeMessages,
  });

  final PageRouteInfo route;
  final IntentionCatalogPurpose purpose;

  /// Общее начало ключей поля названия, списка и отмены страницы.
  final String keyPrefix;
  final IntentionReadinessFilter readinessFilter;

  /// Готовность строк выдачи, допустимая ограничением страницы.
  final List<IntentionReadiness> rowReadiness;
  final String Function(int count) totalCountLabel;

  /// Сообщение о пустом допустимом охвате по языку.
  final Map<String, String> emptyScopeMessages;
}

/// Проверки подключения поиска по тегам к странице выбора намерения.
void defineDailyChoicePickerTagSearchTests(
  DailyChoicePickerTagSearchCase page,
) {
  for (final (language, ownTags, otherTags, noTags) in [
    ('en', 'Tags: Здоровье, Отдых', 'Tags: Семья', 'No tags'),
    ('ru', 'Теги: Здоровье, Отдых', 'Теги: Семья', 'Без тегов'),
  ]) {
    testWidgets('$language: строки без условий показывают собственные теги, '
        'а выбор одноимённого намерения возвращает его идентификатор', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final repository = ControlledCatalogRepository();
      final opened = await _openPicker(
        tester,
        repository,
        page,
        locale: Locale(language),
      );
      final items = [
        _summary(
          page,
          3,
          title: 'Гулять',
          tags: [_tag(1, 'Здоровье'), _tag(2, 'Отдых')],
        ),
        _summary(page, 2, title: 'Гулять', tags: [_tag(3, 'Семья')]),
        _summary(page, 1, title: 'Читать'),
      ];
      repository.complete(1, _firstPage(items));
      await tester.pumpAndSettle();

      _expectPickerQuery(page, repository.queryAt(1), IntentionTagFilter.empty);
      expect(_shownConditions(tester), isEmpty);
      final rows = find.byType(IntentionSummaryView);
      expect(rows, findsNWidgets(3));
      for (final (index, title, tagsLine) in [
        (0, 'Гулять', ownTags),
        (1, 'Гулять', otherTags),
        (2, 'Читать', noTags),
      ]) {
        final row = rows.at(index);
        expect(
          find.descendant(of: row, matching: find.text(tagsLine)),
          findsOneWidget,
        );
        expect(
          tester.getSemantics(row).label,
          allOf(contains(title), contains(tagsLine)),
        );
      }

      await tester.tap(find.text('Гулять').last);
      await tester.pumpAndSettle();
      expect(await opened.selection, items[1].id);
      semantics.dispose();
    });
  }

  testWidgets('условие добавляется через экран поиска тега под полем '
      'названия, переключается и снимается, а отмена ничего не меняет', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    repository.tagCatalogItems = [health, sport];
    final opened = await _openPicker(tester, repository, page);
    repository.complete(1, _firstPage(_summaries(page, const [], count: 3)));
    await tester.pumpAndSettle();

    final section = tester.getRect(find.byType(IntentionTagConditionsSection));
    expect(
      section.top,
      greaterThanOrEqualTo(tester.getRect(_filterField(page)).bottom),
    );
    expect(section.bottom, lessThanOrEqualTo(tester.getRect(_list(page)).top));

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
    expect(find.text('Tags: Здоровье'), findsNWidgets(2));

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
    expect(find.text('Tags: Спорт'), findsOneWidget);

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

  testWidgets('добавление, переключение и снятие условия начинают выдачу '
      'прокрученного списка с верхней позиции', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    repository.tagCatalogItems = [health];
    final opened = await _openPicker(tester, repository, page);
    repository.complete(1, _firstPage(_summaries(page, const [], count: 60)));
    await tester.pumpAndSettle();
    await _scrollListDown(tester, page);

    await tester.tap(_addCondition);
    await tester.pumpAndSettle();
    await tester.tap(
      _pickerAction(health, IntentionTagRequirement.mustBeAbsent),
    );
    await _pumpUntilQueries(tester, repository, 3);
    _expectPickerQuery(
      page,
      repository.queryAt(2),
      IntentionTagFilter(excludedTagIds: [health.id]),
    );
    repository.complete(2, _firstPage(_summaries(page, const [], count: 59)));
    await tester.pumpAndSettle();

    expect(opened.router.current.name, page.route.routeName);
    expect(_shownConditions(tester), ['not Здоровье']);
    expect(_listPosition(tester, page).pixels, 0);
    expect(find.text('Намерение 59'), findsOneWidget);
    await _scrollListDown(tester, page);

    await tester.tap(_conditionToggle(health));
    await _pumpUntilQueries(tester, repository, 4);
    _expectPickerQuery(
      page,
      repository.queryAt(3),
      IntentionTagFilter(requiredTagIds: [health.id]),
    );
    repository.complete(3, _firstPage(_summaries(page, [health], count: 58)));
    await tester.pumpAndSettle();

    expect(_shownConditions(tester), ['Здоровье']);
    expect(_listPosition(tester, page).pixels, 0);
    expect(find.text('Намерение 58'), findsOneWidget);
    await _scrollListDown(tester, page);

    await tester.tap(_conditionRemove(health));
    await _pumpUntilQueries(tester, repository, 5);
    _expectPickerQuery(page, repository.queryAt(4), IntentionTagFilter.empty);
    repository.complete(4, _firstPage(_summaries(page, const [], count: 60)));
    await tester.pumpAndSettle();

    expect(_shownConditions(tester), isEmpty);
    expect(_listPosition(tester, page).pixels, 0);
    expect(find.text('Намерение 60'), findsOneWidget);
    _expectNoCommands(repository);
  });

  testWidgets('отказ обновления и согласование без изменения условий '
      'сохраняют экранную позицию прокрученного списка', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final opened = await _openPicker(tester, repository, page);
    await _applyConditions(tester, opened.container, repository, page, [
      (health, IntentionTagRequirement.mustBePresent),
      (rest, IntentionTagRequirement.mustBeAbsent),
    ], _firstPage(_summaries(page, [health], count: 60), revision: 1));
    await _scrollListDown(tester, page);
    final positionBefore = _listPosition(tester, page).pixels;
    final visibleRow = _rowAtListCenter(tester, page);
    final rowTopBefore = tester.getRect(visibleRow).top;

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
    await tester.pump();
    await tester.pump();
    await _pumpUntilReconciliationQueries(tester, repository, 1);
    repository.completeReconciliation(
      0,
      const ResultFailure(IntentionUnavailableFailure()),
    );
    await tester.pumpAndSettle();

    final message = find.text(
      'The intention list isn’t up to date: changes couldn’t be loaded.',
    );
    expect(message, findsOneWidget);
    expect(_listPosition(tester, page).pixels, positionBefore);
    // Отказ лежит поверх верхнего края списка и не сдвигает его строки.
    expect(tester.getRect(visibleRow).top, rowTopBefore);
    expect(
      tester.getRect(_refreshStatus).top,
      moreOrLessEquals(tester.getRect(_list(page)).top, epsilon: 0.01),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await _pumpUntilReconciliationQueries(tester, repository, 2);
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(const [], totalCount: 60, revision: 2),
    );
    await tester.pumpAndSettle();

    expect(message, findsNothing);
    expect(find.text(page.totalCountLabel(60)), findsOneWidget);
    expect(_listPosition(tester, page).pixels, positionBefore);
    expect(tester.getRect(visibleRow).top, rowTopBefore);
  });

  for (final (name, change) in <(String, Future<void> Function(WidgetTester))>[
    (
      'снятие условия',
      (tester) => tester.tap(_conditionRemove(_tag(1, 'Здоровье'))),
    ),
    (
      'новый текст названия',
      (tester) => tester.enterText(_filterField(page), 'Намерение'),
    ),
  ]) {
    testWidgets('$name начинает выдачу с верхней позиции, когда прокрученный '
        'список снят с экрана успешной пустой выдачей', (tester) async {
      final repository = ControlledCatalogRepository();
      final health = _tag(1, 'Здоровье');
      final opened = await _openPicker(tester, repository, page);
      await _applyConditions(tester, opened.container, repository, page, [
        (health, IntentionTagRequirement.mustBePresent),
      ], _firstPage(_summaries(page, [health], count: 60), revision: 1));
      await _scrollListDown(tester, page);

      // Удаление обязательного тега снимает список с экрана без смены
      // параметров поиска.
      await _deleteTag(tester, opened.container, repository, health, 2);
      expect(_list(page), findsNothing);
      expect(find.text(_emptyByConditions), findsOneWidget);

      final answered = repository.queries.length;
      await change(tester);
      await _pumpUntilQueries(tester, repository, answered + 1);
      // Состав новой выдачи задаёт управляемое хранилище: странице важна
      // только смена параметров над снятым с экрана списком.
      repository.complete(
        answered,
        _firstPage(_summaries(page, const [], count: 60), revision: 2),
      );
      await tester.pumpAndSettle();

      expect(_listPosition(tester, page).pixels, 0);
      expect(find.text('Намерение 60'), findsOneWidget);
    });
  }

  testWidgets('выдача, вернувшаяся после временной пустоты без смены '
      'параметров, сохраняет экранную позицию', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
    final opened = await _openPicker(tester, repository, page);
    await _applyConditions(tester, opened.container, repository, page, [
      (health, IntentionTagRequirement.mustBePresent),
      (rest, IntentionTagRequirement.mustBeAbsent),
    ], _firstPage(_summaries(page, [health], count: 60), revision: 1));
    await _scrollListDown(tester, page);
    final positionBefore = _listPosition(tester, page).pixels;

    await _deleteTag(tester, opened.container, repository, health, 2);
    expect(_list(page), findsNothing);

    // Согласование после удаления исключённого тега возвращает совпадения
    // без смены параметров; их состав задаёт управляемое хранилище.
    await _deleteTag(tester, opened.container, repository, rest, 3);
    await _pumpUntilReconciliationQueries(tester, repository, 1);
    repository.completeReconciliation(
      0,
      reconciliationFirstPortion(
        _summaries(page, const [], count: 60),
        totalCount: 60,
        revision: 3,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Намерение 60'), findsNothing);
    expect(_listPosition(tester, page).pixels, positionBefore);
  });

  testWidgets('условия по тегам действуют вместе с ограничениями страницы, '
      'а выбор строки возвращает идентификатор намерения', (tester) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final sport = _tag(2, 'Спорт');
    final opened = await _openPicker(tester, repository, page);
    final items = _summaries(page, [health], count: 2);
    await _applyConditions(tester, opened.container, repository, page, [
      (health, IntentionTagRequirement.mustBePresent),
      (sport, IntentionTagRequirement.mustBeAbsent),
    ], _firstPage(items));

    _expectPickerQuery(
      page,
      repository.queries.last,
      IntentionTagFilter(
        requiredTagIds: [health.id],
        excludedTagIds: [sport.id],
      ),
    );
    expect(_shownConditions(tester), ['Здоровье', 'not Спорт']);
    expect(find.text(page.totalCountLabel(2)), findsOneWidget);

    await tester.tap(find.text(items.last.title));
    await tester.pumpAndSettle();
    expect(await opened.selection, items.last.id);
    _expectNoCommands(repository);
  });

  testWidgets('условия по тегам не сохраняются после закрытия поиска', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final opened = await _openPicker(tester, repository, page);
    await _applyConditions(tester, opened.container, repository, page, [
      (_tag(1, 'Здоровье'), IntentionTagRequirement.mustBePresent),
    ], _firstPage(const []));
    expect(_shownConditions(tester), ['Здоровье']);

    await tester.tap(find.byKey(ValueKey('${page.keyPrefix}-cancel')));
    await tester.pumpAndSettle();
    expect(await opened.selection, isNull);
    final reopenedQuery = repository.queries.length;
    unawaited(opened.router.push<IntentionId>(page.route));
    await _pumpUntilQueries(tester, repository, reopenedQuery + 1);

    _expectPickerQuery(
      page,
      repository.queryAt(reopenedQuery),
      IntentionTagFilter.empty,
    );
    expect(_shownConditions(tester), isEmpty);
  });

  for (final (language, byConditions) in [
    ('en', 'No intentions match the tag conditions.'),
    ('ru', 'По условиям по тегам совпадений нет.'),
  ]) {
    testWidgets('$language: пустая выдача при условиях по тегам сообщает об '
        'отсутствии совпадений по условиям, а не о пустом охвате', (
      tester,
    ) async {
      final repository = ControlledCatalogRepository();
      final byScope = page.emptyScopeMessages[language]!;
      final opened = await _openPicker(
        tester,
        repository,
        page,
        locale: Locale(language),
      );
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
  }

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
    // Место под отказ отведено перед началом выдачи: первая строка стоит
    // под ним и остаётся достижимой.
    expect(
      tester.getRect(_refreshStatus).bottom,
      lessThanOrEqualTo(
        tester.getRect(find.byType(IntentionSummaryView).first).top,
      ),
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

  for (final (name, failure, text) in <(String, IntentionFailure, String)>[
    (
      'повреждения',
      const IntentionCorruptionFailure(),
      'The intention list isn’t up to date: stored data is damaged.',
    ),
    (
      'неожиданной ошибки',
      const IntentionUnexpectedFailure(),
      'The intention list isn’t up to date because of an unexpected error.',
    ),
  ]) {
    testWidgets('отказ обновления из-за $name показан над сохранённым '
        'списком без повтора', (tester) async {
      final repository = ControlledCatalogRepository();
      final health = _tag(1, 'Здоровье');
      final opened = await _openPicker(tester, repository, page);
      await _failRefresh(
        tester,
        opened.container,
        repository,
        page,
        required: health,
        deletedExcluded: _tag(2, 'Отдых'),
        items: _summaries(page, [health], count: 3),
        failure: failure,
      );

      expect(find.text(text), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(find.text(page.totalCountLabel(3)), findsOneWidget);
      expect(find.byType(IntentionSummaryView), findsNWidgets(3));
      expect(repository.reconciliationQueries, hasLength(1));
    });
  }

  testWidgets('успешная пустая выдача показывает только сообщение о пустоте, '
      'без представления отказа обновления', (tester) async {
    final repository = ControlledCatalogRepository();
    final opened = await _openPicker(tester, repository, page);
    await _applyConditions(tester, opened.container, repository, page, [
      (_tag(1, 'Здоровье'), IntentionTagRequirement.mustBePresent),
    ], _firstPage(const []));

    expect(find.text(_emptyByConditions), findsOneWidget);
    expect(tester.getSize(_refreshStatus).height, 0);
    expect(
      find.descendant(of: _refreshStatus, matching: find.byType(Text)),
      findsNothing,
    );
    expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
  });

  testWidgets('отказ обновления из-за недоступности показан над исходно '
      'пустой выдачей, а повтор согласует её с прежними ограничениями', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final health = _tag(1, 'Здоровье');
    final rest = _tag(2, 'Отдых');
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
      items: const [],
      failure: const IntentionUnavailableFailure(),
    );

    // Сообщение о пустоте остаётся, но выдача явно названа не обновлённой.
    final message = find.text(
      'The intention list isn’t up to date: changes couldn’t be loaded.',
    );
    expect(message, findsOneWidget);
    expect(find.text(_emptyByConditions), findsOneWidget);
    expect(
      tester.getRect(_refreshStatus).bottom,
      lessThanOrEqualTo(tester.getRect(find.text(_emptyByConditions)).top),
    );
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
    _expectPickerQuery(
      page,
      repository.reconciliationQueryAt(0).catalogQuery,
      filter,
    );

    final retry = find.descendant(
      of: _refreshStatus,
      matching: find.widgetWithText(FilledButton, 'Try again'),
    );
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await _pumpUntilReconciliationQueries(tester, repository, 2);
    // Повтор читает ту же область с прежними условиями и ограничениями.
    expect(
      repository.reconciliationQueryAt(1).catalogQuery,
      same(repository.reconciliationQueryAt(0).catalogQuery),
    );
    repository.completeReconciliation(
      1,
      reconciliationFirstPortion(const [], totalCount: 0, revision: 2),
    );
    await tester.pumpAndSettle();

    expect(message, findsNothing);
    expect(retry, findsNothing);
    expect(find.text(_emptyByConditions), findsOneWidget);
    expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
    _expectNoCommands(repository, tagCommands: 1);
  });

  for (final (name, failure, text) in <(String, IntentionFailure, String)>[
    (
      'повреждения',
      const IntentionCorruptionFailure(),
      'The intention list isn’t up to date: stored data is damaged.',
    ),
    (
      'неожиданной ошибки',
      const IntentionUnexpectedFailure(),
      'The intention list isn’t up to date because of an unexpected error.',
    ),
  ]) {
    testWidgets('отказ обновления из-за $name показан над исходно пустой '
        'выдачей без повтора', (tester) async {
      final repository = ControlledCatalogRepository();
      final health = _tag(1, 'Здоровье');
      final opened = await _openPicker(tester, repository, page);
      await _failRefresh(
        tester,
        opened.container,
        repository,
        page,
        required: health,
        deletedExcluded: _tag(2, 'Отдых'),
        items: const [],
        failure: failure,
      );

      expect(find.text(text), findsOneWidget);
      expect(find.text(_emptyByConditions), findsOneWidget);
      expect(
        tester.getRect(_refreshStatus).bottom,
        lessThanOrEqualTo(tester.getRect(find.text(_emptyByConditions)).top),
      );
      expect(find.widgetWithText(FilledButton, 'Try again'), findsNothing);
      expect(_shownConditions(tester), ['Здоровье', 'not Отдых (tag deleted)']);
      expect(repository.reconciliationQueries, hasLength(1));
    });
  }
}

const _emptyByConditions = 'No intentions match the tag conditions.';

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
  DailyChoicePickerTagSearchCase page, {
  Locale locale = const Locale('en'),
}) async {
  final container = reconciliationCatalogContainer(repository);
  final router = AppRouter();
  addTearDown(container.dispose);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
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
        .read(intentionTagConditionsViewModelProvider(page.purpose).notifier)
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

/// Подтверждает физическое удаление тега без действий на странице выбора.
Future<void> _deleteTag(
  WidgetTester tester,
  ProviderContainer container,
  ControlledCatalogRepository repository,
  Tag tag,
  int revision,
) async {
  final accepted = acceptTagCommand(
    container,
    repository,
    DeleteTag(tag.id),
    tagDeletionSuccess(tagId: tag.id, revision: TestCatalogRevision(revision)),
  );
  await accepted.future;
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

final _refreshStatus = find.byType(IntentionCatalogRefreshStatusView);
final _addCondition = find.byKey(
  const ValueKey('intention-tag-conditions-add'),
);

Finder _filterField(DailyChoicePickerTagSearchCase page) =>
    find.byKey(ValueKey('${page.keyPrefix}-filter'));

Finder _list(DailyChoicePickerTagSearchCase page) =>
    find.byKey(PageStorageKey<String>('${page.keyPrefix}-list'));

ScrollPosition _listPosition(
  WidgetTester tester,
  DailyChoicePickerTagSearchCase page,
) => tester
    .state<ScrollableState>(
      find.descendant(of: _list(page), matching: find.byType(Scrollable)),
    )
    .position;

/// Строка выдачи, занимающая середину области списка.
Finder _rowAtListCenter(
  WidgetTester tester,
  DailyChoicePickerTagSearchCase page,
) {
  final center = tester.getRect(_list(page)).center.dy;
  final rows = find.byType(IntentionSummaryView);
  for (final row in tester.widgetList<IntentionSummaryView>(rows)) {
    final finder = find.byWidget(row);
    final rect = tester.getRect(finder);
    if (rect.top <= center && rect.bottom > center) {
      final title = row.title;
      return find.byWidgetPredicate(
        (widget) => widget is IntentionSummaryView && widget.title == title,
      );
    }
  }
  fail('В середине списка нет строки выдачи.');
}

/// Прокручивает список выдачи ниже начала.
Future<void> _scrollListDown(
  WidgetTester tester,
  DailyChoicePickerTagSearchCase page,
) async {
  await tester.drag(_list(page), const Offset(0, -600));
  await tester.pumpAndSettle();
  expect(_listPosition(tester, page).pixels, greaterThan(0));
}

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
    text.data!,
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
