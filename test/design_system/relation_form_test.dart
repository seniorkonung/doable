import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/path_rail.dart';
import 'package:doable/src/design_system/components/relation_form.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
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
    group('в $themeName теме', () {
      testWidgets('выбираемое поле — плоскость accent-soft с кольцом accent, '
          'подписью и пунктирным глифом accent', (tester) async {
        await tester.pumpWidget(
          _app(
            _form(
              role: RelationFormRole.source,
              other: const RelationFieldFilled('Много ходить'),
            ),
            brightness: brightness,
          ),
        );

        final decoration = _decoration(tester, 'Из этого списка');
        expect(decoration.color, colors.accentSoft);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(DoableMetrics.radiusLg),
        );
        expect(decoration.border, Border.all(color: colors.accent, width: 1.5));
        expect(
          (decoration.border! as Border).top.strokeAlign,
          BorderSide.strokeAlignInside,
        );
        _expectStyle(
          _style(tester, 'Сейчас выбирается'),
          DoableType.label.copyWith(color: colors.accent),
        );
        _expectStyle(
          _style(tester, 'Из этого списка'),
          DoableType.action.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.muted,
          ),
        );
        _expectGlyph(
          tester,
          PathGlyphShape.diamond,
          PathGlyphOutline.dashed,
          colors.accent,
        );
      });

      testWidgets('заполненное поле — плоскость fill с названием ink '
          'начертания 500 и сплошным глифом grip, архивное — muted', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            _form(
              role: RelationFormRole.source,
              other: const RelationFieldFilled('Много ходить'),
            ),
            brightness: brightness,
          ),
        );

        final decoration = _decoration(tester, 'Много ходить');
        expect(decoration.color, colors.fill);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(DoableMetrics.radiusLg),
        );
        expect(decoration.border, isNull);
        _expectStyle(
          _style(tester, 'Много ходить'),
          DoableType.action.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.ink,
          ),
        );
        _expectGlyph(
          tester,
          PathGlyphShape.ring,
          PathGlyphOutline.solid,
          colors.grip,
        );

        await tester.pumpWidget(
          _app(
            _form(
              role: RelationFormRole.source,
              other: const RelationFieldFilled('Много ходить', archived: true),
            ),
            brightness: brightness,
          ),
        );
        _expectStyle(
          _style(tester, 'Много ходить'),
          DoableType.action.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.muted,
          ),
        );
        _expectGlyph(
          tester,
          PathGlyphShape.ring,
          PathGlyphOutline.solid,
          colors.grip,
        );
      });

      testWidgets('пустое поле — плоскость fill с текстом muted начертания '
          '400 и пунктирным глифом grip', (tester) async {
        await tester.pumpWidget(
          _app(
            _form(
              role: RelationFormRole.source,
              other: const RelationFieldEmpty(),
            ),
            brightness: brightness,
          ),
        );

        final decoration = _decoration(tester, 'Ещё не выбрано');
        expect(decoration.color, colors.fill);
        expect(decoration.border, isNull);
        _expectStyle(
          _style(tester, 'Ещё не выбрано'),
          DoableType.action.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.muted,
          ),
        );
        _expectGlyph(
          tester,
          PathGlyphShape.ring,
          PathGlyphOutline.dashed,
          colors.grip,
        );
      });

      for (final (kind, word, expectStroke) in [
        (
          RelationFormKind.need,
          'Нужно',
          (RelationStrokeKind stroke) => expect(
            stroke,
            isA<RelationStrokeNeed>().having(
              (need) => need.color,
              'color',
              colors.grip,
            ),
          ),
        ),
        (
          RelationFormKind.can,
          'Можно',
          (RelationStrokeKind stroke) => expect(
            stroke,
            isA<RelationStrokeCan>().having(
              (can) => can.color,
              'color',
              colors.grip,
            ),
          ),
        ),
        (
          RelationFormKind.undetermined,
          'Нужно или можно: ещё не выбрано',
          (RelationStrokeKind stroke) =>
              expect(stroke, isA<RelationStrokeUndetermined>()),
        ),
      ]) {
        testWidgets('вид ${kind.name}: линия между полями и отметка у слова '
            'одного вида, слово в стиле section', (tester) async {
          await tester.pumpWidget(
            _app(
              _form(
                role: RelationFormRole.related,
                other: const RelationFieldFilled('Быть здоровым'),
                kind: kind,
                kindWord: word,
              ),
              brightness: brightness,
            ),
          );

          final strokes = tester
              .widgetList<RelationStroke>(find.byType(RelationStroke))
              .toList();
          // Под ромбом, на строке вида, над кольцом и у слова.
          expect(strokes, hasLength(4));
          for (final stroke in strokes) {
            expectStroke(stroke.kind);
          }
          expectStroke(
            tester.widget<RelationKindMark>(find.byType(RelationKindMark)).kind,
          );
          _expectStyle(
            _style(tester, word),
            DoableType.section.copyWith(
              color: kind == RelationFormKind.undetermined
                  ? colors.muted
                  : colors.ink,
            ),
          );
        });
      }
    });
  }

  testWidgets('три строки рейки сверху вниз: ромб, строка вида, кольцо; '
      'у первой нет линии сверху, у последней — снизу', (tester) async {
    await tester.pumpWidget(
      _app(
        _form(
          role: RelationFormRole.related,
          other: const RelationFieldFilled('Быть здоровым'),
        ),
      ),
    );

    final rails = tester.widgetList<PathRail>(find.byType(PathRail)).toList();
    expect(rails, hasLength(3));
    expect(
      rails[0].mark,
      isA<PathRailGlyph>()
          .having((mark) => mark.glyph.shape, 'shape', PathGlyphShape.diamond)
          .having((mark) => mark.above, 'above', isNull)
          .having((mark) => mark.below, 'below', isA<RelationStrokeNeed>()),
    );
    expect(rails[1].mark, isA<PathRailStroke>());
    expect(
      rails[2].mark,
      isA<PathRailGlyph>()
          .having((mark) => mark.glyph.shape, 'shape', PathGlyphShape.ring)
          .having((mark) => mark.above, 'above', isA<RelationStrokeNeed>())
          .having((mark) => mark.below, 'below', isNull),
    );
    final top = tester.getRect(find.byType(PathRail).at(0));
    final middle = tester.getRect(find.byType(PathRail).at(1));
    final bottom = tester.getRect(find.byType(PathRail).at(2));
    expect(middle.top, top.bottom);
    expect(bottom.top, middle.bottom);
    expect(
      tester.getRect(find.text('Быть здоровым')).top,
      lessThan(tester.getRect(find.text('Нужно')).top),
    );
    expect(
      tester.getRect(find.text('Нужно')).top,
      lessThan(tester.getRect(find.text('Сейчас выбирается')).top),
    );
  });

  testWidgets('поле — в 10 от рейки, не ниже 48, с отступами 13 и 14; '
      'строка вида 52 со словом в 24 от рейки', (tester) async {
    await tester.pumpWidget(
      _app(
        _form(role: RelationFormRole.source, other: const RelationFieldEmpty()),
      ),
    );

    final form = tester.getRect(find.byType(RelationForm));
    final empty = tester.getRect(_field('Ещё не выбрано'));
    expect(empty.left, form.left + 22 + 10);
    expect(empty.right, form.right);
    expect(empty.height, 48);
    final emptyText = tester.getRect(find.text('Ещё не выбрано'));
    expect(emptyText.left - empty.left, 14);
    expect(emptyText.top - empty.top, 13);

    final chosen = tester.getRect(_field('Из этого списка'));
    final caption = tester.getRect(find.text('Сейчас выбирается'));
    final text = tester.getRect(find.text('Из этого списка'));
    expect(caption.left - chosen.left, 14);
    expect(caption.top - chosen.top, 13);
    expect(text.top - caption.bottom, 2);
    expect(chosen.bottom - text.bottom, 13);

    final kindRow = tester.getRect(find.byType(PathRail).at(1));
    expect(kindRow.height, 52);
    final mark = tester.getRect(find.byType(RelationKindMark));
    expect(mark.size, const Size(15, 2));
    expect(mark.left, form.left + 22 + 24);
    expect(mark.center.dy, kindRow.center.dy);
    final word = tester.getRect(find.text('Нужно'));
    expect(word.left - mark.right, 7);
    expect(word.center.dy, kindRow.center.dy);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets('при масштабе текста $textScale длинное название '
        'заполненного поля переносится без обрезки на ширине тела листа', (
      tester,
    ) async {
      const longName =
          'Каждое утро проходить пешком до работы через парк и обратно, '
          'даже когда идёт дождь';
      await tester.pumpWidget(
        _app(
          _form(
            role: RelationFormRole.related,
            replacing: 'Много ходить по вечерам вдоль реки',
            other: const RelationFieldFilled(longName),
            kind: RelationFormKind.undetermined,
            kindWord: 'Нужно или можно: ещё не выбрано',
          ),
          textScale: textScale,
        ),
      );

      expect(tester.takeException(), isNull);
      final form = tester.getRect(find.byType(RelationForm));
      for (final text in [
        longName,
        'Сейчас выбирается',
        'Вместо: Много ходить по вечерам вдоль реки',
        'Нужно или можно: ещё не выбрано',
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.textScaler.scale(16), 16 * textScale);
        final rect = tester.getRect(find.text(text));
        expect(rect.right, lessThanOrEqualTo(form.right));
        expect(rect.bottom, lessThanOrEqualTo(form.bottom));
      }
      final name = tester.renderObject<RenderParagraph>(find.text(longName));
      expect(
        name.getMaxIntrinsicWidth(double.infinity),
        greaterThan(tester.getSize(find.text(longName)).width),
      );
      final field = tester.getRect(_field(longName));
      expect(field.bottom - tester.getRect(find.text(longName)).bottom, 13);
    });
  }

  testWidgets('экранный диктор слышит каждое поле одним узлом без нажатия: '
      'роль, состояние и название, у архивного — архивность', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        _form(
          role: RelationFormRole.related,
          replacing: 'Много ходить',
          other: const RelationFieldFilled('Быть здоровым', archived: true),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Быть здоровым')),
      matchesSemantics(label: 'Исходное намерение\nБыть здоровым\nВ архиве'),
    );
    expect(
      tester.getSemantics(find.text('Вместо: Много ходить')),
      matchesSemantics(
        label: 'Связанное намерение\nСейчас выбирается\nВместо: Много ходить',
      ),
    );
    expect(
      tester.getSemantics(find.text('Нужно')),
      matchesSemantics(label: 'Нужно'),
    );

    await tester.pumpWidget(
      _app(
        _form(role: RelationFormRole.source, other: const RelationFieldEmpty()),
      ),
    );
    expect(
      tester.getSemantics(find.text('Из этого списка')),
      matchesSemantics(
        label: 'Исходное намерение\nСейчас выбирается\nИз этого списка',
      ),
    );
    expect(
      tester.getSemantics(find.text('Ещё не выбрано')),
      matchesSemantics(label: 'Связанное намерение\nЕщё не выбрано'),
    );
    semantics.dispose();
  });

  testWidgets('в форме нет кнопок и шевронов', (tester) async {
    await tester.pumpWidget(
      _app(
        _form(
          role: RelationFormRole.source,
          other: const RelationFieldFilled('Много ходить'),
        ),
      ),
    );

    for (final type in [GestureDetector, InkWell, Icon]) {
      expect(
        find.descendant(
          of: find.byType(RelationForm),
          matching: find.byType(type),
        ),
        findsNothing,
      );
    }
  });
}

