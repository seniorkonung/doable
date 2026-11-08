import 'package:doable/src/design_system/components/action_path.dart';
import 'package:doable/src/design_system/components/path_brief.dart';
import 'package:doable/src/design_system/components/path_glyph.dart';
import 'package:doable/src/design_system/components/relation_stroke.dart';
import 'package:doable/src/design_system/doable_priority.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('пустой путь предлагает выбрать причину и поясняет её', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        PathBrief(
          steps: const [],
          priority: DoablePriority.p4,
          emptyText: 'Выберите причину',
          emptyHint: 'Нужно намерение',
          betweenText: '1 промежуточное намерение',
          label: 'Выберите причину',
          onPressed: () => taps++,
        ),
      ),
    );
    expect(find.text('Нужно намерение'), findsOneWidget);
    final glyph = tester.widget<PathGlyph>(find.byType(PathGlyph));
    expect(glyph.shape, PathGlyphShape.diamond);
    expect(glyph.outline, PathGlyphOutline.dashed);
    await tester.tap(find.text('Выберите причину'));
    expect(taps, 1);
  });

  testWidgets(
    'путь показывает концы, связь или число промежуточных и полное доступное имя',
    (tester) async {
      final semantics = tester.ensureSemantics();
      Future<void> pump(List<PathBriefStep> steps) => tester.pumpWidget(
        _app(
          PathBrief(
            steps: steps,
            priority: DoablePriority.p2,
            emptyText: 'Выберите причину',
            emptyHint: 'Нужно намерение',
            betweenText: '2 промежуточных намерения',
            label: 'Путь: Корень, затем Середина, затем Конец. Изменить путь',
            onPressed: () {},
          ),
        ),
      );
      await pump(const [PathBriefStep(name: 'Корень')]);
      expect(find.byType(PathGlyph), findsOneWidget);
      await pump(const [
        PathBriefStep(name: 'Корень'),
        PathBriefStep(name: 'Конец', relation: ActionPathRelationKind.need),
      ]);
      expect(find.byType(PathGlyph), findsNWidgets(2));
      expect(
        tester.widget<RelationStroke>(find.byType(RelationStroke).first).kind,
        isA<RelationStrokeNeed>(),
      );
      await pump(const [
        PathBriefStep(name: 'Корень'),
        PathBriefStep(name: 'Середина'),
        PathBriefStep(name: 'Другая'),
        PathBriefStep(name: 'Конец'),
      ]);
      expect(find.text('2 промежуточных намерения'), findsOneWidget);
      expect(find.text('Середина'), findsNothing);
      expect(
        tester.getSize(find.byType(RelationStroke).at(1)).height,
        greaterThan(0),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel(
            'Путь: Корень, затем Середина, затем Конец. Изменить путь',
          ),
        ),
        isSemantics(
          label: 'Путь: Корень, затем Середина, затем Конец. Изменить путь',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'длинные названия и отметки концов и блока помещаются без обрезки',
    (tester) async {
      const name =
          'Очень длинное название корневого намерения для проверки переноса';
      await tester.pumpWidget(
        _app(
          SizedBox(
            width: 240,
            child: PathBrief(
              steps: const [
                PathBriefStep(name: name, marks: [Text('Удалено')]),
                PathBriefStep(
                  name: 'Конечное намерение',
                  relation: ActionPathRelationKind.can,
                  marks: [Text('В архиве')],
                ),
              ],
              marks: const [Text('Разрыв')],
              priority: DoablePriority.p1,
              emptyText: 'Выберите причину',
              emptyHint: 'Нужно намерение',
              betweenText: 'Промежуточные',
              label: 'Путь целиком',
              onPressed: () {},
            ),
          ),
        ),
      );
      expect(tester.getSize(find.text(name)).height, greaterThan(20));
      expect(tester.widget<Text>(find.text(name)).maxLines, isNull);
      expect(find.text('Удалено'), findsOneWidget);
      expect(find.text('В архиве'), findsOneWidget);
      expect(find.text('Разрыв'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Widget _app(Widget child) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
