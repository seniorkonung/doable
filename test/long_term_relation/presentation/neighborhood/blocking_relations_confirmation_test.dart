import 'dart:async';

import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_projection.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_confirmation.dart';
import 'package:doable/src/long_term_relation/presentation/neighborhood/blocking_relations_selection_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'neighborhood_test_support.dart';

void main() {
  testWidgets('показывает весь выбор из разных групп и порций при крупном тексте', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(480, 720);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final harness = await _pumpAction(tester, const Locale('ru'));
    final rows = [
      testGroupRow(ownerId: harness.intentionId, index: 1),
      for (var index = 2; index <= 18; index++)
        testGroupRow(
          ownerId: harness.intentionId,
          index: index,
          type: LongTermRelationType.can,
          direction: RelationDirection.incoming,
          scope: RelationScope.archived,
          neighborTitle: 'Одноимённое',
        ),
    ];
    for (final row in rows) {
      harness.select(row);
    }
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();
    expect(
      find.text('Чтобы Намерение-владелец, нужно Связанное 1'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(
        ValueKey(
          'blocking-relations-confirm-row-${rows[1].relation.id.toCanonicalString()}',
        ),
      ),
      250,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Связь в архиве'), findsWidgets);
    expect(find.text('Входящие'), findsWidgets);
    expect(
      find.textContaining(rows[1].source.id.toCanonicalString()),
      findsWidgets,
    );
    expect(harness.repository.commands, isEmpty);

    final last = find.byKey(
      ValueKey(
        'blocking-relations-confirm-row-${rows.last.relation.id.toCanonicalString()}',
      ),
    );
    await tester.scrollUntilVisible(
      last,
      450,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              ValueKey(
                'blocking-relations-confirm-semantics-${rows.last.relation.id.toCanonicalString()}',
              ),
            ),
          )
          .label,
      contains('Входящие'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      350,
      scrollable: find.byType(Scrollable).last,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-cancel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-confirm-delete')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'отмена не отправляет команду, а подтверждение отправляет только снимок один раз',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('en'));
      final first = testGroupRow(ownerId: harness.intentionId, index: 1);
      final second = testGroupRow(
        ownerId: harness.intentionId,
        index: 2,
        type: LongTermRelationType.can,
        direction: RelationDirection.incoming,
        scope: RelationScope.archived,
        neighborTitle: 'Same name',
      );
      harness.select(first);
      harness.select(second);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('blocking-relations-cancel')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-cancel')));
      await tester.pumpAndSettle();
      expect(harness.repository.commands, isEmpty);

      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();
      final later = testGroupRow(ownerId: harness.intentionId, index: 3);
      expect(
        harness.container
            .read(
              blockingRelationsSelectionViewModelProvider(harness.intentionId),
            )
            .selected
            .containsKey(later.relation.id),
        isFalse,
      );
      final confirm = find.byKey(
        const ValueKey('blocking-relations-confirm-delete'),
      );
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.tap(confirm, warnIfMissed: false);
      await tester.pump();
      expect(harness.repository.commands, hasLength(1));
      expect(
        (harness.repository.commands.single as DeleteBlockingRelations)
            .relationIds,
        {first.relation.id, second.relation.id},
      );
    },
  );

  testWidgets(
    'английский резервный язык и пустой выбор не запускают удаление',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('fr'));
      expect(
        find.byKey(const ValueKey('blocking-relations-review')),
        findsNothing,
      );
      expect(harness.repository.commands, isEmpty);
      harness.select(testGroupRow(ownerId: harness.intentionId, index: 1));
      await tester.pump();
      expect(find.text('Review selected relations'), findsOneWidget);
    },
  );

  testWidgets('ошибка принятой операции остаётся у инлайн-сообщения', (
    tester,
  ) async {
    final harness = await _pumpAction(tester, const Locale('ru'));
    harness.select(testGroupRow(ownerId: harness.intentionId, index: 1));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(
      const ValueKey('blocking-relations-confirm-delete'),
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pump();
    expect(find.text('Удаляем выбранные связи…'), findsOneWidget);
    harness.repository.requests.single.complete(
      const GraphCommandFailed<
        BlockingRelationsDeleted,
        DeleteBlockingRelationsFailure
      >(DeleteBlockingRelationsUnavailableFailure()),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('blocking-relations-delete-failure')),
      findsOneWidget,
    );
    expect(
      find.text('Не удалось удалить выбранные связи. Повторите попытку.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('blocking-relations-edit-selection')),
      findsOneWidget,
    );
  });

  testWidgets(
    'изменённый во время просмотра черновик требует нового подтверждения',
    (tester) async {
      final harness = await _pumpAction(tester, const Locale('en'));
      harness.select(testGroupRow(ownerId: harness.intentionId, index: 1));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('blocking-relations-review')));
      await tester.pumpAndSettle();
      harness.select(testGroupRow(ownerId: harness.intentionId, index: 2));
      await tester.pump();
      final confirm = find.byKey(
        const ValueKey('blocking-relations-confirm-delete'),
      );
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(harness.repository.commands, isEmpty);
      expect(
        find.byKey(const ValueKey('blocking-relations-review')),
        findsOneWidget,
      );
    },
  );
}

Future<_Harness> _pumpAction(WidgetTester tester, Locale locale) async {
  final harness = _Harness();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(harness.repository),
      ],
      child: MaterialApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: Center(
            child: BlockingRelationsConfirmationAction(
              intentionId: harness.intentionId,
              intentionTitle: 'Намерение-владелец',
            ),
          ),
        ),
      ),
    ),
  );
  return harness
    ..container = ProviderScope.containerOf(
      tester.element(find.byType(BlockingRelationsConfirmationAction)),
    );
}

final class _Harness {
  final intentionId = testIntentionId(1);
  final repository = _CommandRepository();
  late ProviderContainer container;

  bool select(LongTermRelationSummary row) => container
      .read(blockingRelationsSelectionViewModelProvider(intentionId).notifier)
      .select(row);
}

final class _CommandRepository implements PersonalGraphRepository {
  final commands = <GraphCommand>[];
  final requests = <Completer<Object>>[];

  @override
  Future<GraphCommandResult<T, F>> execute<
    T extends GraphCommandOutcome,
    F extends GraphCommandFailure
  >(GraphCommand<T, F> command) async {
    commands.add(command);
    final request = Completer<Object>();
    requests.add(request);
    return await request.future as GraphCommandResult<T, F>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    'Неожиданный вызов репозитория: ${invocation.memberName}',
  );
}
