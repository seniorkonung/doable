import 'package:doable/src/design_system/components/badge.dart' as ds;
import 'package:doable/src/design_system/components/choice_path.dart';
import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _note = 'Архивные шаги остаются в сохранённом пути.';
const _archive = 'Архив';

const _sourceKey = ValueKey('source');
const _actionKey = ValueKey('action');
const _relationKey = ValueKey('relation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  testWidgets('шаги идут по порядку пути с ромбом, кольцами и кругом, связи '
      'стоят между ними высотой 30, а длинный путь не сокращается', (
    tester,
  ) async {
    const middle = ['Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З'];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          intermediate: [
            for (final name in middle)
              ChoicePathLink(relation: _relation(), step: _step(name)),
          ],
        ),
      ),
    );

    expect(
      tester.widgetList<PathGlyph>(find.byType(PathGlyph)).map((g) => g.shape),
      [
        PathGlyphShape.diamond,
        for (final _ in middle) PathGlyphShape.ring,
        PathGlyphShape.circle,
      ],
    );
    final names = ['А', ...middle, 'Я'];
    expect(find.text('нужно'), findsNWidgets(names.length - 1));
    for (var step = 1; step < names.length; step++) {
      final above = tester.getRect(find.text(names[step - 1]));
      final below = tester.getRect(find.text(names[step]));
      // Шаг на 11 выше и ниже своего текста, а между шагами стоит связь.
      expect(below.top - above.bottom, closeTo(11 + 30 + 11, 1e-6));
    }
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме ромб и круг цвета приоритета выбора, а '
        'кольца и линии — он же пополам с grip, и узор линии следует виду '
        'связи', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            priority: DoablePriority.p2,
            intermediate: [
              ChoicePathLink(
                relation: _relation(priority: DoablePriority.p1),
                step: _step('Б'),
              ),
            ],
            actionRelation: _relation(
              buttonKey: _relationKey,
              kind: ChoicePathRelationKind.can,
              priority: DoablePriority.p1,
            ),
          ),
        ),
      );

      final tone = Color.lerp(colors.p2, colors.grip, .5)!;
      expect(_glyphColors(tester), [colors.p2, tone, colors.p2]);
      final strokes = _strokes(tester);
      expect(strokes.take(3), [
        isA<RelationStrokeNeed>().having((s) => s.color, 'цвет', tone),
        isA<RelationStrokeNeed>().having((s) => s.color, 'цвет', tone),
        isA<RelationStrokeNeed>().having((s) => s.color, 'цвет', tone),
      ]);
      expect(strokes.skip(3), [
        isA<RelationStrokeCan>().having((s) => s.color, 'цвет', tone),
        isA<RelationStrokeCan>().having((s) => s.color, 'цвет', tone),
        isA<RelationStrokeCan>().having((s) => s.color, 'цвет', tone),
      ]);
    });

    testWidgets('в $themeName теме выполненный выбор красит линии и глифы в '
        'grip, а плитка сохраняет приоритет связи', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            done: true,
            priority: DoablePriority.p2,
            intermediate: [
              ChoicePathLink(relation: _relation(), step: _step('Б')),
            ],
            actionRelation: _relation(
              buttonKey: _relationKey,
              priority: DoablePriority.p1,
            ),
          ),
        ),
      );

      expect(_glyphColors(tester), everyElement(colors.grip));
      expect(
        _strokes(tester),
        everyElement(
          isA<RelationStrokeNeed>().having((s) => s.color, 'цвет', colors.grip),
        ),
      );
      expect(
        _tile(tester, _relationKey).color,
        colors.p1.withValues(alpha: .12),
      );
    });

    testWidgets('в $themeName теме плитка показывает приоритет самой связи: '
        'значок p1–p3 на подкраске 12 %, p4 на fill', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            priority: DoablePriority.p3,
            intermediate: [
              ChoicePathLink(
                relation: _relation(
                  priority: DoablePriority.p4,
                  buttonKey: const ValueKey('p4'),
                ),
                step: _step('Б'),
              ),
            ],
            actionRelation: _relation(
              buttonKey: _relationKey,
              priority: DoablePriority.p1,
            ),
          ),
        ),
      );

      final tile = tester.getSize(_tileFinder(_relationKey));
      expect(tile, const Size.square(26));
      expect(_tile(tester, _relationKey).shape, BoxShape.circle);
      expect(
        _tile(tester, _relationKey).color,
        colors.p1.withValues(alpha: .12),
      );
      expect(_tileIcon(tester, _relationKey).color, colors.p1);
      expect(_tile(tester, const ValueKey('p4')).color, colors.fill);
      expect(_tileIcon(tester, const ValueKey('p4')).color, colors.p4);
      final word = tester
          .renderObject<RenderParagraph>(find.text('нужно').first)
          .text
          .style!;
      expect(word.color, colors.muted);
      expect(word.fontSize, DoableType.caption.fontSize);
    });

    testWidgets('в $themeName теме архивированный шаг получает имя muted, глиф '
        'grip и метку, а архивированная связь — линию grip с прежним узором, '
        'плитку fill со значком muted и метку', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            source: _step('А', archived: true),
            actionRelation: _relation(
              buttonKey: _relationKey,
              kind: ChoicePathRelationKind.can,
              archived: true,
            ),
          ),
        ),
      );

      final colorsOfGlyphs = _glyphColors(tester);
      expect(colorsOfGlyphs.first, colors.grip);
      expect(colorsOfGlyphs.last, colors.p1);
      final name = tester.renderObject<RenderParagraph>(find.text('А')).text;
      expect(name.style!.color, colors.muted);
      expect(
        _strokes(tester),
        everyElement(
          isA<RelationStrokeCan>().having((s) => s.color, 'цвет', colors.grip),
        ),
      );
      expect(_tile(tester, _relationKey).color, colors.fill);
      expect(_tileIcon(tester, _relationKey).color, colors.muted);
      expect(find.text(_archive), findsNWidgets(2));
      final hint = tester
          .renderObject<RenderParagraph>(find.text(_note))
          .text
          .style!;
      expect(hint.color, colors.muted);
      expect(hint.fontSize, DoableType.hint.fontSize);
    });
  }

  testWidgets('строка под архивным путём стоит в 10 под ним вровень с '
      'названиями', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(actionStep: _step('Я', archived: true, key: _actionKey)),
      ),
    );

    final note = tester.getRect(find.text(_note));
    expect(note.left, tester.getRect(find.text('Я')).left);
    expect(note.top, tester.getRect(find.byKey(_actionKey)).bottom + 10);
  });

  testWidgets('путь без архива не показывает ни меток, ни строки под ним', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.light, _path()));

    expect(find.text(_archive), findsNothing);
    expect(find.text(_note), findsNothing);
  });

  testWidgets('длинное название с меткой переносится целиком, глиф остаётся на '
      'первой строке, а линия под ним тянется до конца шага', (tester) async {
    final name = 'Длинное исходное намерение ' * 6;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        SizedBox(
          width: 240,
          child: _path(source: _step(name, archived: true, key: _sourceKey)),
        ),
      ),
    );

    final step = tester.getRect(find.byKey(_sourceKey));
    final title = tester.getRect(find.text(name));
    final badge = tester.getRect(find.text(_archive));
    expect(title.height, greaterThan(22 * 3));
    expect(title.top, step.top + 11);
    expect(badge.top, greaterThanOrEqualTo(title.bottom));
    expect(step.bottom, greaterThanOrEqualTo(badge.bottom + 11));
    final glyph = tester.getRect(find.byType(PathGlyph).first);
    expect(glyph.center.dy, step.top + 22);
    final line = tester.getRect(find.byType(RelationStroke).first);
    expect(line.top, glyph.bottom);
    expect(line.bottom, step.bottom);
  });

  testWidgets('шаг и связь — отдельные кнопки не ниже tap-min', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          source: _step('А', key: _sourceKey, onOpen: () => opened.add('А')),
          actionRelation: _relation(
            buttonKey: _relationKey,
            onOpen: () => opened.add('связь'),
          ),
          actionStep: _step(
            'Я',
            key: _actionKey,
            onOpen: () => opened.add('Я'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('А'));
    await tester.tap(find.text('нужно'));
    await tester.tap(find.text('Я'));

    expect(opened, ['А', 'связь', 'Я']);
    expect(tester.getSize(find.byKey(_sourceKey)).height, DoableMetrics.tapMin);
    expect(tester.getSize(find.byKey(_actionKey)).height, DoableMetrics.tapMin);
    expect(
      tester.getSize(find.byKey(_relationKey)).height,
      DoableMetrics.tapMin,
    );
  });

  testWidgets('область связи заходит на 7 на соседние шаги только над самой '
      'кнопкой: дальше нажатие принадлежит шагу', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          source: _step('А', key: _sourceKey, onOpen: () => opened.add('А')),
          actionRelation: _relation(
            buttonKey: _relationKey,
            onOpen: () => opened.add('связь'),
          ),
          actionStep: _step(
            'Я',
            key: _actionKey,
            onOpen: () => opened.add('Я'),
          ),
        ),
      ),
    );

    final above = tester.getRect(find.byKey(_sourceKey));
    final below = tester.getRect(find.byKey(_actionKey));
    final relation = tester.getRect(find.byKey(_relationKey));
    expect(relation.top, above.bottom - 7);
    expect(relation.bottom, below.top + 7);

    await tester.tapAt(Offset(relation.center.dx, above.bottom - 3));
    await tester.tapAt(Offset(relation.center.dx, below.top + 3));
    expect(opened, ['связь', 'связь']);

    opened.clear();
    await tester.tapAt(Offset(relation.right + 10, above.bottom - 3));
    await tester.tapAt(Offset(relation.right + 10, below.top + 3));
    expect(opened, ['А', 'Я']);
  });

  testWidgets('диктор читает шаги и связи отдельными кнопками по порядку пути '
      'с названиями потребителя', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          intermediate: [
            ChoicePathLink(
              relation: _relation(label: 'Связь: для А нужно Б'),
              step: _step('Б', label: 'Промежуточное намерение Б'),
            ),
          ],
          actionRelation: _relation(
            buttonKey: _relationKey,
            label: 'Связь: для Б нужно Я',
          ),
        ),
      ),
    );

    expect(
      tester.semantics.simulatedAccessibilityTraversal(
        startNode: find.semantics.byLabel('Шаг А'),
        endNode: find.semantics.byLabel('Шаг Я'),
      ),
      [
        for (final label in const [
          'Шаг А',
          'Связь: для А нужно Б',
          'Промежуточное намерение Б',
          'Связь: для Б нужно Я',
          'Шаг Я',
        ])
          isSemantics(label: label, isButton: true, hasTapAction: true),
      ],
    );
    semantics.dispose();
  });

  testWidgets('клавиатура обходит шаги и связи по порядку пути', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          source: _step('А', onOpen: () => opened.add('А')),
          actionRelation: _relation(
            buttonKey: _relationKey,
            onOpen: () => opened.add('связь'),
          ),
          actionStep: _step('Я', onOpen: () => opened.add('Я')),
        ),
      ),
    );

    for (var presses = 1; presses <= 3; presses++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
    }

    expect(opened, ['А', 'связь', 'Я']);
  });

  testWidgets('при крупном шрифте слово и метка связи не наезжают на соседние '
      'шаги и не вылезают за край', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        MediaQuery.withClampedTextScaling(
          minScaleFactor: 3,
          maxScaleFactor: 3,
          child: SizedBox(
            width: 240,
            child: _path(
              actionRelation: _relation(
                buttonKey: _relationKey,
                archived: true,
              ),
            ),
          ),
        ),
      ),
    );

    final word = tester.getRect(find.text('нужно'));
    final badge = tester.getRect(find.text(_archive));
    expect(
      word.top,
      greaterThanOrEqualTo(tester.getRect(find.text('А')).bottom),
    );
    expect(
      tester.getRect(find.text('Я')).top,
      greaterThanOrEqualTo(badge.bottom),
    );
    expect(
      badge.right,
      lessThanOrEqualTo(tester.getRect(find.byType(ChoicePath)).right),
    );
  });
}

