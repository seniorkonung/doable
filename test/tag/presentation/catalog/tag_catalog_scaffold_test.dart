import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/editor/intention_draft_tag_set.dart';
import 'package:doable/src/intention/presentation/editor/intention_editor_view_model.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_storage_fixture.dart';

void main() {
  final intentionId =
      (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;
  for (final (name, contextOf)
      in <(String, TagSelectionContext Function(IntentionDraftTagSet))>[
        ('просмотр', (_) => const TagBrowseContext()),
        ('назначение', (_) => TagAssignmentContext(intentionId)),
        ('черновик', TagDraftContext.new),
      ]) {
    testWidgets('$name сохраняет свой каркас при загрузке, отказе и повторе', (
      tester,
    ) async {
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
      final selectionContext = contextOf(
        container.read(session.notifier).draftTagSet,
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        subscription.close();
        container.dispose();
        await repository.dispose();
      });
      var openedNavigation = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: OrdinaryPageTestApp(
            locale: const Locale('ru'),
            home: TagCatalogView(
              selectionContext: selectionContext,
              onOpenEditor: (_) async => null,
              onOpenNavigation: (_) => openedNavigation++,
            ),
          ),
        ),
      );
      await tester.pump();
      final browsing = selectionContext is TagBrowseContext;
      void expectNavigation() => expect(
        find.byType(AppNavigationBar),
        browsing ? findsOneWidget : findsNothing,
      );
      expectNavigation();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      repository.reads.last.complete(
        const TagCatalogError(TagCatalogUnavailableFailure()),
      );
      await tester.pumpAndSettle();
      expectNavigation();
      await tester.tap(find.text('Повторить'));
      await tester.pump();
      expectNavigation();
      final tag = Tag(
        id: (TagId.decode(tagFixtureId(301)) as TagIdDecodingSuccess).id,
        name: TagName.fromInput('Дом'),
      );
      repository.complete([tag]);
      await tester.pumpAndSettle();
      expectNavigation();
      expect(find.byKey(const ValueKey('tag-catalog-create')), findsOneWidget);
      final open = find.byKey(
        ValueKey('tag-catalog-open-${tagFixtureId(301)}'),
      );
      expect(open, browsing ? findsOneWidget : findsNothing);
      if (browsing) {
        await tester.tap(open);
        expect(openedNavigation, 1);
      } else {
        await tester.tap(
          find.byKey(ValueKey('tag-catalog-row-${tagFixtureId(301)}')),
        );
        await tester.pump();
        expect(openedNavigation, 0);
        final actionKey = switch (selectionContext) {
          TagAssignmentContext() => 'tag-catalog-assign',
          TagDraftContext() => 'tag-catalog-add-to-draft',
          TagBrowseContext() => throw StateError('Открыт выбор тега'),
        };
        expect(find.byKey(ValueKey(actionKey)), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
