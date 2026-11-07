import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/action/application/action_list_item.dart';
import 'package:doable/src/action/application/intention_actions.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/action/presentation/intention_actions/intention_actions_sliver.dart';
import 'package:doable/src/action/presentation/intention_actions/intention_actions_view_model.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/details/intention_page_target.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/tag_read_contract_test_fallback.dart';

void main() {
  testWidgets('устаревший список не показывает неработающую подгрузку', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _Repository();
    final intentionId = (IntentionId.decode(
      '018f1200-0000-7000-8000-000000000001',
    ) as IntentionIdDecodingSuccess).id;
    final actionId = (ActionId.decode(
      '018f1400-0000-7000-8000-000000000001',
    ) as ActionIdDecodingSuccess).id;
    final today = CalendarDate.fromParts(2026, 10, 8);
    final instance = IntentionPageInstance(target: const ActionsTarget());
    final provider = intentionActionsViewModelProvider(intentionId, instance);
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: doableTheme(Brightness.light),
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                IntentionActionsSliver(
                  intentionId: intentionId,
                  pageInstance: instance,
                  today: today,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    container.read(provider.notifier).setVisible(true);
    repository.requests[0].complete(
      IntentionActionsPageSuccess(
        IntentionActionsFirstPage(
          items: [
            ActionListItem(
              id: actionId,
              title: ActionTitle('Действие'),
              description: null,
              date: today,
              schedule: const ActionAllDay(),
              priority: ActionPriority.p4,
              isCompleted: false,
              rootIntentionId: intentionId,
              rootTitle: 'Намерение',
              pathIntentionCount: 1,
            ),
          ],
          counts: const IntentionActionCounts(
            root: 2,
            intermediate: 0,
            terminal: 0,
            total: 2,
          ),
          nextCursor: _Cursor(),
          revision: const _Revision(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.bySemanticsLabel('Загружаем ещё действия…'), findsOneWidget);

    repository.requests[1].complete(
      const IntentionActionsPageError(IntentionActionsSnapshotExpired()),
    );
    await tester.pump();
    repository.requests[2].complete(
      const IntentionActionsPageError(IntentionActionsUnavailableFailure()),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Действие'), findsOneWidget);
    expect(find.text('Не удалось загрузить действия.'), findsOneWidget);
    expect(find.bySemanticsLabel('Загружаем ещё действия…'), findsNothing);
    semantics.dispose();
  });
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  final requests = <Completer<IntentionActionsPageResult>>[];

  @override
  Future<IntentionActionsPageResult> getIntentionActionsPage(
    IntentionActionsQuery query,
  ) {
    final request = Completer<IntentionActionsPageResult>();
    requests.add(request);
    return request.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Cursor implements IntentionActionsCursor {}

final class _Revision implements GraphRevision {
  const _Revision();

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => GraphRevisionOrder.same;
}
