import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/main.dart';
import 'package:doable/src/app/app_runtime.dart';
import 'package:doable/src/app/routing/app_router.dart';
import 'package:doable/src/app/routing/app_router.gr.dart';
import 'package:doable/src/app/routing/app_router_provider.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/application/tagged_intentions_page.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_page.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_state.dart';
import 'package:doable/src/tag/presentation/navigation/tag_navigation_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../support/in_memory_diagnostics_sink.dart';
import '../support/tag_storage_fixture.dart';

part 'tag_navigation_graph_lifecycle_scenarios.dart';

const _extraPairs = 51;

void main() {
  for (final locale in ['ru', 'en']) {
    testWidgets(
      'каталог ведёт через все порции обоих охватов к точным подробностям на $locale',
      (tester) async {
        final app = await _pumpApp(tester, locale);
        final before = _snapshot(app.raw);
        await _openCatalogTag(tester, firstTagNumber);
        final state = await _loaded(tester, firstTagNumber);
        expect(app.router.current.name, TagNavigationRoute.name);
        expect(
          app.router.current.argsAs<TagNavigationRouteArgs>().tagId,
          _tagId(firstTagNumber),
        );
        _expectNavigation(tester, state, TaggedIntentionsScope.active);
        for (final scope in TaggedIntentionsScope.values) {
          await _selectScope(tester, scope);
          await _loadAll(tester, scope);
          final archived = scope == TaggedIntentionsScope.archived;
          for (final (target, title, description) in [
            if (!archived) ...[
              (_intentionId(1), 'Одинаковое намерение', 'Описание 1'),
              (_intentionId(4), 'Одинаковое намерение', 'Описание 4'),
            ] else
              (_intentionId(2), 'Намерение 2', 'Описание 2'),
            (
              _intentionId(archived ? 1150 : 1050),
              'Получатель ${archived ? 1 : 0}/50',
              'Описание ${archived ? 1 : 0}/50',
            ),
          ]) {
            await _openDetailsAndReturn(
              tester,
              app.router,
              target,
              title: title,
              description: description,
            );
          }
        }
        await _selectScope(tester, TaggedIntentionsScope.active);
        _expectNavigation(
          tester,
          await _loaded(tester, firstTagNumber),
          TaggedIntentionsScope.active,
        );
        app.router.pop();
        await _until(
          tester,
          find.byKey(
            ValueKey('tag-catalog-open-${tagFixtureId(firstTagNumber)}'),
          ),
        );
        expect(app.router.current.name, TagCatalogRoute.name);
        expect(_snapshot(app.raw), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'назначения намерений открывают тот же тег с активным входом на $locale',
      (tester) async {
        final app = await _pumpApp(tester, locale);
        final before = _snapshot(app.raw);
        for (final target in [_intentionId(1), _intentionId(2)]) {
          unawaited(
            app.router.push(IntentionDetailsRoute(intentionId: target)),
          );
          final open = find.byKey(
            ValueKey('tag-assignment-open-${tagFixtureId(firstTagNumber)}'),
          );
          await _until(tester, open);
          await _tap(tester, open);
          _expectNavigation(
            tester,
            await _loaded(tester, firstTagNumber),
            TaggedIntentionsScope.active,
          );
          await _selectScope(tester, TaggedIntentionsScope.archived);
          _expectNavigation(
            tester,
            await _loaded(tester, firstTagNumber),
            TaggedIntentionsScope.archived,
          );
          await _openDetailsAndReturn(
            tester,
            app.router,
            _intentionId(2),
            title: 'Намерение 2',
            description: 'Описание 2',
          );
          app.router.pop();
          await _until(tester, open);
          _expectDetailsRoute(app.router, target);
          await _tap(tester, open);
          _expectNavigation(
            tester,
            await _loaded(tester, firstTagNumber),
            TaggedIntentionsScope.active,
          );
          app.router.pop();
          await _until(tester, open);
          app.router.pop();
          await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
        }
        expect(_snapshot(app.raw), before);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'смена системного языка на открытой навигации сохраняет тег, охваты и все порции из $locale',
      (tester) async {
        final app = await _pumpApp(tester, locale);
        final before = _snapshot(app.raw);
        await _openCatalogTag(tester, firstTagNumber);
        await _loaded(tester, firstTagNumber);
        for (final scope in TaggedIntentionsScope.values) {
          await _selectScope(tester, scope);
          await _loadAll(tester, scope);
          final loaded = await _loaded(tester, firstTagNumber);
          for (final language in [locale == 'ru' ? 'en' : 'ru', locale]) {
            tester.binding.platformDispatcher.localesTestValue = [
              Locale(language),
            ];
            await tester.pumpAndSettle();
            final current = await _loaded(tester, firstTagNumber);
            expect(app.router.current.name, TagNavigationRoute.name);
            expect(
              app.router.current.argsAs<TagNavigationRouteArgs>().tagId,
              loaded.tagId,
            );
            expect(current.tag, loaded.tag);
            expect(current.scope, loaded.scope);
            expect(current.items, orderedEquals(loaded.items));
            expect(current.revision, loaded.revision);
            expect(current.nextCursor, loaded.nextCursor);
            expect(current.hasReachedEnd, isTrue);
            expect(_l10n(tester).localeName, language);
            await _scrollToTop(tester);
            final l10n = _l10n(tester);
            expect(find.text(l10n.tagNavigationTag('Дом 🏷️')), findsOneWidget);
            expect(
              tester.widget<ChoiceChip>(find.byKey(ValueKey(scope))).selected,
              isTrue,
            );
            final archived = scope == TaggedIntentionsScope.archived;
            for (final (target, title) in [
              (
                _intentionId(archived ? 2 : 1),
                archived ? 'Намерение 2' : 'Одинаковое намерение',
              ),
            ]) {
              final row = find.byKey(ValueKey(target));
              await tester.scrollUntilVisible(
                row,
                800,
                scrollable: find.byType(Scrollable).last,
              );
              expect(
                find.descendant(of: row, matching: find.text(title)),
                findsOneWidget,
              );
            }
            expect(_snapshot(app.raw), before);
            expect(tester.takeException(), isNull);
          }
        }
      },
    );

    testWidgets(
      'теги без назначений и только в архиве доступны из основного каталога на $locale',
      (tester) async {
        final app = await _pumpApp(tester, locale);
        final before = _snapshot(app.raw);
        for (final (number, name) in [
          (303, 'Без назначений'),
          (304, 'Только в архиве'),
        ]) {
          await _openCatalogTag(tester, number);
          final active = await _loaded(tester, number);
          final l10n = _l10n(tester);
          expect(active.tagId, _tagId(number));
          expect(active.tag.name.value, name);
          expect(active.scope, TaggedIntentionsScope.active);
          expect(active.items, isEmpty);
          expect(find.text(l10n.tagNavigationTag(name)), findsOneWidget);
          expect(find.text(l10n.tagNavigationEmptyActive), findsOneWidget);
          expect(find.text(l10n.tagNotFound), findsNothing);
          await _selectScope(
            tester,
            TaggedIntentionsScope.archived,
            tagNumber: number,
          );
          final archived = await _loaded(tester, number);
          expect(archived.tagId, active.tagId);
          if (number == 303) {
            expect(archived.items, isEmpty);
            expect(find.text(l10n.tagNavigationEmptyArchived), findsOneWidget);
          } else {
            expect(archived.items.map((item) => item.id), [_intentionId(2)]);
            await _openDetailsAndReturn(
              tester,
              app.router,
              _intentionId(2),
              title: 'Намерение 2',
              description: 'Описание 2',
              tagNumber: number,
            );
          }
          app.router.pop();
          await _until(
            tester,
            find.byKey(ValueKey('tag-catalog-open-${tagFixtureId(number)}')),
          );
          expect(app.router.current.name, TagCatalogRoute.name);
          app.router.pop();
          await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
        }
        expect(_snapshot(app.raw), before);
        expect(tester.takeException(), isNull);
      },
    );
    _testTaggedGraphLifecycle(locale);
  }
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(TagNavigationPage)));

void _expectNavigation(
  WidgetTester tester,
  TagNavigationLoaded state,
  TaggedIntentionsScope scope,
) {
  expect(state.tagId, _tagId(firstTagNumber));
  expect(state.scope, scope);
  expect(state.items.map((item) => item.id), _targets(scope).take(50));
  expect(
    tester.widget<ChoiceChip>(find.byKey(ValueKey(scope))).selected,
    isTrue,
  );
  expect(find.text(_l10n(tester).tagNavigationTag('Дом 🏷️')), findsOneWidget);
}

Future<void> _selectScope(
  WidgetTester tester,
  TaggedIntentionsScope scope, {
  int tagNumber = firstTagNumber,
}) async {
  await _scrollToTop(tester);
  await _tap(tester, find.byKey(ValueKey(scope)));
  await _loaded(tester, tagNumber);
  await _scrollToTop(tester);
  expect(_state(tester, tagNumber).scope, scope);
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).last, const Offset(0, 20000));
  await tester.pumpAndSettle();
}

