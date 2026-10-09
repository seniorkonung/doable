import 'package:doable/src/app/navigation/app_destination.dart';
import 'package:doable/src/app/navigation/app_navigation_bar.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/presentation/details/relation_details_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/ordinary_page_test_app.dart';
import '../neighborhood/neighborhood_test_support.dart';
import 'relation_details_test_support.dart';

void main() {
  testWidgets(
    'панель связи доступна при загрузке, чтении, отсутствии и отказах',
    (tester) async {
      final repository = ControlledRelationDetailsRepository();
      addTearDown(repository.dispose);
      final relationId = testRelationId(101);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personalGraphRepositoryProvider.overrideWithValue(repository),
          ],
          child: OrdinaryPageTestApp(
            home: RelationDetailsPage(relationId: relationId),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      _expectNavigation(tester);
      expect(find.text('Loading the relation…'), findsOneWidget);

      final watch = repository.watchAt(0);
      watch.emitDetails(
        testRelationDetails(
          relationId: relationId,
          sourceId: testIntentionId(1),
          relatedId: testIntentionId(2),
        ),
        revision: const TestGraphRevision(1),
      );
      await tester.pumpAndSettle();
      _expectNavigation(tester);
      watch.emitMissing(revision: const TestGraphRevision(2));
      await tester.pumpAndSettle();
      _expectNavigation(tester);

      for (final failure in [
        const LongTermRelationReadUnavailableFailure(),
        const LongTermRelationReadCorruptionFailure(),
        const LongTermRelationReadUnexpectedFailure(),
      ]) {
        watch.fail(failure);
        await tester.pumpAndSettle();
        _expectNavigation(tester);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

void _expectNavigation(WidgetTester tester) {
  expect(find.byType(AppNavigationBar), findsOneWidget);
  expect(
    tester.widget<AppNavigationBar>(find.byType(AppNavigationBar)).selected,
    AppDestination.home,
  );
}
