import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_page.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_state.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_storage_fixture.dart';

final _search = find.byKey(const ValueKey('tag-catalog-search'));
final _list = find.byKey(const ValueKey('tag-catalog-list'));

void main() {
  final intention = IntentionTagTarget(
    (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id,
  );
  final need = LongTermRelationTagTarget(
    (LongTermRelationId.decode(
      tagFixtureId(101),
    ) as LongTermRelationIdDecodingSuccess).id,
  );
  final can = LongTermRelationTagTarget(
    (LongTermRelationId.decode(
      tagFixtureId(102),
    ) as LongTermRelationIdDecodingSuccess).id,
  );
  for (final (description, mode) in <(String, TagCatalogMode)>[
    ('каталог', const TagCatalogBrowseMode()),
    ('выбор для намерения', TagCatalogSelectionMode(intention)),
    ('выбор для связи «нужно»', TagCatalogSelectionMode(need)),
    ('выбор для связи «можно»', TagCatalogSelectionMode(can)),
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
                target: mode is TagCatalogSelectionMode ? mode.target : null,
              ),
            ),
          ),
        );
        final home = _tag(firstTagNumber, 'Дом');
        final work = _tag(lastTagNumber, 'Работа');
        repository.complete([home, work], assignedIds: {home.id});
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(TagCatalogPage)),
        );
        final provider = tagCatalogViewModelProvider(mode: mode);
        container.read(provider.notifier).selectTag(home.id);
        await tester.pumpAndSettle();
        final snapshot = container.read(provider) as TagCatalogLoaded;
        final beforeSearch = _calls(repository);
        expect(beforeSearch, (1, 0, 0));

        for (final (query, names) in [
          ('д', ['Дом']),
          ('до', ['Дом']),
          ('дом', ['Дом']),
          ('дом\u0000', ['Дом']),
          ('дом', ['Дом']),
          ('спорт', <String>[]),
          ('работ', ['Работа']),
        ]) {
          await tester.enterText(_search, query);
          await tester.pumpAndSettle();
          expect(_visibleNames(tester), names);
          expect(_calls(repository), beforeSearch);
          expect(container.read(provider), same(snapshot));
          if (query == 'спорт') {
            expect(find.text('Теги не найдены'), findsOneWidget);
          }
        }
        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Дом', 'Работа']);
        expect(_calls(repository), beforeSearch);
        expect(container.read(provider), same(snapshot));
        if (mode is TagCatalogSelectionMode) {
          expect(_assignment(tester, home), 'Назначен');
          expect(_assignment(tester, work), 'Доступен для назначения');
        }

        final renamed = _tag(lastTagNumber, 'Рабочее');
        final accepted = container
            .read(graphCommandCoordinatorProvider.notifier)
            .acceptTagRename(RenameTag(tagId: work.id, name: renamed.name));
        expect(accepted, isA<TagCommandAccepted>());
        repository.command.complete(
          TagCommandSucceeded(
            ConfirmedGraphResult(
              revision: const TagCatalogTestRevision(2),
              value: TagRenamed(
                TagRenamedChange(
                  revision: const TagCatalogTestRevision(2),
                  before: work,
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
          [home, renamed],
          revision: 2,
          assignedIds: {home.id},
        );
        await tester.pumpAndSettle();
        final afterRename = _calls(repository);
        await tester.enterText(_search, 'раб');
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Рабочее']);
        expect(_calls(repository), afterRename);
        await tester.tap(find.byTooltip('Очистить поиск тегов'));
        await tester.pumpAndSettle();
        expect(_visibleNames(tester), ['Дом', 'Рабочее']);
        expect(_calls(repository), afterRename);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

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
