import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/search_field.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(390, 844);
const _statusBar = 47.0;
const _compact = 534.0;
const _full = 844.0 - _statusBar;
const _growth = _full - _compact;
const _expandLabel = 'Раскрыть на весь экран';
const _collapseLabel = 'Свернуть';
const _homeIndicator = 34.0;
const _resetLabel = 'Сбросить условия по тегам';

void main() {
  testWidgets('на отрезке раскрытия верхний край стоит под пальцем, «Готово» '
      'на месте, а скругление углов следует положению; ниже компактного '
      'размера лист уходит вместе с «Готово», и одно движение закрывает '
      'полный лист', (tester) async {
    final sheet = await _openExpandableSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final footer = tester.getRect(find.text('Готово'));
    final gesture = await _SlowGesture.start(tester, _header);

    for (final rise in [100.0, _growth / 2, _growth, _growth + 60]) {
      await gesture.moveTo(-rise);
      final expected = rise.clamp(0, _growth);
      expect(
        tester.getRect(find.byType(Sheet)).top,
        closeTo(compact.top - expected, 1),
        reason: 'подъём $rise',
      );
      expect(
        tester.getRect(find.text('Готово')),
        footer,
        reason: 'подъём $rise',
      );
    }
    await gesture.moveTo(-_growth / 2);
    expect(_topRadius(tester), inExclusiveRange(0, DoableMetrics.radiusXl));

    for (final depth in [100.0, compact.height * 0.3]) {
      await gesture.moveTo(depth);
      expect(
        tester.getRect(find.byType(Sheet)).top,
        closeTo(compact.top + depth, 1),
        reason: 'глубина $depth',
      );
      expect(_sheetHeight(tester), _compact, reason: 'глубина $depth');
      expect(
        tester.getRect(find.text('Готово')).top,
        closeTo(footer.top + depth, 1),
        reason: 'глубина $depth',
      );
      expect(
        _topRadius(tester),
        DoableMetrics.radiusXl,
        reason: 'глубина $depth',
      );
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);

    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();
    final full = await _SlowGesture.start(tester, _header);
    await full.moveTo(_growth / 2);
    expect(_sheetHeight(tester), closeTo(_full - _growth / 2, 1));
    await full.moveTo(_growth + compact.height * 0.6);
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top + compact.height * 0.6, 1),
    );
    await full.up();
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  for (final scenario
      in <
        ({
          String name,
          bool fromFull,
          Future<void> Function(WidgetTester) release,
          double? height,
        })
      >[
        (
          name: 'бросок вверх из компактного размера раскрывает',
          fromFull: false,
          release: (tester) =>
              tester.fling(_header, const Offset(0, -60), 1000),
          height: _full,
        ),
        (
          name: 'бросок вниз из полного размера сворачивает',
          fromFull: true,
          release: (tester) => tester.fling(_header, const Offset(0, 60), 1000),
          height: _compact,
        ),
        (
          name: 'бросок вниз из компактного размера закрывает',
          fromFull: false,
          release: (tester) => tester.fling(_header, const Offset(0, 60), 1000),
          height: null,
        ),
        (
          name: 'бросок вверх с отрезка сдвига возвращает компактный размер',
          fromFull: false,
          release: (tester) async {
            final gesture = await _SlowGesture.start(tester, _header);
            // Медленное отпускание здесь закрыло бы лист.
            await gesture.moveTo(_compact * 0.7);
            await gesture.flingTo(_compact * 0.6);
          },
          height: _compact,
        ),
        (
          name: 'бросок вниз с отрезка раскрытия сворачивает',
          fromFull: false,
          release: (tester) async {
            final gesture = await _SlowGesture.start(tester, _header);
            // Медленное отпускание здесь раскрыло бы лист.
            await gesture.moveTo(-_growth * 0.8);
            await gesture.flingTo(-_growth * 0.7);
          },
          height: _compact,
        ),
        (
          name: 'медленный подъём меньше чем на половину пути возвращает',
          fromFull: false,
          release: (tester) => _slowDrag(tester, -_growth * 0.4),
          height: _compact,
        ),
        (
          name: 'медленный подъём больше чем на половину пути раскрывает',
          fromFull: false,
          release: (tester) => _slowDrag(tester, -_growth * 0.6),
          height: _full,
        ),
        (
          name: 'медленный спуск меньше чем на половину пути возвращает',
          fromFull: true,
          release: (tester) => _slowDrag(tester, _growth * 0.4),
          height: _full,
        ),
        (
          name: 'медленный спуск больше чем на половину пути сворачивает',
          fromFull: true,
          release: (tester) => _slowDrag(tester, _growth * 0.6),
          height: _compact,
        ),
        (
          name:
              'медленный спуск из полного размера, пока видно больше половины '
              'компактной высоты, сворачивает',
          fromFull: true,
          release: (tester) => _slowDrag(tester, _growth + _compact * 0.4),
          height: _compact,
        ),
        (
          name:
              'медленный спуск из полного размера, пока видно меньше половины '
              'компактной высоты, закрывает',
          fromFull: true,
          release: (tester) => _slowDrag(tester, _growth + _compact * 0.6),
          height: null,
        ),
      ]) {
    testWidgets('раскрываемый лист: ${scenario.name}', (tester) async {
      final sheet = await _openExpandableSheet(tester);
      if (scenario.fromFull) {
        await tester.tap(find.bySemanticsLabel(_expandLabel));
        await tester.pumpAndSettle();
      }

      await scenario.release(tester);
      await tester.pumpAndSettle();

      switch (scenario.height) {
        case final height?:
          expect(_sheetHeight(tester), height);
          expect(tester.getRect(find.byType(Sheet)).bottom, _screen.height);
          expect(_chevron, height == _full ? findsOne : findsNothing);
          expect(sheet.isClosed, isFalse);
        case null:
          expect(find.byType(Sheet), findsNothing);
          expect(sheet.isClosed, isTrue);
      }
    });
  }

  testWidgets('отменённый системой жест возвращает раскрываемый лист в '
      'размер, из которого он начат', (tester) async {
    final sheet = await _openExpandableSheet(tester);

    await _cancelHeaderDrag(tester, const Offset(0, -200));
    expect(_sheetHeight(tester), _compact);

    await _cancelHeaderDrag(tester, const Offset(0, 200));
    expect(tester.getRect(find.byType(Sheet)).bottom, _screen.height);
    expect(_sheetHeight(tester), _compact);

    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();
    await _cancelHeaderDrag(tester, const Offset(0, _growth + 200));
    expect(tester.getRect(find.byType(Sheet)).bottom, _screen.height);
    expect(_sheetHeight(tester), _full);
    expect(_chevron, findsOne);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('второй палец во время раскрытия не меняет размер листа '
      'скачком', (tester) async {
    await _openExpandableSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final first = await _SlowGesture.start(tester, _header);
    await first.moveTo(-100);

    final second = await tester.startGesture(
      tester.getCenter(find.text('Готово')),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top - 100, 1),
    );

    await second.moveBy(const Offset(0, -2));
    await tester.pump();
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top - 102, 1),
    );
    expect(_sheetHeight(tester), closeTo(_compact + 102, 1));

    await second.up();
    await first.up();
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), _compact);
  });

  testWidgets('перетаскивание вверх, начатое на закреплённом поле, раскрывает '
      'лист под пальцем', (tester) async {
    await _openExpandableSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final gesture = await _SlowGesture.start(tester, find.byType(SearchField));

    await gesture.moveTo(-_growth * 0.6);
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top - _growth * 0.6, 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _full);
  });

  testWidgets('перетаскивание вниз, начатое на нижней кнопке, уводит лист '
      'вместе с ней, и кнопка не срабатывает', (tester) async {
    var presses = 0;
    final sheet = await _openExpandableSheet(tester, onDone: () => presses++);
    final compact = tester.getRect(find.byType(Sheet));
    final done = find.widgetWithText(Button, 'Готово');
    final footer = tester.getRect(done);
    final gesture = await _SlowGesture.start(tester, done);

    await gesture.moveTo(compact.height * 0.6);
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top + compact.height * 0.6, 1),
    );
    expect(
      tester.getRect(done).top,
      closeTo(footer.top + compact.height * 0.6, 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
    expect(presses, 0);
  });

  testWidgets('нажатие нижней кнопки со сдвигом пальца в пределах допуска '
      'срабатывает, а лист остаётся на месте', (tester) async {
    var presses = 0;
    await _openExpandableSheet(tester, onDone: () => presses++);
    final compact = tester.getRect(find.byType(Sheet));
    final gesture = await tester.startGesture(
      tester.getCenter(find.widgetWithText(Button, 'Готово')),
    );

    await gesture.moveBy(const Offset(0, kTouchSlop / 2));
    await tester.pump();
    expect(tester.getRect(find.byType(Sheet)), compact);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(presses, 1);
    expect(tester.getRect(find.byType(Sheet)), compact);
  });

  for (final (segment, depth) in [('раскрытия', -100.0), ('сдвига', 100.0)]) {
    testWidgets('«назад» во время перетаскивания раскрываемого листа на '
        'отрезке $segment закрывает лист, после чего палец его не двигает, а '
        'отпускание не закрывает страницу под ним', (tester) async {
      final page = await _openSheet(
        tester,
        (context) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => _showExpandableSheet(context),
                  child: const Text('Лист'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Лист'));
      await tester.pumpAndSettle();

      final gesture = await _SlowGesture.start(tester, _header);
      await gesture.moveTo(depth);
      await tester.binding.handlePopRoute();
      await tester.pump();
      final closing = tester.getRect(find.byType(Sheet));
      await gesture.moveTo(depth * 3);
      expect(tester.getRect(find.byType(Sheet)), closing);
      await gesture.moveTo(_compact * 0.7);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.byType(Sheet), findsNothing);
      expect(find.text('Лист'), findsOne);
      expect(page.isClosed, isFalse);
    });
  }

  testWidgets('когда клавиатура не оставляет места для роста, перетаскивание '
      'и бросок вверх не меняют размер листа, нажатие ручки раскрывает его, а '
      'бросок вниз из полного размера закрывает', (tester) async {
    final sheet = await _openExpandableSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final compact = tester.getRect(find.byType(Sheet));

    final gesture = await _SlowGesture.start(tester, _header);
    await gesture.moveTo(-100);
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(_topRadius(tester), DoableMetrics.radiusXl);
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.fling(_header, const Offset(0, -60), 1000);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(_topRadius(tester), DoableMetrics.radiusXl);
    expect(_chevron, findsNothing);

    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(_topRadius(tester), 0);
    expect(_chevron, findsOne);

    await tester.fling(_header, const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('ручка — кнопка раскрытия, а в полном размере её заменяет '
      'шеврон сворачивания', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openExpandableSheet(tester);

    expect(
      tester.getSemantics(find.bySemanticsLabel(_expandLabel)),
      isSemantics(
        label: _expandLabel,
        isButton: true,
        hasExpandedState: true,
        isExpanded: false,
        hasTapAction: true,
      ),
    );
    expect(_chevron, findsNothing);

    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _full);
    expect(_chevron, findsOne);
    expect(find.bySemanticsLabel(_expandLabel), findsNothing);
    expect(
      tester.getSemantics(find.bySemanticsLabel(_collapseLabel)),
      isSemantics(
        label: _collapseLabel,
        isButton: true,
        hasExpandedState: true,
        isExpanded: true,
        hasTapAction: true,
      ),
    );

    await tester.tap(find.bySemanticsLabel(_collapseLabel));
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _compact);
    expect(_chevron, findsNothing);
    semantics.dispose();
  });

  testWidgets('размер меняется плавно, а при уменьшенной анимации — сразу', (
    tester,
  ) async {
    await _openExpandableSheet(tester);

    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(_sheetHeight(tester), inExclusiveRange(_compact, _full));
    await tester.pump(const Duration(milliseconds: 90));
    expect(_sheetHeight(tester), _full);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    await tester.tap(find.bySemanticsLabel(_collapseLabel));
    await tester.pump();
    expect(_sheetHeight(tester), _compact);
  });

  testWidgets('при открытой клавиатуре лист не выше места над ней, и поиск с '
      'первой строкой видны', (tester) async {
    await _openExpandableSheet(tester);
    const keyboard = 400.0;
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _screen.height - _statusBar - keyboard);
    expect(
      tester.getRect(find.text('Поиск')).bottom,
      lessThan(_screen.height - keyboard),
    );
    expect(
      tester.getRect(find.text('Тег 0')).bottom,
      lessThan(_screen.height - keyboard),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('лист по содержимому с сообщениями поверх той же высоты, что и '
      'без них, а его нижняя часть над системным отступом', (tester) async {
    await _openContentSheet(tester);
    final height = _sheetHeight(tester);
    final footer = tester.getRect(find.text('Создать'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _openContentSheet(tester, hostsMessages: true);

    expect(height, lessThan(_screen.height / 2));
    expect(_sheetHeight(tester), height);
    expect(tester.getRect(find.text('Создать')), footer);
    expect(footer.bottom, _screen.height - _homeIndicator - 16);
  });

  testWidgets('лист по содержимому с сообщениями поверх растёт и '
      'уменьшается вместе с содержимым после открытия', (tester) async {
    final showsError = ValueNotifier(false);
    addTearDown(showsError.dispose);
    await _openContentSheet(
      tester,
      hostsMessages: true,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 120, child: Text('Название')),
          ValueListenableBuilder(
            valueListenable: showsError,
            builder: (context, showsError, _) => showsError
                ? const SizedBox(height: 40, child: Text('Ошибка'))
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
    final height = _sheetHeight(tester);
    const footerBottom = 844.0 - _homeIndicator - 16;

    showsError.value = true;
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), height + 40);
    expect(
      tester.getRect(find.text('Ошибка')).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Создать')).top),
    );
    expect(tester.getRect(find.text('Создать')).bottom, footerBottom);

    showsError.value = false;
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), height);
    expect(tester.getRect(find.text('Создать')).bottom, footerBottom);
    expect(tester.takeException(), isNull);
  });

  for (final scenario
      in <
        ({
          String name,
          Future<void> Function(WidgetTester) open,
          String head,
          Finder footer,
        })
      >[
        (
          name: 'раскрываемый',
          open: (tester) => _openExpandableSheet(tester, hostsMessages: true),
          head: 'Поиск',
          footer: find.widgetWithText(Button, 'Готово'),
        ),
        (
          name: 'по содержимому',
          open: (tester) => _openContentSheet(tester, hostsMessages: true),
          head: 'Новый тег',
          footer: find.text('Создать'),
        ),
      ]) {
    testWidgets('${scenario.name} лист с сообщениями поверх при открытой '
        'клавиатуре не выше места над ней, учитывает её один раз, а его шапка '
        'и нижняя часть видны', (tester) async {
      await scenario.open(tester);
      const keyboard = 400.0;
      // Клавиатура закрывает системный отступ: он остаётся только в
      // viewPadding.
      tester.view
        ..viewInsets = const FakeViewPadding(bottom: keyboard)
        ..padding = const FakeViewPadding(top: _statusBar);
      await tester.pumpAndSettle();

      const aboveKeyboard = 844.0 - keyboard;
      final sheet = tester.getRect(find.byType(Sheet));
      expect(sheet.bottom, aboveKeyboard);
      expect(sheet.top, greaterThanOrEqualTo(_statusBar));
      expect(
        tester.getRect(find.text(scenario.head)).top,
        greaterThan(sheet.top),
      );
      // Системный отступ под клавиатурой не поднимает нижнюю часть.
      expect(tester.getRect(scenario.footer).bottom, aboveKeyboard - 16);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('свайп вверх по списку раскрывает компактный лист вслед за '
      'пальцем, «Готово» стоит на месте, а список начинает прокручиваться '
      'только в полном размере', (tester) async {
    await _openExpandableSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final footer = tester.getRect(find.text('Готово'));
    final body = _bodyPosition(tester);
    final gesture = await _SlowGesture.start(tester, find.text('Тег 2'));
    // Первое движение список тратит на принятие жеста.
    await gesture.moveTo(-20);

    for (final rise in [100.0, _growth]) {
      await gesture.moveTo(-20 - rise);
      expect(
        tester.getRect(find.byType(Sheet)).top,
        closeTo(compact.top - rise, 1),
        reason: 'подъём $rise',
      );
      expect(
        tester.getRect(find.text('Готово')),
        footer,
        reason: 'подъём $rise',
      );
      expect(body.pixels, 0, reason: 'подъём $rise');
    }

    await gesture.moveTo(-20 - _growth - 120);
    expect(_sheetHeight(tester), _full);
    expect(body.pixels, 120);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _full);
    expect(body.pixels, 120);
    expect(_chevron, findsOne);
  });

  testWidgets('свайп вниз по списку, прокрученному до середины полного '
      'листа, прокручивает его к началу, а затем сворачивает лист вслед за '
      'пальцем', (tester) async {
    final sheet = await _openExpandableSheet(tester);
    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();
    final full = tester.getRect(find.byType(Sheet));
    final footer = tester.getRect(find.text('Готово'));
    final body = _bodyPosition(tester);
    body.jumpTo(200);
    await tester.pump();
    final gesture = await _SlowGesture.start(tester, find.text('Тег 8'));
    await gesture.moveTo(20);

    await gesture.moveTo(20 + 150);
    expect(body.pixels, 50);
    expect(tester.getRect(find.byType(Sheet)), full);

    for (final depth in [100.0, _growth]) {
      await gesture.moveTo(20 + 200 + depth);
      expect(body.pixels, 0, reason: 'глубина $depth');
      expect(
        tester.getRect(find.byType(Sheet)).top,
        closeTo(full.top + depth, 1),
        reason: 'глубина $depth',
      );
      expect(
        tester.getRect(find.text('Готово')),
        footer,
        reason: 'глубина $depth',
      );
    }
    await gesture.moveTo(20 + 200 + _growth + 60);
    expect(
      tester.getRect(find.text('Готово')).top,
      closeTo(footer.top + 60, 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _compact);
    expect(tester.getRect(find.byType(Sheet)).bottom, _screen.height);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('когда клавиатура не оставляет места для роста, движение вверх '
      'по списку компактного листа прокручивает список, а лист остаётся '
      'компактным со скруглёнными углами и ручкой', (tester) async {
    await _openExpandableSheet(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 400);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final compact = tester.getRect(find.byType(Sheet));
    final body = _bodyPosition(tester);

    final gesture = await _SlowGesture.start(tester, find.text('Тег 0'));
    await gesture.moveTo(-20);
    await gesture.moveTo(-20 - 60);
    expect(body.pixels, 60);
    expect(tester.getRect(find.byType(Sheet)), compact);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(_topRadius(tester), DoableMetrics.radiusXl);
    expect(find.bySemanticsLabel(_expandLabel), findsOne);
    expect(_chevron, findsNothing);
  });

  testWidgets('короткий быстрый бросок вверх по списку компактного листа '
      'раскрывает лист, а список остаётся в начале', (tester) async {
    await _openExpandableSheet(tester);
    final body = _bodyPosition(tester);

    await tester.fling(find.text('Тег 2'), const Offset(0, -60), 1000);
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _full);
    expect(body.pixels, 0);
  });

  testWidgets('список, который помещается только в полном размере, ведёт '
      'лист вслед за пальцем до полного размера, а дальнейшее движение вверх '
      'не вызывает эффекта края', (tester) async {
    var overscrolls = 0;
    await _openSheet(
      tester,
      (context) => showDoableSheet<void>(
        context: context,
        builder: (context, sheet) =>
            NotificationListener<OverscrollNotification>(
              onNotification: (_) {
                overscrolls++;
                return false;
              },
              child: Sheet.expandable(
                sheet,
                title: 'Теги',
                text: 'Выберите сколько нужно',
                expandLabel: _expandLabel,
                collapseLabel: _collapseLabel,
                pinned: const _Search(),
                slivers: [
                  SliverList.builder(
                    itemCount: 10,
                    itemBuilder: (context, index) =>
                        SizedBox(height: 48, child: Text('Тег $index')),
                  ),
                ],
                footer: Button.primary(label: 'Готово', onPressed: _ignore),
              ),
            ),
      ),
    );
    final compact = tester.getRect(find.byType(Sheet));
    final body = _bodyPosition(tester);
    expect(body.maxScrollExtent, greaterThan(0));

    final gesture = await _SlowGesture.start(tester, find.text('Тег 1'));
    await gesture.moveTo(-20);
    for (final rise in [60.0, 120.0]) {
      await gesture.moveTo(-20 - rise);
      expect(
        tester.getRect(find.byType(Sheet)).top,
        closeTo(compact.top - rise, 1),
        reason: 'подъём $rise',
      );
    }
    // Это движение доводит лист до полного размера, и его остаток список
    // гасит.
    await gesture.moveTo(-20 - _growth - 100);
    expect(_sheetHeight(tester), _full);
    expect(body.maxScrollExtent, 0);
    expect(body.pixels, 0);
    await gesture.moveTo(-20 - _growth - 200);
    expect(body.pixels, 0);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(_sheetHeight(tester), _full);
    expect(overscrolls, 0);
  });

  testWidgets('scrollUp диктора над списком компактного листа прокручивает '
      'список, а лист остаётся компактным', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openExpandableSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final body = _bodyPosition(tester);

    tester.semantics.scrollUp(scrollable: find.semantics.scrollable());
    await tester.pumpAndSettle();

    expect(body.pixels, greaterThan(0));
    expect(tester.getRect(find.byType(Sheet)), compact);
    semantics.dispose();
  });

  testWidgets('действие шапки стоит справа на строке заголовка в компактном '
      'и полном размерах, заголовок остаётся по центру, а нажатие вызывает '
      'обработчик без изменения размера листа', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await _openExpandableSheet(tester, onReset: () => presses++);

    for (final (size, height) in [
      ('компактный', _compact),
      ('полный', _full),
    ]) {
      final title = tester.getRect(find.text('Теги'));
      final label = tester.getRect(find.text('Сбросить'));
      expect(label.right, _screen.width - 20, reason: size);
      expect(label.center.dy, closeTo(title.center.dy, 0.01), reason: size);
      expect(title.center.dx, _screen.width / 2, reason: size);
      expect(
        tester.getSemantics(find.bySemanticsLabel(_resetLabel)),
        isSemantics(
          label: _resetLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
        reason: size,
      );

      // Верх области нажатия выше строки заголовка.
      final area = tester.getRect(find.widgetWithText(Button, 'Сбросить'));
      expect(area.height, greaterThanOrEqualTo(44), reason: size);
      expect(area.top, lessThan(title.top), reason: size);
      final before = presses;
      await tester.tapAt(Offset(area.center.dx, area.top + 1));
      await tester.pumpAndSettle();
      expect(presses, before + 1, reason: size);
      expect(_sheetHeight(tester), height, reason: size);

      if (height == _compact) {
        await tester.tap(find.bySemanticsLabel(_expandLabel));
        await tester.pumpAndSettle();
      }
    }
    semantics.dispose();
  });

  testWidgets('без действия шапка листа та же, что и с ним, но без кнопки', (
    tester,
  ) async {
    await _openExpandableSheet(tester, onReset: () {});
    final title = tester.getCenter(find.text('Теги'));
    final text = tester.getRect(find.text('Выберите сколько нужно'));
    final pinned = tester.getRect(find.text('Поиск'));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await _openExpandableSheet(tester);

    expect(find.widgetWithText(Button, 'Сбросить'), findsNothing);
    expect(tester.getCenter(find.text('Теги')), title);
    expect(tester.getRect(find.text('Выберите сколько нужно')), text);
    expect(tester.getRect(find.text('Поиск')), pinned);
  });

  testWidgets('касание затемнения закрывает лист', (tester) async {
    final sheet = await _openExpandableSheet(tester);

    await tester.tapAt(const Offset(195, 120));
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('лист по содержимому вместе с нижней кнопкой стоит под '
      'пальцем, не поднимается выше компактного размера, а после медленного '
      'малого отклонения возвращается', (tester) async {
    final sheet = await _openContentSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));

    await _dragContentSheetAndRelease(tester);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('короткий быстрый бросок вниз закрывает лист по содержимому', (
    tester,
  ) async {
    final sheet = await _openContentSheet(tester);
    expect(_sheetHeight(tester), greaterThan(2 * 60));

    await tester.fling(find.text('Новый тег'), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('медленное отпускание закрывает лист по содержимому, только '
      'когда видно меньше половины его высоты', (tester) async {
    final sheet = await _openContentSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));

    await tester.timedDrag(
      find.text('Новый тег'),
      Offset(0, compact.height * 0.4),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);

    await tester.timedDrag(
      find.text('Новый тег'),
      Offset(0, compact.height * 0.6),
      const Duration(seconds: 2),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('отменённый системой жест возвращает лист по содержимому', (
    tester,
  ) async {
    final sheet = await _openContentSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Новый тег')),
    );
    await gesture.moveBy(Offset(0, compact.height * 0.8));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('второй палец, коснувшийся нижней кнопки, сдвигает лист по '
      'содержимому только на своё движение, и после отпускания лист остаётся '
      'открытым', (tester) async {
    final sheet = await _openContentSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final first = await tester.startGesture(
      tester.getCenter(find.text('Новый тег')),
    );
    await first.moveBy(
      const Offset(0, 30),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();

    final second = await tester.startGesture(
      tester.getCenter(find.text('Создать')),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top + 30, 1),
    );

    await second.moveBy(
      const Offset(0, 2),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top + 32, 1),
    );

    await second.up(timeStamp: const Duration(milliseconds: 300));
    await first.up(timeStamp: const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('отменённый системой жест возвращает лист по содержимому, даже '
      'когда после отмены листа касается другой палец', (tester) async {
    final sheet = await _openContentSheet(tester);
    final compact = tester.getRect(find.byType(Sheet));
    final first = await tester.startGesture(
      tester.getCenter(find.text('Новый тег')),
    );
    await first.moveBy(Offset(0, compact.height * 0.8));
    await tester.pump();
    final second = await tester.startGesture(
      tester.getCenter(find.text('Новый тег')),
    );
    await tester.pump();

    await first.cancel();
    final third = await tester.startGesture(
      tester.getCenter(find.text('Новый тег')),
    );
    await tester.pump();
    await second.up();
    await third.up();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('«назад» во время перетаскивания верхнего листа закрывает только '
      'его, а дальнейшее движение и отпускание пальца не двигают и не '
      'закрывают нижний лист', (tester) async {
    var isUpperClosed = false;
    final lower = await _openContentSheet(
      tester,
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDoableSheet<void>(
            context: context,
            builder: (context, sheet) => Sheet(
              sheet,
              title: 'Верхний лист',
              child: const SizedBox(height: 120),
            ),
          ).whenComplete(() => isUpperClosed = true),
          child: const Text('Ещё лист'),
        ),
      ),
    );
    final lowerRect = tester.getRect(find.byType(Sheet));
    await tester.tap(find.text('Ещё лист'));
    await tester.pumpAndSettle();

    final upper = tester.getRect(find.byType(Sheet).last);
    final start = tester.getCenter(find.text('Верхний лист'));
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(
      start + const Offset(0, 60),
      timeStamp: const Duration(milliseconds: 100),
    );
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    // Отпускание в зоне закрытия, но не у самого края пути листа.
    expect(upper.height * 0.7, greaterThan(60));
    await gesture.moveTo(
      start + Offset(0, upper.height * 0.7),
      timeStamp: const Duration(milliseconds: 200),
    );
    await tester.pump();
    expect(tester.getRect(find.byType(Sheet).first), lowerRect);
    await gesture.up(timeStamp: const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(isUpperClosed, isTrue);
    expect(find.text('Верхний лист'), findsNothing);
    expect(tester.getRect(find.byType(Sheet)), lowerRect);
    expect(lower.isClosed, isFalse);
  });

  testWidgets('движение вниз по длинному телу листа по содержимому '
      'прокручивает тело к началу, а затем в том же жесте опускает лист с '
      'нижней кнопкой вслед за пальцем; движение обратно вверх сначала '
      'возвращает лист в компактное положение, а затем прокручивает '
      'тело', (tester) async {
    final sheet = await _openContentSheet(tester, body: _longBody);
    final compact = tester.getRect(find.byType(Sheet));
    final footer = tester.getRect(find.text('Создать'));
    final scrim = _scrimAlpha(tester);
    final body = _bodyPosition(tester);
    body.jumpTo(200);
    await tester.pump();
    final gesture = await _SlowGesture.start(tester, find.text('Строка 8'));
    // Первое движение список тратит на принятие жеста.
    await gesture.moveTo(20);

    await gesture.moveTo(20 + 150);
    expect(body.pixels, 50);
    expect(tester.getRect(find.byType(Sheet)), compact);

    for (final depth in [120.0, 40.0]) {
      await gesture.moveTo(20 + 200 + depth);
      expect(body.pixels, 0, reason: 'глубина $depth');
      expect(
        tester.getRect(find.byType(Sheet)).top,
        closeTo(compact.top + depth, 1),
        reason: 'глубина $depth',
      );
      expect(
        tester.getRect(find.text('Создать')).top,
        closeTo(footer.top + depth, 1),
        reason: 'глубина $depth',
      );
      expect(_scrimAlpha(tester), lessThan(scrim), reason: 'глубина $depth');
    }

    await gesture.moveTo(20 + 200 - 60);
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(body.pixels, 60);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(body.pixels, 60);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('короткий быстрый бросок вниз по длинному телу в начале '
      'закрывает лист по содержимому, а медленное малое отклонение '
      'возвращает его', (tester) async {
    final sheet = await _openContentSheet(tester, body: _longBody);
    final compact = tester.getRect(find.byType(Sheet));

    final gesture = await _SlowGesture.start(tester, find.text('Строка 3'));
    await gesture.moveTo(20);
    await gesture.moveTo(20 + 40);
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top + 40, 1),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);

    await tester.fling(find.text('Строка 3'), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('быстрый бросок вверх после того, как жест по длинному телу '
      'опустил лист по содержимому, возвращает лист, а тело остаётся в '
      'начале; бросок вверх, при котором лист не двигался, прокручивает тело '
      'по инерции', (tester) async {
    final sheet = await _openContentSheet(tester, body: _longBody);
    final compact = tester.getRect(find.byType(Sheet));
    final body = _bodyPosition(tester);

    final gesture = await _SlowGesture.start(tester, find.text('Строка 3'));
    await gesture.moveTo(20);
    // Медленное отпускание здесь закрыло бы лист.
    await gesture.moveTo(20 + compact.height * 0.7);
    await gesture.flingTo(20 + compact.height * 0.6);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(body.pixels, 0);
    expect(sheet.isClosed, isFalse);

    await tester.fling(find.text('Строка 3'), const Offset(0, -200), 2000);
    await tester.pumpAndSettle();
    expect(body.pixels, greaterThan(200));
    expect(tester.getRect(find.byType(Sheet)), compact);
  });

  testWidgets('быстрый бросок вниз по длинному телу, отпущенный до того, как '
      'тело дошло до начала, прокручивает тело по инерции до начала, а лист '
      'по содержимому остаётся открытым в компактном размере', (tester) async {
    final sheet = await _openContentSheet(tester, body: _longBody);
    final compact = tester.getRect(find.byType(Sheet));
    final body = _bodyPosition(tester);
    body.jumpTo(100);
    await tester.pump();

    await tester.fling(find.text('Строка 5'), const Offset(0, 60), 1000);
    expect(body.pixels, greaterThan(0));
    await tester.pumpAndSettle();

    expect(body.pixels, 0);
    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('движение вниз по короткому телу опускает лист по содержимому, '
      'а движение вверх не поднимает его выше компактного размера и не '
      'вызывает эффекта края', (tester) async {
    var overscrolls = 0;
    await _openSheet(
      tester,
      (context) => showDoableSheet<void>(
        context: context,
        builder: (context, sheet) =>
            NotificationListener<OverscrollNotification>(
              onNotification: (_) {
                overscrolls++;
                return false;
              },
              child: Sheet(
                sheet,
                title: 'Новый тег',
                footer: const SizedBox(height: 44, child: Text('Создать')),
                child: const SizedBox(height: 120, child: Text('Название')),
              ),
            ),
      ),
    );
    final compact = tester.getRect(find.byType(Sheet));
    final footer = tester.getRect(find.text('Создать'));

    final gesture = await _SlowGesture.start(tester, find.text('Название'));
    await gesture.moveTo(20);
    await gesture.moveTo(20 + 60);
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(compact.top + 60, 1),
    );
    expect(
      tester.getRect(find.text('Создать')).top,
      closeTo(footer.top + 60, 1),
    );
    await gesture.moveTo(20 - 100);
    expect(tester.getRect(find.byType(Sheet)), compact);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(overscrolls, 0);
  });

  testWidgets('отменённый системой жест по длинному телу возвращает лист по '
      'содержимому', (tester) async {
    final sheet = await _openContentSheet(tester, body: _longBody);
    final compact = tester.getRect(find.byType(Sheet));

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Строка 3')),
    );
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(Offset(0, compact.height * 0.8));
    await tester.pump();
    expect(tester.getRect(find.byType(Sheet)).top, greaterThan(compact.top));
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
  });

  testWidgets('«назад» во время перетаскивания верхнего листа за длинное тело '
      'закрывает только его, а дальнейшее движение и отпускание пальца не '
      'двигают и не закрывают нижний лист', (tester) async {
    var isUpperClosed = false;
    final lower = await _openContentSheet(
      tester,
      body: Builder(
        builder: (context) => TextButton(
          onPressed: () => showDoableSheet<void>(
            context: context,
            builder: (context, sheet) =>
                Sheet(sheet, title: 'Верхний лист', child: _longBody),
          ).whenComplete(() => isUpperClosed = true),
          child: const Text('Ещё лист'),
        ),
      ),
    );
    final lowerRect = tester.getRect(find.byType(Sheet));
    await tester.tap(find.text('Ещё лист'));
    await tester.pumpAndSettle();

    final upper = tester.getRect(find.byType(Sheet).last);
    final gesture = await _SlowGesture.start(tester, find.text('Строка 3'));
    await gesture.moveTo(20);
    await gesture.moveTo(20 + 60);
    expect(
      tester.getRect(find.byType(Sheet).last).top,
      closeTo(upper.top + 60, 1),
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    // Отпускание в зоне закрытия, но не у самого края пути листа.
    await gesture.moveTo(20 + upper.height * 0.7);
    expect(tester.getRect(find.byType(Sheet).first), lowerRect);
    await gesture.up();
    await tester.pumpAndSettle();

    expect(isUpperClosed, isTrue);
    expect(find.text('Верхний лист'), findsNothing);
    expect(tester.getRect(find.byType(Sheet)), lowerRect);
    expect(lower.isClosed, isFalse);
  });

  testWidgets('scrollUp и scrollDown диктора прокручивают длинное тело, а лист '
      'по содержимому остаётся на месте, в том числе когда scrollDown доводит '
      'тело до начала с запасом', (tester) async {
    final semantics = tester.ensureSemantics();
    final sheet = await _openContentSheet(tester, body: _longBody);
    final compact = tester.getRect(find.byType(Sheet));
    final body = _bodyPosition(tester);

    tester.semantics.scrollUp(scrollable: find.semantics.scrollable());
    await tester.pump();
    final scrolled = body.pixels;
    expect(scrolled, greaterThan(0));
    expect(tester.getRect(find.byType(Sheet)), compact);
    await tester.pumpAndSettle();

    body.jumpTo(scrolled / 2);
    await tester.pump();
    tester.semantics.scrollDown(scrollable: find.semantics.scrollable());
    await tester.pump();
    expect(body.pixels, 0);
    expect(tester.getRect(find.byType(Sheet)), compact);
    await tester.pumpAndSettle();

    expect(tester.getRect(find.byType(Sheet)), compact);
    expect(sheet.isClosed, isFalse);
    semantics.dispose();
  });

  testWidgets('при уменьшении движения лист по содержимому стоит под пальцем, '
      'а открытие, возврат после отпускания и закрытие происходят сразу', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    final sheet = await _openContentSheet(tester, settle: false);
    final compact = tester.getRect(find.byType(Sheet));
    expect(compact.bottom, _screen.height);

    await _dragContentSheetAndRelease(tester);
    await tester.pump();
    expect(tester.getRect(find.byType(Sheet)), compact);

    await tester.fling(find.text('Новый тег'), const Offset(0, 60), 1000);
    await tester.pump();
    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('системное «назад» закрывает раскрытый лист', (tester) async {
    final sheet = await _openExpandableSheet(tester);
    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });
}

final _chevron = find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.chevronDown,
);

final _header = find.text('Выберите сколько нужно');

/// Радиус верхних углов листа.
double _topRadius(WidgetTester tester) => tester
    .widget<Material>(
      find
          .descendant(of: find.byType(Sheet), matching: find.byType(Material))
          .first,
    )
    .borderRadius!
    .resolve(TextDirection.ltr)
    .topLeft
    .x;

/// Тело листа по содержимому, которое не помещается в лист.
final _longBody = Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var index = 0; index < 40; index++)
      SizedBox(height: 48, child: Text('Строка $index')),
  ],
);

/// Позиция прокрутки тела единственного открытого листа.
ScrollPosition _bodyPosition(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(Sheet),
        // Поле поиска прокручивается по горизонтали.
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      ),
    )
    .position;

double _sheetHeight(WidgetTester tester) =>
    tester.getSize(find.byType(Sheet)).height;

/// Непрозрачность затемнения под листом.
double _scrimAlpha(WidgetTester tester) => tester
    .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier))
    .color
    .value!
    .a;

/// Ведёт шапку открытого листа по содержимому вниз на несколько глубин и выше
/// компактного размера, не отпуская палец, и проверяет, что лист с нижней
/// кнопкой стоит под пальцем, а затемнение слабеет. Затем медленно отпускает
/// палец на малой глубине.
Future<void> _dragContentSheetAndRelease(WidgetTester tester) async {
  final sheet = tester.getRect(find.byType(Sheet));
  final footer = tester.getRect(find.text('Создать'));
  final scrim = _scrimAlpha(tester);
  final start = tester.getCenter(find.text('Новый тег'));
  final gesture = await tester.startGesture(start);
  // Касания разделены паузой длиннее 40 мс, поэтому отпускание медленное:
  // https://api.flutter.dev/flutter/gestures/VelocityTracker-class.html
  var time = Duration.zero;
  Future<void> moveTo(double depth) async {
    time += const Duration(milliseconds: 100);
    await gesture.moveTo(start + Offset(0, depth), timeStamp: time);
    await tester.pump();
  }

  // Глубина 1 — ближайшая к компактному положению, где обратная функция
  // кривой маршрута круче всего.
  for (final depth in [40.0, sheet.height * 0.8, sheet.height * 0.3, 1.0]) {
    await moveTo(depth);
    expect(
      tester.getRect(find.byType(Sheet)).top,
      closeTo(sheet.top + depth, 1),
      reason: 'глубина $depth',
    );
    expect(
      tester.getRect(find.text('Создать')).top,
      closeTo(footer.top + depth, 1),
      reason: 'глубина $depth',
    );
    if (depth > sheet.height / 2) {
      expect(
        _scrimAlpha(tester),
        lessThan(scrim / 2),
        reason: 'глубина $depth',
      );
    }
  }

  await moveTo(-60);
  expect(tester.getRect(find.byType(Sheet)), sheet);

  await moveTo(40);
  await gesture.up(timeStamp: time);
}

final class _OpenedSheet {
  bool isClosed = false;
}

/// С [onReset] у листа есть действие шапки «Сбросить».
Future<_OpenedSheet> _openExpandableSheet(
  WidgetTester tester, {
  bool hostsMessages = false,
  VoidCallback? onReset,
  VoidCallback onDone = _ignore,
}) => _openSheet(
  tester,
  (context) => _showExpandableSheet(
    context,
    hostsMessages: hostsMessages,
    onReset: onReset,
    onDone: onDone,
  ),
);

void _ignore() {}

/// Закреплённое поле и нижняя кнопка — те же элементы, что в панели тегов.
Future<void> _showExpandableSheet(
  BuildContext context, {
  bool hostsMessages = false,
  VoidCallback? onReset,
  VoidCallback onDone = _ignore,
}) => showDoableSheet<void>(
  context: context,
  hostsMessages: hostsMessages,
  builder: (context, sheet) => Sheet.expandable(
    sheet,
    title: 'Теги',
    text: 'Выберите сколько нужно',
    expandLabel: _expandLabel,
    collapseLabel: _collapseLabel,
    action: switch (onReset) {
      final onReset? => (
        label: 'Сбросить',
        semanticLabel: _resetLabel,
        onPressed: onReset,
      ),
      null => null,
    },
    pinned: const _Search(),
    slivers: [
      SliverList.builder(
        itemCount: 40,
        itemBuilder: (context, index) =>
            SizedBox(height: 48, child: Text('Тег $index')),
      ),
    ],
    footer: Button.primary(label: 'Готово', onPressed: onDone),
  ),
);

final class _Search extends StatefulWidget {
  const _Search();

  @override
  State<_Search> createState() => _SearchState();
}

final class _SearchState extends State<_Search> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SearchField(
    controller: _controller,
    placeholder: 'Поиск',
    label: 'Поиск тегов',
    clearLabel: 'Очистить поиск',
    onChanged: (_) {},
  );
}

/// Без [settle] лист открыт одним кадром после нажатия.
Future<_OpenedSheet> _openContentSheet(
  WidgetTester tester, {
  bool hostsMessages = false,
  Widget body = const SizedBox(height: 120, child: Text('Название')),
  bool settle = true,
}) => _openSheet(
  tester,
  (context) => showDoableSheet<void>(
    context: context,
    hostsMessages: hostsMessages,
    builder: (context, sheet) => Sheet(
      sheet,
      title: 'Новый тег',
      footer: const SizedBox(height: 44, child: Text('Создать')),
      child: body,
    ),
  ),
  settle: settle,
);

/// Касание шапки, которое движется медленно: шаги разделены паузой длиннее
/// 40 мс, поэтому отпускание после [moveTo] медленное:
/// https://api.flutter.dev/flutter/gestures/VelocityTracker-class.html
final class _SlowGesture {
  _SlowGesture._(this._tester, this._gesture, this._start);

  static Future<_SlowGesture> start(WidgetTester tester, Finder finder) async {
    final start = tester.getCenter(finder);
    return _SlowGesture._(tester, await tester.startGesture(start), start);
  }

  final WidgetTester _tester;
  final TestGesture _gesture;
  final Offset _start;
  var _time = Duration.zero;
  var _dy = 0.0;

  /// Ставит палец на [dy] ниже касания.
  Future<void> moveTo(double dy) async {
    _dy = dy;
    _time += const Duration(milliseconds: 100);
    await _gesture.moveTo(_start + Offset(0, dy), timeStamp: _time);
    await _tester.pump();
  }

  /// Быстро переводит палец на [dy] ниже касания и отпускает его.
  Future<void> flingTo(double dy) async {
    const steps = 3;
    final from = _dy;
    for (var step = 1; step <= steps; step++) {
      _time += const Duration(milliseconds: 10);
      _dy = from + (dy - from) * step / steps;
      await _gesture.moveTo(_start + Offset(0, _dy), timeStamp: _time);
    }
    await _gesture.up(timeStamp: _time);
  }

  Future<void> up() => _gesture.up(timeStamp: _time);
}

/// Медленно ведёт шапку на [dy] вниз и отпускает.
Future<void> _slowDrag(WidgetTester tester, double dy) async {
  final gesture = await _SlowGesture.start(tester, _header);
  await gesture.moveTo(dy);
  await gesture.up();
}

/// Сдвигает касание шапки на [offset] и отменяет его системой, а не
/// отпусканием.
Future<void> _cancelHeaderDrag(WidgetTester tester, Offset offset) async {
  final gesture = await tester.startGesture(tester.getCenter(_header));
  await gesture.moveBy(offset);
  await tester.pump();
  await gesture.cancel();
  await tester.pumpAndSettle();
}

Future<_OpenedSheet> _openSheet(
  WidgetTester tester,
  Future<void> Function(BuildContext context) show, {
  bool settle = true,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen
    ..padding = const FakeViewPadding(top: _statusBar, bottom: _homeIndicator)
    ..viewPadding = const FakeViewPadding(
      top: _statusBar,
      bottom: _homeIndicator,
    );
  addTearDown(tester.view.reset);
  final opened = _OpenedSheet();

  await tester.pumpWidget(
    MaterialApp(
      theme: doableTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () =>
                  show(context).whenComplete(() => opened.isClosed = true),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return opened;
}
