import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_line.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_row.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/intention_description_preview.dart';
import '../../../support/tag_positions.dart';
import '../../../support/intention_title_order_key.dart';

void main() {
  testWidgets('карточка показывает начало описания, метку вспомогательного и '
      'теги, которые '
      'поместились, а диктор слышит все шесть тегов на двух языках', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const description =
        'Разминка десять минут,\n\nзатем три круга: приседания, тяга, жим '
        'лёжа, подтягивания и планка, в конце растяжка спины и ног.';
    const preview =
        'Разминка десять минут, затем три круга: приседания, тяга, жим '
        'лёжа, подтягивания и планка, в конце растяжка спины и ног.';
    final summary = _summary(
      'Сделать силовую тренировку',
      description: description,
      kind: IntentionKind.supporting,
      tags: [
        _tag(1, 'Утро'),
        _tag(2, 'Спорт'),
        _tag(3, 'Здоровье'),
        _tag(4, 'Сила'),
        _tag(5, 'Дом'),
        _tag(6, 'Привычки'),
      ],
    );

    for (final (locale, kind, tagsLabel) in const [
      (
        Locale('ru'),
        'вспомогательное',
        'Теги: Утро, Спорт, Здоровье, Сила, Дом, Привычки',
      ),
      (
        Locale('en'),
        'supporting',
        'Tags: Утро, Спорт, Здоровье, Сила, Дом, Привычки',
      ),
    ]) {
      await tester.pumpWidget(_app(locale: locale, summary: summary));

      expect(find.text('Сделать силовую тренировку'), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
      expect(_marks(tester), [(DoableIconData.supporting, BadgeTone.muted)]);
      expect(tester.widget<PickerRow>(find.byType(PickerRow)).archived, false);
      expect(find.byType(TagChip), findsNWidgets(6));
      expect(
        tester.renderObject<RenderTagLine>(find.byType(TagLine)).hiddenTagCount,
        greaterThan(0),
      );
      expect(
        find.bySemanticsLabel(
          'Сделать силовую тренировку, $kind, $preview, $tagsLabel',
        ),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });

  testWidgets('метка и доступное название отличают главное намерение от '
      'вспомогательного и неудерживаемое вспомогательное на двух языках', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    for (final (locale, main, supporting, unheld) in const [
      (
        Locale('ru'),
        'Быть здоровым, главное, Без тегов',
        'Пройти пешком до парка, вспомогательное, Без тегов',
        'Пройти пешком до парка, вспомогательное, его не удерживает ни одно '
            'главное намерение, Без тегов',
      ),
      (
        Locale('en'),
        'Быть здоровым, main, No tags',
        'Пройти пешком до парка, supporting, No tags',
        'Пройти пешком до парка, supporting, no main intention holds it, '
            'No tags',
      ),
    ]) {
      await tester.pumpWidget(
        _app(locale: locale, summary: _summary('Быть здоровым')),
      );
      expect(_marks(tester), isEmpty);
      expect(find.bySemanticsLabel(main), findsOneWidget);

      final walk = _summary(
        'Пройти пешком до парка',
        kind: IntentionKind.supporting,
      );
      await tester.pumpWidget(
        _app(locale: locale, summary: walk, holding: IntentionHolding.held),
      );
      expect(_marks(tester), [(DoableIconData.supporting, BadgeTone.muted)]);
      expect(find.bySemanticsLabel(supporting), findsOneWidget);

      await tester.pumpWidget(
        _app(locale: locale, summary: walk, holding: IntentionHolding.notHeld),
      );
      expect(_marks(tester), [(DoableIconData.supporting, BadgeTone.accent)]);
      expect(find.bySemanticsLabel(unheld), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('отметка начала пути стоит первой в линии меток, а диктор '
      'слышит её на двух языках', (tester) async {
    final semantics = tester.ensureSemantics();

    for (final (locale, word, label) in const [
      (
        Locale('ru'),
        'Сейчас в начале пути',
        'Пройти пешком до парка, Сейчас в начале пути, вспомогательное, Без '
            'тегов',
      ),
      (
        Locale('en'),
        'Current start of path',
        'Пройти пешком до парка, Current start of path, supporting, No tags',
      ),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: locale,
          summary: _summary(
            'Пройти пешком до парка',
            kind: IntentionKind.supporting,
          ),
          currentPathStart: true,
        ),
      );
      final marks = tester.widgetList<Badge>(find.bySubtype<Badge>()).toList();
      expect(marks, [
        isA<BadgeWord>().having((mark) => mark.word, 'word', word),
        isA<BadgeMark>().having(
          (mark) => mark.icon,
          'icon',
          DoableIconData.supporting,
        ),
      ]);
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('теги из фильтра стоят первыми и выделены, а цвет тега '
      'сохраняется', (tester) async {
    final semantics = tester.ensureSemantics();
    final health = _tag(3, 'Здоровье', color: TagColor.blue);

    await tester.pumpWidget(
      _app(
        summary: _summary(
          'Бегать по утрам',
          tags: [_tag(1, 'Утро'), _tag(2, 'Спорт'), health],
        ),
        requiredTagIds: {health.id},
      ),
    );

    expect(
      [
        for (final chip in tester.widgetList<TagChip>(find.byType(TagChip)))
          (chip.name, chip.color, chip.strong),
      ],
      [
        ('Здоровье', DoableTagColor.blue, true),
        ('Утро', null, false),
        ('Спорт', null, false),
      ],
    );
    expect(
      find.bySemanticsLabel(
        'Бегать по утрам, главное, Теги: Здоровье, Утро, Спорт',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('строка без тегов называет их отсутствие, а стрелка открывает '
      'страницу намерения без выбора на двух языках', (tester) async {
    final semantics = tester.ensureSemantics();
    var picks = 0;
    var pageOpenings = 0;

    for (final (locale, label, page) in const [
      (
        Locale('ru'),
        'Бегать по утрам, главное, Без тегов',
        'Открыть страницу намерения «Бегать по утрам»',
      ),
      (
        Locale('en'),
        'Бегать по утрам, main, No tags',
        'Open the page of intention Бегать по утрам',
      ),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: locale,
          summary: _summary('Бегать по утрам'),
          onPick: () => picks++,
          onOpenPage: () => pageOpenings++,
        ),
      );
      expect(find.bySemanticsLabel(label), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(page));
      expect((picks, pageOpenings), (0, 1));
      await tester.tap(find.bySemanticsLabel(label));
      expect((picks, pageOpenings), (1, 1));
      picks = pageOpenings = 0;
    }
    semantics.dispose();
  });
}

List<(DoableIconData, BadgeTone)> _marks(WidgetTester tester) => [
  for (final badge in tester.widgetList<BadgeMark>(find.bySubtype<Badge>()))
    (badge.icon, badge.tone),
];

IntentionSummary _summary(
  String title, {
  String? description,
  IntentionKind kind = IntentionKind.main,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  List<Tag> tags = const [],
}) => IntentionSummary(
  id: (IntentionId.decode(
    '00000000-0000-4000-8000-000000000001',
  ) as IntentionIdDecodingSuccess).id,
  title: title,
  descriptionPreview: testDescriptionPreview(description),
  kind: kind,
  readiness: IntentionReadiness.notReady,
  archiveState: archiveState,
  createdAt: IntentionTimestamp(DateTime.utc(2026)),
  updatedAt: IntentionTimestamp(DateTime.utc(2026)),
  titleOrderKey: testTitleOrderKey(title),
  tags: tags,
);

Tag _tag(int number, String name, {TagColor? color}) => Tag(
  id: (TagId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
  color: color,
  position: tagPositionAt(number),
);

Widget _app({
  required IntentionSummary summary,
  Locale locale = const Locale('ru'),
  Set<TagId> requiredTagIds = const {},
  VoidCallback? onPick,
  VoidCallback? onOpenPage,
  IntentionHolding? holding,
  bool currentPathStart = false,
}) => MaterialApp(
  theme: doableTheme(Brightness.light),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 300,
        child: IntentionPickerRow(
          summary: summary,
          requiredTagIds: requiredTagIds,
          holding: holding,
          onPick: onPick ?? () {},
          onOpenPage: onOpenPage ?? () {},
          currentPathStart: currentPathStart,
        ),
      ),
    ),
  ),
);
