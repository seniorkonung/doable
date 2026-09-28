import 'dart:async';

import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
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
      '${isIntention ? 'намерение' : 'долговременная связь'} $number: сквозное назначение и снятие на ${locale.languageCode}',
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
        final runtime = AppRuntime(
          connectionFactory: () =>
              openInMemoryLocalDatabase(setup: (database) => raw = database),
          diagnosticsSink: InMemoryDiagnosticsSink(),
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
        }
        final choose = find.byKey(const ValueKey('tag-assignments-choose'));
        await _until(tester, choose);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tag-catalog-search')), findsNothing);
        if (!isIntention) {
          await tester.scrollUntilVisible(
            choose,
            200,
            scrollable: find.byType(Scrollable).last,
          );
        }
        await _tap(tester, choose);

        final existingTagId = tagFixtureId(lastTagNumber);
        await _tap(
          tester,
          find.byKey(ValueKey('tag-catalog-row-$existingTagId')),
        );
        await _tap(tester, find.byKey(const ValueKey('tag-catalog-assign')));
        await _until(tester, find.text('Работа'));
        await _waitFor(tester, () => _assigned(raw, existingTagId, number));
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
        if (isIntention && number == 1) {
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

List<sqlite.Row> _assignments(sqlite.Database raw, String tagId) =>
    raw.select('SELECT * FROM tag_assignments WHERE tag_id = ?', [tagId]);

bool _assigned(sqlite.Database raw, String tagId, int number) =>
    raw.select(
      'SELECT * FROM tag_assignments WHERE tag_id = ? AND ${number < 100 ? 'intention_id' : 'long_term_relation_id'} = ?',
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
