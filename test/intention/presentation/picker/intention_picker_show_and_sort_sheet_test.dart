import 'dart:async';
import 'dart:ui' show CheckedState, Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_show_and_sort_sheet.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  for (final locale in [const Locale('ru'), const Locale('en')]) {
    final ru = locale.languageCode == 'ru';
    testWidgets(
      '${locale.languageCode}: выбор типа сразу меняет список, а количества учитывают поиск',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final purpose = SelectDailyChoiceSource(
          session: IntentionSearchSession(),
        );
        final h = await _open(tester, purpose, locale);
        final model = h.container.read(
          intentionCatalogViewModelProvider(purpose).notifier,
        );
        model.changeTitleFilter('чит');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(h.repository.queries, hasLength(2));
        final action = testSummary(
          index: 3,
          title: 'Читать книгу',
          readiness: IntentionReadiness.ready,
        );
        final intentions = [
          testSummary(index: 2, title: 'Читать чаще'),
          testSummary(index: 1, title: 'Читать лучше'),
        ];
        await _show(tester, purpose);

        final all = ru ? 'Всё' : 'All';
        final intentionsOnly = ru ? 'Только намерения' : 'Intentions only';
        final actions = ru ? 'Только действия' : 'Actions only';
        expect(
          find.text(
            ru
                ? 'Список меняется по мере выбора'
                : 'The list changes as you choose',
          ),
          findsOneWidget,
        );
        _selectedType(tester, all);
        await _openTypes(tester, ru);
        _menuChecked(tester, all);
        expect(_menuText('3'), findsNothing);
        expect(_menuText('2'), findsNothing);
        expect(_menuText('1'), findsNothing);

        h.repository.complete(
          h.repository.queries.length - 1,
          _page([action, ...intentions]),
        );
        await tester.pumpAndSettle();
        _menuChecked(tester, '$all\n3');
        expect(_menuOption(intentionsOnly), findsOneWidget);
        expect(_menuText('2'), findsOneWidget);
        expect(_menuText('1'), findsOneWidget);
        await tester.tap(_menuOption(actions));
        await tester.pump();
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNothing);
        _selectedType(tester, actions);
        await _openTypes(tester, ru);
        _menuChecked(tester, actions);
        expect(_menuText('3'), findsNothing);
        expect(_menuText('2'), findsNothing);
        expect(_menuText('1'), findsNothing);
        expect(find.text(ru ? 'Сбросить' : 'Reset'), findsOneWidget);
        _header(
          tester,
          ru ? 'Действия' : 'Actions',
          ru ? 'Создание, сначала новые' : 'Created, newest first',
        );
        expect(
          h.repository.queries.last.readinessFilter,
          IntentionReadinessFilter.readyOnly,
        );
        expect(
          h.repository.queries.last.titleFilter?.map((value) => value),
          'чит',
        );

        h.repository.complete(
          h.repository.queries.length - 1,
          _page([action], all: 3, actions: 1),
        );
        await tester.pumpAndSettle();
        _menuChecked(tester, '$actions\n1');
        expect(_menuText('3'), findsOneWidget);
        expect(_menuText('2'), findsOneWidget);
        await tester.tap(_menuOption(actions));
        await tester.pumpAndSettle();
        await _close(tester);
        expect(find.text('Читать книгу'), findsOneWidget);
        expect(find.text('Читать чаще'), findsNothing);
        expect(find.text('Читать лучше'), findsNothing);
        final header = tester.widget<CatalogHeader>(find.byType(CatalogHeader));
        expect(header.count, 1);
        semantics.dispose();
      },
    );

    testWidgets(
      '${locale.languageCode}: открытое меню убирает прежние количества при новом поиске и после отказа',
      (tester) async {
        final purpose = SelectDailyChoiceSource(
          session: IntentionSearchSession(),
        );
        final h = await _open(tester, purpose, locale);
        h.repository.complete(0, _page([testSummary(index: 1)]));
        await tester.pumpAndSettle();
        await _show(tester, purpose);
        await _openTypes(tester, ru);
        expect(_menuText('1'), findsNWidgets(2));
        expect(_menuText('0'), findsOneWidget);

        h.container
            .read(intentionCatalogViewModelProvider(purpose).notifier)
            .changeTitleFilter('чит');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNWidgets(3));
        expect(_menuText('1'), findsNothing);
        expect(_menuText('0'), findsNothing);
        h.repository.complete(
          h.repository.queries.length - 1,
          const ResultFailure(IntentionUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNWidgets(3));
        expect(_menuText('1'), findsNothing);
        expect(_menuText('0'), findsNothing);
        expect(_menuOption(ru ? 'Всё' : 'All'), findsOneWidget);
        expect(
          _menuOption(ru ? 'Только намерения' : 'Intentions only'),
          findsOneWidget,
        );
        expect(
          _menuOption(ru ? 'Только действия' : 'Actions only'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '${locale.languageCode}: повторный тип сохраняет выдачу и прокрутку, новый возвращает список к началу',
      (tester) async {
        final purpose = SelectRelationParticipant(
          selectionContext: RelationParticipantSelectionContext.activeRelation,
          session: IntentionSearchSession(),
        );
        final h = await _open(tester, purpose, locale);
        final items = [
          for (var i = 10; i > 0; i--)
            testSummary(index: i, readiness: IntentionReadiness.ready),
        ];
        h.repository.complete(0, _page(items));
        await tester.pumpAndSettle();
        final list = find.byKey(
          const PageStorageKey<String>('participant-picker-list'),
        );
        await tester.drag(list, const Offset(0, -200));
        await tester.pumpAndSettle();
        final position = _position(tester, list).pixels;
        expect(position, greaterThan(0));
        await _show(tester, purpose);
        await _openTypes(tester, ru);
        await tester.tap(_menuOption(ru ? 'Всё' : 'All'));
        await tester.pumpAndSettle();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(h.repository.queries, hasLength(1));
        expect(_position(tester, list).pixels, position);
        expect(
          tester.widget<CatalogHeader>(find.byType(CatalogHeader)).count,
          10,
        );
        expect(find.byType(Sheet), findsOneWidget);

        await _openTypes(tester, ru);
        await tester.tap(_menuOption(ru ? 'Только действия' : 'Actions only'));
        await tester.pump();
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(find.byType(Sheet), findsOneWidget);
        expect(h.repository.queries, hasLength(2));
        h.repository.complete(1, _page(items));
        await tester.pumpAndSettle();
        await _close(tester);
        expect(_position(tester, list).pixels, 0);
      },
    );

    testWidgets(
      '${locale.languageCode}: выбранный тип и пункты с количествами целиком переносятся при крупном тексте',
      (tester) async {
        final purpose = SelectDailyChoiceSource(
          session: IntentionSearchSession(),
        );
        final h = await _open(
          tester,
          purpose,
          locale,
          width: ru ? 390 : 320,
          textScale: 2,
        );
        h.container
            .read(intentionCatalogViewModelProvider(purpose).notifier)
            .changeType(IntentionTypeChoice.intentions);
        await tester.pump();
        h.repository.complete(
          h.repository.queries.length - 1,
          _page([testSummary(index: 1)], all: 123, actions: 122),
        );
        await tester.pumpAndSettle();
        await _show(tester, purpose);
        await tester.pumpAndSettle();
        final selected = _option(ru ? 'Только намерения' : 'Intentions only');
        final row = tester.getRect(_typeButton(ru));
        _wholeText(tester, selected, row, wraps: true);
        await _openTypes(tester, ru);
        for (final (label, count) in [
          (ru ? 'Всё' : 'All', '123'),
          (ru ? 'Только намерения' : 'Intentions only', '1'),
          (ru ? 'Только действия' : 'Actions only', '122'),
        ]) {
          final item = _menuOption(label);
          final bounds = tester.getRect(item);
          final name = find.descendant(of: item, matching: find.text(label));
          final number = find.descendant(of: item, matching: find.text(count));
          _wholeText(tester, name, bounds, wraps: count != '123');
          _wholeText(tester, number, bounds);
          expect(
            tester.getRect(name).right,
            lessThan(tester.getRect(number).left),
          );
        }
      },
    );

    testWidgets(
      '${locale.languageCode}: поле и направление меняются по последнему выбору до ответа новой порции',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final purpose = SelectDailyChoiceSource(
          session: IntentionSearchSession(),
        );
        final h = await _open(tester, purpose, locale);
        h.container
            .read(intentionCatalogViewModelProvider(purpose).notifier)
            .changeOrder(IntentionCatalogOrder.createdAtAscending);
        await tester.pump();
        h.repository.complete(
          h.repository.queries.length - 1,
          _page([testSummary(index: 1)]),
        );
        await tester.pumpAndSettle();
        await _show(tester, purpose);

        final all = ru ? 'Все' : 'All';
        final created = ru ? 'Дата создания' : 'Date created';
        final changed = ru ? 'Дата изменения' : 'Date changed';
        final name = ru ? 'Название' : 'Name';
        final oldest = ru ? 'Сначала старые' : 'Oldest first';
        final newest = ru ? 'Сначала новые' : 'Newest first';
        final aToZ = ru ? 'От А до Я' : 'A to Z';
        final zToA = ru ? 'От Я до А' : 'Z to A';
        _checked(tester, oldest);

        for (final (label, directionLabel, expectedOrder, summary) in [
          (
            changed,
            oldest,
            IntentionCatalogOrder.updatedAtAscending,
            ru ? 'Изменение, сначала старые' : 'Changed, oldest first',
          ),
          (
            created,
            oldest,
            IntentionCatalogOrder.createdAtAscending,
            ru ? 'Создание, сначала старые' : 'Created, oldest first',
          ),
          (
            name,
            aToZ,
            IntentionCatalogOrder.titleAscending,
            ru ? 'Название, от А до Я' : 'Name, A to Z',
          ),
          (
            changed,
            newest,
            IntentionCatalogOrder.updatedAtDescending,
            ru ? 'Изменение, сначала новые' : 'Changed, newest first',
          ),
        ]) {
          await tester.tap(_option(label));
          await tester.pump();
          _checked(tester, label);
          _checked(tester, directionLabel);
          _selectedType(tester, ru ? 'Всё' : 'All');
          expect(_option('1'), findsNothing);
          expect(find.text(ru ? 'Сбросить' : 'Reset'), findsOneWidget);
          _header(tester, all, summary);
          expect(h.repository.queries.last.order, expectedOrder);
        }
        await tester.tap(_option(oldest));
        await tester.pump();
        _checked(tester, oldest);
        _header(
          tester,
          all,
          ru ? 'Изменение, сначала старые' : 'Changed, oldest first',
        );
        expect(
          h.repository.queries.last.order,
          IntentionCatalogOrder.updatedAtAscending,
        );

        await tester.tap(_option(name));
        await tester.pump();
        _checked(tester, aToZ);
        expect(_option(oldest), findsNothing);
        expect(_option(newest), findsNothing);
        await tester.tap(_option(zToA));
        await tester.pump();
        _checked(tester, zToA);
        _header(tester, all, ru ? 'Название, от Я до А' : 'Name, Z to A');
        expect(
          h.repository.queries.last.order,
          IntentionCatalogOrder.titleDescending,
        );
        semantics.dispose();
      },
    );

    testWidgets(
      '${locale.languageCode}: сброс сразу возвращает начальный показ и верх списка, сохраняя поиск',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final purpose = SelectRelationParticipant(
          selectionContext: RelationParticipantSelectionContext.activeRelation,
          session: IntentionSearchSession(),
        );
        final h = await _open(tester, purpose, locale);
        final model = h.container.read(
          intentionCatalogViewModelProvider(purpose).notifier,
        );
        model.changeTitleFilter('Читать');
        model.changeType(IntentionTypeChoice.actions);
        model.changeOrder(IntentionCatalogOrder.titleDescending);
        await tester.pump();
        final items = [
          for (var i = 10; i > 0; i--)
            testSummary(
              index: i,
              title: 'Читать ${i.toString().padLeft(2, '0')}',
              readiness: IntentionReadiness.ready,
            ),
        ];
        h.repository.complete(h.repository.queries.length - 1, _page(items));
        await tester.pumpAndSettle();
        final list = find.byKey(
          const PageStorageKey<String>('participant-picker-list'),
        );
        await tester.drag(list, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(_position(tester, list).pixels, greaterThan(0));
        await _show(tester, purpose);
        _checked(tester, ru ? 'От Я до А' : 'Z to A');

        await tester.tap(_option(ru ? 'Сбросить' : 'Reset'));
        await tester.pump();
        _selectedType(tester, ru ? 'Всё' : 'All');
        _checked(tester, ru ? 'Дата создания' : 'Date created');
        _checked(tester, ru ? 'Сначала новые' : 'Newest first');
        expect(_option(ru ? 'Сбросить' : 'Reset'), findsNothing);
        expect(_option('10'), findsNothing);
        _header(
          tester,
          ru ? 'Все' : 'All',
          ru ? 'Создание, сначала новые' : 'Created, newest first',
        );
        expect(
          h.repository.queries.last.order,
          IntentionCatalogOrder.createdAtDescending,
        );
        expect(
          h.repository.queries.last.readinessFilter,
          IntentionReadinessFilter.all,
        );
        expect(
          h.repository.queries.last.titleFilter?.map((value) => value),
          'Читать',
        );

        h.repository.complete(h.repository.queries.length - 1, _page(items));
        await tester.pumpAndSettle();
        await _close(tester);
        expect(_position(tester, list).pixels, 0);
        semantics.dispose();
      },
    );

    testWidgets(
      '${locale.languageCode}: тип действия закреплён, остальные группы доступны и лист проходит проверки доступности',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final purpose = SelectDailyChoiceAction(
          session: IntentionSearchSession(),
        );
        final h = await _open(
          tester,
          purpose,
          locale,
          brightness: ru ? Brightness.light : Brightness.dark,
        );
        final items = [
          testSummary(index: 1, readiness: IntentionReadiness.ready),
        ];
        h.repository.complete(0, _page(items));
        await tester.pumpAndSettle();
        await _show(tester, purpose);
        final actions = ru ? 'Только действия' : 'Actions only';
        final note = ru
            ? 'Конечным в дневном выборе может быть только действие'
            : 'Only an action can be the final intention of a daily choice';
        _selectedType(tester, actions);
        expect(_option(note), findsOneWidget);
        final group = tester.getSemantics(
          find.bySemanticsLabel(ru ? 'Тип' : 'Type'),
        );
        expect(group.flagsCollection.isEnabled, Tristate.isFalse);
        expect(group.value, actions);
        expect(group.hint, note);
        expect(_option('1'), findsNothing);
        await tester.tap(_option(actions));
        await tester.pump();
        expect(find.byType(MenuItemButton), findsNothing);
        expect(_option(ru ? 'Всё' : 'All'), findsNothing);
        expect(h.repository.queries, hasLength(1));
        expect(_option(ru ? 'Сбросить' : 'Reset'), findsNothing);

        await tester.tap(_option(ru ? 'Название' : 'Name'));
        await tester.pump();
        _selectedType(tester, actions);
        _checked(tester, ru ? 'От А до Я' : 'A to Z');
        h.repository.complete(h.repository.queries.length - 1, _page(items));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(_option(ru ? 'Сбросить' : 'Reset'));
        await tester.pump();
        _selectedType(tester, actions);
        _checked(tester, ru ? 'Дата создания' : 'Date created');
        _checked(tester, ru ? 'Сначала новые' : 'Newest first');
        expect(_option(ru ? 'Сбросить' : 'Reset'), findsNothing);
        expect(
          h.repository.queries.last.readinessFilter,
          IntentionReadinessFilter.readyOnly,
        );
        semantics.dispose();
      },
    );
  }
}

