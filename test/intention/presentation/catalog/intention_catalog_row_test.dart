import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/badge.dart';
import 'package:doable/src/design_system/components/catalog_row.dart';
import 'package:doable/src/design_system/components/tag_chip.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
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
  testWidgets('вся карточка — одна кнопка, которая называет открытие и тип '
      'намерения на двух языках', (tester) async {
    final semantics = tester.ensureSemantics();
    var openings = 0;

    for (final (locale, summary, label) in [
      (
        const Locale('ru'),
        testSummary(
          title: 'Бегать по утрам',
          readiness: IntentionReadiness.ready,
        ),
        'Открыть: Бегать по утрам, действие, Без тегов',
      ),
      (
        const Locale('ru'),
        testSummary(title: 'Быть здоровым'),
        'Открыть: Быть здоровым, намерение, Без тегов',
      ),
      (
        const Locale('en'),
        testSummary(
          title: 'Бегать по утрам',
          readiness: IntentionReadiness.ready,
        ),
        'Open: Бегать по утрам, action, No tags',
      ),
      (
        const Locale('en'),
        testSummary(title: 'Быть здоровым'),
        'Open: Быть здоровым, intention, No tags',
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

  testWidgets('архивированное действие несёт метку архива, приглушено, не '
      'выделяет обязательный тег и называет архив на двух языках', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final health = _tag(2, 'Здоровье');
    final summary = testSummary(
      title: 'Бегать',
      readiness: IntentionReadiness.ready,
      archiveState: IntentionArchiveState.archived,
      tags: [_tag(1, 'Утро'), health],
    );

    for (final (locale, label) in const [
      (
        Locale('ru'),
        'Открыть: Бегать, в архиве, действие, Теги: Здоровье, Утро',
      ),
      (Locale('en'), 'Open: Бегать, archived, action, Tags: Здоровье, Утро'),
    ]) {
      await tester.pumpWidget(
        _app(
          locale: locale,
          summary: summary,
          requiredTagIds: {health.id},
          onOpen: () {},
        ),
      );

      final row = tester.widget<CatalogRow>(find.byType(CatalogRow));
      expect(row.archived, isTrue);
      expect(row.marks, [
        isA<BadgeMark>()
            .having((mark) => mark.icon, 'icon', DoableIconData.archive)
            .having((mark) => mark.tone, 'tone', BadgeTone.muted),
        isA<BadgeMark>()
            .having((mark) => mark.icon, 'icon', DoableIconData.bolt)
            .having((mark) => mark.tone, 'tone', BadgeTone.muted),
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
          onOpen: onOpen,
        ),
      ),
    ),
  ),
);
