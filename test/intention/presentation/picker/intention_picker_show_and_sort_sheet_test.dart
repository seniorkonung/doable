import 'dart:async';
import 'dart:ui' show CheckedState, SemanticsRole, Tristate;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/components/order_button.dart';
import 'package:doable/src/design_system/components/select_row.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_state.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_show_and_sort_sheet.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_view.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
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
      '${locale.languageCode}: закрытие любого меню сохраняет выдачу и прокрутку, направление применяется отдельным нажатием',
      (tester) async {
        final purpose = SelectRelationParticipant(
          selectionContext: RelationParticipantSelectionContext.activeRelation,
          session: IntentionSearchSession(),
        );
        final h = await _open(tester, purpose, locale);
        h.container
            .read(intentionCatalogViewModelProvider(purpose).notifier)
            .changeOrder(IntentionCatalogOrder.titleAscending);
        await tester.pump();
        final items = [
          for (var i = 1; i <= 14; i++)
            testSummary(
              index: i,
              title: 'Намерение ${i.toString().padLeft(2, '0')}',
            ),
        ];
        h.repository.complete(h.repository.queries.length - 1, _page(items));
        await tester.pumpAndSettle();
        final list = find.byKey(
          const PageStorageKey<String>('participant-picker-list'),
        );
        await tester.drag(list, const Offset(0, -200));
        await tester.pumpAndSettle();
        final position = _position(tester, list).pixels;
        expect(position, greaterThan(0));
        final requests = h.repository.queries.length;
        await _show(tester, purpose);

        void unchanged() {
          expect(find.byType(MenuItemButton), findsNothing);
          expect(find.byType(Sheet), findsOneWidget);
          expect(h.repository.queries, hasLength(requests));
          expect(_position(tester, list).pixels, position);
          final header = tester.widget<CatalogHeader>(
            find.byType(CatalogHeader),
          );
          expect(header.count, items.length);
          expect(header.summary, ru ? 'Название, от А до Я' : 'Name, A to Z');
        }

        for (final open in [_openTypes, _openSort]) {
          await open(tester, ru);
          expect(find.byType(MenuItemButton), findsNWidgets(3));
          await tester.tap(find.byType(OrderButton));
          await tester.pumpAndSettle();
          unchanged();
          await open(tester, ru);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();
          unchanged();
        }
        await _openTypes(tester, ru);
        await _openSort(tester, ru);
        unchanged();
        await _openSort(tester, ru);
        expect(find.byType(MenuItemButton), findsNWidgets(3));
        expect(_menuOption(ru ? 'Всё' : 'All'), findsNothing);
        await tester.tap(_menuOption(ru ? 'Название' : 'Name'));
        await tester.pumpAndSettle();
        unchanged();
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(Sheet), findsNothing);
        expect(_position(tester, list).pixels, position);

        await _show(tester, purpose);
        await tester.tap(find.byType(OrderButton));
        await tester.pump();
        expect(
          h.repository.queries.last.order,
          IntentionCatalogOrder.titleDescending,
        );
        _header(
          tester,
          ru ? 'Все' : 'All',
          ru ? 'Название, от Я до А' : 'Name, Z to A',
        );
        h.repository.complete(
          h.repository.queries.length - 1,
          _page(items.reversed.toList()),
        );
        await tester.pumpAndSettle();
        await _close(tester);
        expect(_position(tester, list).pixels, 0);
      },
    );

    for (final width in [320.0, 390.0]) {
      for (final textScale in [1.0, 2.0]) {
        for (final pinned in [false, true]) {
          testWidgets(
            '${locale.languageCode}, $width, масштаб $textScale, закреплённый тип $pinned: вся панель и меню читаются целиком',
            (tester) async {
              final purpose = pinned
                  ? SelectDailyChoiceAction(session: IntentionSearchSession())
                  : SelectDailyChoiceSource(session: IntentionSearchSession());
              final h = await _open(
                tester,
                purpose,
                locale,
                width: width,
                textScale: textScale,
              );
              final model = h.container.read(
                intentionCatalogViewModelProvider(purpose).notifier,
              );
              if (!pinned) model.changeType(IntentionTypeChoice.intentions);
              model.changeOrder(IntentionCatalogOrder.updatedAtDescending);
              await tester.pump();
              h.repository.complete(
                h.repository.queries.length - 1,
                _page(
                  [
                    testSummary(
                      index: 1,
                      readiness: pinned
                          ? IntentionReadiness.ready
                          : IntentionReadiness.notReady,
                    ),
                  ],
                  all: 123,
                  actions: pinned ? 1 : 122,
                ),
              );
              await tester.pumpAndSettle();
              await _show(tester, purpose);
              await tester.pumpAndSettle();

              final type = find.byType(SelectRow<IntentionTypeChoice>);
              final sort = find.byType(SelectRow<IntentionCatalogSortField>);
              final typeBounds = tester.getRect(type);
              final sortBounds = tester.getRect(sort);
              final screen = Rect.fromLTWH(0, 0, width, 844);
              final selected = pinned
                  ? (ru ? 'Только действия' : 'Actions only')
                  : (ru ? 'Только намерения' : 'Intentions only');
              for (final (label, value, bounds) in [
                (ru ? 'Тип' : 'Type', selected, typeBounds),
                (
                  ru ? 'Сортировка' : 'Sort by',
                  ru ? 'Дата изменения' : 'Date changed',
                  sortBounds,
                ),
              ]) {
                final caption = _option(label);
                final chosen = _option(value);
                _wholeText(tester, caption, bounds, textScale: textScale);
                _wholeText(tester, chosen, bounds, textScale: textScale);
                expect(
                  tester.getRect(caption).right,
                  lessThan(tester.getRect(chosen).left),
                );
                expect(screen.contains(bounds.topLeft), isTrue);
                expect(screen.contains(bounds.bottomRight), isTrue);
              }
              final button = tester.getRect(find.byType(OrderButton));
              expect(
                tester
                    .getRect(_option(ru ? 'Дата изменения' : 'Date changed'))
                    .right,
                lessThan(button.left),
              );
              expect(typeBounds.bottom, lessThanOrEqualTo(sortBounds.top));
              if (textScale == 2 && width == 320) {
                expect(sortBounds.height, greaterThan(52));
              }
              if (pinned) {
                final note = _option(
                  ru ? 'Конечным в дневном выборе может быть только действие' : 'Only an action can be the final intention of a daily choice',
                );
                _wholeText(tester, note, typeBounds, textScale: textScale);
                expect(
                  tester.getRect(_option(selected)).bottom,
                  lessThan(tester.getRect(note).top),
                );
                expect(tester.getRect(note).bottom, lessThan(sortBounds.top));
              } else {
                await _openTypes(tester, ru);
                final menu = tester.getRect(_menuPanel);
                expect(menu.right, typeBounds.right - 4);
                expect(menu.width, lessThanOrEqualTo(typeBounds.width - 8));
                expect(screen.contains(menu.topLeft), isTrue);
                expect(screen.contains(menu.bottomRight), isTrue);
                for (final (label, count) in [
                  (ru ? 'Всё' : 'All', '123'),
                  (ru ? 'Только намерения' : 'Intentions only', '1'),
                  (ru ? 'Только действия' : 'Actions only', '122'),
                ]) {
                  final item = _menuOption(label);
                  final bounds = tester.getRect(item);
                  final name = find.descendant(
                    of: item,
                    matching: find.text(label),
                  );
                  final number = find.descendant(
                    of: item,
                    matching: find.text(count),
                  );
                  _wholeText(tester, name, bounds, textScale: textScale);
                  _wholeText(tester, number, bounds, textScale: textScale);
                  expect(
                    tester.getRect(name).right,
                    lessThan(tester.getRect(number).left),
                  );
                }
                await tester.binding.handlePopRoute();
                await tester.pumpAndSettle();
              }
              await _openSort(tester, ru);
              final menu = tester.getRect(_menuPanel);
              expect(menu.right, button.right);
              expect(menu.width, lessThanOrEqualTo(sortBounds.width - 8));
              expect(menu.bottom, closeTo(sortBounds.top - 4, 0.01));
              expect(screen.contains(menu.topLeft), isTrue);
              expect(screen.contains(menu.bottomRight), isTrue);
              for (final label in [
                ru ? 'Дата создания' : 'Date created',
                ru ? 'Дата изменения' : 'Date changed',
                ru ? 'Название' : 'Name',
              ]) {
                final item = _menuOption(label);
                _wholeText(
                  tester,
                  find.descendant(of: item, matching: find.text(label)),
                  tester.getRect(item),
                  textScale: textScale,
                );
              }
            },
          );
        }
      }
    }

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
        _direction(tester, ru, oldest, newest, descending: false);

        var selectedField = created;
        for (final (label, directionLabel, nextLabel, expectedOrder, summary)
            in [
              (
                changed,
                oldest,
                newest,
                IntentionCatalogOrder.updatedAtAscending,
                ru ? 'Изменение, сначала старые' : 'Changed, oldest first',
              ),
              (
                created,
                oldest,
                newest,
                IntentionCatalogOrder.createdAtAscending,
                ru ? 'Создание, сначала старые' : 'Created, oldest first',
              ),
              (
                name,
                aToZ,
                zToA,
                IntentionCatalogOrder.titleAscending,
                ru ? 'Название, от А до Я' : 'Name, A to Z',
              ),
              (
                changed,
                newest,
                oldest,
                IntentionCatalogOrder.updatedAtDescending,
                ru ? 'Изменение, сначала новые' : 'Changed, newest first',
              ),
            ]) {
          await _openSort(tester, ru);
          _menuChecked(tester, selectedField);
          expect(_menuText('1'), findsNothing);
          await tester.tap(_menuOption(label));
          await tester.pump();
          await tester.pump();
          expect(find.byType(MenuItemButton), findsNothing);
          expect(find.byType(Sheet), findsOneWidget);
          expect(_option(label), findsOneWidget);
          _direction(
            tester,
            ru,
            directionLabel,
            nextLabel,
            descending:
                expectedOrder.direction ==
                IntentionCatalogSortDirection.descending,
          );
          _selectedType(tester, ru ? 'Всё' : 'All');
          expect(_option('1'), findsNothing);
          expect(find.text(ru ? 'Сбросить' : 'Reset'), findsOneWidget);
          _header(tester, all, summary);
          expect(h.repository.queries.last.order, expectedOrder);
          selectedField = label;
        }
        await tester.tap(find.byType(OrderButton));
        await tester.pump();
        _direction(tester, ru, oldest, newest, descending: false);
        _header(
          tester,
          all,
          ru ? 'Изменение, сначала старые' : 'Changed, oldest first',
        );
        expect(
          h.repository.queries.last.order,
          IntentionCatalogOrder.updatedAtAscending,
        );

        await _openSort(tester, ru);
        await tester.tap(_menuOption(name));
        await tester.pump();
        await tester.pump();
        _direction(tester, ru, aToZ, zToA, descending: false);
        expect(_option(oldest), findsNothing);
        expect(_option(newest), findsNothing);
        await tester.tap(find.byType(OrderButton));
        await tester.pump();
        _direction(tester, ru, zToA, aToZ, descending: true);
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
        final excludedTag = switch (TagId.decode(
          '018f0000-0000-7000-8000-000000000001',
        )) {
          TagIdDecodingSuccess(:final id) => id,
          InvalidTagIdDecoding() => throw StateError(
            'Некорректный ID тега в тесте',
          ),
        };
        final tagFilter = IntentionTagFilter(excludedTagIds: [excludedTag]);
        model.changeTagFilter(tagFilter);
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
        _direction(
          tester,
          ru,
          ru ? 'От Я до А' : 'Z to A',
          ru ? 'От А до Я' : 'A to Z',
          descending: true,
        );

        await tester.tap(_option(ru ? 'Сбросить' : 'Reset'));
        await tester.pump();
        _selectedType(tester, ru ? 'Всё' : 'All');
        expect(_option(ru ? 'Дата создания' : 'Date created'), findsOneWidget);
        _direction(
          tester,
          ru,
          ru ? 'Сначала новые' : 'Newest first',
          ru ? 'Сначала старые' : 'Oldest first',
          descending: true,
        );
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
        expect(h.repository.queries.last.tagFilter.excludedTagIds, {
          excludedTag,
        });

        h.repository.complete(h.repository.queries.length - 1, _page(items));
        await tester.pumpAndSettle();
        await _close(tester);
        expect(_position(tester, list).pixels, 0);
        semantics.dispose();
      },
    );

    testWidgets(
      '${locale.languageCode}: тип действия закреплён, сортировка доступна и лист проходит проверки доступности',
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
          textScale: 2,
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

        await _openSort(tester, ru);
        await tester.tap(_menuOption(ru ? 'Название' : 'Name'));
        await tester.pump();
        await tester.pump();
        _selectedType(tester, actions);
        _direction(
          tester,
          ru,
          ru ? 'От А до Я' : 'A to Z',
          ru ? 'От Я до А' : 'Z to A',
          descending: false,
        );
        h.repository.complete(h.repository.queries.length - 1, _page(items));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));

        await tester.tap(_option(ru ? 'Сбросить' : 'Reset'));
        await tester.pump();
        _selectedType(tester, actions);
        expect(_option(ru ? 'Дата создания' : 'Date created'), findsOneWidget);
        _direction(
          tester,
          ru,
          ru ? 'Сначала новые' : 'Newest first',
          ru ? 'Сначала старые' : 'Oldest first',
          descending: true,
        );
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

