import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/intention/application/intention_catalog.dart'
    hide IntentionCatalogPage;
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_status_views.dart';
import 'package:doable/src/intention/presentation/catalog/intention_search_layout.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_section.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_root_pages.dart';
import 'catalog/catalog_reconciliation_test_support.dart';
import 'catalog/catalog_test_support.dart';

/// Нижняя граница области над открытой клавиатурой: окно 900, inset 300.
const _keyboardTop = 600.0;

/// Страница поиска намерений и то, чем она отличается от остальных трёх.
final class _SearchPage {
  const _SearchPage({
    required this.name,
    required this.route,
    required this.filterKey,
    required this.listKey,
  });

  final String name;

  /// Маршрут поверх каталога; каталог открыт сразу и маршрута не требует.
  final PageRouteInfo? route;
  final String filterKey;
  final String listKey;
}

final _secondParticipant = testSummary(index: 99).id;

final _pages = [
  const _SearchPage(
    name: 'каталог намерений',
    route: null,
    filterKey: 'catalog-filter-field',
    listKey: 'intention-catalog-list',
  ),
  _SearchPage(
    name: 'поиск действия',
    route: DailyChoiceActionPickerRoute(),
    filterKey: 'daily-choice-action-filter',
    listKey: 'daily-choice-action-list',
  ),
  _SearchPage(
    name: 'поиск исходного намерения',
    route: DailyChoiceSourcePickerRoute(),
    filterKey: 'daily-choice-source-filter',
    listKey: 'daily-choice-source-list',
  ),
  _SearchPage(
    name: 'поиск участника долговременной связи',
    route: RelationParticipantPickerRoute(
      excludedIntentionId: _secondParticipant,
      selectionContext: RelationParticipantSelectionContext.archivedRelation,
    ),
    filterKey: 'participant-picker-filter-field',
    listKey: 'participant-picker-list',
  ),
];

/// Теги каталога тегов с длинными названиями в порядке создания.
final _tags = [
  for (var index = 1; index <= 9; index++)
    _tag(index, 'Здоровье и долгие прогулки на свежем воздухе $index'),
];

/// Число условий, выбранных до открытия экрана поиска тега.
const _initialConditions = 6;

