import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/catalog/intention_tag_conditions_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';
import '../../../support/tag_positions.dart';

const _screen = Size(390, 844);
const _closeLabel = 'Закрыть поиск';
const _emptyScopeMessage = 'Доступных активных действий нет.';
const _revision = TestCatalogRevision(1);

final _actionField = find.byKey(const ValueKey('daily-choice-action-filter'));
final _filterButton = find.byType(FilterButton);
final _list = find.byKey(
  const PageStorageKey<String>('daily-choice-action-list'),
);

void main() {
  for (final (locale, action, intention) in [
    (const Locale('ru'), 'Выбор действия', 'Выбор намерения'),
    (const Locale('en'), 'Choose an action', 'Choose an intention'),
  ]) {
    for (final (purpose, title, keyPrefix) in [
      (
        SelectDailyChoiceAction(session: IntentionSearchSession()),
        action,
        'daily-choice-action',
      ),
      (
        SelectDailyChoiceSource(session: IntentionSearchSession()),
        intention,
        'daily-choice-source',
      ),
      (
        SelectRelationParticipant(
          selectionContext: RelationParticipantSelectionContext.activeRelation,
          session: IntentionSearchSession(),
        ),
        intention,
        'participant-picker',
      ),
    ]) {
      testWidgets(
        '${locale.languageCode}: $keyPrefix показывает текущие тип и сортировку без прежнего числа до подтверждения новой выдачи',
        (tester) async {
          final ru = locale.languageCode == 'ru';
          final pinned = purpose is SelectDailyChoiceAction;
          final initialTitle = pinned
              ? (ru ? 'Действия' : 'Actions')
              : (ru ? 'Все' : 'All');
          final initialSummary = ru
              ? 'Создание, сначала новые'
              : 'Created, newest first';
          final h = await _open(tester, locale: locale, purpose: purpose);
          final notifier = h.container.read(
            intentionCatalogViewModelProvider(purpose).notifier,
          );

          expect(_header(initialTitle, null), findsOneWidget);
          expect(find.text(initialSummary), findsOneWidget);
          h.repository.complete(0, _firstPage(_actions(3), totalCount: 13));
          await tester.pump();
          await tester.pump();
          expect(_header(initialTitle, 13), findsOneWidget);

          if (!pinned) {
            notifier.changeType(IntentionTypeChoice.intentions);
            await tester.pump();
            expect(
              _header(ru ? 'Намерения' : 'Intentions', null),
              findsOneWidget,
            );
            expect(find.text(initialSummary), findsOneWidget);
            h.repository.complete(
              h.repository.queries.length - 1,
              _firstPage(const []),
            );
            await tester.pumpAndSettle();
            expect(_header(ru ? 'Намерения' : 'Intentions', 0), findsOneWidget);
            notifier.changeType(IntentionTypeChoice.actions);
            await tester.pump();
            expect(_header(ru ? 'Действия' : 'Actions', null), findsOneWidget);
            h.repository.complete(
              h.repository.queries.length - 1,
              _firstPage(_actions(2)),
            );
            await tester.pumpAndSettle();
          }

          for (final (order, ruSummary, enSummary) in [
            (
              IntentionCatalogOrder.createdAtAscending,
              'Создание, сначала старые',
              'Created, oldest first',
            ),
            (
              IntentionCatalogOrder.updatedAtAscending,
              'Изменение, сначала старые',
              'Changed, oldest first',
            ),
            (
              IntentionCatalogOrder.updatedAtDescending,
              'Изменение, сначала новые',
              'Changed, newest first',
            ),
            (
              IntentionCatalogOrder.titleAscending,
              'Название, от А до Я',
              'Name, A to Z',
            ),
            (
              IntentionCatalogOrder.titleDescending,
              'Название, от Я до А',
              'Name, Z to A',
            ),
          ]) {
            notifier.changeOrder(order);
            await tester.pump();
            expect(_header(ru ? 'Действия' : 'Actions', null), findsOneWidget);
            expect(find.text(ru ? ruSummary : enSummary), findsOneWidget);
          }
          h.repository.complete(
            h.repository.queries.length - 1,
            const ResultFailure(IntentionUnavailableFailure()),
          );
          await tester.pumpAndSettle();
          expect(_header(ru ? 'Действия' : 'Actions', null), findsOneWidget);
          expect(
            find.text(ru ? 'Название, от Я до А' : 'Name, Z to A'),
            findsOneWidget,
          );
        },
      );

      testWidgets('${locale.languageCode}: шапка «$title» с крестиком, '
          'который закрывает экран', (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await _open(tester, locale: locale, purpose: purpose);

        expect(
          tester.getSemantics(_title(title)),
          isSemantics(label: title, isHeader: true),
        );
        expect(find.byKey(ValueKey('$keyPrefix-filter')), findsOneWidget);
        expect(
          tester.getSemantics(find.byKey(ValueKey('$keyPrefix-cancel'))),
          isSemantics(label: _closeLabel, isButton: true, hasTapAction: true),
        );
        await tester.tap(find.byKey(ValueKey('$keyPrefix-cancel')));
        await tester.pump(const Duration(seconds: 1));

        expect(h.closes, 1);
        semantics.dispose();
      });
    }
  }

  for (final (locale, done, unfiltered, filtered) in [
    (
      const Locale('ru'),
      'Готово',
      'Фильтр по тегам',
      'Фильтр по тегам, 2 условия',
    ),
    (
      const Locale('en'),
      'Done',
      'Filter by tags',
      'Filter by tags, 2 conditions',
    ),
  ]) {
    testWidgets('${locale.languageCode}: кнопка фильтра показывает число '
        'условий', (tester) async {
      final semantics = tester.ensureSemantics();
      final health = _tag(1, 'Здоровье');
      final sport = _tag(2, 'Спорт');
      final h = await _open(tester, locale: locale, tags: [health, sport]);
      h.repository.complete(0, _firstPage(_actions(3)));
      await tester.pumpAndSettle();
      expect(tester.widget<FilterButton>(_filterButton).count, 0);
      expect(
        tester.getSemantics(_filterButton),
        isSemantics(label: unfiltered, isButton: true, hasTapAction: true),
      );

      await tester.tap(_filterButton);
      await tester.pumpAndSettle();
      await tester.tap(_panelRow(health));
      await tester.pump();
      // Первое нажатие требует тег, второе исключает его.
      await tester.tap(_panelRow(sport));
      await tester.pump();
      await tester.tap(_panelRow(sport));
      await tester.pump();
      await tester.tap(find.text(done));
      await tester.pump();
      h.repository.complete(
        h.repository.queries.length - 1,
        _firstPage(const []),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<FilterButton>(_filterButton).count, 2);
      expect(
        tester.getSemantics(_filterButton),
        isSemantics(label: filtered, isButton: true, hasTapAction: true),
      );
      // Под полем поиска условий нет: названия тегов не показаны нигде.
      expect(find.text('Здоровье'), findsNothing);
      expect(find.text('Спорт'), findsNothing);
      expect(
        h.repository.queries.last.tagFilter,
        IntentionTagFilter(
          requiredTagIds: [health.id],
          excludedTagIds: [sport.id],
        ),
      );
      semantics.dispose();
    });
  }

  for (final (locale, texts) in [
    (
      const Locale('ru'),
      (
        actions: 'Действия',
        intentions: 'Все',
        byTitle: (
          'Нет действий с таким названием',
          'Попробуйте название короче.',
        ),
        byTags: (
          'Нет действий под эти теги',
          'Измените теги в фильтре или сбросьте его.',
        ),
        byBoth: (
          'Ничего не найдено',
          'Измените название или условия по тегам.',
        ),
        scope: 'Выбрать не из чего',
        reset: 'Сбросить фильтры',
      ),
    ),
    (
      const Locale('en'),
      (
        actions: 'Actions',
        intentions: 'All',
        byTitle: ('No actions with this name', 'Try a shorter name.'),
        byTags: (
          'No actions match these tags',
          'Change the tags in the filter or reset it.',
        ),
        byBoth: ('Nothing found', 'Change the name or the tag conditions.'),
        scope: 'Nothing to choose from',
        reset: 'Reset filters',
      ),
    ),
  ]) {
    final lang = locale.languageCode;
    for (final (scenario, purpose, filter, required, header, message, reset)
        in [
          (
            'пустая выдача по названию советует название короче',
            SelectDailyChoiceAction(session: IntentionSearchSession()),
            'бег',
            false,
            texts.actions,
            texts.byTitle,
            true,
          ),
          (
            'пустая выдача по условиям отличается от пустого охвата',
            SelectDailyChoiceAction(session: IntentionSearchSession()),
            '',
            true,
            texts.actions,
            texts.byTags,
            true,
          ),
          (
            'пустая выдача называет обе причины',
            SelectDailyChoiceSource(session: IntentionSearchSession()),
            'бег',
            true,
            texts.intentions,
            texts.byBoth,
            true,
          ),
          (
            'пустой охват без фильтров не предлагает сброс',
            SelectDailyChoiceAction(session: IntentionSearchSession()),
            '',
            false,
            texts.actions,
            (texts.scope, _emptyScopeMessage),
            false,
          ),
        ]) {
      testWidgets('$lang: $scenario', (tester) async {
        final sport = _tag(1, 'Спорт');
        final h = await _open(tester, locale: locale, purpose: purpose);
        final prefix = switch (purpose) {
          SelectDailyChoiceAction() => 'daily-choice-action',
          SelectDailyChoiceSource() => 'daily-choice-source',
          SelectRelationParticipant() => 'participant-picker',
        };
        await tester.enterText(find.byKey(ValueKey('$prefix-filter')), filter);
        if (required) {
          h.conditions(purpose).cycle(sport, snapshotRevision: _revision);
        }
        await tester.pump(const Duration(milliseconds: 300));
        h.repository.complete(
          h.repository.queries.length - 1,
          _firstPage(const []),
        );
        await tester.pumpAndSettle();

        final (title, text) = message;
        expect(_header(header, 0), findsOneWidget);
        expect(_inEmptyState(title), findsOneWidget);
        expect(_inEmptyState(text), findsOneWidget);
        expect(
          _inEmptyState(texts.reset),
          reset ? findsOneWidget : findsNothing,
        );
      });
    }

    testWidgets('$lang: «${texts.reset}» снимает название и условия', (
      tester,
    ) async {
      final sport = _tag(1, 'Спорт');
      final work = _tag(2, 'Работа');
      final purpose = SelectDailyChoiceAction(
        session: IntentionSearchSession(),
      );
      final h = await _open(tester, locale: locale, purpose: purpose);
      await tester.enterText(_actionField, 'бег');
      final conditions = h.conditions(purpose)
        ..cycle(sport, snapshotRevision: _revision)
        // Второй шаг круга исключает тег.
        ..cycle(work, snapshotRevision: _revision)
        ..cycle(work, snapshotRevision: _revision);
      await tester.pump(const Duration(milliseconds: 300));
      h.repository.complete(
        h.repository.queries.length - 1,
        _firstPage(const []),
      );
      await tester.pumpAndSettle();
      expect(conditions.current.conditions, hasLength(2));

      await tester.tap(_inEmptyState(texts.reset));
      await tester.pump();
      final query = h.repository.queries.last;
      expect(query.titleFilter, isNull);
      expect(query.tagFilter, IntentionTagFilter.empty);
      expect(query.cursor, isNull);
      h.repository.complete(
        h.repository.queries.length - 1,
        _firstPage(_actions(3)),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: _actionField,
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        isEmpty,
      );
      expect(tester.widget<FilterButton>(_filterButton).count, 0);
      expect(_header(texts.actions, 3), findsOneWidget);
      expect(_row(3), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
    });
  }

  testWidgets(
    'поле поиска, фильтр и заголовок исходного намерения остаются на месте при прокрутке',
    (tester) async {
      final h = await _open(
        tester,
        purpose: SelectDailyChoiceSource(session: IntentionSearchSession()),
      );
      h.repository.complete(0, _firstPage(_actions(20)));
      await tester.pumpAndSettle();
      final sourceField = find.byKey(
        const ValueKey('daily-choice-source-filter'),
      );
      final sourceList = find.byKey(
        const PageStorageKey<String>('daily-choice-source-list'),
      );
      final field = tester.getRect(sourceField);
      final button = tester.getRect(_filterButton);
      final header = tester.getRect(find.byType(CatalogHeader));
      expect(header.top, field.bottom + 4);
      expect(_header('Все', 20), findsOneWidget);

      await tester.drag(sourceList, const Offset(0, -300));
      await tester.pumpAndSettle();

      expect(tester.getRect(sourceField), field);
      expect(tester.getRect(_filterButton), button);
      expect(tester.getRect(find.byType(CatalogHeader)), header);
    },
  );

  for (final (locale, error) in [
    (const Locale('ru'), 'Используйте не более 255 символов.'),
    (const Locale('en'), 'Use no more than 255 characters.'),
  ]) {
    testWidgets('${locale.languageCode}: недопустимый фильтр показан строкой '
        'поля без выдачи', (tester) async {
      final h = await _open(tester, locale: locale);
      h.repository.complete(0, _firstPage(_actions(3)));
      await tester.pumpAndSettle();

      await tester.enterText(_actionField, 'а' * 256);
      await tester.pump();
      expect(
        _header(locale.languageCode == 'ru' ? 'Действия' : 'Actions', null),
        findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _actionField, matching: find.text(error)),
        findsOneWidget,
      );
      expect(
        _header(locale.languageCode == 'ru' ? 'Действия' : 'Actions', null),
        findsOneWidget,
      );
      expect(find.byWidgetPredicate((w) => w is ListState), findsNothing);
      expect(find.text('Действие 1'), findsNothing);
    });
  }

  testWidgets('при тексте масштаба 2 и открытой клавиатуре шапка, поле и '
      'первая строка видны, а список прокручивается', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final h = await _open(tester);
    h.repository.complete(0, _firstPage(_actions(10)));
    await tester.pumpAndSettle();
    await tester.showKeyboard(_actionField);
    const keyboard = 336.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    const aboveKeyboard = 844.0 - keyboard;
    final bar = tester.getRect(find.byType(TopBar));
    final field = tester.getRect(_actionField);
    final firstRow = tester.getRect(_row(10));
    expect(bar.top, greaterThanOrEqualTo(0));
    expect(field.top, greaterThanOrEqualTo(bar.bottom));
    expect(firstRow.top, greaterThan(field.bottom));
    expect(firstRow.bottom, lessThanOrEqualTo(aboveKeyboard));
    expect(tester.getRect(_list).bottom, lessThanOrEqualTo(aboveKeyboard));

    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(
      tester
          .state<ScrollableState>(
            find.descendant(of: _list, matching: find.byType(Scrollable)),
          )
          .position
          .pixels,
      greaterThan(0),
    );
    expect(tester.getRect(_actionField), field);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name}: при пустом поле поиска цели касания не '
        'меньше tap-min, подписаны и контрастны', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _open(tester, brightness: brightness);
      h.repository.complete(0, _firstPage(_actions(3)));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantics.dispose();
    });
  }
}

