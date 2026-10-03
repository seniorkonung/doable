import 'package:auto_route/auto_route.dart';
import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/favorite/application/favorite_intentions.dart';
import 'package:doable/src/favorite/application/favorite_order_command.dart';
import 'package:doable/src/favorite/domain/favorite_order.dart';
import 'package:doable/src/favorite/presentation/home/home_page.dart';
import 'package:doable/src/favorite/presentation/home/home_state.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_test_support.dart';

const _titles = {1: 'А', 2: 'Б', 3: 'В', 4: 'Г', 5: 'Д'};

const _saving = 'Новое место сохраняется…';
const _handleTooltip = 'Перетащите, чтобы переместить намерение';

// Системные названия действий перемещения строк списка.
const _moveToStart = 'Переместить в начало';
const _moveUp = 'Переместить вверх';
const _moveDown = 'Переместить вниз';
const _moveToEnd = 'Переместить в конец';

/// Перестановка ручкой на странице Главной над управляемыми границей и
/// чтением избранного.
///
/// Намерения 1 «А», 2 «Б», 3 «В» и 4 «Г» избранные в этом порядке и показаны
/// списком на ревизии 1; тестовая граница исполняет перестановку функцией
/// правила над тем же полным порядком. Маршрутизатор теста знает только
/// Главную и пустую страницу намерения.
void main() {
  group('ручка перемещения', () {
    testWidgets('каждая строка списка получает ручку в конце строки, а '
        'список — устойчивые ключи идентификаторов намерений', (tester) async {
      await _pumpLoadedHome(tester);

      expect(find.byType(SliverReorderableList), findsOneWidget);
      expect(find.byType(ReorderableDelayedDragStartListener), findsNothing);
      expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));
      for (final number in [1, 2, 3, 4]) {
        final row = find.byKey(ValueKey(homeTestIntentionId(number)));
        expect(row, findsOneWidget);
        expect(tester.widget(row), isA<HomeIntentionRow>());
        final handle = _handle(number);
        expect(handle, findsOneWidget);
        expect(
          find.descendant(
            of: row,
            matching: find.byType(ReorderableDragStartListener),
          ),
          findsOneWidget,
        );
        // Ручка стоит после содержимого строки, у её конца, и в её высоте.
        final rowRect = tester.getRect(row);
        final contentRect = tester.getRect(
          find.descendant(of: row, matching: find.byType(ListTile)),
        );
        final handleRect = tester.getRect(handle);
        expect(handleRect.left, greaterThanOrEqualTo(contentRect.right));
        expect(handleRect.right, greaterThan(rowRect.right - 16));
        expect(handleRect.top, greaterThanOrEqualTo(rowRect.top));
        expect(handleRect.bottom, lessThanOrEqualTo(rowRect.bottom));
        expect(handleRect.width, greaterThanOrEqualTo(48));
        expect(handleRect.height, greaterThanOrEqualTo(48));
      }
      // Список по-прежнему без звёзд и снятия отметки.
      expect(find.byIcon(Icons.star), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets('долгое нажатие строки не начинает перетаскивание, а нажатие '
        'строки открывает её намерение', (tester) async {
      final h = await _pumpLoadedHome(tester);
      final rowHeight = tester.getSize(_row(1)).height;

      final gesture = await tester.startGesture(tester.getCenter(_title(1)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(Offset(0, rowHeight / 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(h.repository.moves, isEmpty);
      expect(_shownTitles(tester), ['А', 'Б', 'В', 'Г']);
      expect(h.router.current.name, HomeRoute.name);

      await tester.tap(_title(3));
      await tester.pumpAndSettle();

      expect(h.router.current.name, IntentionDetailsRoute.name);
      expect(
        h.router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
        homeTestIntentionId(3),
      );
    });
  });

  group('перетаскивание ручкой передаёт перемещение по идентификаторам', () {
    for (final (name, moved, places, anchor, shown) in [
      ('на одно место ниже', 1, 1, 2, ['Б', 'А', 'В', 'Г']),
      ('на одно место выше', 4, -1, 2, ['А', 'Б', 'Г', 'В']),
      ('на несколько мест выше', 4, -2, 1, ['А', 'Г', 'Б', 'В']),
      ('на несколько мест ниже', 1, 2, 3, ['Б', 'В', 'А', 'Г']),
      ('в начало списка', 3, -2, null, ['В', 'А', 'Б', 'Г']),
      ('в конец списка', 1, 3, 4, ['Б', 'В', 'Г', 'А']),
    ]) {
      testWidgets('$name: намерение ставится '
          '${anchor == null ? 'первым' : 'после «${_titles[anchor]}»'}, а '
          'список показывает запрошенное положение с признаком сохранения', (
        tester,
      ) async {
        final h = await _pumpLoadedHome(tester);

        await _dragHandle(tester, moved, places);

        final command = h.repository.moves.single.command;
        expect(command.intentionId, homeTestIntentionId(moved));
        switch (command.placement) {
          case FirstFavoritePlacement():
            expect(anchor, isNull);
          case AfterFavoritePlacement(:final anchorId):
            expect(anchorId, homeTestIntentionId(anchor!));
        }
        expect(_shownTitles(tester), shown);
        _expectSaving(tester, moved);
        _expectHandles(tester, enabled: false);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('отпускание строки на прежнем месте не отправляет '
        'перемещение', (tester) async {
      final h = await _pumpLoadedHome(tester);
      final rowHeight = tester.getSize(_row(2)).height;

      final gesture = await tester.startGesture(tester.getCenter(_handle(2)));
      for (final dy in [rowHeight / 4, rowHeight / 4, -rowHeight / 2]) {
        await gesture.moveBy(Offset(0, dy));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(h.repository.moves, isEmpty);
      expect(_shownTitles(tester), ['А', 'Б', 'В', 'Г']);
      expect(find.text(_saving), findsNothing);
      _expectHandles(tester, enabled: true);
    });
  });

  group('сохранение нового положения', () {
    testWidgets('запрошенное положение сохраняется до цельного снимка, а '
        'подтверждённый успех показывает новый порядок без отдельного '
        'сообщения', (tester) async {
      final h = await _pumpLoadedHome(tester);

      await _dragHandle(tester, 4, -2);
      expect(_shownTitles(tester), ['А', 'Г', 'Б', 'В']);
      _expectSaving(tester, 4);

      // Запись подтверждена, а цельного снимка с ней ещё нет.
      h.repository.completeMove(0, revision: 2);
      await tester.pumpAndSettle();
      expect(
        (h.harness.state as HomeList).reorder,
        isA<HomeReorderAwaitingSnapshot>(),
      );
      expect(h.repository.readCount, 2);
      expect(_shownTitles(tester), ['А', 'Г', 'Б', 'В']);
      _expectSaving(tester, 4);
      _expectHandles(tester, enabled: false);

      h.repository.completeRead(1, items: _rows([1, 4, 2, 3]), revision: 2);
      await tester.pumpAndSettle();

      expect(_shownTitles(tester), ['А', 'Г', 'Б', 'В']);
      expect(find.text(_saving), findsNothing);
      _expectHandles(tester, enabled: true);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('сохранён'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('отказ записи возвращает подтверждённый порядок без признака '
        'сохранения и без сообщения на странице', (tester) async {
      final h = await _pumpLoadedHome(tester);
      await _dragHandle(tester, 4, -2);

      h.repository.failMove(0, const FavoriteOrderUnavailableFailure());
      await tester.pumpAndSettle();

      expect(_shownTitles(tester), ['А', 'Б', 'В', 'Г']);
      expect(find.text(_saving), findsNothing);
      _expectHandles(tester, enabled: true);
      // Отказ принадлежит общей поверхности, а не Главной.
      expect(find.textContaining('порядок'), findsNothing);
      expect(h.repository.readCount, 1);
    });

    testWidgets('конфликт возвращает подтверждённый порядок и приводит '
        'список к актуальному без повторной отправки', (tester) async {
      final h = await _pumpLoadedHome(tester);
      await _dragHandle(tester, 4, -2);

      h.repository.failMove(0, const FavoriteOrderConflictFailure());
      await tester.pumpAndSettle();

      expect(_shownTitles(tester), ['А', 'Б', 'В', 'Г']);
      expect(find.text(_saving), findsNothing);
      _expectHandles(tester, enabled: false);

      h.repository.completeRead(1, items: _rows([1, 3, 4]), revision: 3);
      await tester.pumpAndSettle();

      expect(_shownTitles(tester), ['А', 'В', 'Г']);
      _expectHandles(tester, enabled: true);
      expect(h.repository.moves, hasLength(1));
    });
  });

  group('ручки и встроенные действия перестановки недоступны', () {
    for (final (name, block, unblock)
        in <
          (
            String,
            Future<void> Function(WidgetTester, _Home),
            Future<void> Function(WidgetTester, _Home),
          )
        >[
          (
            'во время записи',
            (tester, h) => _dragHandle(tester, 4, -2),
            (tester, h) async => h.repository.failMove(
              0,
              const FavoriteOrderUnavailableFailure(),
            ),
          ),
          (
            'в ожидании актуального снимка после записи',
            (tester, h) async {
              await _dragHandle(tester, 4, -2);
              h.repository.completeMove(0, revision: 2);
            },
            (tester, h) async => h.repository.completeRead(
              1,
              items: _rows([1, 4, 2, 3]),
              revision: 2,
            ),
          ),
          (
            'во время обновления списка',
            (tester, h) => _confirmMark(tester, h, revision: 2),
            (tester, h) async => h.repository.completeRead(
              1,
              items: _rows([1, 2, 3, 4, 5]),
              revision: 2,
            ),
          ),
          (
            'при неактуальном списке',
            (tester, h) async {
              await _confirmMark(tester, h, revision: 2);
              h.repository.failRead(
                1,
                const FavoriteIntentionsUnavailableFailure(),
              );
            },
            (tester, h) async {
              await tester.tap(find.text('Повторить'));
              await tester.pump();
              h.repository.completeRead(
                2,
                items: _rows([1, 2, 3, 4, 5]),
                revision: 2,
              );
            },
          ),
        ]) {
      testWidgets('$name, а после восстановления снова доступны', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final h = await _pumpLoadedHome(tester);
        expect(_moveActionNodes(), findsNWidgets(4));

        await block(tester, h);
        await tester.pumpAndSettle();

        _expectHandles(tester, enabled: false);
        expect(_moveActionNodes(), findsNothing);
        final shown = _shownTitles(tester);
        final moves = h.repository.moves.length;
        await _dragHandle(tester, 1, 1);
        expect(h.repository.moves, hasLength(moves));
        expect(_shownTitles(tester), shown);

        await unblock(tester, h);
        await tester.pumpAndSettle();

        _expectHandles(tester, enabled: true);
        expect(_moveActionNodes(), findsWidgets);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    testWidgets('перетаскивание, во время которого список перестал принимать '
        'перестановку, прекращается без перемещения', (tester) async {
      final h = await _pumpLoadedHome(tester);
      final rowHeight = tester.getSize(_row(1)).height;

      final gesture = await tester.startGesture(tester.getCenter(_handle(1)));
      for (var step = 0; step < 3; step++) {
        await gesture.moveBy(Offset(0, rowHeight / 4));
        await tester.pump();
      }
      await _confirmMark(tester, h, revision: 2);
      await tester.pump();
      for (var step = 0; step < 3; step++) {
        await gesture.moveBy(Offset(0, rowHeight / 4));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(h.repository.moves, isEmpty);
      expect(_shownTitles(tester), ['А', 'Б', 'В', 'Г']);
      expect(tester.takeException(), isNull);

      h.repository.completeRead(1, items: _rows([1, 2, 3, 4, 5]), revision: 2);
      await tester.pumpAndSettle();
      await _dragHandle(tester, 5, -1);
      expect(
        h.repository.moves.single.command.intentionId,
        homeTestIntentionId(5),
      );
    });
  });

  group('экранный диктор', () {
    testWidgets('строка объявляется одним узлом с названием, готовностью, '
        'числом активных связей, переходом и системными действиями '
        'перемещения без невозможных у крайних строк', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpLoadedHome(tester);

      final expected = {
        1: {_moveDown, _moveToEnd},
        2: {_moveToStart, _moveUp, _moveDown, _moveToEnd},
        3: {_moveToStart, _moveUp, _moveDown, _moveToEnd},
        4: {_moveToStart, _moveUp},
      };
      for (final MapEntry(key: number, value: actions) in expected.entries) {
        final data = _rowNode(number).evaluate().single.getSemanticsData();
        expect(data.hasAction(SemanticsAction.tap), isTrue);
        expect(_customActions(data), actions, reason: _titles[number]);
      }
      // Других узлов с действиями перемещения нет.
      expect(_moveActionNodes(), findsNWidgets(4));
      semantics.dispose();
    });

    for (final (action, number, anchor, shown) in [
      (_moveUp, 3, 1, ['А', 'В', 'Б', 'Г']),
      (_moveDown, 1, 2, ['Б', 'А', 'В', 'Г']),
      (_moveToStart, 4, null, ['Г', 'А', 'Б', 'В']),
      (_moveToEnd, 2, 4, ['А', 'В', 'Г', 'Б']),
    ]) {
      testWidgets('действие «$action» у «${_titles[number]}» ставит его '
          '${anchor == null ? 'первым' : 'после «${_titles[anchor]}»'} без '
          'перетаскивания, а строки объявляются в показанном порядке с '
          'признаком сохранения и без действий перемещения', (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await _pumpLoadedHome(tester);

        tester.semantics.customAction(
          _rowNode(number),
          CustomSemanticsAction(label: action),
        );
        await tester.pumpAndSettle();

        final command = h.repository.moves.single.command;
        expect(command.intentionId, homeTestIntentionId(number));
        switch (command.placement) {
          case FirstFavoritePlacement():
            expect(anchor, isNull);
          case AfterFavoritePlacement(:final anchorId):
            expect(anchorId, homeTestIntentionId(anchor!));
        }
        expect(_shownTitles(tester), shown);
        final labels = [
          for (final title in shown)
            _rowLabel(title, saving: title == _titles[number]),
        ];
        expect([
          for (final node in tester.semantics.simulatedAccessibilityTraversal())
            if (labels.contains(node.label)) node.label,
        ], labels);
        expect(_moveActionNodes(), findsNothing);
        semantics.dispose();
      });
    }

    testWidgets('новое место объявляется живой областью только после '
        'цельного снимка, подтвердившего запись, и не показывается на '
        'экране', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpLoadedHome(tester);
      const announcement = '«Г» теперь на месте 2 из 4';

      await _dragHandle(tester, 4, -2);
      expect(_announcements(), findsNothing);

      h.repository.completeMove(0, revision: 2);
      await tester.pumpAndSettle();
      expect(_announcements(), findsNothing);

      h.repository.completeRead(1, items: _rows([1, 4, 2, 3]), revision: 2);
      await tester.pumpAndSettle();

      final node = _announcements().evaluate().single;
      expect(node.label, announcement);
      expect(node.flagsCollection.isLiveRegion, isTrue);
      // Успех предъявляется новым порядком: отдельного сообщения на экране
      // нет.
      expect(find.textContaining('теперь на месте'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(_shownTitles(tester), ['А', 'Г', 'Б', 'В']);

      // Объявление длится столько же, сколько общее сообщение, и затем
      // исчезает, чтобы не повторяться при возвращении на Главную.
      await tester.pump(const Duration(seconds: 3));
      expect(_announcements(), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(_announcements(), findsNothing);
      semantics.dispose();
    });

    for (final (name, complete) in <(String, void Function(_Home h))>[
      (
        'отказ записи',
        (h) =>
            h.repository.failMove(0, const FavoriteOrderUnavailableFailure()),
      ),
      (
        'успех без изменения',
        (h) {
          h.repository.favoriteOrder = homeTestOrder([1, 4, 2, 3]);
          h.repository.completeMove(0, revision: 1);
        },
      ),
      (
        'конфликт актуального состояния',
        (h) {
          h.repository.favoriteOrder = homeTestOrder([2, 3, 4]);
          h.repository.completeMove(0, revision: 1);
        },
      ),
    ]) {
      testWidgets('$name не объявляет новое место', (tester) async {
        final semantics = tester.ensureSemantics();
        final h = await _pumpLoadedHome(tester);
        await _dragHandle(tester, 4, -2);

        complete(h);
        await tester.pumpAndSettle();
        if (h.repository.readCount > 1) {
          h.repository.completeRead(1, items: _rows([2, 3, 4]), revision: 2);
          await tester.pumpAndSettle();
        }

        expect(_announcements(), findsNothing);
        semantics.dispose();
      });
    }

    testWidgets('то же объявление после следующей подтверждённой '
        'перестановки звучит заново новым узлом живой области', (tester) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpLoadedHome(tester);
      const announcement = '«Г» теперь на месте 2 из 4';
      await _dragHandle(tester, 4, -2);
      h.repository.completeMove(0, revision: 2);
      await tester.pumpAndSettle();
      h.repository.completeRead(1, items: _rows([1, 4, 2, 3]), revision: 2);
      await tester.pumpAndSettle();
      final first = _announcements().evaluate().single;
      expect(first.label, announcement);

      // Отметка Д и снятие отметки А ставят Г первым из четырёх без
      // объявления: объявленный текст остаётся прежним.
      h.repository.favoriteOrder = homeTestOrder([4, 2, 3, 5]);
      await _confirmMark(tester, h, revision: 3);
      await _confirmUnmark(tester, h, 1, revision: 4);
      h.repository.completeRead(2, items: _rows([4, 2, 3, 5]), revision: 4);
      await tester.pumpAndSettle();
      expect(_shownTitles(tester), ['Г', 'Б', 'В', 'Д']);
      expect(_announcements().evaluate().single.id, first.id);
      expect(_announcements().evaluate().single.label, announcement);

      // Перемещение Г после Б снова даёт место 2 из 4.
      tester.semantics.customAction(
        find.semantics.byLabel(_rowLabel('Г')),
        const CustomSemanticsAction(label: _moveDown),
      );
      await tester.pumpAndSettle();
      // Координатор после подтверждённых команд намерения завершает
      // перестановку в настоящем цикле событий.
      await tester.runAsync(() async {
        h.repository.completeMove(1, revision: 5);
        await pumpEventQueue();
      });
      await tester.pumpAndSettle();
      h.repository.completeRead(3, items: _rows([2, 4, 3, 5]), revision: 5);
      await tester.pumpAndSettle();

      final second = _announcements().evaluate().single;
      expect(second.label, announcement);
      expect(second.id, isNot(first.id));
      semantics.dispose();
    });

    testWidgets('объявление нового места на языке интерфейса: en', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final h = await _pumpLoadedHome(tester, locale: 'en');
      tester.semantics.customAction(
        find.semantics.byLabel(
          _rowLabel('Г', l10n: lookupAppLocalizations(const Locale('en'))),
        ),
        const CustomSemanticsAction(label: 'Move up'),
      );
      await tester.pumpAndSettle();
      h.repository.completeMove(0, revision: 2);
      await tester.pumpAndSettle();
      h.repository.completeRead(1, items: _rows([1, 2, 4, 3]), revision: 2);
      await tester.pumpAndSettle();

      expect(
        _announcements(RegExp('is now in position')).evaluate().single.label,
        '“Г” is now in position 3 of 4',
      );
      semantics.dispose();
    });
  });

  group('позиция прокрутки', () {
    testWidgets('запрошенное положение, подтверждённый снимок и отказ '
        'перестановки не сбрасывают позицию прокрутки', (tester) async {
      final h = await _pumpHome(tester);
      final numbers = [for (var i = 1; i <= 40; i++) i];
      h.repository.favoriteOrder = homeTestOrder(numbers);
      h.repository.completeRead(0, items: _manyRows(numbers));
      await tester.pumpAndSettle();
      await tester.drag(_listScrollable, const Offset(0, -1500));
      await tester.pumpAndSettle();
      final offset = _scrollOffset(tester);
      expect(offset, greaterThan(0));

      final moved = _middleVisibleRow(tester);
      await _dragHandle(tester, moved, 1);
      expect(
        h.repository.moves.single.command.intentionId,
        homeTestIntentionId(moved),
      );
      expect(_scrollOffset(tester), offset);

      h.repository.completeMove(0, revision: 2);
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester), offset);
      final order = [
        for (final id in h.repository.favoriteOrder.intentionIds)
          numbers.firstWhere((n) => homeTestIntentionId(n) == id),
      ];
      h.repository.completeRead(1, items: _manyRows(order), revision: 2);
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester), offset);
      expect(find.text(_saving), findsNothing);

      await _dragHandle(tester, _middleVisibleRow(tester), -1);
      h.repository.failMove(1, const FavoriteOrderUnavailableFailure());
      await tester.pumpAndSettle();
      expect(_scrollOffset(tester), offset);
      _expectHandles(tester, enabled: true);
    });
  });

  group('локализация', () {
    for (final (locale, tooltip, saving) in [
      ('ru', _handleTooltip, _saving),
      ('en', 'Drag to move the intention', 'Saving the new position…'),
    ]) {
      testWidgets('ручка и состояние сохранения на языке интерфейса: $locale', (
        tester,
      ) async {
        await _pumpLoadedHome(tester, locale: locale);

        expect(find.byTooltip(tooltip), findsNWidgets(4));

        await _dragHandle(tester, 4, -2);
        expect(
          find.descendant(of: _row(4), matching: find.text(saving)),
          findsOneWidget,
        );
      });
    }

    test('объявление подтверждённого нового места есть в обеих локалях и '
        'сохраняет название намерения без изменения', () {
      expect(
        lookupAppLocalizations(const Locale('ru'))
            .homeReorderMoved('Быть Здоровым', 2, 5),
        '«Быть Здоровым» теперь на месте 2 из 5',
      );
      expect(
        lookupAppLocalizations(const Locale('en'))
            .homeReorderMoved('Быть Здоровым', 2, 5),
        '“Быть Здоровым” is now in position 2 of 5',
      );
    });
  });
}

typedef _Home = ({
  HomeTestRepository repository,
  HomeHarness harness,
  _TestRouter router,
});

/// Маршрутизатор с Главной и пустой страницей намерения.
final class _TestRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, initial: true),
    AutoRoute(
      page: PageInfo(
        IntentionDetailsRoute.name,
        builder: (_) => const SizedBox.shrink(),
      ),
    ),
  ];
}

Future<_Home> _pumpHome(WidgetTester tester, {String locale = 'ru'}) async {
  final harness = HomeHarness();
  addTearDown(harness.dispose);
  final router = _TestRouter();
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: harness.container,
      child: MaterialApp.router(
        routerConfig: router.config(),
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
  expect(find.byType(HomePage), findsOneWidget);
  return (repository: harness.repository, harness: harness, router: router);
}

/// Главная со списком А, Б, В, Г на ревизии 1; тестовая граница хранит тот
/// же полный порядок.
Future<_Home> _pumpLoadedHome(
  WidgetTester tester, {
  String locale = 'ru',
}) async {
  final h = await _pumpHome(tester, locale: locale);
  h.repository.favoriteOrder = homeTestOrder([1, 2, 3, 4]);
  h.repository.completeRead(0, items: _rows([1, 2, 3, 4]));
  await tester.pumpAndSettle();
  expect(_shownTitles(tester), ['А', 'Б', 'В', 'Г']);
  return h;
}

List<FavoriteIntentionRow> _rows(List<int> numbers) => [
  for (final number in numbers) homeTestRow(number, _titles[number]!),
];

List<FavoriteIntentionRow> _manyRows(List<int> numbers) => [
  for (final number in numbers) homeTestRow(number, 'Намерение $number'),
];

/// Подтверждённая отметка намерения 5 «Д» на ревизии [revision]: пакет
/// требует обновления списка.
///
/// Координатор завершает команду в настоящем цикле событий, поэтому она
/// проводится вне поддельного времени теста.
Future<void> _confirmMark(
  WidgetTester tester,
  _Home h, {
  required int revision,
}) => tester.runAsync(
  () => h.harness.confirm(
    MarkIntentionFavorite(homeTestIntentionId(5)),
    revision: revision,
    before: homeTestSummary(5, 'Д', favoriteMark: FavoriteMark.notFavorite),
    after: homeTestSummary(5, 'Д'),
  ),
);

/// Подтверждённое снятие отметки намерения [number] на ревизии [revision].
Future<void> _confirmUnmark(
  WidgetTester tester,
  _Home h,
  int number, {
  required int revision,
}) => tester.runAsync(
  () => h.harness.confirm(
    UnmarkIntentionFavorite(homeTestIntentionId(number)),
    revision: revision,
    before: homeTestSummary(number, _titles[number]!),
    after: homeTestSummary(
      number,
      _titles[number]!,
      favoriteMark: FavoriteMark.notFavorite,
    ),
  ),
);

Finder _row(int number) => find.byKey(ValueKey(homeTestIntentionId(number)));

/// Название, готовность, признак сохранения и число активных связей строки
/// одним текстом — так строку объявляет экранный диктор.
String _rowLabel(String title, {bool saving = false, AppLocalizations? l10n}) {
  final localizations = l10n ?? lookupAppLocalizations(const Locale('ru'));
  return [
    title,
    localizations.catalogNotReady,
    if (saving) localizations.homeReorderSaving,
    localizations.intentionActiveRelationCount(0),
  ].join('\n');
}

/// Узел семантики строки намерения [number] без признака сохранения.
SemanticsFinder _rowNode(int number) =>
    find.semantics.byLabel(_rowLabel(_titles[number]!));

/// Названия действий перемещения узла.
Set<String> _customActions(SemanticsData data) => {
  for (final id in data.customSemanticsActionIds ?? const <int>[])
    CustomSemanticsAction.getAction(id)!.label!,
};

/// Узлы живой области с объявлением нового места намерения.
SemanticsFinder _announcements([Pattern? text]) =>
    find.semantics.byLabel(text ?? RegExp('теперь на месте'));

Finder _title(int number) =>
    find.descendant(of: _row(number), matching: find.text(_titles[number]!));

/// Ручка строки намерения [number].
Finder _handle(int number) =>
    find.descendant(of: _row(number), matching: find.byIcon(Icons.drag_handle));

/// Узлы семантики со встроенными действиями перемещения строк.
SemanticsFinder _moveActionNodes() =>
    find.semantics.byAction(SemanticsAction.customAction);

/// Названия строк Главной в порядке, в котором их видит человек.
List<String> _shownTitles(WidgetTester tester) {
  final rows = [
    for (final element in find.byType(HomeIntentionRow).evaluate())
      (
        top: (element.renderObject! as RenderBox).localToGlobal(Offset.zero).dy,
        title: (element.widget as HomeIntentionRow).row.title,
      ),
  ]..sort((a, b) => a.top.compareTo(b.top));
  return [for (final row in rows) row.title];
}

/// Только строка перемещаемого намерения показывает, что её новое место
/// сохраняется.
void _expectSaving(WidgetTester tester, int moved) {
  expect(find.text(_saving), findsOneWidget);
  expect(
    find.descendant(of: _row(moved), matching: find.text(_saving)),
    findsOneWidget,
  );
}

/// Каждая построенная строка показывает ручку: доступная начинает
/// перетаскивание, а недоступная показана приглушённой и перетаскивание не
/// начинает. Встроенная перестановка списка существует только вместе с
/// доступными ручками.
void _expectHandles(WidgetTester tester, {required bool enabled}) {
  final rows = find.byType(HomeIntentionRow).evaluate().length;
  expect(rows, greaterThan(0));
  final icons = find.byIcon(Icons.drag_handle);
  expect(icons, findsNWidgets(rows));
  final theme = Theme.of(tester.element(find.byType(HomePage)));
  for (final icon in tester.widgetList<Icon>(icons)) {
    expect(icon.color, enabled ? isNull : theme.disabledColor);
  }
  expect(
    find.byType(ReorderableDragStartListener),
    enabled ? findsNWidgets(rows) : findsNothing,
  );
  expect(
    find.byType(SliverReorderableList),
    enabled ? findsOneWidget : findsNothing,
  );
}

/// Перетаскивает строку намерения [number] ручкой на [places] мест: вниз при
/// положительном числе, вверх — при отрицательном.
///
/// Перетаскиваемая строка занимает место соседней, когда её край заходит за
/// середину соседней строки, поэтому смещение на три четверти высоты строки
/// на каждое место однозначно задаёт новое место.
Future<void> _dragHandle(WidgetTester tester, int number, int places) async {
  final rowHeight = tester.getSize(_row(number)).height;
  final distance = (places.abs() - 0.25) * rowHeight * places.sign;
  final gesture = await tester.startGesture(tester.getCenter(_handle(number)));
  const steps = 10;
  for (var step = 0; step < steps; step++) {
    await gesture.moveBy(Offset(0, distance / steps));
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Прокрутка списка избранных намерений, а не места пометки над ним.
final _listScrollable = find.descendant(
  of: find.byType(CustomScrollView),
  matching: find.byType(Scrollable),
);

double _scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(_listScrollable).position.pixels;

/// Номер строки, которая целиком видна в середине области просмотра списка
/// вместе с соседями: её перемещение на одно место не доходит до краёв, у
/// которых список прокручивается сам.
int _middleVisibleRow(WidgetTester tester) {
  final viewport = tester.getRect(_listScrollable);
  final rows = [
    for (final element in find.byType(HomeIntentionRow).evaluate())
      (
        rect: tester.getRect(find.byWidget(element.widget)),
        title: (element.widget as HomeIntentionRow).row.title,
      ),
  ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
  final visible = [
    for (final row in rows)
      if (row.rect.top >= viewport.top && row.rect.bottom <= viewport.bottom)
        row,
  ];
  expect(visible.length, greaterThanOrEqualTo(3));
  final middle = visible[visible.length ~/ 2];
  return int.parse(middle.title.split(' ').last);
}
