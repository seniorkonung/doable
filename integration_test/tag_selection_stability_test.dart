import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/shared/diagnostics/diagnostics_sink.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../test/support/in_memory_diagnostics_sink.dart';
import '../test/support/local_database_harness.dart';
import '../test/support/tag_storage_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final relation in [false, true]) {
    for (final (locale, scale) in [
      (const Locale('ru'), 1.0),
      (const Locale('en'), 2.5),
    ]) {
      final recipient = relation ? 'долговременная связь' : 'намерение';
      testWidgets(
        'стабильный выбор на устройстве: $recipient, ${locale.languageCode}, текст $scale',
        (tester) async {
          final storage = await LocalDatabaseHarness.fileBacked();
          late sqlite.Database raw;
          final database = await storage.openReadyDatabase(
            setup: (connection) => raw = connection,
          );
          seedTagStorageFixture(raw);
          for (var number = 1; number <= 130; number++) {
            raw.execute('INSERT INTO tags (id, name) VALUES (?, ?)', [
              tagFixtureId(10000 + number),
              'Дополнительный тег $number',
            ]);
          }
          final diagnostics = InMemoryDiagnosticsSink();
          final repository = DriftPersonalGraphRepository(
            database,
            UuidV7IntentionIdGenerator(),
            () => DateTime.utc(2026, 9, 28),
            diagnostics,
          );
          final target = relation
              ? LongTermRelationTagTarget(
                  (LongTermRelationId.decode(
                    tagFixtureId(101),
                  ) as LongTermRelationIdDecodingSuccess).id,
                )
              : IntentionTagTarget(
                  (IntentionId.decode(
                    tagFixtureId(1),
                  ) as IntentionIdDecodingSuccess).id,
                );
          final provider = tagCatalogViewModelProvider(
            mode: TagCatalogSelectionMode(target),
          );
          final container = ProviderContainer.test(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
          );
          try {
            await tester.pumpWidget(
              UncontrolledProviderScope(
                container: container,
                child: MaterialApp(
                  locale: locale,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: TagCatalogPage(target: target),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final loaded = container.read(provider) as TagCatalogLoaded;
            expect(loaded.items, hasLength(132));
            expect(loaded.selection, isA<TagCatalogNoSelection>());
            final list = find.byKey(const ValueKey('tag-catalog-list'));
            final scrollable = find.descendant(
              of: list,
              matching: find.byType(Scrollable),
            );
            final scrollState = tester.state<ScrollableState>(scrollable);
            scrollState.position.jumpTo(16);
            await tester.pump();
            final viewport = find.byKey(const ValueKey('tag-catalog-viewport'));
            final geometry = tester.getRect(viewport);
            final assignmentsBefore = raw
                .select('SELECT * FROM tag_assignments')
                .length;

            for (final index in [0, 1, 1, 0, 1, 0, 1]) {
              final tag = loaded.items[index];
              final row = find.byKey(
                ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
              );
              await tester.tap(row);
              final immediate = container.read(provider) as TagCatalogLoaded;
              expect(immediate.selection, isA<TagCatalogSelectionReady>());
              expect(immediate.selection.id, tag.id);
              for (var frame = 0; frame < 3; frame++) {
                await tester.pump(const Duration(milliseconds: 16));
                expect(tester.getRect(viewport), geometry);
                expect(
                  tester.state<ScrollableState>(scrollable),
                  same(scrollState),
                );
                expect(scrollState.position.pixels, 16);
                expect(find.byType(CircularProgressIndicator), findsNothing);
                expect(row.hitTestable(), findsOneWidget);
              }
              final button = tester.widget<FilledButton>(
                find.byKey(const ValueKey('tag-catalog-assign')),
              );
              expect(
                button.onPressed == null,
                loaded.selectionRows[index].isAssigned,
              );
            }
            expect(
              raw.select('SELECT * FROM tag_assignments'),
              hasLength(assignmentsBefore),
            );
            await tester.scrollUntilVisible(
              find.text('Дополнительный тег 130'),
              400,
              scrollable: scrollable,
              maxScrolls: 150,
            );
            expect(find.text('Дополнительный тег 130'), findsOneWidget);
            expect(
              find.byKey(const ValueKey('tag-catalog-load-more')),
              findsNothing,
            );
            expect(
              diagnostics.events
                  .whereType<TagCatalogReadDiagnosticsEvent>()
                  .where((event) => event.status is DiagnosticsSucceeded),
              hasLength(1),
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            container.dispose();
            await storage.dispose();
          }
        },
      );
    }
  }
}