ChoicePathStep _step(
  String name, {
  bool archived = false,
  Key? key,
  String? label,
  VoidCallback? onOpen,
}) => ChoicePathStep(
  name: name,
  archived: archived,
  buttonKey: key,
  semanticLabel: label ?? 'Шаг $name',
  onOpen: onOpen ?? () {},
);

ChoicePathRelation _relation({
  ChoicePathRelationKind kind = ChoicePathRelationKind.need,
  DoablePriority priority = DoablePriority.p1,
  bool archived = false,
  Key? buttonKey,
  String? label,
  VoidCallback? onOpen,
}) => ChoicePathRelation(
  kind: kind,
  priority: priority,
  archived: archived,
  buttonKey: buttonKey,
  semanticLabel: label ?? 'Связь',
  onOpen: onOpen ?? () {},
);

ChoicePath _path({
  ChoicePathStep? source,
  List<ChoicePathLink> intermediate = const [],
  ChoicePathRelation? actionRelation,
  ChoicePathStep? actionStep,
  DoablePriority priority = DoablePriority.p1,
  bool done = false,
}) => ChoicePath(
  source: source ?? _step('А'),
  intermediate: intermediate,
  action: ChoicePathLink(
    relation: actionRelation ?? _relation(buttonKey: _relationKey),
    step: actionStep ?? _step('Я'),
  ),
  priority: priority,
  done: done,
  kindWord: (kind) => switch (kind) {
    ChoicePathRelationKind.need => 'нужно',
    ChoicePathRelationKind.can => 'можно',
  },
  archivedBadge: const ds.Badge.archived(word: _archive),
  archivedNote: _note,
);

List<Color> _glyphColors(WidgetTester tester) => tester
    .widgetList<PathGlyph>(find.byType(PathGlyph))
    .map((glyph) => glyph.color)
    .toList();

List<RelationStrokeKind> _strokes(WidgetTester tester) => tester
    .widgetList<RelationStroke>(find.byType(RelationStroke))
    .map((stroke) => stroke.kind)
    .toList();

Finder _tileFinder(Key relation) => find.descendant(
  of: find.byKey(relation),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is DecoratedBox &&
        widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).shape == BoxShape.circle,
  ),
);

BoxDecoration _tile(WidgetTester tester, Key relation) =>
    tester.widget<DecoratedBox>(_tileFinder(relation)).decoration
        as BoxDecoration;

DoableIcon _tileIcon(WidgetTester tester, Key relation) =>
    tester.widget<DoableIcon>(
      find.descendant(
        of: _tileFinder(relation),
        matching: find.byType(DoableIcon),
      ),
    );

Widget _app(Brightness brightness, Widget child) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: SingleChildScrollView(
      child: Align(alignment: Alignment.topCenter, child: child),
    ),
  ),
);
