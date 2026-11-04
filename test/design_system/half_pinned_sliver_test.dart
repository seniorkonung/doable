import 'package:doable/src/design_system/components/half_pinned_sliver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _viewportHeight = 400.0;
const _rowHeight = 100.0;

void main() {
  group('срез сравнивает ребёнка с половиной видимой высоты', () {
    testWidgets('ребёнок ровно в половину высоты остаётся у верхнего края '
        'над прокрученным телом', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          controller: controller,
          header: const SizedBox(key: _headerKey, height: _viewportHeight / 2),
        ),
      );

      controller.jumpTo(_viewportHeight);
      await tester.pump();

      expect(tester.getTopLeft(find.byKey(_headerKey)).dy, 0);
    });

    testWidgets('ребёнок выше половины уходит вместе с телом', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          controller: controller,
          header: const SizedBox(key: _headerKey, height: 201),
        ),
      );

      controller.jumpTo(50);
      await tester.pump();

      expect(tester.getTopLeft(find.byKey(_headerKey)).dy, -50);
    });

    testWidgets('рост ребёнка выше половины без смены видимой высоты '
        'отпускает его', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          controller: controller,
          header: const SizedBox(key: _headerKey, height: 200),
        ),
      );
      controller.jumpTo(50);
      await tester.pump();

      await tester.pumpWidget(
        _host(
          controller: controller,
          header: const SizedBox(key: _headerKey, height: 201),
        ),
      );

      expect(tester.getTopLeft(find.byKey(_headerKey)).dy, -50);
    });
  });

  testWidgets('смена видимой высоты через порог в обе стороны закрепляет '
      'и отпускает срез, а ребёнок сохраняет текст и фокус', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final header = SizedBox(
      key: _headerKey,
      height: 180,
      child: TextField(focusNode: focus),
    );
    Widget host(double viewportHeight) => _host(
      controller: controller,
      header: header,
      viewportHeight: viewportHeight,
    );

    await tester.pumpWidget(host(_viewportHeight));
    await tester.enterText(find.byType(TextField), 'черновик');
    controller.jumpTo(50);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_headerKey)).dy, 0);

    await tester.pumpWidget(host(300));
    expect(tester.getTopLeft(find.byKey(_headerKey)).dy, -50);
    expect(find.text('черновик'), findsOneWidget);
    expect(focus.hasFocus, isTrue);

    await tester.pumpWidget(host(_viewportHeight));
    expect(tester.getTopLeft(find.byKey(_headerKey)).dy, 0);
    expect(find.text('черновик'), findsOneWidget);
    expect(focus.hasFocus, isTrue);
  });

  group('срез сообщает о препятствии прокрутке', () {
    testWidgets('показ строки под закреплённым срезом ставит её сразу под ним, '
        'а не за ним', (tester) async {
      await tester.pumpWidget(
        _host(
          controller: null,
          header: const SizedBox(key: _headerKey, height: 150),
        ),
      );

      await _revealAtTop(tester, _rowKey(1));

      expect(tester.getTopLeft(find.byKey(_rowKey(1))).dy, 150);
    });

    testWidgets('показ строки под прокручиваемым срезом ставит её '
        'к верхнему краю', (tester) async {
      await tester.pumpWidget(
        _host(
          controller: null,
          header: const SizedBox(key: _headerKey, height: 250),
        ),
      );

      await _revealAtTop(tester, _rowKey(1));

      expect(tester.getTopLeft(find.byKey(_rowKey(1))).dy, 0);
    });
  });

  testWidgets('тело проходит под закреплённым срезом и не получает нажатие '
      'по нему, даже если ребёнок сам нажатия не принимает', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final tappedRows = <int>[];
    await tester.pumpWidget(
      _host(
        controller: controller,
        header: const SizedBox(key: _headerKey, height: 150),
        onRowTap: tappedRows.add,
      ),
    );

    controller.jumpTo(_rowHeight);
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(_rowKey(0))).dy, 50);

    await tester.tapAt(const Offset(10, 100));
    await tester.pump();
    expect(tappedRows, isEmpty);

    await tester.tapAt(const Offset(10, 160));
    await tester.pump();
    expect(tappedRows, [1]);
  });

  group('нажатие доходит до ребёнка в его месте на экране', () {
    Future<List<double>> tapDownsAt100(
      WidgetTester tester, {
      required double headerHeight,
    }) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final tapDowns = <double>[];
      await tester.pumpWidget(
        _host(
          controller: controller,
          header: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => tapDowns.add(details.localPosition.dy),
            child: SizedBox(height: headerHeight),
          ),
        ),
      );

      controller.jumpTo(50);
      await tester.pump();
      await tester.tapAt(const Offset(10, 100));
      await tester.pump();
      return tapDowns;
    }

    testWidgets('у закреплённого среза прокрутка не сдвигает точку', (
      tester,
    ) async {
      expect(await tapDownsAt100(tester, headerHeight: 150), [100]);
    });

    testWidgets('у прокручиваемого среза точка сдвинута прокруткой', (
      tester,
    ) async {
      expect(await tapDownsAt100(tester, headerHeight: 250), [150]);
    });
  });

  testWidgets('диктор видит закреплённый срез вне прокручиваемого списка, '
      'а прокручиваемый срез — внутри него', (tester) async {
    final semantics = tester.ensureSemantics();
    Widget host(double headerHeight) => _host(
      controller: null,
      header: SizedBox(height: headerHeight, child: const Text('Шапка')),
    );

    await tester.pumpWidget(host(150));
    expect(
      tester
          .getSemantics(find.text('Шапка'))
          .isTagged(RenderViewport.excludeFromScrolling),
      isTrue,
    );

    await tester.pumpWidget(host(250));
    expect(
      tester
          .getSemantics(find.text('Шапка'))
          .isTagged(RenderViewport.excludeFromScrolling),
      isFalse,
    );
    semantics.dispose();
  });
}

const _headerKey = ValueKey('header');

ValueKey<String> _rowKey(int index) => ValueKey('row-$index');

Future<void> _revealAtTop(WidgetTester tester, Key row) async {
  await Scrollable.ensureVisible(tester.element(find.byKey(row)));
  await tester.pump();
}

Widget _host({
  required ScrollController? controller,
  required Widget header,
  double viewportHeight = _viewportHeight,
  ValueChanged<int>? onRowTap,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: viewportHeight,
        child: CustomScrollView(
          controller: controller,
          slivers: [
            HalfPinnedSliver(child: header),
            SliverList.builder(
              itemCount: 30,
              itemBuilder: (context, index) => GestureDetector(
                key: _rowKey(index),
                behavior: HitTestBehavior.opaque,
                onTap: () => onRowTap?.call(index),
                child: const SizedBox(height: _rowHeight),
              ),
            ),
          ],
        ),
      ),
    ),
  ),
);
