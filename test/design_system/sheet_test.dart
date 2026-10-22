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

  testWidgets('касание затемнения закрывает лист', (tester) async {
    final sheet = await _openExpandableSheet(tester);

    await tester.tapAt(const Offset(195, 120));
    await tester.pumpAndSettle();

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

final class _OpenedSheet {
  bool isClosed = false;
}

Future<_OpenedSheet> _openExpandableSheet(
  WidgetTester tester, {
  bool hostsMessages = false,
}) => _openSheet(
  tester,
  size: DoableSheetSize.expandable,
  hostsMessages: hostsMessages,
  builder: (context) => Sheet.expandable(
    title: 'Теги',
    text: 'Выберите сколько нужно',
    expandLabel: _expandLabel,
    collapseLabel: _collapseLabel,
    pinned: const SizedBox(height: 44, child: Text('Поиск')),
    body: ListView.builder(
      itemCount: 40,
      itemBuilder: (context, index) =>
          SizedBox(height: 48, child: Text('Тег $index')),
    ),
    footer: const SizedBox(height: 44, child: Text('Готово')),
  ),
);

Future<_OpenedSheet> _openContentSheet(
  WidgetTester tester, {
  bool hostsMessages = false,
  Widget body = const SizedBox(height: 120, child: Text('Название')),
}) => _openSheet(
  tester,
  size: DoableSheetSize.content,
  hostsMessages: hostsMessages,
  builder: (context) => Sheet(
    title: 'Новый тег',
    footer: const SizedBox(height: 44, child: Text('Создать')),
    child: body,
  ),
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
  WidgetTester tester, {
  required DoableSheetSize size,
  required bool hostsMessages,
  required WidgetBuilder builder,
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
              onPressed: () => showDoableSheet<void>(
                context: context,
                size: size,
                hostsMessages: hostsMessages,
                builder: builder,
              ).whenComplete(() => opened.isClosed = true),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  return opened;
}
