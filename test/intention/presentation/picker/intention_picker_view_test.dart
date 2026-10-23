import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/filter_button.dart';
import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
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
    ]) {
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

  testWidgets('поле поиска и кнопка фильтра остаются на месте при прокрутке, '
      'а заголовок выдачи уходит вверх вместе со строками', (tester) async {
    final h = await _open(tester);
    h.repository.complete(0, _firstPage(_actions(20)));
    await tester.pumpAndSettle();
    final field = tester.getRect(_actionField);
    final button = tester.getRect(_filterButton);
    final header = tester.getRect(find.byType(CatalogHeader));
    final listTop = tester.getRect(_list).top;
    expect(listTop, field.bottom + 8);

    await tester.drag(_list, const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(tester.getRect(_actionField), field);
    expect(tester.getRect(_filterButton), button);
    expect(tester.getRect(_list).top, listTop);
    expect(
      tester.getRect(find.byType(CatalogHeader, skipOffstage: false)).top,
      lessThan(header.top),
    );
  });

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
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: _actionField, matching: find.text(error)),
        findsOneWidget,
      );
      expect(find.byType(CatalogHeader), findsNothing);
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

Result<IntentionCatalogPage> _firstPage(List<IntentionSummary> items) =>
    ResultSuccess(
      IntentionCatalogFirstPage(
        items: items,
        totalCount: items.length,
        nextCursor: null,
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
  _Harness(this.repository);

  final ControlledCatalogRepository repository;
  int closes = 0;
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
  final h = _Harness(repository);
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
          emptyScopeMessage: 'Доступных активных действий нет.',
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
