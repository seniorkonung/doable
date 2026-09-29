import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';

void main() {
  for (final (isIntention, number, locale) in [
    (true, 1, const Locale('ru')),
    (true, 2, const Locale('en')),
    (false, 101, const Locale('ru')),
    (false, 102, const Locale('en')),
  ]) {
    testWidgets(
      '${isIntention ? 'намерение $number: сквозное назначение и снятие' : 'долговременная связь $number: собственные теги недоступны'} на ${locale.languageCode}',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        tester.binding.platformDispatcher.localesTestValue = [locale];
        addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
        tester.view.physicalSize = const Size(1200, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        late sqlite.Database raw;
        final diagnostics = InMemoryDiagnosticsSink();
        final runtime = AppRuntime(
          connectionFactory: () =>
              openInMemoryLocalDatabase(setup: (database) => raw = database),
          diagnosticsSink: diagnostics,
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await runtime.shutdown();
        });
        final ready =
            (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
        seedTagStorageFixture(raw);
        raw.execute('UPDATE long_term_relations SET type = ? WHERE id = ?', [
          'can',
          tagFixtureId(102),
        ]);
        final graphBefore = retainedTagFixtureGraph(raw);
        final router = ready.container.read(appRouterProvider);
        await tester.pumpWidget(MainApp(runtime: runtime));
        await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));

        if (isIntention) {
          final id = (IntentionId.decode(
            tagFixtureId(number),
          ) as IntentionIdDecodingSuccess).id;
          unawaited(router.push(IntentionDetailsRoute(intentionId: id)));
        } else {
          final id = (LongTermRelationId.decode(
            tagFixtureId(number),
          ) as LongTermRelationIdDecodingSuccess).id;
          unawaited(router.push(RelationDetailsRoute(relationId: id)));
          await _until(
            tester,
            find.byKey(const ValueKey('relation-details-phrase')),
          );
          await tester.pumpAndSettle();
          final storedBefore = _storedGraph(raw);
          final participant = find.byKey(
            const ValueKey('relation-details-related-participant'),
          );
          await tester.scrollUntilVisible(
            participant,
            200,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.pumpAndSettle();
          expect(find.byType(TagAssignmentsSection), findsNothing);
          expect(
            find.byKey(const ValueKey('tag-assignments-choose')),
            findsNothing,
          );
          for (final action in ['open', 'remove']) {
            expect(
              find.byKey(
                ValueKey(
                  'tag-assignment-$action-${tagFixtureId(firstTagNumber)}',
                ),
              ),
              findsNothing,
            );
          }
          expect(find.text('Дом'), findsNothing);
          expect(_storedGraph(raw), storedBefore);
          expect(retainedTagFixtureGraph(raw), graphBefore);
          expect(tester.takeException(), isNull);
          return;
        }
        final choose = find.byKey(const ValueKey('tag-assignments-choose'));
        await _until(tester, choose);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-catalog-search')), findsNothing);
        await _tap(tester, choose);

        final homeTagId = tagFixtureId(firstTagNumber);
        final existingTagId = tagFixtureId(lastTagNumber);
        final homeRow = find.byKey(ValueKey('tag-catalog-row-$homeTagId'));
        final workRow = find.byKey(ValueKey('tag-catalog-row-$existingTagId'));
        await _until(tester, homeRow);
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('tag-catalog-search'));
        final localizations = AppLocalizations.of(tester.element(search));
        final storedBeforeSearch = _storedGraph(raw);
        final diagnosticsBeforeSearch = diagnostics.events;
        for (final (query, hasHome, hasWork) in [
          ('д', true, false),
          ('до', true, false),
          ('дмо', false, false),
          ('дом', true, false),
          ('спорт', false, false),
          ('раб', false, true),
          ('работ', false, true),
        ]) {
          await tester.enterText(search, query);
          await tester.pumpAndSettle();
          expect(homeRow, hasHome ? findsOneWidget : findsNothing);
          expect(workRow, hasWork ? findsOneWidget : findsNothing);
          if (hasHome) {
            expect(
              _assignmentLabel(tester, homeRow),
              localizations.tagCatalogAssigned,
            );
          }
          if (hasWork) {
            expect(
              _assignmentLabel(tester, workRow),
              localizations.tagCatalogAvailable,
            );
          }
          if (!hasHome && !hasWork) {
            expect(
              find.text(localizations.tagCatalogNoMatches),
              findsOneWidget,
            );
          }
          expect(_storedGraph(raw), storedBeforeSearch);
          expect(diagnostics.events, diagnosticsBeforeSearch);
        }
        await tester.tap(find.byTooltip(localizations.tagCatalogClearSearch));
        await tester.pumpAndSettle();
        expect(homeRow, findsOneWidget);
        expect(workRow, findsOneWidget);
        expect(
          _assignmentLabel(tester, homeRow),
          localizations.tagCatalogAssigned,
        );
        expect(_storedGraph(raw), storedBeforeSearch);
        expect(diagnostics.events, diagnosticsBeforeSearch);

        await tester.enterText(search, 'работ');
        await tester.pumpAndSettle();
        expect(homeRow, findsNothing);
        expect(_storedGraph(raw), storedBeforeSearch);
        expect(diagnostics.events, diagnosticsBeforeSearch);
        await _tap(tester, workRow);
        expect(_storedGraph(raw), storedBeforeSearch);
        await _tap(tester, find.byKey(const ValueKey('tag-catalog-assign')));
        await _until(tester, find.text('Работа'));
        await _waitFor(tester, () => _assigned(raw, existingTagId, number));
        final storedAfterAssign = _storedGraph(raw);
        final assignmentsBefore = storedBeforeSearch['tag_assignments']!;
        expect(storedAfterAssign['tags'], storedBeforeSearch['tags']);
        expect(
          storedAfterAssign['tag_assignments']!.take(assignmentsBefore.length),
          assignmentsBefore,
        );
        expect(
          storedAfterAssign['tag_assignments'],
          hasLength(assignmentsBefore.length + 1),
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);
        router.pop();
        await _until(
          tester,
          find.byKey(ValueKey('tag-assignment-remove-$existingTagId')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-catalog-search')), findsNothing);

        await _tap(tester, choose);
        await _tap(tester, find.byKey(const ValueKey('tag-catalog-create')));
        const newName = 'Общий тег 🏷️';
        await _until(tester, find.byKey(const ValueKey('tag-editor-name')));
        await tester.enterText(
          find.byKey(const ValueKey('tag-editor-name')),
          newName,
        );
        await _tap(tester, find.byKey(const ValueKey('tag-editor-submit')));
        await _waitFor(
          tester,
          () =>
              find.byKey(const ValueKey('tag-editor-name')).evaluate().isEmpty,
        );
        final newTagId =
            raw.select('SELECT id FROM tags WHERE name = ?', [
                  newName,
                ]).single['id']
                as String;
        expect(_assignments(raw, newTagId), isEmpty);
        final assign = find.byKey(const ValueKey('tag-catalog-assign'));
        expect(assign, findsOneWidget);
        await tester.pumpAndSettle();
        expect(
          assign.hitTestable(),
          findsOneWidget,
          reason:
              'Сообщение об успешном создании не перекрывает назначение тега.',
        );

        await _tap(tester, assign);
        await _waitFor(tester, () => _assigned(raw, newTagId, number));
        router.pop();
        final remove = find.byKey(ValueKey('tag-assignment-remove-$newTagId'));
        await _until(tester, remove);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-catalog-search')), findsNothing);
        await _tap(
          tester,
          find.byKey(ValueKey('tag-assignment-open-$newTagId')),
        );
        await _until(tester, find.byType(TagNavigationPage));
        await tester.pumpAndSettle();
        expect(
          router.current
              .argsAs<TagNavigationRouteArgs>()
              .tagId
              .toCanonicalString(),
          newTagId,
        );
        expect(find.byKey(const ValueKey('tag-catalog-search')), findsNothing);
        router.pop();
        await _tap(tester, remove);
        await _waitFor(tester, () => _assignments(raw, newTagId).isEmpty);
        expect(
          raw.select('SELECT id FROM tags WHERE id = ?', [newTagId]),
          hasLength(1),
        );
        expect(_assigned(raw, existingTagId, number), isTrue);
        expect(
          raw.select('SELECT id FROM daily_choices WHERE id = ?', [
            tagFixtureId(201),
          ]),
          hasLength(1),
        );
        expect(retainedTagFixtureGraph(raw), graphBefore);

        router.pop();
        await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
        await _until(tester, find.text(newName));
        expect(find.text(newName), findsOneWidget);
        await tester.pumpAndSettle();
        final storedBeforeBrowseSearch = _storedGraph(raw);
        for (final query in ['общ', 'спорт', 'общий']) {
          await tester.enterText(search, query);
          await tester.pumpAndSettle();
          expect(
            find.text(newName),
            query == 'спорт' ? findsNothing : findsOneWidget,
          );
          expect(_storedGraph(raw), storedBeforeBrowseSearch);
        }
        await tester.tap(find.byTooltip(localizations.tagCatalogClearSearch));
        await tester.pumpAndSettle();
        expect(find.text(newName), findsOneWidget);
        expect(_storedGraph(raw), storedBeforeBrowseSearch);
        if (number == 1) {
          router.pop();
          final choiceId = (DailyChoiceId.decode(
            tagFixtureId(201),
          ) as DailyChoiceIdDecodingSuccess).id;
          unawaited(router.push(DailyChoiceDetailsRoute(choiceId: choiceId)));
          await _until(
            tester,
            find.byKey(const ValueKey('daily-choice-edit-open')),
          );
          expect(choose, findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Map<String, List<List<Object?>>> _storedGraph(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

String _assignmentLabel(WidgetTester tester, Finder row) =>
    (tester
                .widget<ListTile>(
                  find.descendant(of: row, matching: find.byType(ListTile)),
                )
                .subtitle!
            as Text)
        .data!;

List<sqlite.Row> _assignments(sqlite.Database raw, String tagId) =>
    raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [tagId]);

bool _assigned(sqlite.Database raw, String tagId, int number) =>
    raw.select(
      'SELECT * FROM tag_assignments WHERE tag_id = ? AND intention_id = ?',
      [tagId, tagFixtureId(number)],
    ).length ==
    1;

Future<void> _until(WidgetTester tester, Finder finder) =>
    _waitFor(tester, () => finder.evaluate().isNotEmpty);

Future<void> _waitFor(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _until(tester, finder);
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}
