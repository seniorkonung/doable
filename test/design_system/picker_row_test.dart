import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_line.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Шрифт тестов рисует каждый знак квадратом в кегль. Строка шириной 300
// оставляет тексту 300 − 48 − 16 = 236: в строку `action` помещается
// 14 знаков, в строку `note` — 16.
void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме строка — карточка fill с углами radius-lg: '
        'название action цвета ink, описание note цвета muted, линия меток и '
        'тегов под ними и стрелка 20 цвета muted по центру области 48', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(
            description: 'Утро',
            marks: const [
              Badge.mark(icon: DoableIconData.bolt, tone: BadgeTone.ink),
            ],
            tags: const [
              TagChip.small(name: 'Дом', color: DoableTagColor.teal),
            ],
          ),
        ),
      );

      final card = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(PickerRow),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(card.color, colors.fill);
      expect(card.borderRadius, BorderRadius.circular(DoableMetrics.radiusLg));
      final name = tester.widget<Text>(find.text('Бег')).style!;
      expect(name.color, colors.ink);
      expect(name.fontSize, DoableType.action.fontSize);
      expect(name.fontWeight, DoableType.action.fontWeight);
      final description = tester.widget<Text>(find.text('Утро')).style!;
      expect(description.color, colors.muted);
      expect(description.fontSize, DoableType.note.fontSize);
      expect(description.fontWeight, DoableType.note.fontWeight);

      final row = tester.getRect(find.byType(PickerRow));
      // 11 + 22 + 2 + 20 + 8 + 20 + 12.
      expect(row.size, const Size(300, 95));
      expect(
        tester.getTopLeft(find.text('Бег')),
        row.topLeft + const Offset(16, 11),
      );
      expect(tester.getTopLeft(find.text('Утро')).dy, row.top + 35);
      expect(
        tester.getTopLeft(find.byType(TagLine)),
        row.topLeft + const Offset(16, 63),
      );

      final arrow = tester.widget<DoableIcon>(find.byType(DoableIcon).last);
      expect(arrow.icon, DoableIconData.arrowUpRight);
      expect(arrow.size, 20);
      expect(arrow.color, colors.muted);
      expect(
        tester.getCenter(find.byWidget(arrow)),
        Offset(row.right - 26, row.center.dy),
      );
      expect(tester.getSize(_arrowArea()), const Size(48, 95));
    });

    testWidgets('в $themeName теме у архивированной строки название цвета '
        'muted, а описание, линия меток и тегов и стрелка прежние', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          row: _row(
            description: 'Утро',
            archived: true,
            marks: const [
              Badge.mark(icon: DoableIconData.archive, tone: BadgeTone.muted),
            ],
            tags: const [
              TagChip.small(name: 'Дом', color: DoableTagColor.teal),
            ],
          ),
        ),
      );

      final name = tester.widget<Text>(find.text('Бег')).style!;
      expect(name.color, colors.muted);
      expect(name.fontSize, DoableType.action.fontSize);
      expect(name.fontWeight, DoableType.action.fontWeight);
      final description = tester.widget<Text>(find.text('Утро')).style!;
      expect(description.color, colors.muted);
      expect(description.fontSize, DoableType.note.fontSize);
      final row = tester.getRect(find.byType(PickerRow));
      expect(row.size, const Size(300, 95));
      expect(
        tester.getTopLeft(find.byType(TagLine)),
        row.topLeft + const Offset(16, 63),
      );
      final arrow = tester.widget<DoableIcon>(find.byType(DoableIcon).last);
      expect(arrow.icon, DoableIconData.arrowUpRight);
      expect(arrow.color, colors.muted);
    });
  }

  testWidgets('длинное название переносится целиком, а не обрезается', (
    tester,
  ) async {
    const name = 'Силовая тренировка';

    await tester.pumpWidget(_app(row: _row(name: name)));

    final paragraph = tester.renderObject<RenderParagraph>(find.text(name));
    expect(paragraph.size.height, 44);
    expect(paragraph.didExceedMaxLines, isFalse);
    // 11 + 44 + 12.
    expect(tester.getSize(find.byType(PickerRow)).height, 67);
  });

  testWidgets('длинное описание занимает две строки и кончается многоточием', (
    tester,
  ) async {
    const description =
        'Сорок минут в зале с тренером, затем растяжка и прогулка домой';

    await tester.pumpWidget(_app(row: _row(description: description)));

    final text = tester.widget<Text>(find.text(description));
    expect(text.maxLines, 2);
    expect(text.overflow, TextOverflow.ellipsis);
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(description),
    );
    expect(paragraph.size.height, 40);
    expect(paragraph.didExceedMaxLines, isTrue);
  });

  testWidgets('у строки без описания, меток и тегов есть только название', (
    tester,
  ) async {
    await tester.pumpWidget(_app(row: _row()));

    expect(find.byType(TagLine), findsNothing);
    expect(
      find.descendant(of: find.byType(PickerRow), matching: find.byType(Text)),
      findsOneWidget,
    );
    // 11 + 22 + 12.
    expect(tester.getSize(find.byType(PickerRow)).height, 45);
  });

  testWidgets('область текста и стрелка — две кнопки со своими названиями, '
      'и каждая вызывает свой обработчик', (tester) async {
    final semantics = tester.ensureSemantics();
    var picks = 0;
    var pageOpenings = 0;

    await tester.pumpWidget(
      _app(
        row: _row(
          description: 'Утро',
          marks: const [
            Badge.mark(icon: DoableIconData.bolt, tone: BadgeTone.ink),
          ],
          tags: const [TagChip.small(name: 'Дом', color: DoableTagColor.teal)],
          onPick: () => picks++,
          onOpenPage: () => pageOpenings++,
        ),
      ),
    );

    final pick = tester.getSemantics(find.bySemanticsLabel(_label));
    expect(
      pick,
      isSemantics(label: _label, isButton: true, hasTapAction: true),
    );
    expect(pick.childrenCount, 0);
    final page = tester.getSemantics(find.bySemanticsLabel(_pageLabel));
    expect(
      page,
      isSemantics(label: _pageLabel, isButton: true, hasTapAction: true),
    );
    expect(page.childrenCount, 0);

    await tester.tap(find.text('Бег'));
    expect((picks, pageOpenings), (1, 0));

    await tester.tap(_arrowArea());
    expect((picks, pageOpenings), (1, 1));
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 строка растёт вместе с текстом и линией, '
      'а стрелка остаётся по центру всей высоты', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2,
        row: _row(
          description: 'Утро',
          tags: const [TagChip.small(name: 'Дом', color: DoableTagColor.teal)],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(PickerRow));
    // 11 + 44 + 2 + 40 + 8 + 38 + 12.
    expect(row.height, 155);
    expect(
      tester.getCenter(find.byType(DoableIcon).last),
      Offset(row.right - 26, row.center.dy),
    );
  });
}

const _label = 'Выбрать: Бег, действие. Утро. Теги: Дом';
const _pageLabel = 'Открыть страницу: Бег';

PickerRow _row({
  String name = 'Бег',
  String? description,
  bool archived = false,
  List<Badge> marks = const [],
  List<TagChip> tags = const [],
  VoidCallback? onPick,
  VoidCallback? onOpenPage,
}) => PickerRow(
  name: name,
  description: description,
  archived: archived,
  marks: marks,
  tags: tags,
  label: _label,
  onPick: onPick ?? () {},
  pageLabel: _pageLabel,
  onOpenPage: onOpenPage ?? () {},
);

Finder _arrowArea() => find.ancestor(
  of: find.byType(DoableIcon).last,
  matching: find.byType(InkWell),
);

Widget _app({
  required PickerRow row,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(child: SizedBox(width: 300, child: row)),
    ),
  ),
);