Finder _title(String text) =>
    find.descendant(of: find.byType(TopBar), matching: find.text(text));

Finder _header(String title, int? count) => find.byWidgetPredicate(
  (widget) =>
      widget is CatalogHeader && widget.title == title && widget.count == count,
);

Finder _inEmptyState(String text) =>
    find.descendant(of: find.byType(EmptyState), matching: find.text(text));

Finder _row(int index) => find.byKey(
  ValueKey('daily-choice-action-${_action(index).id.toCanonicalString()}'),
);

Finder _panelRow(Tag tag) =>
    find.byKey(ValueKey('tags-panel-row-${tag.id.toCanonicalString()}'));

IntentionSummary _action(int index) => testSummary(
  index: index,
  title: 'Действие $index',
  readiness: IntentionReadiness.ready,
);

/// Сводки действий в порядке выдачи: от новых к старым.
List<IntentionSummary> _actions(int count) => [
  for (var index = count; index >= 1; index--) _action(index),
];

Result<IntentionCatalogPage> _firstPage(
  List<IntentionSummary> items, {
  int? totalCount,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: totalCount ?? items.length,
    nextCursor: (totalCount ?? items.length) > items.length
        ? const TestCatalogCursor()
        : null,
    revision: const TestCatalogRevision(1),
  ),
);

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(number),
);

final class _Harness {
  _Harness(this.container, this.repository);

  final ProviderContainer container;
  final ControlledCatalogRepository repository;
  int closes = 0;

  IntentionTagConditionsViewModel conditions(IntentionPickerPurpose purpose) =>
      container.read(intentionTagConditionsViewModelProvider(purpose).notifier);
}

Future<_Harness> _open(
  WidgetTester tester, {
  Locale locale = const Locale('ru'),
  Brightness brightness = Brightness.light,
  IntentionPickerPurpose? purpose,
  List<Tag>? tags,
}) async {
  tester.view
    ..physicalSize = _screen
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ControlledCatalogRepository()..tagCatalogItems = tags;
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  final h = _Harness(container, repository);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: doableTheme(brightness),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IntentionPickerView(
          purpose:
              purpose ??
              SelectDailyChoiceAction(session: IntentionSearchSession()),
          closeLabel: _closeLabel,
          emptyScopeMessage: _emptyScopeMessage,
          onClose: () => h.closes++,
          onPick: (_) {},
          onOpenDetails: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}
