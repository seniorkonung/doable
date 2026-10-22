import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме заголовок title цвета ink и текст body цвета muted не шире '
        '260 по центру', (tester) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          room: 400,
          state: const EmptyState(title: _title, text: _text),
        ),
      );

      final titleStyle = _style(tester, _title);
      expect(titleStyle.color, colors.ink);
      expect(titleStyle.fontSize, DoableType.title.fontSize);
      expect(titleStyle.fontWeight, DoableType.title.fontWeight);
      expect(titleStyle.height, DoableType.title.height);
      final textStyle = _style(tester, _text);
      expect(textStyle.color, colors.muted);
      expect(textStyle.fontSize, DoableType.body.fontSize);
      expect(textStyle.fontWeight, DoableType.body.fontWeight);
      expect(
        tester.renderObject<RenderParagraph>(find.text(_text)).textAlign,
        TextAlign.center,
      );

      final title = tester.getRect(find.text(_title));
      final text = tester.getRect(find.text(_text));
      expect(text.width, lessThanOrEqualTo(260));
      expect(text.top - title.bottom, 6);
      final room = tester.getRect(find.byType(EmptyState));
      expect(title.center.dx, room.center.dx);
      expect(text.center.dx, room.center.dx);
    });
  }

  testWidgets('блок стоит по центру оставшегося места над свободными 40', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        room: 400,
        state: const EmptyState(title: _title, text: _text),
      ),
    );

    final title = tester.getRect(find.text(_title));
    final text = tester.getRect(find.text(_text));
    expect((title.top + text.bottom) / 2, (400 - 40) / 2);
  });

  testWidgets('заголовок объявляется заголовком, а текст читается после '
      'него', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        room: 400,
        state: const EmptyState(title: _title, text: _text),
      ),
    );

    expect(
      tester.getSemantics(find.text(_title)),
      isSemantics(label: _title, isHeader: true),
    );
    expect(
      tester.getSemantics(find.text(_text)),
      isSemantics(label: _text, isHeader: false),
    );
    semantics.dispose();
  });

  testWidgets('с крупным шрифтом в низком месте блок начинается сверху и '
      'прокручивается целиком', (tester) async {
    await tester.pumpWidget(
      _app(
        room: 120,
        textScale: 2,
        state: const EmptyState(title: _title, text: _text),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.text(_title)).top, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pump();
    expect(tester.getRect(find.text(_text)).bottom, lessThanOrEqualTo(120));
  });
}

const _title = 'Тегов пока нет';
const _text = 'Введите название в поиске, чтобы создать первый тег.';

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

/// Пустое состояние на месте списка: прокручиваемое тело заданной высоты,
/// остаток которого занимает блок.
Widget _app({
  required EmptyState state,
  required double room,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: 360,
          height: room,
          child: CustomScrollView(
            slivers: [SliverFillRemaining(hasScrollBody: false, child: state)],
          ),
        ),
      ),
    ),
  ),
);
