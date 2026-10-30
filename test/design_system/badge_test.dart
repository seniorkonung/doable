import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    for (final (tone, toneColor) in [
      (BadgeTone.ink, colors.ink),
      (BadgeTone.muted, colors.muted),
    ]) {
      testWidgets('в $themeName теме метка тона ${tone.name} — плитка 22×20 '
          'на bg с углами radius-xs и иконкой 14 цвета ${tone.name} по '
          'центру', (tester) async {
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            child: Badge.mark(icon: DoableIconData.bolt, tone: tone),
          ),
        );

        final mark = tester.getRect(find.bySubtype<Badge>());
        expect(mark.size, const Size(22, 20));
        final ground = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.bySubtype<Badge>(),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(
          ground.decoration,
          BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
          ),
        );
        final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
        expect(icon.icon, DoableIconData.bolt);
        expect(icon.size, 14);
        expect(icon.color, toneColor);
        expect(tester.getCenter(find.byType(DoableIcon)), mark.center);
      });
    }
  }

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме метка архива — слово caption цвета muted '
        'в одну строку на fill с углами radius-xs за значком архива 13', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: const Badge.archived(word: 'Архив'),
        ),
      );

      final badge = tester.getRect(find.bySubtype<Badge>());
      final ground = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.bySubtype<Badge>(),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        ground.decoration,
        BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
        ),
      );

      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.archive);
      expect(icon.size, 13);
      expect(icon.color, colors.muted);

      final word = tester.getRect(find.text('Архив'));
      final iconRect = tester.getRect(find.byType(DoableIcon));
      expect(badge.height, 20);
      expect(word.top - badge.top, 1);
      expect(badge.bottom - word.bottom, 1);
      expect(iconRect.left - badge.left, 5);
      expect(word.left - iconRect.right, DoableMetrics.space1);
      expect(badge.right - word.right, 7);
      expect(iconRect.center.dy, badge.center.dy);

      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.text('Архив'),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.maxLines, 1);
      expect(paragraph.softWrap, isFalse);
      final style = paragraph.text.style!;
      expect(style.color, colors.muted);
      expect(style.fontSize, DoableType.caption.fontSize);
      expect(style.height, DoableType.caption.height);
      expect(style.fontWeight, DoableType.caption.fontWeight);
    });
  }

  testWidgets('диктор читает слово метки архива, и метка не кнопка', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(child: const Badge.archived(word: 'Архив')));

    expect(
      tester.getSemantics(find.text('Архив')),
      matchesSemantics(label: 'Архив'),
    );
    semantics.dispose();
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    for (final word in ['Уже связано', 'Связь в архиве']) {
      testWidgets('в $themeName теме метка-слово «$word» — только слово '
          'caption цвета ink в одну строку на bg с углами radius-xs, без '
          'значка', (tester) async {
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            child: Badge.word(word: word),
          ),
        );

        final badge = tester.getRect(find.bySubtype<Badge>());
        final ground = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.bySubtype<Badge>(),
            matching: find.byType(DecoratedBox),
          ),
        );
        expect(
          ground.decoration,
          BoxDecoration(
            color: colors.bg,
            borderRadius: BorderRadius.circular(DoableMetrics.radiusXs),
          ),
        );
        expect(find.byType(DoableIcon), findsNothing);

        final text = tester.getRect(find.text(word));
        expect(badge.height, 20);
        expect(text.top - badge.top, 1);
        expect(badge.bottom - text.bottom, 1);
        expect(text.left - badge.left, 7);
        expect(badge.right - text.right, 7);

        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: find.text(word), matching: find.byType(RichText)),
        );
        expect(paragraph.maxLines, 1);
        expect(paragraph.softWrap, isFalse);
        final style = paragraph.text.style!;
        expect(style.color, colors.ink);
        expect(style.fontSize, DoableType.caption.fontSize);
        expect(style.height, DoableType.caption.height);
        expect(style.fontWeight, DoableType.caption.fontWeight);
      });
    }
  }

  testWidgets('метка-слово не создаёт узла экранного диктора: слово называет '
      'доступное название строки', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Прогулка, уже связано',
          child: const Badge.word(word: 'Уже связано'),
        ),
      ),
    );

    final node = tester.getSemantics(find.bySubtype<Badge>());
    expect(node.label, 'Прогулка, уже связано');
    expect(node.childrenCount, 0);
    semantics.dispose();
  });

  testWidgets('метка не создаёт узла экранного диктора', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: 'Прогулка',
          child: const Badge.mark(
            icon: DoableIconData.bolt,
            tone: BadgeTone.ink,
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.bySubtype<Badge>());
    expect(node.label, 'Прогулка');
    expect(node.childrenCount, 0);
    semantics.dispose();
  });
}

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(body: Center(child: child)),
);
