import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

Widget _app({
  required Locale locale,
  required IntentionSummary summary,
  required VoidCallback onOpen,
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
          requiredTagIds: const {},
          onOpen: onOpen,
        ),
      ),
    ),
  ),
);
