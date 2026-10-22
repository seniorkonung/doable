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

Future<_OpenedSheet> _openExpandableSheet(WidgetTester tester) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = _screen
    ..padding = const FakeViewPadding(top: _statusBar);
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
                size: DoableSheetSize.expandable,
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
