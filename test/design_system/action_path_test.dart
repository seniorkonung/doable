import 'package:doable/src/design_system/components/action_path.dart';
import 'package:doable/src/design_system/components/badge.dart' as ds;
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

const _archivedNote = 'Архивные остаются в сохранённом пути.';
const _deletedNote = 'Удалённые остаются в сохранённом пути как были.';
const _bothNote = 'Архивные и удалённые остаются в сохранённом пути.';
const _notes = ActionPathNotes(
  archived: _archivedNote,
  deleted: _deletedNote,
  archivedAndDeleted: _bothNote,
);
const _archive = 'В архиве';
const _deleted = 'Удалено';

const _rootKey = ValueKey('root');
const _finalKey = ValueKey('final');
const _relationKey = ValueKey('relation');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  testWidgets('намерения идут по порядку пути с ромбом, кольцами и жирным '
      'кольцом, связи стоят между ними высотой 30, действия в конце нет, а '
      'длинный путь не сокращается', (tester) async {
    const middle = ['Б', 'В', 'Г', 'Д', 'Е', 'Ж', 'З'];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          links: [
            for (final name in [...middle, 'Я'])
              ActionPathLink(
                relation: _relation(),
                step: _step(name, key: name == 'Я' ? _finalKey : null),
              ),
          ],
        ),
      ),
    );

    expect(
      tester.widgetList<PathGlyph>(find.byType(PathGlyph)).map((g) => g.shape),
      [
        PathGlyphShape.diamond,
        for (final _ in middle) PathGlyphShape.ring,
        PathGlyphShape.finalRing,
      ],
    );
    final names = ['А', ...middle, 'Я'];
    expect(find.text('нужно'), findsNWidgets(names.length - 1));
    for (var step = 1; step < names.length; step++) {
      final above = tester.getRect(find.text(names[step - 1]));
      final below = tester.getRect(find.text(names[step]));
      // Намерение на 11 выше и ниже своего текста, а между ними стоит связь.
      expect(below.top - above.bottom, closeTo(11 + 30 + 11, 1e-6));
    }
    // К действию линия не ведёт: ни одна линия не лежит ниже глифа конечного
    // намерения.
    final finalGlyph = tester.getRect(find.byType(PathGlyph).last);
    final strokes = tester.widgetList<RelationStroke>(
      find.byType(RelationStroke),
    );
    expect(strokes, hasLength((names.length - 1) * 3));
    for (final stroke in find.byType(RelationStroke).evaluate()) {
      expect(
        tester.getRect(find.byWidget(stroke.widget)).bottom,
        lessThanOrEqualTo(finalGlyph.top),
      );
    }
  });

  testWidgets('путь из одного намерения — один ромб без линий и связей', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.light, _path()));

    expect(
      tester.widgetList<PathGlyph>(find.byType(PathGlyph)).map((g) => g.shape),
      [PathGlyphShape.diamond],
    );
    expect(find.byType(RelationStroke), findsNothing);
    expect(find.text('нужно'), findsNothing);
    expect(tester.getSize(find.byKey(_rootKey)).height, DoableMetrics.tapMin);
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме ромб и жирное кольцо цвета приоритета '
        'действия, а кольца и линии — он же пополам с grip, и узор линии '
        'следует виду связи', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            priority: DoablePriority.p2,
            links: [
              ActionPathLink(
                relation: _relation(priority: DoablePriority.p1),
                step: _step('Б'),
              ),
              ActionPathLink(
                relation: _relation(
                  kind: ActionPathRelationKind.can,
                  priority: DoablePriority.p1,
                ),
                step: _step('Я'),
              ),
            ],
          ),
        ),
      );

      final tone = Color.lerp(colors.p2, colors.grip, .5)!;
      expect(_glyphColors(tester), [colors.p2, tone, colors.p2]);
      // Каждая связь рисует три отрезка: под глифом выше, в своей строке и над
      // глифом ниже.
      expect(_strokes(tester), [
        for (var i = 0; i < 3; i++)
          isA<RelationStrokeNeed>().having((s) => s.color, 'цвет', tone),
        for (var i = 0; i < 3; i++)
          isA<RelationStrokeCan>().having((s) => s.color, 'цвет', tone),
      ]);
    });

    testWidgets('в $themeName теме выполненное действие красит линии и глифы '
        'в grip, а плитка сохраняет приоритет связи', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            done: true,
            priority: DoablePriority.p2,
            links: [
              ActionPathLink(
                relation: _relation(
                  buttonKey: _relationKey,
                  priority: DoablePriority.p1,
                ),
                step: _step('Я'),
              ),
            ],
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
            links: [
              ActionPathLink(
                relation: _relation(
                  priority: DoablePriority.p4,
                  buttonKey: const ValueKey('p4'),
                ),
                step: _step('Б'),
              ),
              ActionPathLink(
                relation: _relation(
                  buttonKey: _relationKey,
                  priority: DoablePriority.p1,
                ),
                step: _step('Я'),
              ),
            ],
          ),
        ),
      );

      expect(tester.getSize(_tileFinder(_relationKey)), const Size.square(26));
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

    testWidgets('в $themeName теме архивное намерение получает имя muted, '
        'глиф grip и метку, а архивная связь — линию grip с прежним узором, '
        'плитку fill со значком muted и метку', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            root: _step('А', archived: true),
            links: [
              ActionPathLink(
                relation: _relation(
                  buttonKey: _relationKey,
                  kind: ActionPathRelationKind.can,
                  archived: true,
                ),
                step: _step('Я'),
              ),
            ],
          ),
        ),
      );

      final glyphColors = _glyphColors(tester);
      expect(glyphColors.first, colors.grip);
      expect(glyphColors.last, colors.p1);
      expect(_nameStyle(tester, 'А').color, colors.muted);
      expect(_nameStyle(tester, 'Я').color, colors.ink);
      expect(
        _strokes(tester),
        everyElement(
          isA<RelationStrokeCan>().having((s) => s.color, 'цвет', colors.grip),
        ),
      );
      expect(_tile(tester, _relationKey).color, colors.fill);
      expect(_tileIcon(tester, _relationKey).color, colors.muted);
      expect(find.text(_archive), findsNWidgets(2));
      expect(find.text(_deleted), findsNothing);
      final hint = tester
          .renderObject<RenderParagraph>(find.text(_archivedNote))
          .text
          .style!;
      expect(hint.color, colors.muted);
      expect(hint.fontSize, DoableType.hint.fontSize);
    });

    testWidgets('в $themeName теме удалённые намерение и связь выглядят как '
        'архивные, но с меткой удаления: имя muted, глиф и линия grip, '
        'плитка fill со значком muted', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness,
          _path(
            links: [
              const ActionPathLink(
                relation: ActionPathRelation.deleted(
                  kind: ActionPathRelationKind.can,
                ),
                step: ActionPathStep.deleted(name: 'Б'),
              ),
              ActionPathLink(relation: _relation(), step: _step('Я')),
            ],
          ),
        ),
      );

      final glyphColors = _glyphColors(tester);
      expect(glyphColors[1], colors.grip);
      expect(_nameStyle(tester, 'Б').color, colors.muted);
      expect(_strokes(tester).take(2), [
        isA<RelationStrokeCan>().having((s) => s.color, 'цвет', colors.grip),
        isA<RelationStrokeCan>().having((s) => s.color, 'цвет', colors.grip),
      ]);
      final tile = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.ancestor(
                of: find.text('можно'),
                matching: find.byType(Row),
              ),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect((tile.decoration as BoxDecoration).color, colors.fill);
      expect(find.text(_deleted), findsNWidgets(2));
      expect(find.text(_archive), findsNothing);
      expect(find.text(_deletedNote), findsOneWidget);
    });
  }

  testWidgets('строка под путём зависит от того, что в нём есть: архивное, '
      'удалённое, оба или ничего, и стоит в 10 под ним вровень с названиями', (
    tester,
  ) async {
    Future<void> pump(ActionPathStep root, ActionPathStep last) async {
      await tester.pumpWidget(
        _app(
          Brightness.light,
          _path(
            root: root,
            links: [ActionPathLink(relation: _relation(), step: last)],
          ),
        ),
      );
    }

    await pump(_step('А'), _step('Я'));
    for (final note in [_archivedNote, _deletedNote, _bothNote]) {
      expect(find.text(note), findsNothing);
    }
    expect(find.text(_archive), findsNothing);
    expect(find.text(_deleted), findsNothing);

    await pump(_step('А'), _step('Я', archived: true, key: _finalKey));
    expect(find.text(_archivedNote), findsOneWidget);
    expect(find.text(_deletedNote), findsNothing);
    expect(find.text(_bothNote), findsNothing);
    final note = tester.getRect(find.text(_archivedNote));
    expect(note.left, tester.getRect(find.text('Я')).left);
    expect(note.top, tester.getRect(find.byKey(_finalKey)).bottom + 10);

    await pump(_step('А'), const ActionPathStep.deleted(name: 'Я'));
    expect(find.text(_deletedNote), findsOneWidget);
    expect(find.text(_archivedNote), findsNothing);
    expect(find.text(_bothNote), findsNothing);

    await pump(
      const ActionPathStep.deleted(name: 'А'),
      _step('Я', archived: true),
    );
    expect(find.text(_bothNote), findsOneWidget);
    expect(find.text(_archivedNote), findsNothing);
    expect(find.text(_deletedNote), findsNothing);
  });

  testWidgets('удалённая связь между существующими намерениями даёт строку '
      'про удалённое, а архивная связь — про архивное', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          links: [
            const ActionPathLink(
              relation: ActionPathRelation.deleted(
                kind: ActionPathRelationKind.need,
              ),
              step: ActionPathStep.existing(
                name: 'Я',
                semanticLabel: 'Намерение Я',
                onOpen: _noop,
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text(_deleted), findsOneWidget);
    expect(find.text(_deletedNote), findsOneWidget);

    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          links: [
            ActionPathLink(
              relation: _relation(archived: true),
              step: _step('Я'),
            ),
          ],
        ),
      ),
    );

    expect(find.text(_archive), findsOneWidget);
    expect(find.text(_archivedNote), findsOneWidget);
  });

  testWidgets('удалённые намерение и связь не принимают нажатия: диктор не '
      'слышит в них кнопок, а нажатие мимо связи достаётся соседним '
      'намерениям', (tester) async {
    final semantics = tester.ensureSemantics();
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          root: _step('А', key: _rootKey, onOpen: () => opened.add('А')),
          links: [
            const ActionPathLink(
              relation: ActionPathRelation.deleted(
                kind: ActionPathRelationKind.need,
              ),
              step: ActionPathStep.deleted(name: 'Б'),
            ),
            ActionPathLink(
              relation: _relation(),
              step: _step('Я', key: _finalKey, onOpen: () => opened.add('Я')),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('Б'));
    await tester.tap(find.text('нужно').first);
    await tester.pump();
    expect(opened, isEmpty);

    expect(find.bySemanticsLabel(RegExp('Шаг Б')), findsNothing);
    expect(
      tester.getSemantics(find.text('Б')),
      isSemantics(label: 'Б\n$_deleted', isButton: false),
    );
    // Удалённая связь читается одним узлом со словом и меткой, без кнопки.
    expect(
      tester.getSemantics(find.text('нужно').first),
      isSemantics(label: 'нужно\n$_deleted', isButton: false),
    );

    final root = tester.getRect(find.byKey(_rootKey));
    await tester.tapAt(Offset(root.center.dx, root.bottom - 3));
    expect(opened, ['А']);
    semantics.dispose();
  });

  testWidgets('длинное название с меткой переносится целиком, глиф остаётся '
      'на первой строке, а линия под ним тянется до конца строки', (
    tester,
  ) async {
    final name = 'Длинное корневое намерение ' * 6;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        SizedBox(
          width: 240,
          child: _path(
            root: _step(name, archived: true, key: _rootKey),
            links: [ActionPathLink(relation: _relation(), step: _step('Я'))],
          ),
        ),
      ),
    );

    final step = tester.getRect(find.byKey(_rootKey));
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

  testWidgets('намерение и связь — отдельные кнопки не ниже tap-min', (
    tester,
  ) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          root: _step('А', key: _rootKey, onOpen: () => opened.add('А')),
          links: [
            ActionPathLink(
              relation: _relation(
                buttonKey: _relationKey,
                onOpen: () => opened.add('связь'),
              ),
              step: _step('Я', key: _finalKey, onOpen: () => opened.add('Я')),
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.text('А'));
    await tester.tap(find.text('нужно'));
    await tester.tap(find.text('Я'));

    expect(opened, ['А', 'связь', 'Я']);
    for (final key in [_rootKey, _finalKey, _relationKey]) {
      expect(tester.getSize(find.byKey(key)).height, DoableMetrics.tapMin);
    }
  });

  testWidgets('область связи заходит на 7 на соседние намерения только над '
      'самой кнопкой: дальше нажатие принадлежит намерению', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          root: _step('А', key: _rootKey, onOpen: () => opened.add('А')),
          links: [
            ActionPathLink(
              relation: _relation(
                buttonKey: _relationKey,
                onOpen: () => opened.add('связь'),
              ),
              step: _step('Я', key: _finalKey, onOpen: () => opened.add('Я')),
            ),
          ],
        ),
      ),
    );

    final above = tester.getRect(find.byKey(_rootKey));
    final below = tester.getRect(find.byKey(_finalKey));
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

  testWidgets('диктор читает намерения и связи отдельными кнопками по порядку '
      'пути с названиями потребителя', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          links: [
            ActionPathLink(
              relation: _relation(label: 'Связь: для А нужно Б'),
              step: _step('Б', label: 'Промежуточное намерение Б'),
            ),
            ActionPathLink(
              relation: _relation(label: 'Связь: для Б нужно Я'),
              step: _step('Я'),
            ),
          ],
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

  testWidgets('клавиатура обходит намерения и связи по порядку пути и '
      'пропускает удалённые', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _path(
          root: _step('А', onOpen: () => opened.add('А')),
          links: [
            const ActionPathLink(
              relation: ActionPathRelation.deleted(
                kind: ActionPathRelationKind.can,
              ),
              step: ActionPathStep.deleted(name: 'Б'),
            ),
            ActionPathLink(
              relation: _relation(onOpen: () => opened.add('связь')),
              step: _step('Я', onOpen: () => opened.add('Я')),
            ),
          ],
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
      'намерения и не вылезают за край', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        MediaQuery.withClampedTextScaling(
          minScaleFactor: 3,
          maxScaleFactor: 3,
          child: SizedBox(
            width: 300,
            child: _path(
              links: [
                const ActionPathLink(
                  relation: ActionPathRelation.deleted(
                    kind: ActionPathRelationKind.need,
                  ),
                  step: ActionPathStep.existing(
                    name: 'Я',
                    semanticLabel: 'Намерение Я',
                    onOpen: _noop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final word = tester.getRect(find.text('нужно'));
    final badge = tester.getRect(find.text(_deleted));
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
      lessThanOrEqualTo(tester.getRect(find.byType(ActionPath)).right),
    );
    expect(tester.takeException(), isNull);
  });
}

void _noop() {}

ActionPathStep _step(
  String name, {
  bool archived = false,
  Key? key,
  String? label,
  VoidCallback? onOpen,
}) => ActionPathStep.existing(
  name: name,
  archived: archived,
  buttonKey: key,
  semanticLabel: label ?? 'Шаг $name',
  onOpen: onOpen ?? _noop,
);

ActionPathRelation _relation({
  ActionPathRelationKind kind = ActionPathRelationKind.need,
  DoablePriority priority = DoablePriority.p1,
  bool archived = false,
  Key? buttonKey,
  String? label,
  VoidCallback? onOpen,
}) => ActionPathRelation.existing(
  kind: kind,
  priority: priority,
  archived: archived,
  buttonKey: buttonKey,
  semanticLabel: label ?? 'Связь',
  onOpen: onOpen ?? _noop,
);

ActionPath _path({
  ActionPathStep? root,
  List<ActionPathLink> links = const [],
  DoablePriority priority = DoablePriority.p1,
  bool done = false,
}) => ActionPath(
  root: root ?? _step('А', key: _rootKey),
  links: links,
  priority: priority,
  done: done,
  kindWord: (kind) => switch (kind) {
    ActionPathRelationKind.need => 'нужно',
    ActionPathRelationKind.can => 'можно',
  },
  archivedBadge: const ds.Badge.archived(word: _archive),
  deletedBadge: const ds.Badge.deleted(word: _deleted),
  notes: _notes,
);

List<Color> _glyphColors(WidgetTester tester) => tester
    .widgetList<PathGlyph>(find.byType(PathGlyph))
    .map((glyph) => glyph.color)
    .toList();

List<RelationStrokeKind> _strokes(WidgetTester tester) => tester
    .widgetList<RelationStroke>(find.byType(RelationStroke))
    .map((stroke) => stroke.kind)
    .toList();

TextStyle _nameStyle(WidgetTester tester, String name) =>
    tester.renderObject<RenderParagraph>(find.text(name)).text.style!;

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
