import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_storage_fixture.dart';

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _list = find.byKey(const ValueKey('tag-catalog-list'));

void main() {
  final intention =
      (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;
  final archivedAction =
      (IntentionId.decode(tagFixtureId(2)) as IntentionIdDecodingSuccess).id;
  for (final (description, mode) in <(String, TagCatalogMode)>[
    ('каталог', const TagCatalogBrowseMode()),
    ('выбор для намерения', TagCatalogSelectionMode(intention)),
    (
      'выбор для архивированного действия',
      TagCatalogSelectionMode(archivedAction),
    ),
  ]) {
    testWidgets(
      '$description: только подтверждённая операция добавляет чтение, поиск сохраняет счётчики',
      (tester) async {
        final repository = TagCatalogTestRepository();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await repository.dispose();
        });
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              personalGraphRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp(
              locale: const Locale('ru'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: TagCatalogPage(
                selectionContext: switch (mode) {
                  TagCatalogBrowseMode() => const TagBrowseContext(),
                  TagCatalogSelectionMode(:final intentionId) =>
                    TagAssignmentContext(intentionId),
                },
              ),
            ),
          ),
        );
        final home = _tag(firstTagNumber, 'Дом');
        final forHome = _tag(firstTagNumber + 2, 'Для дома');
        final work = _tag(lastTagNumber, 'Работа');
        repository.complete([home, forHome, work], assignedIds: {home.id});
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(TagCatalogPage)),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TagCatalogPage)),
        );
        final provider = tagCatalogViewModelProvider(mode: mode);
        container.read(provider.notifier).selectTag(home.id);
        await tester.pumpAndSettle();
        final snapshot = container.read(provider) as TagCatalogLoaded;
        final beforeSearch = _calls(repository);
        expect(beforeSearch, (1, 0, 0));

        for (final (query, names, invalid) in [
          ('\u0000', ['Дом', 'Для дома', 'Работа'], true),
          ('д', ['Дом', 'Для дома'], false),
          ('до', ['Дом', 'Для дома'], false),
          ('дом', ['Дом', 'Для дома'], false),
          ('работ\u0000', ['Дом', 'Для дома'], true),
          ('работ', ['Работа'], false),
          ('дом\ud800', ['Работа'], true),
          ('дом', ['Дом', 'Для дома'], false),
          ('работ\udc00', ['Дом', 'Для дома'], true),
          ('', ['Дом', 'Для дома', 'Работа'], false),
          ('спорт', <String>[], false),
          ('дом\u0000', <String>[], true),
          ('работ', ['Работа'], false),
        ]) {
          await tester.enterText(_search, query);
          await tester.pumpAndSettle();
          expect(_visibleNames(tester), names);
          expect(_calls(repository), beforeSearch);
          expect(container.read(provider), same(snapshot));
          expect(tester.widget<TextField>(_search).controller!.text, query);
          expect(
            find.text(l10n.tagCatalogInvalidSearch),
            invalid ? findsOneWidget : findsNothing,
          );
          expect(
            find.text(l10n.tagCatalogNoMatches),
            names.isEmpty ? findsOneWidget : findsNothing,
          );
        }
        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Дом', 'Для дома', 'Работа']);
        expect(_calls(repository), beforeSearch);
        expect(container.read(provider), same(snapshot));
        if (mode is TagCatalogSelectionMode) {
          expect(_assignment(tester, home), 'Назначен');
          expect(_assignment(tester, forHome), 'Доступен для назначения');
          expect(_assignment(tester, work), 'Доступен для назначения');
        }

        await tester.enterText(_search, 'дом');
        await tester.pumpAndSettle();
        const invalidInput = 'работ\ud800';
        await tester.enterText(_search, invalidInput);
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Дом', 'Для дома']);
        expect(_calls(repository), beforeSearch);
        final renamed = _tag(firstTagNumber, 'Спорт');
        final accepted = container
            .read(graphCommandCoordinatorProvider.notifier)
            .acceptTagRename(RenameTag(tagId: home.id, name: renamed.name));
        expect(accepted, isA<TagCommandAccepted>());
        repository.command.complete(
          TagCommandSucceeded(
            ConfirmedGraphResult(
              revision: const TagCatalogTestRevision(2),
              value: TagRenamed(
                TagRenamedChange(
                  revision: const TagCatalogTestRevision(2),
                  before: home,
                  after: renamed,
                ),
              ),
            ),
          ),
        );
        await (accepted as TagCommandAccepted).future;
        await tester.pump();
        expect(_calls(repository), (beforeSearch.$1 + 1, 0, 1));
        repository.complete(
          [renamed, forHome, work],
          revision: 2,
          assignedIds: {home.id},
        );
        await tester.pumpAndSettle();
        final afterRename = _calls(repository);
        expect(afterRename, (beforeSearch.$1 + 1, 0, 1));
        final updatedSnapshot = container.read(provider);
        expect(_visibleNames(tester), ['Для дома']);
        expect(
          tester.widget<TextField>(_search).controller!.text,
          invalidInput,
        );
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(find.text(l10n.tagCatalogNoMatches), findsNothing);
        if (mode is TagCatalogSelectionMode) {
          expect(_assignment(tester, forHome), 'Доступен для назначения');
        }
        await tester.enterText(_search, 'раб');
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Работа']);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
        expect(_calls(repository), afterRename);
        expect(container.read(provider), same(updatedSnapshot));
        await tester.enterText(_search, 'дом\udc00');
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Работа']);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsOneWidget);
        expect(_calls(repository), afterRename);
        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Спорт', 'Для дома', 'Работа']);
        expect(find.text(l10n.tagCatalogInvalidSearch), findsNothing);
        expect(tester.widget<TextField>(_search).controller!.text, isEmpty);
        expect(_calls(repository), afterRename);
        expect(container.read(provider), same(updatedSnapshot));
        if (mode is TagCatalogSelectionMode) {
          expect(_assignment(tester, renamed), 'Назначен');
          expect(_assignment(tester, forHome), 'Доступен для назначения');
          expect(_assignment(tester, work), 'Доступен для назначения');
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'черновик: поиск и локальные добавления не добавляют чтений, команд и проверок пар, а поиск не меняет набор',
    (tester) async {
      final repository = TagCatalogTestRepository();
      final container = ProviderContainer(
        overrides: [
          personalGraphRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final session = intentionEditorViewModelProvider(
        IntentionCreationFormKey(),
      );
      final subscription = container.listen(session, (_, _) {});
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        subscription.close();
        container.dispose();
        await repository.dispose();
      });
      final draft = container.read(session.notifier).draftTagSet;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TagCatalogView(
              selectionContext: TagDraftContext(draft),
              onOpenEditor: (_) async => null,
              onOpenNavigation: (_) {},
            ),
          ),
        ),
      );
      final home = _tag(firstTagNumber, 'Дом');
      final forHome = _tag(firstTagNumber + 2, 'Для дома');
      final work = _tag(lastTagNumber, 'Работа');
      repository.complete([home, forHome, work]);
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(TagCatalogView)),
      );
      final add = find.byKey(const ValueKey('tag-catalog-add-to-draft'));
      await tester.tap(_row(home));
      await tester.pump();
      await tester.tap(add);
      await tester.pumpAndSettle();
      final included = draft.current.tagIds;
      expect(included, [home.id]);
      final beforeSearch = _calls(repository);
      expect(beforeSearch, (1, 0, 0));

      for (final (query, names, invalid) in [
        ('\u0000', ['Дом', 'Для дома', 'Работа'], true),
        ('д', ['Дом', 'Для дома'], false),
        ('дом', ['Дом', 'Для дома'], false),
        ('работ\u0000', ['Дом', 'Для дома'], true),
        ('работ', ['Работа'], false),
        ('дом\ud800', ['Работа'], true),
        ('', ['Дом', 'Для дома', 'Работа'], false),
        ('спорт', <String>[], false),
        ('дом\u0000', <String>[], true),
        ('дом', ['Дом', 'Для дома'], false),
      ]) {
        await tester.enterText(_search, query);
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), names);
        expect(_calls(repository), beforeSearch);
        expect(draft.current.tagIds, same(included));
        expect(tester.widget<TextField>(_search).controller!.text, query);
        expect(
          find.text(l10n.tagCatalogInvalidSearch),
          invalid ? findsOneWidget : findsNothing,
        );
        expect(
          find.text(l10n.tagCatalogNoMatches),
          names.isEmpty ? findsOneWidget : findsNothing,
        );
      }

      // Локальное добавление под активным поиском не перечитывает каталог.
      await tester.tap(_row(forHome));
      await tester.pump();
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(draft.current.tagIds, [home.id, forHome.id]);
      expect(_draftStatus(forHome, l10n.tagCatalogInDraft), findsOneWidget);
      expect(_visibleNames(tester), ['Дом', 'Для дома']);
      expect(tester.widget<TextField>(_search).controller!.text, 'дом');
      expect(_calls(repository), beforeSearch);

      // Только подтверждённая постоянная операция добавляет чтение.
      final renamed = _tag(firstTagNumber, 'Спорт');
      final accepted = container
          .read(graphCommandCoordinatorProvider.notifier)
          .acceptTagRename(RenameTag(tagId: home.id, name: renamed.name));
      expect(accepted, isA<TagCommandAccepted>());
      repository.command.complete(
        TagCommandSucceeded(
          ConfirmedGraphResult(
            revision: const TagCatalogTestRevision(2),
            value: TagRenamed(
              TagRenamedChange(
                revision: const TagCatalogTestRevision(2),
                before: home,
                after: renamed,
              ),
            ),
          ),
        ),
      );
      await (accepted as TagCommandAccepted).future;
      await tester.pump();
      expect(_calls(repository), (beforeSearch.$1 + 1, 0, 1));
      repository.complete([renamed, forHome, work], revision: 2);
      await tester.pumpAndSettle();
      final afterRename = _calls(repository);
      expect(afterRename, (beforeSearch.$1 + 1, 0, 1));
      expect(_visibleNames(tester), ['Для дома']);
      expect(tester.widget<TextField>(_search).controller!.text, 'дом');

      await tester.tap(find.byTooltip('Очистить поиск тегов'));
      await tester.pumpAndSettle();
      expect(_visibleNames(tester), ['Спорт', 'Для дома', 'Работа']);
      expect(_draftStatus(renamed, l10n.tagCatalogInDraft), findsOneWidget);
      expect(_draftStatus(forHome, l10n.tagCatalogInDraft), findsOneWidget);
      expect(
        _draftStatus(work, l10n.tagCatalogAvailableForDraft),
        findsOneWidget,
      );
      expect(draft.current.tagIds, [home.id, forHome.id]);
      expect(_calls(repository), afterRename);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder _row(Tag tag) =>
    find.byKey(ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'));

Finder _draftStatus(Tag tag, String status) =>
    find.descendant(of: _row(tag), matching: find.text(status));

(int, int, int) _calls(TagCatalogTestRepository repository) => (
  repository.reads.length,
  repository.statusReads.length,
  repository.commands.length,
);

List<String> _visibleNames(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(of: _list, matching: find.byType(ListTile)),
  ))
    (tile.title! as Text).data!,
];

String _assignment(WidgetTester tester, Tag tag) =>
    (tester
                .widget<ListTile>(
                  find.descendant(
                    of: find.byKey(
                      ValueKey('tag-catalog-row-${tag.id.toCanonicalString()}'),
                    ),
                    matching: find.byType(ListTile),
                  ),
                )
                .subtitle!
            as Text)
        .data!;

Tag _tag(int number, String name) => Tag(
  id: (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id,
  name: TagName.fromInput(name),
);