Future<void> _loadAll(WidgetTester tester, TaggedIntentionsScope scope) async {
  final expected = _targets(scope);
  for (final count in [50, expected.length]) {
    final state = await _loaded(tester, firstTagNumber);
    expect(state.scope, scope);
    expect(state.items.map((item) => item.id), expected.take(count));
    expect(state.items.map((item) => item.id).toSet(), hasLength(count));
    if (count == expected.length) {
      expect(state.hasReachedEnd, isTrue);
      final allShown = find.text(_l10n(tester).tagNavigationAllShown);
      await tester.scrollUntilVisible(
        allShown,
        800,
        scrollable: find.byType(Scrollable).last,
      );
      expect(allShown, findsOneWidget);
    } else {
      expect(state.nextCursor, isNotNull);
      final more = find.widgetWithText(
        OutlinedButton,
        _l10n(tester).tagNavigationLoadMore,
      );
      await tester.scrollUntilVisible(
        more,
        800,
        scrollable: find.byType(Scrollable).last,
      );
      await _tap(tester, more);
    }
  }
}

void _expectDetailsRoute(AppRouter router, IntentionId intentionId) {
  expect(router.current.name, IntentionDetailsRoute.name);
  expect(
    router.current.argsAs<IntentionDetailsRouteArgs>().intentionId,
    intentionId,
  );
}

