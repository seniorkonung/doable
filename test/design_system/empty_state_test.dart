import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/empty_state.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
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

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме с иконкой и кнопкой над заголовком стоит '
        'круг fill 52 с иконкой 24 цвета muted, а под текстом — тихая '
        'кнопка', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          room: 400,
          state: EmptyState(
            title: _searchTitle,
            text: _searchText,
            icon: DoableIconData.search,
            action: (label: 'Сбросить фильтры', onPressed: () {}),
          ),
        ),
      );

      final tile = tester.getRect(_tile);
      expect(tile.size, const Size.square(52));
      expect(
        tester.widget<DecoratedBox>(_tile).decoration,
        BoxDecoration(color: colors.fill, shape: BoxShape.circle),
      );
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.search);
      expect(icon.size, 24);
      expect(icon.color, colors.muted);
      expect(tester.getCenter(find.byType(DoableIcon)), tile.center);

      final title = tester.getRect(find.text(_searchTitle));
      final text = tester.getRect(find.text(_searchText));
      expect(title.top - tile.bottom, 14);
      expect(text.top - title.bottom, 6);
      // Тихая кнопка — плашка fill с подписью ink.
      expect(tester.widget<Material>(_buttonPlate).color, colors.fill);
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('Сбросить фильтры'))
            .text
            .style!
            .color,
        colors.ink,
      );
      final plate = tester.getRect(_buttonPlate);
      expect(plate.top - text.bottom, 16);
      final room = tester.getRect(find.byType(EmptyState));
      expect(tile.center.dx, room.center.dx);
      expect(plate.center.dx, room.center.dx);
    });
  }

  testWidgets('кнопка объявляется кнопкой, и её нажатие получает '
      'потребитель', (tester) async {
    final semantics = tester.ensureSemantics();
    var resets = 0;
    await tester.pumpWidget(
      _app(
        room: 400,
        state: EmptyState(
          title: _searchTitle,
          text: _searchText,
          icon: DoableIconData.search,
          action: (label: 'Сбросить фильтры', onPressed: () => resets++),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text(_searchTitle)),
      isSemantics(label: _searchTitle, isHeader: true),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Сбросить фильтры')),
      isSemantics(
        label: 'Сбросить фильтры',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Сбросить фильтры'));
    expect(resets, 1);
    semantics.dispose();
  });

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

  testWidgets('с иконкой, кнопкой и текстом масштаба 2 в низком месте блок '
      'начинается сверху и прокручивается до кнопки', (tester) async {
    await tester.pumpWidget(
      _app(
        room: 200,
        textScale: 2,
        state: EmptyState(
          title: _searchTitle,
          text: _searchText,
          icon: DoableIconData.search,
          action: (label: 'Сбросить фильтры', onPressed: () {}),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getRect(_tile).top, 0);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1000));
    await tester.pump();
    expect(tester.getRect(_buttonPlate).bottom, lessThanOrEqualTo(200));
  });
}

const _title = 'Тегов пока нет';
const _searchTitle = 'Нет действий с таким названием';
const _searchText = 'Попробуйте название короче.';

final _tile = find.ancestor(
  of: find.byType(DoableIcon),
  matching: find.byType(DecoratedBox),
);

final _buttonPlate = find.descendant(
  of: find.byType(Button),
  matching: find.byType(Material),
);
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
