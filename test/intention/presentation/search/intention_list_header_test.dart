import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/design_system/components/catalog_header.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_view_model.dart';
import 'package:doable/src/intention/presentation/search/intention_list_header.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/application/relation_pair_probe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../catalog/catalog_reconciliation_test_support.dart';
import '../catalog/catalog_test_support.dart';

void main() {
  for (final locale in [const Locale('ru'), const Locale('en')]) {
    final ru = locale.languageCode == 'ru';

    testWidgets(
      '${locale.languageCode}: каталог называет словами все девять сочетаний '
      'охвата и вида',
      (tester) async {
        final purpose = const BrowseIntentionCatalog();
        final h = await _open(tester, purpose, locale);
        final model = h.container.read(
          intentionCatalogViewModelProvider(purpose).notifier,
        );
        final titles = {
          (IntentionScope.active, IntentionKindFilter.mainOnly): ru
              ? 'Активные главные'
              : 'Active main',
          (IntentionScope.active, IntentionKindFilter.supportingOnly): ru
              ? 'Активные вспомогательные'
              : 'Active supporting',
          (IntentionScope.active, IntentionKindFilter.mainAndSupporting): ru
              ? 'Активные'
              : 'Active',
          (IntentionScope.archived, IntentionKindFilter.mainOnly): ru
              ? 'Архивные главные'
              : 'Archived main',
          (IntentionScope.archived, IntentionKindFilter.supportingOnly): ru
              ? 'Архивные вспомогательные'
              : 'Archived supporting',
          (IntentionScope.archived, IntentionKindFilter.mainAndSupporting): ru
              ? 'Архивные'
              : 'Archived',
          (IntentionScope.all, IntentionKindFilter.mainOnly): ru
              ? 'Все главные'
              : 'All main',
          (IntentionScope.all, IntentionKindFilter.supportingOnly): ru
              ? 'Все вспомогательные'
              : 'All supporting',
          (IntentionScope.all, IntentionKindFilter.mainAndSupporting): ru
              ? 'Все'
              : 'All',
        };

        for (final MapEntry(key: (scope, kind), value: title)
            in titles.entries) {
          model
            ..changeScope(scope)
            ..changeKind(kind);
          await tester.pump();
          expect(_header(tester).title, title, reason: '$scope, $kind');
        }
      },
    );

    testWidgets(
      '${locale.languageCode}: заголовок каталога называет охват и вид и '
      'сообщает их в доступном названии с количеством и без него',
      (tester) async {
        final semantics = tester.ensureSemantics();
        const purpose = BrowseIntentionCatalog();
        final h = await _open(tester, purpose, locale);
        final model = h.container.read(
          intentionCatalogViewModelProvider(purpose).notifier,
        );
        model
          ..changeScope(IntentionScope.archived)
          ..changeKind(IntentionKindFilter.supportingOnly);
        await tester.pump();
        final title = ru ? 'Архивные вспомогательные' : 'Archived supporting';
        final summary = ru
            ? 'Создание, сначала новые'
            : 'Created, newest first';

        expect(_header(tester).title, title);
        expect(_header(tester).count, isNull);
        expect(
          tester.getSemantics(find.byType(CatalogHeader)),
          isSemantics(
            label: ru
                ? 'Показать и упорядочить. Показаны: $title. Сортировка: $summary.'
                : 'Show and sort. Showing: $title. Sorted by: $summary.',
            isButton: true,
          ),
        );

        h.repository.complete(h.repository.queries.length - 1, _page(2));
        await tester.pumpAndSettle();

        expect(_header(tester).title, title);
        expect(_header(tester).count, 2);
        expect(_header(tester).summary, summary);
        expect(
          tester.getSemantics(find.byType(CatalogHeader)),
          isSemantics(
            label: ru
                ? 'Показать и упорядочить. Показаны: $title, 2. Сортировка: $summary.'
                : 'Show and sort. Showing: $title, 2. Sorted by: $summary.',
            isButton: true,
          ),
        );
        semantics.dispose();
      },
    );

    testWidgets(
      '${locale.languageCode}: экран выбора называет «Намерения» и сообщает '
      'это в доступном названии с количеством и без него',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final purpose = SelectRelationParticipant(
          session: IntentionSearchSession(),
          pairProbe: RelationPairProbe(
            counterpartId: testSummary(index: 999).id,
            candidateRole: RelationParticipantRole.related,
          ),
        );
        final h = await _open(tester, purpose, locale);
        final title = ru ? 'Намерения' : 'Intentions';
        final summary = ru
            ? 'Создание, сначала новые'
            : 'Created, newest first';

        expect(_header(tester).title, title);
        expect(_header(tester).count, isNull);
        expect(
          tester.getSemantics(find.byType(CatalogHeader)),
          isSemantics(
            label: ru
                ? 'Показать и упорядочить. Показаны: $title. Сортировка: $summary.'
                : 'Show and sort. Showing: $title. Sorted by: $summary.',
            isButton: true,
          ),
        );

        h.repository.complete(h.repository.queries.length - 1, _page(2));
        await tester.pumpAndSettle();

        expect(_header(tester).title, title);
        expect(_header(tester).count, 2);
        expect(
          tester.getSemantics(find.byType(CatalogHeader)),
          isSemantics(
            label: ru
                ? 'Показать и упорядочить. Показаны: $title, 2. Сортировка: $summary.'
                : 'Show and sort. Showing: $title, 2. Sorted by: $summary.',
            isButton: true,
          ),
        );
        semantics.dispose();
      },
    );
  }
}

CatalogHeader _header(WidgetTester tester) =>
    tester.widget<CatalogHeader>(find.byType(CatalogHeader));

Result<IntentionCatalogPage> _page(int count) => ResultSuccess(
  IntentionCatalogFirstPage(
    items: [for (var i = 1; i <= count; i++) testSummary(index: i)],
    totalCount: count,
    counts: const IntentionCountsTotalOnly(),
    nextCursor: null,
    revision: const TestCatalogRevision(1),
  ),
);

Future<({ProviderContainer container, ControlledCatalogRepository repository})>
_open(
  WidgetTester tester,
  IntentionCatalogPurpose purpose,
  Locale locale,
) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = ControlledCatalogRepository();
  final container = reconciliationCatalogContainer(repository);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        theme: doableTheme(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: IntentionListHeader(purpose: purpose)),
      ),
    ),
  );
  await tester.pump();
  return (container: container, repository: repository);
}
