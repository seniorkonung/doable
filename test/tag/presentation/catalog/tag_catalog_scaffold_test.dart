import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/tag/application/tag_catalog.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/presentation/catalog/tag_catalog_view.dart';
import 'package:doable/src/tag/presentation/catalog/tag_selection_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_root_pages.dart';
import '../../../support/ordinary_page_test_app.dart';
import '../../../support/tag_catalog_test_repository.dart';
import '../../../support/tag_storage_fixture.dart';
import '../../../support/tag_positions.dart';

void main() {
  final intentionId =
      (IntentionId.decode(tagFixtureId(1)) as IntentionIdDecodingSuccess).id;
  for (final (name, selectionContext, showsPrimaryNavigation)
      in <(String, TagSelectionContext, bool)>[
        ('просмотр', const TagBrowseContext(), true),
        ('назначение', TagAssignmentContext(intentionId), false),
      ]) {
    testWidgets(
      '$name ${showsPrimaryNavigation ? 'показывает' : 'не показывает'} основную навигацию при загрузке, отказе и повторе',
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
            child: OrdinaryPageTestApp(
              locale: const Locale('ru'),
              home: TagCatalogView(
                selectionContext: selectionContext,
                onOpenEditor: (_) async => null,
              ),
            ),
          ),
        );
        await tester.pump();
        final navigation = appNavigationDestinations().hitTestable();
        void expectNavigation() => expect(
          navigation,
          showsPrimaryNavigation ? findsNWidgets(3) : findsNothing,
        );
        expectNavigation();
        repository.reads.last.complete(
          const TagCatalogError(TagCatalogUnavailableFailure()),
        );
        await tester.pumpAndSettle();
        expect(find.text('Повторить'), findsOneWidget);
        expectNavigation();
        await tester.tap(find.text('Повторить'));
        await tester.pump();
        expectNavigation();
        repository.complete([
          Tag(
            id: (TagId.decode(tagFixtureId(301)) as TagIdDecodingSuccess).id,
            name: TagName.fromInput('Дом'),
            color: null,
            position: tagPositionAt(1000),
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Дом'), findsOneWidget);
        expectNavigation();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
