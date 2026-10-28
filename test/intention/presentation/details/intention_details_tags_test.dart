import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_details_state.dart';
import 'package:doable/src/intention/presentation/details/intention_details_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/app_root_pages.dart';
import '../../../support/graph_seed.dart';
import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/in_memory_quick_creation_mode_store.dart';

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
        seedRawGraph(raw, () {
          raw.execute('UPDATE intentions SET title = ? WHERE id IN (?, ?)', [
            'Общее название',
            tagFixtureId(1),
            tagFixtureId(2),
          ]);
        });
        final graphBefore = retainedTagFixtureGraph(raw);
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
              inMemoryQuickCreationModeOverride,
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp.router(
              theme: doableTheme(Brightness.light),
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              routerConfig: router.config(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await openIntentionGraph(tester);
        unawaited(
          router.push(IntentionDetailsRoute(intentionId: _intentionId(number))),
        );
        await tester.pumpAndSettle();

        final choose = find.byKey(const ValueKey('tag-assignments-choose'));
        await tester.scrollUntilVisible(
          choose,
          200,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        expect(choose, findsOneWidget);
        expect(find.text('Дом'), findsOneWidget);
        await Scrollable.ensureVisible(tester.element(choose), alignment: 0.3);
        await tester.pumpAndSettle();
        await tester.tap(choose);
        await tester.pumpAndSettle();
        // Панель открыта над страницей намерения, а не отдельной страницей.
        expect(router.current.name, IntentionDetailsRoute.name);
        expect(find.byType(Sheet), findsOneWidget);
        expect(find.text('Теги'), findsOneWidget);

        // Нажатие на существующий тег сразу назначает его этому намерению
        // без восстановления архивного и без изменения остальных данных.
        final workId = tagFixtureId(lastTagNumber);
        await tester.tap(find.byKey(ValueKey('tags-panel-row-$workId')));
        await _waitUntil(
          tester,
          () => raw.select(
            'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
            [workId, tagFixtureId(number)],
          ).isNotEmpty,
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);

        await tester.enterText(
          find.descendant(
            of: find.byType(Sheet),
            matching: find.byType(TextField),
          ),
          'Новый тег $number',
        );
        await tester.pump();
        await tester.tap(find.text('Создать тег «Новый тег $number»'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Создать тег'));
        await _waitUntil(
          tester,
          () => raw.select('SELECT id FROM tags WHERE name = ?', [
            'Новый тег $number',
          ]).isNotEmpty,
        );
        final newTagId =
            raw.select('SELECT id FROM tags WHERE name = ?', [
                  'Новый тег $number',
                ]).single['id']
                as String;
        // Созданный в панели тег сразу назначен именно этому намерению.
        await _waitUntil(
          tester,
          () => raw.select(
            'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
            [newTagId, tagFixtureId(number)],
          ).isNotEmpty,
        );
        expect(
          raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [
            newTagId,
          ]),
          hasLength(1),
        );
        await tester.tap(find.text('Готово'));
        await tester.pumpAndSettle();
        expect(find.byType(Sheet), findsNothing);
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
        // сбрасывается.
        expect(detailsStates, everyElement(isA<IntentionDetailsLoaded>()));
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
