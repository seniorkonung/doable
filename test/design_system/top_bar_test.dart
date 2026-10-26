import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Экран 390 с системным отступом 54, как в макете экрана выбора.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме панель высотой 44 стоит под системным '
        'отступом: крестик 24 цвета ink по центру области 44 в space-2 от '
        'края и заголовок title цвета ink по центру панели', (tester) async {
      await _pump(tester, _app(brightness: brightness, bar: _bar()));

      expect(tester.getTopLeft(find.byKey(_body)).dy, 54 + 44);

      final cross = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(cross.icon, DoableIconData.close);
      expect(cross.size, 24);
      expect(cross.color, colors.ink);
      expect(tester.getRect(_crossArea()), const Rect.fromLTWH(8, 54, 44, 44));
      expect(tester.getCenter(find.byWidget(cross)), const Offset(30, 76));

      final title = _style(tester, 'Выбор');
      expect(title.color, colors.ink);
      expect(title.fontSize, DoableType.title.fontSize);
      expect(title.fontWeight, DoableType.title.fontWeight);
      expect(title.height, DoableType.title.height);
      expect(tester.getCenter(find.text('Выбор')), const Offset(195, 76));
    });

    testWidgets('в $themeName теме строка назначения стоит под заголовком: '
        'кнопка 44 шириной панели без 56 с каждой стороны, подзаголовок hint '
        'цвета muted и в его конце шеврон 12 того же цвета', (tester) async {
      await _pump(
        tester,
        _app(
          brightness: brightness,
          bar: _purposeBar(subtitle: 'Для чего'),
        ),
      );

      expect(tester.getTopLeft(find.byKey(_body)).dy, 54 + 44);
      expect(
        tester.getRect(_purposeButton()),
        const Rect.fromLTWH(56, 54, 278, 44),
      );
      expect(tester.getRect(_crossArea()), const Rect.fromLTWH(8, 54, 44, 44));

      final title = _style(tester, 'Выбор');
      expect(title.color, colors.ink);
      expect(title.fontSize, DoableType.title.fontSize);
      expect(title.fontWeight, DoableType.title.fontWeight);
      final subtitle = _style(tester, 'Для чего');
      expect(subtitle.color, colors.muted);
      expect(subtitle.fontSize, DoableType.hint.fontSize);
      expect(subtitle.fontWeight, DoableType.hint.fontWeight);
      expect(subtitle.height, DoableType.hint.height);

      final chevron = tester.widget<DoableIcon>(_chevron());
      expect(chevron.size, 12);
      expect(chevron.color, colors.muted);

      // Две строки 22 и 18 по центру кнопки 44, шеврон в 5 после текста.
      final titleRect = tester.getRect(find.text('Выбор'));
      final subtitleRect = tester.getRect(find.text('Для чего'));
      final chevronRect = tester.getRect(_chevron());
      expect(titleRect.top, 56);
      expect(titleRect.height, 22);
      expect(titleRect.center.dx, 195);
      expect(subtitleRect.top, 78);
      expect(subtitleRect.height, 18);
      expect(chevronRect.left - subtitleRect.right, 5);
      expect(chevronRect.center.dy, subtitleRect.center.dy);
      expect((subtitleRect.left + chevronRect.right) / 2, 195);
      expect(find.byType(PathGlyph), findsNothing);
    });

    for (final (mark, shape) in [
      (TopBarPurposeMark.sourceField, PathGlyphShape.diamond),
      (TopBarPurposeMark.relatedField, PathGlyphShape.ring),
    ]) {
      testWidgets('в $themeName теме отметка ${mark.name} — пунктирный '
          '${shape.name} 12 цвета muted в 5 перед подзаголовком, а высота '
          'панели и кнопки остаётся 44', (tester) async {
        await _pump(
          tester,
          _app(
            brightness: brightness,
            bar: _purposeBar(subtitle: 'Для чего', mark: mark),
          ),
        );

        final glyph = tester.widget<PathGlyph>(find.byType(PathGlyph));
        expect(glyph.shape, shape);
        expect(glyph.outline, PathGlyphOutline.dashed);
        expect(glyph.size, 12);
        expect(glyph.color, colors.muted);

        expect(tester.getTopLeft(find.byKey(_body)).dy, 54 + 44);
        expect(
          tester.getRect(_purposeButton()),
          const Rect.fromLTWH(56, 54, 278, 44),
        );
        final glyphRect = tester.getRect(find.byType(PathGlyph));
        final subtitleRect = tester.getRect(find.text('Для чего'));
        final chevronRect = tester.getRect(_chevron());
        expect(glyphRect.size, const Size.square(12));
        expect(subtitleRect.left - glyphRect.right, 5);
        expect(glyphRect.center.dy, subtitleRect.center.dy);
        expect(chevronRect.left - subtitleRect.right, 5);
        expect((glyphRect.left + chevronRect.right) / 2, 195);
      });
    }
  }

  testWidgets('длинный заголовок занимает одну строку не шире панели без 64 '
      'с каждой стороны и кончается многоточием', (tester) async {
    const title = 'Выбор исходного намерения для нового дневного выбора';

    await _pump(tester, _app(bar: _bar(title: title)));

    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(
      tester.getRect(find.text(title)),
      const Rect.fromLTWH(64, 65, 262, 22),
    );
  });

  for (final width in [360.0, 390.0]) {
    for (final subtitle in [
      'Новый дневной выбор: исходное намерение',
      'Новый дневной выбор: конечное действие',
    ]) {
      testWidgets('на ширине ${width.toInt()} подзаголовок «$subtitle» стоит '
          'в одну строку и обрезается многоточием, шеврон виден, а доступное '
          'название кнопки содержит подзаголовок целиком', (tester) async {
        final semantics = tester.ensureSemantics();

        await _pump(
          tester,
          _app(
            bar: _purposeBar(
              title: 'Выбор исходного намерения',
              subtitle: subtitle,
              label: 'Выбор исходного намерения. $subtitle',
            ),
          ),
          width: width,
        );

        final paragraph = tester.renderObject<RenderParagraph>(
          find.text(subtitle),
        );
        expect(paragraph.didExceedMaxLines, isTrue);
        final button = tester.getRect(_purposeButton());
        expect(button.width, width - 2 * 56);
        final line = tester.getRect(find.text(subtitle));
        final chevron = tester.getRect(_chevron());
        expect(line.height, 18);
        expect(line.left, greaterThanOrEqualTo(button.left));
        expect(chevron.left - line.right, 5);
        expect(chevron.size, const Size.square(12));
        expect(chevron.right, lessThanOrEqualTo(button.right));
        expect(
          tester.getSemantics(_purposeButton()).label,
          'Выбор исходного намерения. $subtitle',
        );
        semantics.dispose();
      });
    }
  }

  testWidgets('длинный подзаголовок с отметкой обрезается многоточием, '
      'отметка и шеврон видны внутри кнопки высотой 44, а отметка не '
      'озвучивается отдельно', (tester) async {
    final semantics = tester.ensureSemantics();
    const subtitle = 'Изменение связи: связанное намерение';

    await _pump(
      tester,
      _app(
        bar: _purposeBar(
          title: 'Выбор намерения',
          subtitle: subtitle,
          label: 'Выбор намерения. $subtitle',
          mark: TopBarPurposeMark.relatedField,
        ),
      ),
      width: 360,
    );

    final paragraph = tester.renderObject<RenderParagraph>(find.text(subtitle));
    expect(paragraph.didExceedMaxLines, isTrue);
    final button = tester.getRect(_purposeButton());
    expect(button.height, 44);
    final glyph = tester.getRect(find.byType(PathGlyph));
    final line = tester.getRect(find.text(subtitle));
    final chevron = tester.getRect(_chevron());
    expect(glyph.size, const Size.square(12));
    expect(glyph.left, greaterThanOrEqualTo(button.left));
    expect(line.left - glyph.right, 5);
    expect(chevron.left - line.right, 5);
    expect(chevron.size, const Size.square(12));
    expect(chevron.right, lessThanOrEqualTo(button.right));
    expect(
      tester.getSemantics(_purposeButton()),
      isSemantics(
        label: 'Выбор намерения. $subtitle',
        isButton: true,
        hasTapAction: true,
        hasExpandedState: true,
        namesRoute: true,
        children: const [],
      ),
    );
    semantics.dispose();
  });

  testWidgets('крестик — кнопка с названием от потребителя и вызывает его '
      'обработчик, а заголовок объявляется заголовком и называет маршрут', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var closings = 0;

    await _pump(tester, _app(bar: _bar(onClose: () => closings++)));

    final cross = tester.getSemantics(find.bySemanticsLabel('Закрыть выбор'));
    expect(
      cross,
      isSemantics(label: 'Закрыть выбор', isButton: true, hasTapAction: true),
    );
    expect(cross.childrenCount, 0);
    expect(
      tester.getSemantics(find.text('Выбор')),
      isSemantics(
        label: 'Выбор',
        isHeader: true,
        namesRoute: true,
        isButton: false,
      ),
    );

    await tester.tap(_crossArea());
    expect(closings, 1);
    semantics.dispose();
  });

  for (final expanded in [false, true]) {
    testWidgets('заголовок со строкой назначения — один узел-кнопка с '
        'названием потребителя, признаком раскрытия '
        '${expanded ? 'открытого' : 'закрытого'} листа и названием маршрута; '
        'нажатие в любой точке кнопки вызывает обработчик', (tester) async {
      final semantics = tester.ensureSemantics();
      var openings = 0;

      await _pump(
        tester,
        _app(
          bar: _purposeBar(expanded: expanded, onOpen: () => openings++),
        ),
      );

      final button = tester.getSemantics(_purposeButton());
      expect(
        button,
        isSemantics(
          label: 'Выбор. Для чего. Показать, что выбирается',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: expanded,
          namesRoute: true,
          children: const [],
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Закрыть выбор')),
        isSemantics(label: 'Закрыть выбор', isButton: true, hasTapAction: true),
      );

      final rect = tester.getRect(_purposeButton());
      for (final point in [
        rect.topLeft + const Offset(1, 1),
        rect.bottomRight - const Offset(1, 1),
        rect.center,
      ]) {
        await tester.tapAt(point);
      }
      expect(openings, 3);
      semantics.dispose();
    });
  }

  testWidgets('при тексте масштаба 2 заголовок по-прежнему вмещается в '
      'панель по центру', (tester) async {
    await _pump(tester, _app(textScale: 2, bar: _bar()));

    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('Выбор'));
    expect(title.height, 44);
    expect(title.center, const Offset(195, 76));
  });

  testWidgets('крупный системный текст увеличивает шапку: при масштабе 2 '
      'панель и кнопка вмещают обе строки в выбранном масштабе без наложения, '
      'шеврон и крестик видны, тело начинается под панелью, а смена масштаба '
      'у показанной панели меняет выделенную ей высоту', (tester) async {
    late StateSetter setScale;
    var scale = 2.0;

    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          setScale = setState;
          return _app(textScale: scale, bar: _purposeBar());
        },
      ),
    );

    expect(tester.takeException(), isNull);
    final title = tester.renderObject<RenderParagraph>(find.text('Выбор'));
    final subtitle = tester.renderObject<RenderParagraph>(
      find.text('Для чего'),
    );
    expect(title.textScaler, const TextScaler.linear(2));
    expect(subtitle.textScaler, const TextScaler.linear(2));
    final titleRect = tester.getRect(find.text('Выбор'));
    final subtitleRect = tester.getRect(find.text('Для чего'));
    expect(titleRect.height, 2 * 22);
    expect(subtitleRect.height, 2 * 18);
    expect(titleRect.top, 54);
    expect(subtitleRect.top, titleRect.bottom);

    const barHeight = 2.0 * 22 + 2 * 18;
    expect(
      tester.widget<TopBar>(find.byType(TopBar)).preferredSize.height,
      barHeight,
    );
    expect(
      tester.getRect(_purposeButton()),
      const Rect.fromLTWH(56, 54, 278, barHeight),
    );
    expect(tester.getTopLeft(find.byKey(_body)).dy, 54 + barHeight);
    final chevron = tester.getRect(_chevron());
    expect(chevron.size, const Size.square(12));
    expect(chevron.bottom, lessThanOrEqualTo(54 + barHeight));
    expect(
      tester.getRect(_crossArea()),
      const Rect.fromLTWH(8, 54 + (barHeight - 44) / 2, 44, 44),
    );

    setScale(() => scale = 1.5);
    await tester.pump();

    const scaledHeight = 1.5 * 22 + 1.5 * 18;
    expect(
      tester.getRect(_purposeButton()),
      const Rect.fromLTWH(56, 54, 278, scaledHeight),
    );
    expect(tester.getTopLeft(find.byKey(_body)).dy, 54 + scaledHeight);
  });
}