Future<void> _openDetailsAndReturn(
  WidgetTester tester,
  AppRouter router,
  IntentionId target, {
  required String title,
  String? description,
  int tagNumber = firstTagNumber,
}) async {
  final before = await _loaded(tester, tagNumber);
  await _scrollToTop(tester);
  final row = find.byKey(ValueKey(target));
  await tester.scrollUntilVisible(
    row,
    800,
    scrollable: find.byType(Scrollable).last,
  );
  expect(find.descendant(of: row, matching: find.text(title)), findsOneWidget);
  await _tap(tester, row);
  const titleKey = 'intention-details-title';
  await _until(tester, find.byKey(ValueKey(titleKey)));
  _expectDetailsRoute(router, target);
  expect(tester.widget<Text>(find.byKey(ValueKey(titleKey))).data, title);
  if (description != null) expect(find.text(description), findsOneWidget);
  final openTag = find.byKey(
    ValueKey('tag-assignment-open-${tagFixtureId(tagNumber)}'),
  );
  await _until(tester, openTag);
  router.pop();
  final after = await _loaded(tester, tagNumber);
  expect(router.current.name, TagNavigationRoute.name);
  expect(router.current.argsAs<TagNavigationRouteArgs>().tagId, before.tagId);
  expect(after.tagId, before.tagId);
  expect(after.scope, before.scope);
  expect(
    after.items.map((item) => item.id),
    before.items.map((item) => item.id),
  );
  expect(after.nextCursor, before.nextCursor);
  expect(after.revision, before.revision);
  await _scrollToTop(tester);
  expect(
    tester.widget<ChoiceChip>(find.byKey(ValueKey(after.scope))).selected,
    isTrue,
  );
}

List<IntentionId> _targets(TaggedIntentionsScope scope) {
  final archived = scope == TaggedIntentionsScope.archived;
  return [
    if (archived) _intentionId(2) else ...[_intentionId(1), _intentionId(4)],
    for (var index = 0; index < _extraPairs; index++)
      _intentionId(1000 + (archived ? 100 : 0) + index),
  ];
}

TagId _tagId(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

IntentionId _intentionId(int number) =>
    (IntentionId.decode(tagFixtureId(number)) as IntentionIdDecodingSuccess).id;

LongTermRelationId _relationId(int number) => (LongTermRelationId.decode(
  tagFixtureId(number),
) as LongTermRelationIdDecodingSuccess).id;

Map<String, List<List<Object?>>> _snapshot(sqlite.Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

Future<({sqlite.Database raw, AppRouter router, AppRuntime runtime})> _pumpApp(
  WidgetTester tester,
  String locale, {
  void Function(sqlite.Database)? seed,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.binding.platformDispatcher.localesTestValue = [Locale(locale)];
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
  final ready = (await tester.runAsync(runtime.bootstrap)) as AppRuntimeReady;
  if (seed != null) {
    seed(raw);
  } else {
    seedTagNavigationFixture(raw, extraPairsPerScope: _extraPairs);
  }
  final router = ready.container.read(appRouterProvider);
  await tester.pumpWidget(MainApp(runtime: runtime));
  await _until(tester, find.byKey(const ValueKey('catalog-open-tags')));
  await _until(
    tester,
    find.text(seed == null ? 'Получатель 0/50' : 'Одинаковое намерение'),
  );
  return (raw: raw, router: router, runtime: runtime);
}

Future<void> _openCatalogTag(WidgetTester tester, int number) async {
  await _tap(tester, find.byKey(const ValueKey('catalog-open-tags')));
  await _tap(
    tester,
    find.byKey(ValueKey('tag-catalog-open-${tagFixtureId(number)}')),
  );
}

TagNavigationState _state(WidgetTester tester, int number) =>
    ProviderScope.containerOf(
      tester.element(find.byType(TagNavigationPage)),
      listen: false,
    ).read(tagNavigationViewModelProvider(_tagId(number)));

Future<TagNavigationLoaded> _loaded(WidgetTester tester, int number) async {
  await _until(tester, find.byType(TagNavigationPage));
  await _waitFor(
    tester,
    () => switch (_state(tester, number)) {
      TagNavigationLoaded(
        :final canUseCurrentItems,
        pageStatus: TagNavigationPageIdle(),
      ) =>
        canUseCurrentItems,
      _ => false,
    },
  );
  await tester.pumpAndSettle();
  final state = _state(tester, number) as TagNavigationLoaded;
  expect(state.canUseCurrentItems, isTrue);
  expect(state.pageStatus, isA<TagNavigationPageIdle>());
  return state;
}

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
  await _waitFor(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
}
