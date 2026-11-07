import 'dart:async';

import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/presentation/catalog/intention_catalog_purpose.dart';
import 'package:doable/src/long_term_relation/application/intention_relation_group.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_state.dart';
import 'package:doable/src/long_term_relation/presentation/batch_picker/relation_batch_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../intention/presentation/catalog/catalog_test_support.dart';

void main() {
  testWidgets('завершение команды согласует отметку под другой страницей', (
    tester,
  ) async {
    final repository = ControlledCatalogRepository();
    final container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final provider = relationBatchViewModelProvider(
      IntentionSearchSession(),
      _id(9),
      IntentionRelationGroup.needs,
      'Страница',
    );
    Widget screen(bool active) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: TickerMode(
          enabled: active,
          child: Consumer(
            builder: (context, ref, child) => Text(
              ref.watch(provider).selected.map((item) => item.title).join(','),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(screen(true));
    container.read(provider.notifier).toggle(_id(1), 'Первое');
    await tester.pump();
    await tester.pumpWidget(screen(false));
    final before = testSummary(index: 1, title: 'Первое');
    final after = testSummary(index: 1, title: 'Новое');
    final accepted =
        container
                .read(graphCommandCoordinatorProvider.notifier)
                .acceptExisting(
                  UpdateIntention(
                    id: _id(1),
                    title: 'Новое',
                    description: null,
                  ),
                  presentationTitle: 'Первое',
                )
            as IntentionCommandAccepted;
    repository.completeCommand(
      0,
      ResultSuccess(
        IntentionSaved(
          testIntention(index: 1, title: 'Новое'),
          catalogMutation: IntentionCatalogUpdated(
            revision: const TestCatalogRevision(1),
            before: TestCatalogEntrySnapshot(before),
            after: TestCatalogEntrySnapshot(after),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await accepted.future;
    });
    await tester.pumpWidget(screen(true));
    await tester.pump();
    expect(find.text('Новое'), findsOneWidget);
  });

  test('отметки упорядочены по последней установке и отделены по сессиям', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final model = h.model;
    model.toggle(_id(1), 'Одинаково');
    model.toggle(_id(2), 'Одинаково');
    model.toggle(_id(1), 'Одинаково');
    model.toggle(_id(1), 'Одинаково');

    expect(h.selected, [(_id(2), 'Одинаково'), (_id(1), 'Одинаково')]);
    final other = relationBatchViewModelProvider(
      IntentionSearchSession(),
      _id(9),
      IntentionRelationGroup.needs,
      'Страница',
    );
    final subscription = h.container.listen(other, (_, _) {});
    addTearDown(subscription.close);
    expect(h.container.read(other).selected, isEmpty);
  });

  test(
    'созданное намерение отмечается последним и факт создания сохраняется',
    () {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.toggle(_id(1), 'Первое');
      h.model.toggle(_id(2), 'Второе');

      h.model.acceptCreated(_id(3), 'Созданное', IntentionKind.main);
      expect(h.selected, [
        (_id(1), 'Первое'),
        (_id(2), 'Второе'),
        (_id(3), 'Созданное'),
      ]);
      expect(h.state.hasCreatedIntentions, isTrue);

      h.model.remove(_id(3));
      expect(h.state.hasCreatedIntentions, isTrue);
      expect(h.selected, [(_id(1), 'Первое'), (_id(2), 'Второе')]);
    },
  );

  test('подтверждённые переименования обновляют названия, а архив и удаление снимают отметки', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.toggle(_id(1), 'Первое');
    h.model.toggle(_id(2), 'Второе');
    h.model.toggle(_id(3), 'Третье');

    h.update(1, title: 'Переименовано');
    h.update(9, title: 'Новая страница');
    h.update(2, title: 'Второе', archived: true);
    h.delete(3);
    expect(h.selected, [(_id(1), 'Переименовано')]);
    expect(h.state.pageTitle, 'Новая страница');

    h.update(9, title: 'Новая страница', archived: true);
    h.delete(9);
    expect(h.state.pageTitle, 'Новая страница');
    expect(h.selected, [(_id(1), 'Переименовано')]);
  });

  test('прочие изменения и восстановление не возвращают снятую отметку', () {
    final h = _Harness();
    addTearDown(h.dispose);
    h.model.toggle(_id(1), 'Первое');
    h.update(1, title: 'Первое', archived: true);
    h.update(1, title: 'Первое');
    h.update(8, title: 'Другое');
    expect(h.selected, isEmpty);
    expect(h.state.pageTitle, 'Страница');
  });

  test('пакет согласует отметки отдельных исходящих и входящих поисков одним снимком', () {
    final h = _Harness();
    addTearDown(h.dispose);
    final incoming = relationBatchViewModelProvider(
      IntentionSearchSession(),
      _id(9),
      IntentionRelationGroup.neededFor,
      'Страница',
    );
    final other = relationBatchViewModelProvider(
      IntentionSearchSession(),
      _id(8),
      IntentionRelationGroup.needs,
      'Другая',
    );
    final incomingSubscription = h.container.listen(incoming, (_, _) {});
    final otherSubscription = h.container.listen(other, (_, _) {});
    addTearDown(incomingSubscription.close);
    addTearDown(otherSubscription.close);
    for (final id in [1, 2, 3]) {
      h.model.toggle(_id(id), 'Намерение $id');
      h.container.read(incoming.notifier).toggle(_id(id), 'Намерение $id');
      h.container.read(other.notifier).toggle(_id(id), 'Намерение $id');
    }
    final snapshots = <List<IntentionId>>[];
    final observer = h.container.listen(h.provider, (_, next) {
      snapshots.add(next.selected.map((item) => item.id).toList());
    });
    addTearDown(observer.close);

    h.changes.add(
      _Package([
        LongTermRelationCreatedChange(
          revision: const TestCatalogRevision(1),
          relation: testRelation(
            sourceIntentionId: _id(9),
            relatedIntentionId: _id(2),
            type: LongTermRelationType.can,
          ),
        ),
        LongTermRelationCreatedChange(
          revision: const TestCatalogRevision(1),
          relation: testRelation(
            sourceIntentionId: _id(3),
            relatedIntentionId: _id(9),
            index: 2,
          ),
        ),
      ]),
    );

    expect(h.selected, [(_id(1), 'Намерение 1'), (_id(3), 'Намерение 3')]);
    expect(h.container.read(incoming).selected.map((item) => item.id), [
      _id(1),
      _id(2),
    ]);
    expect(h.container.read(other).selected.map((item) => item.id), [
      _id(1),
      _id(2),
      _id(3),
    ]);
    expect(snapshots, [
      [_id(1), _id(3)],
    ]);
  });

  testWidgets(
    'занятая пара снимает отметку и освобождает право предъявления отказа',
    (tester) async {
      final h = _Harness();
      addTearDown(h.dispose);
      h.model.toggle(_id(1), 'Первое');
      h.model.submit();
      h.repository.completeRelationCommand(
        0,
        const GraphResultFailure(LongTermRelationUnexpectedFailure()),
      );
      await tester.pump();
      final failure = h.state.operation as RelationBatchFailed;
      final claim = failure.claim!;

      h.changes.add(
        _Package([
          LongTermRelationCreatedChange(
            revision: const TestCatalogRevision(1),
            relation: testRelation(
              sourceIntentionId: _id(9),
              relatedIntentionId: _id(1),
            ),
          ),
        ]),
      );

      expect(h.state.operation, isA<RelationBatchIdle>());
      expect(h.state.canEdit, isTrue);
      expect(h.selected, isEmpty);
      expect(
        h.container
            .read(graphCommandCoordinatorProvider.notifier)
            .claimInitiatorFailure(claim.token),
        isNull,
      );
    },
  );
}

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWithValue(repository),
        relationBatchChangesProvider.overrideWithValue(changes.stream),
      ],
    );
    subscription = container.listen(provider, (_, _) {});
  }
  final changes = StreamController<ConfirmedGraphChangePackage>.broadcast(
    sync: true,
  );
  final repository = ControlledCatalogRepository();
  final provider = relationBatchViewModelProvider(
    IntentionSearchSession(),
    _id(9),
    IntentionRelationGroup.needs,
    'Страница',
  );
  late final ProviderContainer container;
  late final ProviderSubscription<RelationBatchState> subscription;
  RelationBatchViewModel get model => container.read(provider.notifier);
  RelationBatchState get state => container.read(provider);
  List<(IntentionId, String)> get selected => [
    for (final item in state.selected) (item.id, item.title),
  ];

  void update(int index, {required String title, bool archived = false}) {
    final before = testSummary(index: index);
    final after = testSummary(
      index: index,
      title: title,
      archiveState: archived
          ? IntentionArchiveState.archived
          : IntentionArchiveState.active,
    );
    changes.add(
      _Package([
        IntentionCatalogUpdated(
          revision: const TestCatalogRevision(1),
          before: TestCatalogEntrySnapshot(before),
          after: TestCatalogEntrySnapshot(after),
        ),
      ]),
    );
  }

  void delete(int index) => changes.add(
    _Package([
      IntentionCatalogDeleted(
        revision: const TestCatalogRevision(1),
        entry: TestCatalogEntrySnapshot(testSummary(index: index)),
      ),
    ]),
  );
  void dispose() {
    subscription.close();
    container.dispose();
    unawaited(changes.close());
  }
}

final class _Package implements ConfirmedGraphChangePackage {
  _Package(this.changes);
  @override
  GraphRevision get revision => const TestCatalogRevision(1);
  @override
  final List<GraphChange> changes;
}

IntentionId _id(int index) => testSummary(index: index).id;
