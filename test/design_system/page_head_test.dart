import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/page_head.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
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
    testWidgets('в $themeName теме шапка показывает название стилем '
        'page-title в ink с полями 2 сверху и 6 снизу, а нажатие на него '
        'вызывает обработчик', (tester) async {
      final semantics = tester.ensureSemantics();
      var edits = 0;
      await tester.pumpWidget(
        _app(brightness, 'Быть здоровым', onEdit: () => edits++),
      );

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
      expect(
        tester.getSemantics(find.bySemanticsLabel(_editLabel)),
        isSemantics(
          label: _editLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          children: const [],
        ),
      );
      expect(_headingLevel(tester), 2);

      await tester.tap(text);
      expect(edits, 1);
      semantics.dispose();
    });

    testWidgets('в $themeName теме недоступное название остаётся заголовком '
        'и выключенной кнопкой без действия нажатия', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(brightness, 'Быть здоровым'));

      expect(
        tester.getSemantics(find.bySemanticsLabel(_editLabel)),
        isSemantics(
          label: _editLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
          children: const [],
        ),
      );
      expect(_headingLevel(tester), 2);
      final style = tester
          .renderObject<RenderParagraph>(find.text('Быть здоровым'))
          .text
          .style!;
      expect(style.color, colors.ink);
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

    testWidgets('в $themeName теме приглушённое название рисуется цветом '
        'muted, а метка стоит на его строке в 8 после него по центру строки '
        'и не меняет семантику названия', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          brightness,
          'Быть здоровым',
          onEdit: () {},
          muted: true,
          badge: const Badge.archived(word: 'Архив'),
        ),
      );

      final text = find.text('Быть здоровым');
      expect(
        tester.renderObject<RenderParagraph>(text).text.style!.color,
        colors.muted,
      );
      final head = tester.getRect(find.byType(PageHead));
      final title = tester.getRect(text);
      final badge = tester.getRect(find.byType(Badge));
      expect(title.left, head.left);
      expect(title.top - head.top, 2);
      expect(badge.left - title.right, 8);
      expect(badge.center.dy, title.center.dy);
      expect(head.bottom - title.bottom, 6);
      expect(
        tester.getSemantics(find.bySemanticsLabel(_editLabel)),
        isSemantics(
          label: _editLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          children: const [],
        ),
      );
      expect(_headingLevel(tester), 2);
      expect(
        tester.getSemantics(find.text('Архив')),
        matchesSemantics(label: 'Архив'),
      );
      semantics.dispose();
    });

    testWidgets('в $themeName теме метка после названия, которое заполняет '
        'строку, переносится на свою строку в 6 ниже', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          'Поддерживать здоровье и хорошее самочувствие',
          muted: true,
          badge: const Badge.archived(word: 'Архив'),
        ),
      );

      final head = tester.getRect(find.byType(PageHead));
      final title = tester.getRect(
        find.text('Поддерживать здоровье и хорошее самочувствие'),
      );
      final badge = tester.getRect(find.byType(Badge));
      expect(badge.left, head.left);
      expect(badge.top - title.bottom, 6);
      expect(head.bottom - badge.bottom, 6);
    });

    testWidgets('в $themeName теме пояснение стилем hint цвета muted стоит '
        'в 6 под названием, а кнопка на всю ширину шапки — в 10 под '
        'пояснением', (tester) async {
      var presses = 0;
      await tester.pumpWidget(
        _app(
          brightness,
          'Быть здоровым',
          note: _note,
          button: Button.quietBlock(
            label: 'Восстановить из архива',
            onPressed: () => presses++,
          ),
        ),
      );

      final head = tester.getRect(find.byType(PageHead));
      final title = tester.getRect(find.text('Быть здоровым'));
      final note = find.text(_note);
      final style = tester.renderObject<RenderParagraph>(note).text.style!;
      expect(style.color, colors.muted);
      expect(style.fontSize, DoableType.hint.fontSize);
      expect(style.fontWeight, DoableType.hint.fontWeight);
      expect(style.height, DoableType.hint.height);
      final noteRect = tester.getRect(note);
      expect(noteRect.left, head.left);
      expect(noteRect.top - title.bottom, 6);
      final button = tester.getRect(find.byType(Button));
      expect(button.left, head.left);
      expect(button.right, head.right);
      expect(button.top - noteRect.bottom, 10);
      expect(head.bottom - button.bottom, 6);

      await tester.tap(find.text('Восстановить из архива'));
      expect(presses, 1);
    });

    testWidgets('в $themeName теме кнопка без пояснения стоит в 10 под '
        'названием', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          'Быть здоровым',
          button: Button.quietBlock(
            label: 'Восстановить из архива',
            onPressed: () {},
          ),
        ),
      );

      final title = tester.getRect(find.text('Быть здоровым'));
      final button = tester.getRect(find.byType(Button));
      expect(button.top - title.bottom, 10);
      expect(tester.getRect(find.byType(PageHead)).bottom - button.bottom, 6);
    });

    testWidgets('в $themeName теме шапка со всеми частями при крупном тексте '
        'переносит название и пояснение целиком без переполнения', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness,
          'Плавать дважды в неделю',
          muted: true,
          badge: const Badge.archived(word: 'Архив'),
          note: _note,
          button: Button.quietBlock(
            label: 'Восстановить из архива',
            onPressed: () {},
          ),
          textScale: 2,
        ),
      );

      for (final text in ['Плавать дважды в неделю', _note]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.maxLines, isNull);
        expect(paragraph.text.toPlainText(), text);
      }
      final head = tester.getRect(find.byType(PageHead));
      final badge = tester.getRect(find.byType(Badge));
      expect(badge.left, head.left);
      final note = tester.getRect(find.text(_note));
      expect(note.top - badge.bottom, 6);
      expect(tester.getRect(find.byType(Button)).top - note.bottom, 10);
      expect(tester.takeException(), isNull);
    });
  }
}

const _editLabel = 'Изменить название: Быть здоровым';

const _note =
    'Архивированные намерения остаются в сохранённых путях '
    'и не предлагаются в новых.';

int _headingLevel(WidgetTester tester) => tester
    .getSemantics(find.bySemanticsLabel(_editLabel))
    .getSemanticsData()
    .headingLevel;

Widget _app(
  Brightness brightness,
  String name, {
  VoidCallback? onEdit,
  bool muted = false,
  Badge? badge,
  String? note,
  Button? button,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: PageHead(
            name: name,
            editLabel: _editLabel,
            onEdit: onEdit,
            muted: muted,
            badge: badge,
            note: note,
            button: button,
          ),
        ),
      ),
    ),
  ),
);