void main() {
  for (final page in _pages) {
    for (final locale in const [Locale('ru'), Locale('en')]) {
      testWidgets('${page.name} и экран поиска тега доступны при увеличенном '
          'тексте, открытой клавиатуре и многих условиях: '
          '${locale.languageCode}', (tester) async {
        tester.view.physicalSize = const Size(420, 900);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        final semantics = tester.ensureSemantics();
        final l10n = await AppLocalizations.delegate.load(locale);
        final repository = ControlledCatalogRepository()
          ..tagCatalogItems = _tags;
        final container = reconciliationCatalogContainer(repository);
        final router = AppRouter();
        addTearDown(container.dispose);
        addTearDown(router.dispose);
        final list = find.byKey(PageStorageKey<String>(page.listKey));

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp.router(
              locale: locale,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(2.5)),
                child: child!,
              ),
              routerConfig: router.config(),
            ),
          ),
        );
        await tester.pump();
        await openIntentionGraph(tester);
        repository.complete(0, _firstPage(const []));
        await _pumpFrames(tester);
        if (page.route case final route?) {
          unawaited(router.push<Object?>(route));
          await _pumpUntilQueries(tester, repository, 2);
          repository.complete(1, _firstPage(const []));
          await _pumpFrames(tester);
        }
        expect(tester.takeException(), isNull);

        final conditionsProvider = intentionTagConditionsViewModelProvider(
          tester
              .widget<IntentionTagConditionsSection>(
                find.byType(IntentionTagConditionsSection),
              )
              .purpose,
        );

        // Поле названия принимает ввод при открытой клавиатуре.
        final field = find.byKey(ValueKey(page.filterKey));
        await _reach(tester, field);
        _expectTappable(tester, field);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(l10n.catalogFilterLabel))),
          findsWidgets,
        );
        await tester.tap(field);
        await tester.enterText(field, 'ход');
        await _pumpUntilQueries(
          tester,
          repository,
          repository.queries.length + 1,
        );
        expect(
          repository.queries.last.titleFilter?.map((value) => value),
          'ход',
        );

        // Много условий с длинными названиями, выбранных как на экране
        // поиска тега.
        for (var index = 0; index < _initialConditions; index++) {
          container
              .read(conditionsProvider.notifier)
              .applySelection(
                IntentionTagConditionSelection(
                  tag: _tags[index],
                  requirement: index.isEven
                      ? IntentionTagRequirement.mustBePresent
                      : IntentionTagRequirement.mustBeAbsent,
                  snapshotRevision: const TestCatalogRevision(0),
                ),
              );
          await tester.pump();
        }
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);

        // Кнопка «+ Тег» открывает экран поиска тега.
        final add = find.byKey(const ValueKey('intention-tag-conditions-add'));
        await _reach(tester, add);
        _expectTappable(tester, add);
        expect(
          find.bySemanticsLabel(l10n.intentionTagConditionsAddSemantics),
          findsOneWidget,
        );
        await tester.tap(add);
        await _pumpFrames(tester);
        expect(router.current.name, TagConditionPickerRoute.name);
        await _expectTagConditionPickerAccessible(tester, l10n);

        // Выбор последнего тега с надобностью «Нет» добавляет условие.
        final absent = _pickerAction(
          _tags.last,
          IntentionTagRequirement.mustBeAbsent,
        );
        await _reach(tester, absent, within: _pickerList);
        _expectTappable(tester, absent);
        await tester.tap(absent);
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
        if (page.route case final route?) {
          expect(router.current.name, route.routeName);
        } else {
          expectIntentionGraphRootPage(router);
        }
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

        // Каждый чип достижим и объявляет надобность, переключение и снятие.
        for (final condition in container.read(conditionsProvider).conditions) {
          final name = condition.name.value;
          final toggle = _conditionToggle(condition.tagId);
          await _reach(tester, toggle);
          _expectTappable(tester, toggle);
          final toggleNode = tester.getSemantics(toggle);
          expect(toggleNode.label, switch (condition.requirement) {
            IntentionTagRequirement.mustBePresent =>
              l10n.intentionTagConditionPresentSemantics(name),
            IntentionTagRequirement.mustBeAbsent =>
              l10n.intentionTagConditionAbsentSemantics(name),
          });
          expect(toggleNode.hint, l10n.intentionTagConditionToggleHint);
          expect(toggleNode, isSemantics(isButton: true, hasTapAction: true));
          _expectNotTruncated(
            tester,
            find.descendant(
              of: toggle,
              matching: find.byKey(
                const ValueKey('intention-tag-condition-label'),
              ),
            ),
          );
          final remove = _conditionRemove(condition.tagId);
          await _reach(tester, remove);
          _expectTappable(tester, remove);
          expect(
            tester.getSemantics(remove),
            isSemantics(
              tooltip: l10n.intentionTagConditionRemove(name),
              isButton: true,
              hasTapAction: true,
            ),
          );
        }
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        // Переключение и снятие срабатывают касанием.
        final firstToggle = _conditionToggle(_tags.first.id);
        await _reach(tester, firstToggle);
        await tester.tap(firstToggle);
        await tester.pump();
        expect(
          container.read(conditionsProvider).conditions.first.requirement,
          IntentionTagRequirement.mustBeAbsent,
        );
        final lastRemove = _conditionRemove(_tags.last.id);
        await _reach(tester, lastRemove);
        await tester.tap(lastRemove);
        await tester.pump();
        final conditions = container.read(conditionsProvider).conditions;
        expect(conditions, hasLength(_initialConditions));
        expect(tester.takeException(), isNull);

        // Выдача со строкой тегов у каждого результата и отказом продолжения.
        final rowTags = [_tags[0], _tags[2]];
        final items = [
          for (var index = 4; index >= 2; index--)
            testSummary(
              index: index,
              title: 'Долгая прогулка до дальнего парка $index',
              readiness: IntentionReadiness.ready,
              hasDescription: true,
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

        final tagsLine = l10n.intentionSummaryTags(
          rowTags.map((tag) => tag.name.value).join(', '),
        );
        for (final summary in items) {
          final row = find.ancestor(
            of: find.text(summary.title),
            matching: find.byType(IntentionSummaryView),
          );
          await _reach(tester, row, within: list);
          _expectTappable(tester, row);
          final line = summary.tags.isEmpty
              ? l10n.intentionSummaryNoTags
              : tagsLine;
          _expectNotTruncated(
            tester,
            find.descendant(of: row, matching: find.text(line)),
          );
          final rowNode = tester.getSemantics(row);
          expect(rowNode.label, allOf(contains(summary.title), contains(line)));
          expect(rowNode, isSemantics(hasTapAction: true));
        }

        final continuation = find.byType(
          IntentionCatalogContinuationStatusView,
        );
        final continuationRetry = find.descendant(
          of: continuation,
          matching: find.widgetWithText(FilledButton, l10n.commonRetry),
        );
        await _reach(tester, continuationRetry, within: list);
        _expectTappable(tester, continuationRetry);
        expect(
          find.descendant(
            of: continuation,
            matching: find.text(l10n.catalogLoadMoreUnavailable),
          ),
          findsOneWidget,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
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
          matching: find.byType(IntentionSummaryView),
        );
        await _reach(tester, lastRow, within: list);
        _expectTappable(tester, lastRow);

        // От конца выдачи поле названия достижимо одними жестами прокрутки.
        for (
          var attempt = 0;
          attempt < 40 && !_isTappable(tester, field);
          attempt++
        ) {
          await tester.dragFrom(
            const Offset(210, _keyboardTop - 80),
            const Offset(0, 400),
          );
          await _pumpFrames(tester);
        }
        _expectTappable(tester, field);
        expect(tester.widget<TextField>(field).controller!.text, 'ход');

        // Отказ обновления после удаления исключённого тега и его повтор.
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
        await _pumpUntilReconciliationQueries(tester, repository, 1);
        repository.completeReconciliation(
          0,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);

        final refresh = find.byType(IntentionCatalogRefreshStatusView);
        final refreshRetry = find.descendant(
          of: refresh,
          matching: find.widgetWithText(FilledButton, l10n.commonRetry),
        );
        await _reach(tester, refreshRetry, within: list, delta: -150);
        _expectTappable(tester, refreshRetry);
        expect(
          tester.getSemantics(refresh),
          isSemantics(
            isLiveRegion: true,
            label: l10n.catalogRefreshUnavailable,
          ),
        );
        expect(find.text(l10n.catalogRefreshUnavailable), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.tap(refreshRetry);
        await _pumpUntilReconciliationQueries(tester, repository, 2);
        repository.completeReconciliation(
          1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await _pumpFrames(tester);
        expect(find.text(l10n.catalogRefreshUnavailable), findsOneWidget);

        // Строки сохранённой выдачи остаются достижимыми под отказом.
        for (final summary in [...items, lastSummary]) {
          final row = find.ancestor(
            of: find.text(summary.title),
            matching: find.byType(IntentionSummaryView),
          );
          await _reach(tester, row, within: list);
          _expectTappable(tester, row);
        }

        // Условие удалённого тега сохраняет надобность, объявляет пометку
        // удаления и остаётся доступным для снятия.
        final deletedToggle = _conditionToggle(deleted.id);
        await _reach(tester, deletedToggle);
        _expectTappable(tester, deletedToggle);
        expect(
          tester.getSemantics(deletedToggle).label,
          l10n.intentionTagConditionDeletedSemantics(
            l10n.intentionTagConditionAbsentSemantics(deleted.name.value),
          ),
        );
        expect(
          find.descendant(
            of: deletedToggle,
            matching: find.text(
              l10n.intentionTagConditionDeleted(
                l10n.intentionTagConditionAbsent(deleted.name.value),
              ),
            ),
          ),
          findsOneWidget,
        );
        final deletedRemove = _conditionRemove(deleted.id);
        await _reach(tester, deletedRemove);
        _expectTappable(tester, deletedRemove);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await tester.tap(deletedRemove);
        await tester.pump();
        expect(
          container.read(conditionsProvider).conditions,
          hasLength(_initialConditions - 1),
        );

        // Поиск и изменение условий не выполняют команд графа, кроме
        // удаления тега, подтверждённого самим сценарием.
        expect(repository.tagCommands, hasLength(1));
        expect(repository.commands, isEmpty);
        expect(repository.relationCommands, isEmpty);
        expect(repository.dailyChoiceCommands, isEmpty);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}

/// Проверяет открытый экран поиска тега: поле поиска, отметки выбранных
/// тегов, действия «Есть» и «Нет» каждого тега и ориентиры доступности.
Future<void> _expectTagConditionPickerAccessible(
  WidgetTester tester,
  AppLocalizations l10n,
) async {
  expect(tester.takeException(), isNull);
  final search = find.byKey(const ValueKey('tag-condition-picker-search'));
  await _reach(tester, search);
  _expectTappable(tester, search);
  expect(
    find.bySemanticsLabel(RegExp(RegExp.escape(l10n.tagCatalogSearch))),
    findsWidgets,
  );
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));

  for (final (index, tag) in _tags.indexed) {
    final name = tag.name.value;
    final row = find.byKey(
      ValueKey('tag-condition-picker-row-${tag.id.toCanonicalString()}'),
    );
    final present = _pickerAction(tag, IntentionTagRequirement.mustBePresent);
    final absent = _pickerAction(tag, IntentionTagRequirement.mustBeAbsent);
    await _reach(tester, present, within: _pickerList);
    _expectTappable(tester, present);
    expect(
      tester.getSemantics(present),
      isSemantics(
        label: l10n.tagConditionPickerPresentNamed(name),
        isButton: true,
        hasTapAction: true,
      ),
    );
    await _reach(tester, absent, within: _pickerList);
    _expectTappable(tester, absent);
    expect(
      tester.getSemantics(absent),
      isSemantics(
        label: l10n.tagConditionPickerAbsentNamed(name),
        isButton: true,
        hasTapAction: true,
      ),
    );
    _expectNotTruncated(
      tester,
      find.descendant(
        of: row,
        matching: find.byKey(const ValueKey('tag-condition-picker-name')),
      ),
    );
    // Тег, уже входящий в условия, отмечен текущей надобностью.
    final mark = switch (index) {
      >= _initialConditions => null,
      _ when index.isEven => l10n.tagConditionPickerSelectedPresent,
      _ => l10n.tagConditionPickerSelectedAbsent,
    };
    expect(
      find.descendant(
        of: row,
        matching: find.text(l10n.tagConditionPickerSelectedPresent),
      ),
      mark == l10n.tagConditionPickerSelectedPresent
          ? findsOneWidget
          : findsNothing,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text(l10n.tagConditionPickerSelectedAbsent),
      ),
      mark == l10n.tagConditionPickerSelectedAbsent
          ? findsOneWidget
          : findsNothing,
    );
  }
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  expect(tester.takeException(), isNull);
}