ScrollPosition _position(WidgetTester tester, Finder list) => tester
    .state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    )
    .position;

Finder _option(String label) =>
    find.descendant(of: find.byType(Sheet), matching: find.text(label));

Finder _typeButton(bool ru) => find.descendant(
  of: find.byType(Sheet),
  matching: find.widgetWithText(InkWell, ru ? 'Тип' : 'Type'),
);

Finder _menuText(String label) => find.descendant(
  of: find.byType(MenuItemButton),
  matching: find.text(label),
);

Finder _menuOption(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(MenuItemButton));

Future<void> _openTypes(WidgetTester tester, bool ru) async {
  await tester.tap(_typeButton(ru));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void _selectedType(WidgetTester tester, String value) {
  expect(tester.getSemantics(_option(value)).value, value);
}

void _menuChecked(WidgetTester tester, String label) {
  final node = tester
      .getSemantics(find.bySemanticsLabel(label))
      .getSemanticsData();
  expect(node.label, label);
  expect(node.flagsCollection.isChecked, CheckedState.isTrue);
}

void _wholeText(
  WidgetTester tester,
  Finder text,
  Rect bounds, {
  bool wraps = false,
}) {
  final rect = tester.getRect(text);
  expect(bounds.contains(rect.topLeft), isTrue);
  expect(bounds.contains(rect.bottomRight), isTrue);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.didExceedMaxLines, isFalse);
  final painter = TextPainter(
    text: paragraph.text,
    textAlign: paragraph.textAlign,
    textDirection: paragraph.textDirection,
    textScaler: paragraph.textScaler,
    locale: paragraph.locale,
    strutStyle: paragraph.strutStyle,
    textWidthBasis: paragraph.textWidthBasis,
    textHeightBehavior: paragraph.textHeightBehavior,
  )..layout(maxWidth: paragraph.size.width);
  expect(rect.height, closeTo(painter.height, 0.01));
  if (wraps) expect(painter.computeLineMetrics().length, greaterThan(1));
  painter.dispose();
}

