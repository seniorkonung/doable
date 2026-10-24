import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _screen = Size(390, 844);
const _statusBar = 47.0;
const _half = 534.0;
const _full = 844.0 - _statusBar;
const _expandLabel = 'Раскрыть на весь экран';
const _collapseLabel = 'Свернуть';
const _homeIndicator = 34.0;
const _resetLabel = 'Сбросить условия по тегам';

void main() {
  testWidgets('перетаскивание шапки на 48 вверх раскрывает лист, вниз '
      'сворачивает полный и закрывает половинный, а меньший сдвиг ничего '
      'не меняет', (tester) async {
    final sheet = await _openExpandableSheet(tester);
    expect(_sheetHeight(tester), _half);

    await tester.drag(
      find.text('Выберите сколько нужно'),
      const Offset(0, -47),
    );
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), _half);

    await tester.drag(
      find.text('Выберите сколько нужно'),
      const Offset(0, -48),
    );
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), _full);

    await tester.drag(find.text('Выберите сколько нужно'), const Offset(0, 47));
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), _full);

    await tester.drag(find.text('Выберите сколько нужно'), const Offset(0, 48));
    await tester.pumpAndSettle();
    expect(_sheetHeight(tester), _half);

    await tester.drag(find.text('Выберите сколько нужно'), const Offset(0, 47));
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsOne);

    await tester.drag(find.text('Выберите сколько нужно'), const Offset(0, 48));
    await tester.pumpAndSettle();
    expect(find.byType(Sheet), findsNothing);
    expect(sheet.isClosed, isTrue);
  });

  testWidgets('отменённое системой касание шапки не раскрывает, не '
      'сворачивает и не закрывает лист', (tester) async {
    final sheet = await _openExpandableSheet(tester);

    await _cancelHeaderDrag(tester, const Offset(0, -60));
    expect(_sheetHeight(tester), _half);

    await _cancelHeaderDrag(tester, const Offset(0, 60));
    expect(_sheetHeight(tester), _half);
    expect(sheet.isClosed, isFalse);

    await tester.tap(find.bySemanticsLabel(_expandLabel));
    await tester.pumpAndSettle();
    await _cancelHeaderDrag(tester, const Offset(0, 60));
    expect(_sheetHeight(tester), _full);
    expect(find.byType(Sheet), findsOne);
    expect(sheet.isClosed, isFalse);
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

    expect(_sheetHeight(tester), _half);
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
    expect(_sheetHeight(tester), inExclusiveRange(_half, _full));
    await tester.pump(const Duration(milliseconds: 90));
    expect(_sheetHeight(tester), _full);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();

    await tester.tap(find.bySemanticsLabel(_collapseLabel));
    await tester.pump();
    expect(_sheetHeight(tester), _half);
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
          String footer,
        })
      >[
        (
          name: 'раскрываемый',
          open: (tester) => _openExpandableSheet(tester, hostsMessages: true),
          head: 'Поиск',
          footer: 'Готово',
        ),
        (
          name: 'по содержимому',
          open: (tester) => _openContentSheet(tester, hostsMessages: true),
          head: 'Новый тег',
          footer: 'Создать',
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
      expect(
        tester.getRect(find.text(scenario.footer)).bottom,
        aboveKeyboard - 16,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('прокрутка тела в обе стороны не меняет размер листа', (
    tester,
  ) async {
    await _openExpandableSheet(tester);

    await tester.drag(find.text('Тег 2'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Тег 0'), findsNothing);
    expect(_sheetHeight(tester), _half);

    await tester.drag(find.text('Тег 8'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Тег 0'), findsOne);
    expect(_sheetHeight(tester), _half);
  });

  testWidgets('действие шапки стоит справа на строке заголовка в половинном '
      'и полном размерах, заголовок остаётся по центру, а нажатие вызывает '
      'обработчик без изменения размера листа', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await _openExpandableSheet(tester, onReset: () => presses++);

    for (final (size, height) in [('половинный', _half), ('полный', _full)]) {
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
      final area = tester.getRect(find.byType(Button));
      expect(area.height, greaterThanOrEqualTo(44), reason: size);
      expect(area.top, lessThan(title.top), reason: size);
      final before = presses;
      await tester.tapAt(Offset(area.center.dx, area.top + 1));
      await tester.pumpAndSettle();
      expect(presses, before + 1, reason: size);
      expect(_sheetHeight(tester), height, reason: size);

      if (height == _half) {
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

    expect(find.byType(Button), findsNothing);
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
}) => _openSheet(
  tester,
  (context) => showDoableSheet<void>(
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
      pinned: const SizedBox(height: 44, child: Text('Поиск')),
      body: ListView.builder(
        itemCount: 40,
        itemBuilder: (context, index) =>
            SizedBox(height: 48, child: Text('Тег $index')),
      ),
      footer: const SizedBox(height: 44, child: Text('Готово')),
    ),
  ),
);

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

/// Сдвигает касание шапки на [offset] и отменяет его системой, а не
/// отпусканием.
Future<void> _cancelHeaderDrag(WidgetTester tester, Offset offset) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.text('Выберите сколько нужно')),
  );
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