final _pickerList = find.byKey(const ValueKey('tag-condition-picker-list'));

/// Общая прокрутка параметров поиска и выдачи страницы поиска.
final _pageScrollable = find
    .descendant(
      of: find.byType(IntentionSearchLayout),
      matching: find.byType(Scrollable),
    )
    .first;

/// Доводит элемент до видимой области прокруткой.
///
/// Лениво создаваемый элемент сначала находится жестами: прокруткой страницы
/// до списка [within] и самого списка на [delta], а параметры поиска —
/// прокруткой страницы к началу. Затем все охватывающие области прокрутки
/// показывают элемент.
Future<void> _reach(
  WidgetTester tester,
  Finder finder, {
  Finder? within,
  double delta = 150,
}) async {
  if (within != null && within.evaluate().isEmpty) {
    // Список скрыт за параметрами поиска: сначала прокручивается страница.
    await tester.scrollUntilVisible(
      within,
      150,
      scrollable: _pageScrollable,
      maxScrolls: 200,
    );
  }
  if (within == null && finder.evaluate().isEmpty) {
    // Параметры поиска скрыты за выдачей: страница прокручивается к началу.
    for (
      var attempt = 0;
      attempt < 200 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.dragFrom(
        _visiblePoint(tester, _pageScrollable),
        const Offset(0, 300),
      );
      await tester.pump();
    }
  }
  if (within != null) {
    final scrollable = find
        .descendant(of: within, matching: find.byType(Scrollable))
        .first;
    for (
      var attempt = 0;
      attempt < 200 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.dragFrom(
        _visiblePoint(tester, scrollable),
        Offset(0, -delta),
      );
      await tester.pump();
    }
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
) => IntentionTagCondition(
  tagId: tag.id,
  requirement: requirement,
  name: tag.name,
  isDeleted: false,
);

Finder _conditionToggle(TagId id) => find.byKey(
  ValueKey('intention-tag-condition-toggle-${id.toCanonicalString()}'),
);

Finder _conditionRemove(TagId id) => find.byKey(
  ValueKey('intention-tag-condition-remove-${id.toCanonicalString()}'),
);

Finder _pickerAction(Tag tag, IntentionTagRequirement requirement) =>
    find.byKey(
      ValueKey(
        'tag-condition-picker-${requirement.name}-'
        '${tag.id.toCanonicalString()}',
      ),
    );

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