TopBar Function(BuildContext) _bar({
  String title = 'Выбор',
  VoidCallback? onClose,
}) =>
    (_) => TopBar(
      title: title,
      closeLabel: 'Закрыть выбор',
      onClose: onClose ?? () {},
    );

TopBar Function(BuildContext) _purposeBar({
  String title = 'Выбор',
  String subtitle = 'Для чего',
  String label = 'Выбор. Для чего. Показать, что выбирается',
  bool expanded = false,
  VoidCallback? onOpen,
  TopBarPurposeMark? mark,
}) =>
    (context) => TopBar.withPurpose(
      context,
      title: title,
      closeLabel: 'Закрыть выбор',
      onClose: () {},
      purpose: TopBarPurpose(
        subtitle: subtitle,
        label: label,
        expanded: expanded,
        onOpen: onOpen ?? () {},
        mark: mark,
      ),
    );

const _body = Key('body');

Finder _crossArea() => find.ancestor(
  of: find.byWidgetPredicate(
    (widget) => widget is DoableIcon && widget.icon == DoableIconData.close,
  ),
  matching: find.byType(InkResponse),
);

Finder _purposeButton() => find.byType(InkWell);

Finder _chevron() => find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == DoableIconData.chevronDown,
);

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Future<void> _pump(
  WidgetTester tester,
  Widget app, {
  double width = 390,
}) async {
  tester.view
    ..physicalSize = Size(width, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

/// Панель строится в контексте под заменённым [MediaQuery], как у экрана,
/// который передаёт её в `Scaffold.appBar`.
Widget _app({
  required TopBar Function(BuildContext) bar,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 54),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: bar(context),
          body: const SizedBox.expand(key: _body),
        ),
      ),
    ),
  ),
);
