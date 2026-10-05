import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/app_root_pages.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

void main() {
  for (final (number, archiveState) in [(1, 'активного'), (2, 'архивного')]) {
    testWidgets(
      'подробности $archiveState намерения управляют только своими назначениями',
      (tester) async {
        late sqlite.Database raw;
        final database = AppDatabase(
          openInMemoryLocalDatabase(setup: (db) => raw = db),
        );
        await database.open();
        addTearDown(database.close);
        seedTagStorageFixture(raw);
        raw.execute('UPDATE intentions SET title = ? WHERE id IN (?, ?)', [
          'Общее название',
          tagFixtureId(1),
          tagFixtureId(2),
        ]);
        final graphBefore = retainedTagFixtureGraph(raw);
        final assignmentsBefore = raw
            .select('SELECT * FROM tag_assignments ORDER BY creation_sequence')
            .map((row) => row.values.toList())
            .toList();
        final repository = DriftPersonalGraphRepository(
          database,
          UuidV7IntentionIdGenerator(),
          () => DateTime.utc(2026, 9, 27),
          InMemoryDiagnosticsSink(),
        );
        final router = AppRouter();
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp.router(
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router.config(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openIntentionGraph(tester);
        final tagId = (TagId.decode(
          tagFixtureId(firstTagNumber),
        ) as TagIdDecodingSuccess).id;
        unawaited(router.push(TagNavigationRoute(tagId: tagId)));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey(TaggedIntentionsScope.archived)),
        );
        await tester.pumpAndSettle();
        unawaited(
          router.push(IntentionDetailsRoute(intentionId: _intentionId(number))),
        );
        await tester.pumpAndSettle();

        final choose = find.byKey(const ValueKey('tag-assignments-choose'));
        expect(choose, findsOneWidget);
        expect(find.text('Дом'), findsOneWidget);
        final open = find.byKey(
          ValueKey('tag-assignment-open-${tagFixtureId(firstTagNumber)}'),
        );
        expect(open, findsOneWidget);
        await Scrollable.ensureVisible(tester.element(open), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(router.current.name, TagNavigationRoute.name);
        expect(
          router.current
              .argsAs<TagNavigationRouteArgs>()
              .tagId
              .toCanonicalString(),
          tagFixtureId(firstTagNumber),
        );
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey(TaggedIntentionsScope.active)),
              )
              .selected,
          isTrue,
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);
        expect(
          raw
              .select(
                'SELECT * FROM tag_assignments ORDER BY creation_sequence',
              )
              .map((row) => row.values.toList())
              .toList(),
          assignmentsBefore,
        );
        router.pop();
        await tester.pumpAndSettle();
        expect(router.current.name, IntentionDetailsRoute.name);
        await Scrollable.ensureVisible(tester.element(choose), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(choose);
        await tester.pumpAndSettle();
        expect(router.current.name, TagCatalogRoute.name);
        expect(
          router.current.argsAs<TagCatalogRouteArgs>().selectionContext,
          TagAssignmentContext(_intentionId(number)),
        );

        await tester.tap(find.byKey(const ValueKey('tag-catalog-create')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          'Новый тег $number',
        );
        await tester.tap(find.byKey(const ValueKey('tag-editor-submit')));
        await _waitUntil(
          tester,
          () =>
              find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
        );
        expect(router.current.name, TagCatalogRoute.name);
        final newTagId =
            raw.select('SELECT id FROM tags WHERE name = ?', [
                  'Новый тег $number',
                ]).single['id']
                as String;
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newTagId,
          ]),
          isEmpty,
        );

        await tester.tap(find.byKey(const ValueKey('tag-catalog-assign')));
        await _waitUntil(
          tester,
          () => raw.select(
            'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
            [newTagId, tagFixtureId(number)],
          ).isNotEmpty,
        );
        expect(
          raw.select(
            'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
            [newTagId, tagFixtureId(number)],
          ),
          hasLength(1),
        );
        router.pop();
        await tester.pumpAndSettle();
        final remove = find.byKey(ValueKey('tag-assignment-remove-$newTagId'));
        await Scrollable.ensureVisible(tester.element(remove), alignment: 0.3);
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(tester.element(remove));
        final detailsProvider = intentionDetailsViewModelProvider(
          _intentionId(number),
        );
        final detailsBefore =
            container.read(detailsProvider) as IntentionDetailsLoaded;
        final detailsStates = <IntentionDetailsState>[];
        final detailsSubscription = container.listen(
          detailsProvider,
          (_, next) => detailsStates.add(next),
        );
        await tester.tap(remove);
        await _waitUntil(
          tester,
          () => raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newTagId,
          ]).isEmpty,
        );
        detailsSubscription.close();
        // Пакет снятия несёт снимок этого же намерения: страница не
        // сбрасывается и публикует новую ревизию ровно один раз.
        expect(detailsStates, everyElement(isA<IntentionDetailsLoaded>()));
        final loadedStates = detailsStates.cast<IntentionDetailsLoaded>();
        final newRevisions = <IntentionDetailsLoaded>[
          for (final (index, state) in loadedStates.indexed)
            if (state.revision.compareTo(
                  index == 0
                      ? detailsBefore.revision
                      : loadedStates[index - 1].revision,
                ) !=
                GraphRevisionOrder.same)
              state,
        ];
        expect(newRevisions, hasLength(1));
        final detailsAfter =
            container.read(detailsProvider) as IntentionDetailsLoaded;
        expect(detailsAfter.intention.title, detailsBefore.intention.title);
        expect(
          detailsAfter.intention.updatedAt,
          detailsBefore.intention.updatedAt,
        );
        expect(
          detailsAfter.details.relationCounts,
          detailsBefore.details.relationCounts,
        );
        expect(detailsAfter.edit, isNull);
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newTagId,
          ]),
          isEmpty,
        );
        expect(
          raw.select('SELECT * FROM tags WHERE id = ?', [newTagId]),
          hasLength(1),
        );
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE intention_id = ?', [
            tagFixtureId(number == 1 ? 2 : 1),
          ]),
          hasLength(1),
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);

        final delete = find.byKey(const ValueKey('intention-details-delete'));
        await tester.scrollUntilVisible(
          delete,
          -200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(delete);
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Это действие нельзя отменить. Намерение, его описание и все назначения тегов, включая не показанные сейчас, будут удалены навсегда. Сами теги сохранятся.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Отмена'));
        await tester.pumpAndSettle();
        expect(retainedTagFixtureGraph(raw), graphBefore);
        router.pop();
        await tester.pumpAndSettle();
        expect(router.current.name, TagNavigationRoute.name);
        expect(
          tester
              .widget<ChoiceChip>(
                find.byKey(const ValueKey(TaggedIntentionsScope.archived)),
              )
              .selected,
          isTrue,
        );
      },
    );
  }
}

Future<void> _waitUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 30 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
  expect(done(), isTrue);
}
