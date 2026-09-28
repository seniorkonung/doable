@Tags(['slow'])
library;

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/data/local/app_database.dart' hide Tags;
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_section.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_state.dart';
import 'package:doable/src/tag/presentation/assignments/tag_assignments_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../../support/in_memory_diagnostics_sink.dart';
import '../../../support/tag_storage_fixture.dart';

void main() {
  late AppDatabase database;
  late sqlite.Database raw;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(
      openInMemoryLocalDatabase(setup: (connection) => raw = connection),
    );
    await database.open();
    seedLargeTagReadFixture(raw);
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 27),
      InMemoryDiagnosticsSink(),
    );
  });
  tearDown(() => database.close());

  for (final (kind, target) in [
    (
      'намерения',
      IntentionTagTarget(
        (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id,
      ),
    ),
    (
      'долговременной связи',
      LongTermRelationTagTarget(
        (LongTermRelationId.decode(
          tagFixtureId(101),
        ) as LongTermRelationIdDecodingSuccess).id,
      ),
    ),
  ]) {
    testWidgets(
      'подгрузка и прокрутка 350 назначений $kind остаются доступными',
      (tester) async {
        tester.view.physicalSize = const Size(600, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: SingleChildScrollView(
                  key: const ValueKey('assignment-cost-scroll'),
                  child: TagAssignmentsSection(
                    target: target,
                    isArchived: false,
                    onChooseTag: (_) {},
                    onOpenTag: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final scroll = find.byKey(const ValueKey('assignment-cost-scroll'));
        expect(scroll, findsOneWidget);
        final container = ProviderScope.containerOf(tester.element(scroll));
        await _pumpUntil(
          tester,
          () =>
              container.read(tagAssignmentsViewModelProvider(target))
                  is TagAssignmentsLoaded,
        );
        final model = container.read(
          tagAssignmentsViewModelProvider(target).notifier,
        );
        for (var page = 0; page < 6; page++) {
          await tester.runAsync(model.loadMore);
          await _pumpUntil(tester, () {
            final value = container.read(
              tagAssignmentsViewModelProvider(target),
            );
            return value is TagAssignmentsLoaded &&
                value.items.length == (page + 2) * 50;
          });
        }
        final state = container.read(tagAssignmentsViewModelProvider(target));
        expect(state, isA<TagAssignmentsLoaded>());
        final loaded = state as TagAssignmentsLoaded;
        expect(loaded.items, hasLength(350));
        expect(loaded.items.first.id.toCanonicalString(), tagFixtureId(10000));
        expect(
          loaded.items.last.id.toCanonicalString(),
          tagFixtureId(target is IntentionTagTarget ? 10698 : 11047),
        );

        final scrollable = tester.state<ScrollableState>(
          find.byType(Scrollable).last,
        );
        var farthestOffset = 0.0;
        for (var movement = 0; movement < 20; movement++) {
          await tester.drag(scroll, Offset(0, movement < 10 ? -600 : 600));
          await tester.pumpAndSettle();
          if (scrollable.position.pixels > farthestOffset) {
            farthestOffset = scrollable.position.pixels;
          }
          expect(tester.takeException(), isNull);
        }
        expect(farthestOffset, greaterThan(0));
        expect(scrollable.position.pixels, lessThan(100));
        expect(
          container.read(tagAssignmentsViewModelProvider(target)),
          same(state),
        );
      },
    );
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var attempt = 0; attempt < 100 && !done(); attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(done(), isTrue);
}
