import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/picker_row.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/tag_line.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/picker/intention_picker_row.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
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
  testWidgets('карточка показывает начало описания, молнию и теги, которые '
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
      tags: [
        _tag(1, 'Утро'),
        _tag(2, 'Спорт'),
        _tag(3, 'Здоровье'),
        _tag(4, 'Сила'),
        _tag(5, 'Дом'),
        _tag(6, 'Привычки'),
      ],
    );
    final purpose = SelectDailyChoiceAction(session: IntentionSearchSession());

    for (final (locale, tagsLabel) in const [
      (Locale('ru'), 'Теги: Утро, Спорт, Здоровье, Сила, Дом, Привычки'),
      (Locale('en'), 'Tags: Утро, Спорт, Здоровье, Сила, Дом, Привычки'),
    ]) {
      await tester.pumpWidget(
        _app(locale: locale, purpose: purpose, summary: summary),
      );

      expect(find.text('Сделать силовую тренировку'), findsOneWidget);
      expect(find.text(preview), findsOneWidget);
      expect(_marks(tester), [(DoableIconData.bolt, BadgeTone.ink)]);
      expect(tester.widget<PickerRow>(find.byType(PickerRow)).archived, false);
      expect(find.byType(TagChip), findsNWidgets(6));
      expect(
        tester.renderObject<RenderTagLine>(find.byType(TagLine)).hiddenTagCount,
        greaterThan(0),
      );
      expect(
        find.bySemanticsLabel(
          'Сделать силовую тренировку, $preview, $tagsLabel',
        ),
        findsOneWidget,
      );
    }
    semantics.dispose();
  });

  for (final (search, purpose) in [
    (
      'исходного намерения',
      SelectDailyChoiceSource(session: IntentionSearchSession()),
    ),
    (
      'участника',
      SelectRelationParticipant(
        selectionContext: RelationParticipantSelectionContext.activeRelation,
        session: IntentionSearchSession(),
      ),
    ),
  ]) {
    testWidgets('в поиске $search молния и доступное название отличают '
        'действие от намерения на двух языках', (tester) async {
      final semantics = tester.ensureSemantics();

      for (final (locale, intention, action) in const [
        (
          Locale('ru'),
          'Быть здоровым, намерение, Без тегов',
          'Пройти пешком до парка, действие, Без тегов',
        ),
        (
          Locale('en'),
          'Быть здоровым, intention, No tags',
          'Пройти пешком до парка, action, No tags',
        ),
      ]) {
        await tester.pumpWidget(
          _app(
            locale: locale,
            purpose: purpose,
            summary: _summary(
              'Быть здоровым',
              readiness: IntentionReadiness.notReady,
            ),
          ),
        );
        expect(_marks(tester), isEmpty);
        expect(find.bySemanticsLabel(intention), findsOneWidget);

        await tester.pumpWidget(
          _app(
            locale: locale,
            purpose: purpose,
            summary: _summary('Пройти пешком до парка'),
          ),
        );
        expect(_marks(tester), [(DoableIconData.bolt, BadgeTone.ink)]);
        expect(find.bySemanticsLabel(action), findsOneWidget);
      }
      semantics.dispose();
    });
  }

  testWidgets('теги из фильтра стоят первыми и выделены, а цвет тега '
      'сохраняется', (tester) async {
    final semantics = tester.ensureSemantics();
    final health = _tag(3, 'Здоровье', color: TagColor.blue);

    await tester.pumpWidget(
      _app(
        purpose: SelectDailyChoiceAction(session: IntentionSearchSession()),
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
      find.bySemanticsLabel('Бегать по утрам, Теги: Здоровье, Утро, Спорт'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('архивированное действие в поиске участника архивированной '
      'связи несёт метку архива, приглушено и называет архив на двух языках', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final health = _tag(2, 'Здоровье', color: TagColor.blue);
    final summary = _summary(
      'Бегать по утрам',
      archiveState: IntentionArchiveState.archived,
      tags: [_tag(1, 'Утро'), health],
    );

    for (final (locale, label) in const [
      (
        Locale('ru'),
        'Бегать по утрам, в архиве, действие, Теги: Здоровье, Утро',
      ),
      (Locale('en'), 'Бегать по утрам, archived, action, Tags: Здоровье, Утро'),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: locale,
          purpose: SelectRelationParticipant(
            selectionContext:
                RelationParticipantSelectionContext.archivedRelation,
            session: IntentionSearchSession(),
          ),
          summary: summary,
          requiredTagIds: {health.id},
        ),
      );

      expect(_marks(tester), [
        (DoableIconData.archive, BadgeTone.muted),
        (DoableIconData.bolt, BadgeTone.muted),
      ]);
      expect(tester.widget<PickerRow>(find.byType(PickerRow)).archived, true);
      expect(
        [
          for (final chip in tester.widgetList<TagChip>(find.byType(TagChip)))
            (chip.name, chip.strong),
        ],
        [('Здоровье', false), ('Утро', false)],
      );
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('строка без тегов называет их отсутствие, а стрелка открывает '
      'страницу без выбора на двух языках', (tester) async {
    final semantics = tester.ensureSemantics();
    var picks = 0;
    var pageOpenings = 0;

    for (final (locale, label, actionPage, intentionPage) in const [
      (
        Locale('ru'),
        'Бегать по утрам, Без тегов',
        'Открыть страницу действия «Бегать по утрам»',
        'Открыть страницу намерения «Быть здоровым»',
      ),
      (
        Locale('en'),
        'Бегать по утрам, No tags',
        'Open the page of action Бегать по утрам',
        'Open the page of intention Быть здоровым',
      ),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: locale,
          purpose: SelectDailyChoiceAction(session: IntentionSearchSession()),
          summary: _summary('Бегать по утрам'),
          onPick: () => picks++,
          onOpenPage: () => pageOpenings++,
        ),
      );
      expect(find.bySemanticsLabel(label), findsOneWidget);

      await tester.tap(find.bySemanticsLabel(actionPage));
      expect((picks, pageOpenings), (0, 1));
      await tester.tap(find.bySemanticsLabel(label));
      expect((picks, pageOpenings), (1, 1));
      picks = pageOpenings = 0;

      await tester.pumpWidget(
        _app(
          locale: locale,
          purpose: SelectDailyChoiceSource(session: IntentionSearchSession()),
          summary: _summary(
            'Быть здоровым',
            readiness: IntentionReadiness.notReady,
          ),
        ),
      );
      expect(find.bySemanticsLabel(intentionPage), findsOneWidget);
    }
    semantics.dispose();
  });

  for (final (scope, ruWord, enWord) in const [
    (RelationScope.active, 'Уже связано', 'Already linked'),
    (RelationScope.archived, 'Связь в архиве', 'Archived relation'),
  ]) {
    testWidgets('строка с занимающей связью (${scope.name}) начинает метки '
        'словом, не приглушает название, называет отметку и действие нажатия '
        'и открывает связь вместо выбора на двух языках', (tester) async {
      final semantics = tester.ensureSemantics();
      var picks = 0;
      var pageOpenings = 0;
      var relationOpenings = 0;

      for (final (locale, word, label, actionPage) in [
        (
          const Locale('ru'),
          ruWord,
          'Много ходить, действие, Без тегов, $ruWord, '
              'нажатие откроет существующую связь',
          'Открыть страницу действия «Много ходить»',
        ),
        (
          const Locale('en'),
          enWord,
          'Много ходить, action, No tags, $enWord, '
              'tapping opens the existing relation',
          'Open the page of action Много ходить',
        ),
      ]) {
        await tester.pumpWidget(
          _app(
            locale: locale,
            purpose: SelectRelationParticipant(
              selectionContext:
                  RelationParticipantSelectionContext.activeRelation,
              session: IntentionSearchSession(),
            ),
            summary: _summary('Много ходить'),
            occupiedPair: OccupiedPairMark(
              scope: scope,
              onOpenRelation: () => relationOpenings++,
            ),
            onPick: () => picks++,
            onOpenPage: () => pageOpenings++,
          ),
        );

        final marks = tester.widget<PickerRow>(find.byType(PickerRow)).marks;
        expect(marks, [
          isA<BadgeWord>().having((mark) => mark.word, 'word', word),
          isA<BadgeMark>().having(
            (mark) => mark.icon,
            'icon',
            DoableIconData.bolt,
          ),
        ]);
        expect(
          tester.widget<PickerRow>(find.byType(PickerRow)).archived,
          false,
        );
        expect(find.bySemanticsLabel(label), findsOneWidget);
        // Метка не создаёт отдельного узла экранного диктора.
        expect(find.bySemanticsLabel(word), findsNothing);

        await tester.tap(find.bySemanticsLabel(label));
        expect((picks, pageOpenings, relationOpenings), (0, 0, 1));
        await tester.tap(find.bySemanticsLabel(actionPage));
        expect((picks, pageOpenings, relationOpenings), (0, 1, 1));
        picks = pageOpenings = relationOpenings = 0;
      }
      semantics.dispose();
    });
  }

  testWidgets('отметка занятой пары не приглушает название активного '
      'намерения, а у архивированного приглушено только оно', (tester) async {
    for (final (archiveState, archived) in const [
      (IntentionArchiveState.active, false),
      (IntentionArchiveState.archived, true),
    ]) {
      await tester.pumpWidget(
        _app(
          purpose: SelectRelationParticipant(
            selectionContext:
                RelationParticipantSelectionContext.archivedRelation,
            session: IntentionSearchSession(),
          ),
          summary: _summary('Плавать', archiveState: archiveState),
          occupiedPair: OccupiedPairMark(
            scope: RelationScope.archived,
            onOpenRelation: () {},
          ),
        ),
      );

      expect(
        tester.widget<PickerRow>(find.byType(PickerRow)).archived,
        archived,
      );
      expect(tester.widget<PickerRow>(find.byType(PickerRow)).marks, [
        isA<BadgeWord>().having((mark) => mark.word, 'word', 'Связь в архиве'),
        if (archived)
          isA<BadgeMark>().having(
            (mark) => mark.icon,
            'icon',
            DoableIconData.archive,
          ),
        isA<BadgeMark>().having(
          (mark) => mark.icon,
          'icon',
          DoableIconData.bolt,
        ),
      ]);
    }
  });
}

List<(DoableIconData, BadgeTone)> _marks(WidgetTester tester) => [
  for (final badge in tester.widgetList<BadgeMark>(find.bySubtype<Badge>()))
    (badge.icon, badge.tone),
];

IntentionSummary _summary(
  String title, {
  String? description,
  IntentionReadiness readiness = IntentionReadiness.ready,
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  List<Tag> tags = const [],
}) => IntentionSummary(
  id: (IntentionId.decode(
    '00000000-0000-4000-8000-000000000001',
  ) as IntentionIdDecodingSuccess).id,
  title: title,
  descriptionPreview: testDescriptionPreview(description),
  readiness: readiness,
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
  required IntentionPickerPurpose purpose,
  required IntentionSummary summary,
  Locale locale = const Locale('ru'),
  Set<TagId> requiredTagIds = const {},
  OccupiedPairMark? occupiedPair,
  VoidCallback? onPick,
  VoidCallback? onOpenPage,
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
          purpose: purpose,
          summary: summary,
          requiredTagIds: requiredTagIds,
          onPick: onPick ?? () {},
          onOpenPage: onOpenPage ?? () {},
          occupiedPair: occupiedPair,
        ),
      ),
    ),
  ),
);