RelationForm _form({
  required RelationFormRole role,
  required RelationFieldShown other,
  String? replacing,
  RelationFormKind kind = RelationFormKind.need,
  String kindWord = 'Нужно',
}) => RelationForm.choosing(
  role: role,
  chosen: RelationFieldChoosing(replacing: replacing),
  other: other,
  kind: kind,
  texts: RelationFormTexts(
    sourceRole: 'Исходное намерение',
    relatedRole: 'Связанное намерение',
    choosingNow: 'Сейчас выбирается',
    fromList: 'Из этого списка',
    replacing: (name) => 'Вместо: $name',
    notChosen: 'Ещё не выбрано',
    archived: 'В архиве',
    kind: kindWord,
  ),
);

/// Плоскость поля, в котором стоит [text].
Finder _field(String text) => find
    .ancestor(of: find.text(text), matching: find.byType(DecoratedBox))
    .first;

BoxDecoration _decoration(WidgetTester tester, String text) =>
    tester.widget<DecoratedBox>(_field(text)).decoration as BoxDecoration;

/// Проверяет глиф поля, которое показывает только форма.
void _expectGlyph(
  WidgetTester tester,
  PathGlyphShape shape,
  PathGlyphOutline outline,
  Color color,
) {
  final glyph = tester
      .widgetList<PathGlyph>(find.byType(PathGlyph))
      .singleWhere((glyph) => glyph.shape == shape);
  expect(glyph.outline, outline);
  expect(glyph.color, color);
  expect(glyph.size, 14);
}

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

void _expectStyle(TextStyle actual, TextStyle expected) {
  expect(actual.color, expected.color);
  expect(actual.fontFamily, expected.fontFamily);
  expect(actual.fontSize, expected.fontSize);
  expect(actual.fontWeight, expected.fontWeight);
  expect(actual.height, expected.height);
  expect(actual.letterSpacing, expected.letterSpacing);
}

/// Ширина тела листа на телефоне 360 dp: поля листа 12 и тела 8.
Widget _app(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: SingleChildScrollView(
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: 320, child: child),
        ),
      ),
    ),
  ),
);