final _menuPanel = find.byWidgetPredicate(
  (widget) =>
      widget is Semantics && widget.properties.role == SemanticsRole.menu,
);

Future<void> _openTypes(WidgetTester tester, bool ru) async {
  await tester.tap(_typeButton(ru));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

Future<void> _openSort(WidgetTester tester, bool ru) async {
  await tester.tap(_option(ru ? 'Сортировка' : 'Sort by'));
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
  required double textScale,
}) {
  final rect = tester.getRect(text);
  expect(bounds.contains(rect.topLeft), isTrue);
  expect(bounds.contains(rect.bottomRight), isTrue);
  final paragraph = tester.renderObject<RenderParagraph>(text);
  expect(paragraph.textScaler.scale(10), 10 * textScale);
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
  painter.dispose();
}

void _direction(
  WidgetTester tester,
  bool ru,
  String current,
  String next, {
  required bool descending,
}) {
  final label = ru
      ? 'Текущий порядок: $current. Переключить на: $next'
      : 'Current order: $current. Switch to: $next';
  final node = tester
      .getSemantics(find.bySemanticsLabel(label))
      .getSemanticsData();
  expect(node.label, label);
  expect(node.flagsCollection.isButton, isTrue);
  expect(
    find.descendant(
      of: find.byType(OrderButton),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DoableIcon &&
            widget.icon ==
                (descending ? DoableIconData.sortDesc : DoableIconData.sortAsc),
      ),
    ),
    findsOneWidget,
  );
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
