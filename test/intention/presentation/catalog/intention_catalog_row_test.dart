import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/catalog_row.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_holding.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_row.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_positions.dart';
import 'catalog_test_support.dart';

void main() {
  testWidgets('вся карточка — одна кнопка, которая называет открытие и вид '
      'намерения на двух языках', (tester) async {
    final semantics = tester.ensureSemantics();
    var openings = 0;
    final supporting = testSummary(
      title: 'Пройти пешком до парка',
      kind: IntentionKind.supporting,
    );

    for (final (locale, summary, label) in [
      (
        const Locale('ru'),
        testSummary(title: 'Быть здоровым'),
        'Открыть: Быть здоровым, главное, Без тегов',
      ),
      (
        const Locale('ru'),
        supporting,
        'Открыть: Пройти пешком до парка, вспомогательное, Без тегов',
      ),
      (
        const Locale('en'),
        testSummary(title: 'Быть здоровым'),
        'Open: Быть здоровым, main, No tags',
      ),
      (
        const Locale('en'),
        supporting,
        'Open: Пройти пешком до парка, supporting, No tags',
      ),
    ]) {
      await tester.pumpWidget(
        _app(locale: locale, summary: summary, onOpen: () => openings++),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        isSemantics(label: label, isButton: true, hasTapAction: true),
      );
      await tester.tap(find.text(summary.title));
      expect(openings, 1);
      openings = 0;
    }
    semantics.dispose();
  });

  testWidgets('метка вспомогательного серая у удерживаемого и при неизвестном '
      'удержании, красная у неудерживаемого, а у главного метки вида нет', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final supporting = testSummary(
      title: 'Вести дневник сна',
      kind: IntentionKind.supporting,
    );

    for (final (summary, holding, marks, label) in [
      (
        testSummary(title: 'Быть в форме'),
        IntentionHolding.notHeld,
        <(DoableIconData, BadgeTone)>[],
        'Открыть: Быть в форме, главное, Без тегов',
      ),
      (
        supporting,
        IntentionHolding.held,
        [(DoableIconData.supporting, BadgeTone.muted)],
        'Открыть: Вести дневник сна, вспомогательное, Без тегов',
      ),
      (
        supporting,
        null,
        [(DoableIconData.supporting, BadgeTone.muted)],
        'Открыть: Вести дневник сна, вспомогательное, Без тегов',
      ),
      (
        supporting,
        IntentionHolding.notHeld,
        [(DoableIconData.supporting, BadgeTone.accent)],
        'Открыть: Вести дневник сна, вспомогательное, его не удерживает ни '
            'одно главное намерение, Без тегов',
      ),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: const Locale('ru'),
          summary: summary,
          holding: holding,
          onOpen: () {},
        ),
      );

      expect(_marks(tester), marks);
      expect(find.bySemanticsLabel(label), findsOneWidget);
    }
    semantics.dispose();
  });

  testWidgets('архивированное вспомогательное намерение несёт приглушённые '
      'метки вида и архива, не выделяет обязательный тег и называет вид и '
      'архив на двух языках', (tester) async {
    final semantics = tester.ensureSemantics();
    final health = _tag(2, 'Здоровье');
    final summary = testSummary(
      title: 'Плавать',
      kind: IntentionKind.supporting,
      archiveState: IntentionArchiveState.archived,
      tags: [_tag(1, 'Утро'), health],
    );

    for (final (locale, label) in const [
      (
        Locale('ru'),
        'Открыть: Плавать, вспомогательное, в архиве, Теги: Здоровье, Утро',
      ),
      (
        Locale('en'),
        'Open: Плавать, supporting, archived, Tags: Здоровье, Утро',
      ),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: locale,
          summary: summary,
          requiredTagIds: {health.id},
          // Архивное намерение не удерживается, но красной метки у него нет.
          holding: IntentionHolding.notHeld,
          onOpen: () {},
        ),
      );

      final row = tester.widget<CatalogRow>(find.byType(CatalogRow));
      expect(row.archived, isTrue);
      expect(_marks(tester), [
        (DoableIconData.supporting, BadgeTone.muted),
        (DoableIconData.archive, BadgeTone.muted),
      ]);
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
}

List<(DoableIconData, BadgeTone)> _marks(WidgetTester tester) => [
  for (final mark in tester.widget<CatalogRow>(find.byType(CatalogRow)).marks)
    switch (mark) {
      BadgeMark(:final icon, :final tone) => (icon, tone),
      _ => throw StateError('Строка каталога несёт только метки-значки.'),
    },
];

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(
    '00000000-0000-4000-8000-${number.toString().padLeft(12, '0')}',
  ) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
  color: null,
  position: tagPositionAt(number),
);

Widget _app({
  required Locale locale,
  required IntentionSummary summary,
  required VoidCallback onOpen,
  Set<TagId> requiredTagIds = const {},
  IntentionHolding? holding,
}) => MaterialApp(
  theme: doableTheme(Brightness.light),
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 300,
        child: IntentionCatalogRow(
          summary: summary,
          requiredTagIds: requiredTagIds,
          holding: holding,
          onOpen: onOpen,
        ),
      ),
    ),
  ),
);
