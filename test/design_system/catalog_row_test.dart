import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/catalog_row.dart';
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
// оставляет тексту 300 − 16 − 16 = 268: в строку `action` помещается
// 16 знаков, в строку `note` — 19.
void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме строка — карточка fill с углами radius-lg: '
        'название action цвета ink, описание note цвета muted, а линия меток '
        'и тегов под ними', (tester) async {
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
              of: find.byType(CatalogRow),
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

      final row = tester.getRect(find.byType(CatalogRow));
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
    });

    testWidgets('в $themeName теме у архивированной строки название цвета '
        'muted, а описание, линия меток и тегов прежние', (tester) async {
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
      final row = tester.getRect(find.byType(CatalogRow));
      expect(row.size, const Size(300, 95));
      expect(
        tester.getTopLeft(find.byType(TagLine)),
        row.topLeft + const Offset(16, 63),
      );
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
    expect(tester.getSize(find.byType(CatalogRow)).height, 67);
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
      find.descendant(of: find.byType(CatalogRow), matching: find.byType(Text)),
      findsOneWidget,
    );
    // 11 + 22 + 12.
    expect(tester.getSize(find.byType(CatalogRow)).height, 45);
  });

  testWidgets('вся карточка — одна кнопка с названием label, метки скрыты '
      'от диктора, а нажатие в любом месте открывает строку', (tester) async {
    final semantics = tester.ensureSemantics();
    var openings = 0;

    await tester.pumpWidget(
      _app(
        row: _row(
          description: 'Утро',
          marks: const [
            Badge.mark(icon: DoableIconData.bolt, tone: BadgeTone.ink),
          ],
          tags: const [TagChip.small(name: 'Дом', color: DoableTagColor.teal)],
          onOpen: () => openings++,
        ),
      ),
    );

    expect(find.byType(InkWell), findsOneWidget);
    final button = tester.getSemantics(find.bySemanticsLabel(_label));
    expect(
      button,
      isSemantics(label: _label, isButton: true, hasTapAction: true),
    );
    expect(button.childrenCount, 0);
    expect(tester.getRect(find.byType(InkWell)), tester.getRect(_card));

    // Углы карточки скруглены, поэтому крайние точки взяты на её кромках
    // за дугой.
    final card = tester.getRect(_card);
    for (final point in [
      card.topLeft + const Offset(DoableMetrics.radiusLg, 1),
      tester.getCenter(find.text('Бег')),
      tester.getCenter(find.byType(TagLine)),
      card.bottomRight - const Offset(DoableMetrics.radiusLg, 1),
    ]) {
      final before = openings;
      await tester.tapAt(point);
      expect(openings, before + 1);
    }
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 строка растёт вместе с текстом и '
      'линией', (tester) async {
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
    // 11 + 44 + 2 + 40 + 8 + 38 + 12.
    expect(tester.getSize(find.byType(CatalogRow)).height, 155);
  });
}

const _label = 'Открыть: Бег, действие. Утро. Теги: Дом';

final _card = find
    .descendant(of: find.byType(CatalogRow), matching: find.byType(Material))
    .first;

CatalogRow _row({
  String name = 'Бег',
  String? description,
  bool archived = false,
  List<Badge> marks = const [],
  List<TagChip> tags = const [],
  VoidCallback? onOpen,
}) => CatalogRow(
  name: name,
  description: description,
  archived: archived,
  marks: marks,
  tags: tags,
  label: _label,
  onOpen: onOpen ?? () {},
);

Widget _app({
  required CatalogRow row,
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
