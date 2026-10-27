import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
    testWidgets('в $themeName теме шапка показывает второй заголовок '
        'стилем page-title в ink с полями 2 сверху и 6 снизу', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(brightness, 'Быть здоровым'));

      final text = find.text('Быть здоровым');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final style = paragraph.text.style!;
      expect(style.color, colors.ink);
      expect(style.fontFamily, DoableType.pageTitle.fontFamily);
      expect(style.fontSize, DoableType.pageTitle.fontSize);
      expect(style.fontWeight, DoableType.pageTitle.fontWeight);
      expect(style.height, DoableType.pageTitle.height);
      expect(style.letterSpacing, DoableType.pageTitle.letterSpacing);
      final head = tester.getRect(find.byType(PageHead));
      final title = tester.getRect(text);
      expect(title.left, head.left);
      expect(title.right, head.right);
      expect(title.top - head.top, 2);
      expect(head.bottom - title.bottom, 6);
      final data = tester.getSemantics(text).getSemanticsData();
      expect(data.label, 'Быть здоровым');
      expect(data.headingLevel, 2);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      semantics.dispose();
    });

    testWidgets('в $themeName теме длинное название, в том числе без пробелов, '
        'переносится целиком при крупном тексте', (tester) async {
      for (final title in [
        'Поддерживать здоровье и хорошее самочувствие каждый день',
        'Самосовершенствование' * 8,
      ]) {
        await tester.pumpWidget(_app(brightness, title, textScale: 2));

        final text = find.text(title);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.maxLines, isNull);
        expect(paragraph.text.toPlainText(), title);
        expect(paragraph.textScaler.scale(24), 48);
        expect(paragraph.size.height, greaterThan(60));
        expect(
          tester.getSize(find.byType(PageHead)).height,
          paragraph.size.height + 8,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }
}

Widget _app(Brightness brightness, String name, {double textScale = 1}) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: SingleChildScrollView(
            child: SizedBox(width: 320, child: PageHead(name: name)),
          ),
        ),
      ),
    );