void _checked(WidgetTester tester, String label) {
  final node = tester.getSemantics(_option(label.split('\n').first));
  expect(node.label, label);
  expect(node.flagsCollection.isChecked, CheckedState.isTrue);
}

void _header(WidgetTester tester, String title, String summary) {
  final header = tester.widget<CatalogHeader>(find.byType(CatalogHeader));
  expect(header.title, title);
  expect(header.summary, summary);
  expect(header.count, isNull);
}

Future<void> _show(WidgetTester tester, IntentionPickerPurpose purpose) async {
  unawaited(
    showIntentionPickerShowAndSortSheet(
      tester.element(find.byType(IntentionPickerView)),
      purpose,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _close(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(Sheet))).pop();
  await tester.pumpAndSettle();
}

Result<IntentionCatalogPage> _page(
  List<IntentionSummary> items, {
  int? all,
  int? actions,
}) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: items,
    totalCount: items.length,
    typeCounts: all == null
        ? null
        : IntentionTypeCounts(all: all, actions: actions!),
    nextCursor: null,
    revision: const TestCatalogRevision(1),
  ),
);

Future<({ProviderContainer container, ControlledCatalogRepository repository})>
_open(
  WidgetTester tester,
  IntentionPickerPurpose purpose,
  Locale locale, {
  Brightness brightness = Brightness.light,
  double width = 390,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        theme: doableTheme(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IntentionPickerView(
          purpose: purpose,
          closeLabel: 'Закрыть поиск',
          emptyScopeMessage: 'Выбрать не из чего',
          onClose: () {},
          onPick: (_) {},
          onOpenDetails: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  return (container: container, repository: repository);
}
