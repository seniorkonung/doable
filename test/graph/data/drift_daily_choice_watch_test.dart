import 'dart:async';

import 'package:doable/src/daily_choice/application/confirmed_choice_path.dart';
import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_diagnostics_sink.dart';

String _uuid(int number) =>
    '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}';
IntentionId _intention(int number) =>
    (IntentionId.decode(_uuid(number)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  _uuid(number),
) as LongTermRelationIdDecodingSuccess).id;
DailyChoiceId _choice(int number) =>
    (DailyChoiceId.decode(_uuid(number)) as DailyChoiceIdDecodingSuccess).id;

final class _FixedChoiceIdGenerator implements DailyChoiceIdGenerator {
  @override
  DailyChoiceId generate() => _choice(201);
}

final class _ChoiceReadObserver extends LocalDatabaseConnectionObserver {
  int pathReads = 0;
  void Function()? onPathRead;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (statement.operation == LocalDatabaseSqlOperation.select &&
        statement.statements.single.contains(
          'FROM daily_choice_path_steps WHERE daily_choice_id',
        )) {
      pathReads++;
      onPathRead?.call();
    }
  }
}

GraphSnapshot<DailyChoiceDetails?> _snapshot(DailyChoiceReadResult result) =>
    (result as DailyChoiceReadSuccess).value;

void main() {
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _ChoiceReadObserver readObserver;

  setUp(() async {
    readObserver = _ChoiceReadObserver();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        readObserver,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 9, 23),
      InMemoryDiagnosticsSink(),
      dailyChoiceIdGenerator: _FixedChoiceIdGenerator(),
    );
    for (var number = 1; number <= 4; number++) {
      await database.customStatement(
        '''INSERT INTO intentions
           (id, title, is_action_ready, is_archived, created_at, updated_at)
           VALUES (?, ?, ?, 0, 1, 1)''',
        [_uuid(number), 'Намерение $number', number >= 3 ? 1 : 0],
      );
    }
    for (final (number, source, target) in [
      (101, 1, 2),
      (102, 2, 3),
      (103, 1, 4),
    ]) {
      await database.customStatement(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id,
            type, priority, is_archived)
           VALUES (?, ?, ?, 'need', 2, 0)''',
        [_uuid(number), _uuid(source), _uuid(target)],
      );
    }
  });
  tearDown(() => database.close());

  ConfirmedChoicePath path(List<(int, int, int)> links) => ConfirmedChoicePath([
    for (final (relation, source, target) in links)
      ConfirmedChoicePathStep(
        relationId: _relation(relation),
        sourceIntentionId: _intention(source),
        type: LongTermRelationType.need,
        relatedIntentionId: _intention(target),
      ),
  ]);

  Future<void> create() async {
    final result = await repository.execute(
      CreateDailyChoice(
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(3),
        path: path([(101, 1, 2), (102, 2, 3)]),
        date: CalendarDate.fromParts(2026, 9, 23),
        description: null,
        isCompleted: false,
      ),
    );
    expect(result, isA<GraphCommandSucceeded>());
  }

  test('наблюдает создание, поля и удаление выбора одной ревизией', () async {
    final events = StreamIterator(repository.watchDailyChoice(_choice(201)));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    final absent = _snapshot(events.current);
    expect(absent.value, isNull);

    await create();
    expect(await events.moveNext(), isTrue);
    final created = _snapshot(events.current);
    expect(created.value!.path, hasLength(2));
    expect(
      created.revision.compareTo(absent.revision),
      GraphRevisionOrder.newer,
    );

    expect(
      await repository.execute(
        UpdateDailyChoiceFields(
          choiceId: _choice(201),
          patch: const DailyChoiceFieldsPatch(
            isCompleted: DailyChoiceFieldSet(true),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    expect(await events.moveNext(), isTrue);
    final updated = _snapshot(events.current);
    expect(updated.value!.choice.isCompleted, isTrue);
    expect(
      updated.revision.compareTo(created.revision),
      GraphRevisionOrder.newer,
    );

    expect(
      await repository.execute(DeleteDailyChoice(_choice(201))),
      isA<GraphCommandSucceeded>(),
    );
    expect(await events.moveNext(), isTrue);
    final deleted = _snapshot(events.current);
    expect(deleted.value, isNull);
    expect(
      deleted.revision.compareTo(updated.revision),
      GraphRevisionOrder.newer,
    );
  });

  test('меняет зависимости наблюдаемого пути вместе со снимком', () async {
    await create();
    final events = <GraphSnapshot<DailyChoiceDetails?>>[];
    final subscription = repository
        .watchDailyChoice(_choice(201))
        .listen((result) => events.add(_snapshot(result)));
    Future<void> waitFor(int count) async {
      for (var attempt = 0; attempt < 100 && events.length < count; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(events, hasLength(count));
    }

    await waitFor(1);
    await repository.execute(
      UpdateIntention(
        id: _intention(2),
        title: 'Переименованное промежуточное',
        description: null,
      ),
    );
    await waitFor(2);
    expect(
      events.last.value!.path.first.related.title,
      'Переименованное промежуточное',
    );

    await repository.execute(ArchiveLongTermRelation(_relation(102)));
    await waitFor(3);
    expect(events.last.value!.path.last.relation.scope, RelationScope.archived);

    await repository.execute(
      ReplaceDailyChoicePath(
        choiceId: _choice(201),
        sourceIntentionId: _intention(1),
        selectedIntentionId: _intention(4),
        path: path([(103, 1, 4)]),
      ),
    );
    await waitFor(4);
    expect(events.last.value!.path.single.relation.id, _relation(103));

    await repository.execute(
      UpdateIntention(
        id: _intention(2),
        title: 'Старый участник изменён снова',
        description: null,
      ),
    );
    await pumpEventQueue();
    expect(events, hasLength(4));

    await repository.execute(ArchiveLongTermRelation(_relation(103)));
    await waitFor(5);
    expect(
      events.last.value!.path.single.relation.scope,
      RelationScope.archived,
    );
    await subscription.cancel().timeout(const Duration(seconds: 2));
  });

  test(
    'согласует счётчики прежнего и нового действия при замене пути',
    () async {
      final oldAction = StreamIterator(
        repository.watchIntention(_intention(3)),
      );
      final newAction = StreamIterator(
        repository.watchIntention(_intention(4)),
      );
      addTearDown(oldAction.cancel);
      addTearDown(newAction.cancel);
      expect(await oldAction.moveNext(), isTrue);
      expect(await newAction.moveNext(), isTrue);

      GraphSnapshot<IntentionDetails?> snapshot(
        Result<GraphSnapshot<IntentionDetails?>> result,
      ) => (result as ResultSuccess<GraphSnapshot<IntentionDetails?>>).value;

      final beforeOld = snapshot(oldAction.current);
      final beforeNew = snapshot(newAction.current);
      expect(beforeOld.value!.relationCounts.dailySelected, 0);
      expect(beforeNew.value!.relationCounts.dailySelected, 0);

      await create();
      expect(await oldAction.moveNext(), isTrue);
      final occupied = snapshot(oldAction.current);
      expect(occupied.value!.relationCounts.dailySelected, 1);
      expect(
        occupied.revision.compareTo(beforeOld.revision),
        GraphRevisionOrder.newer,
      );

      await repository.execute(
        ReplaceDailyChoicePath(
          choiceId: _choice(201),
          sourceIntentionId: _intention(1),
          selectedIntentionId: _intention(4),
          path: path([(103, 1, 4)]),
        ),
      );
      expect(await oldAction.moveNext(), isTrue);
      expect(await newAction.moveNext(), isTrue);
      final released = snapshot(oldAction.current);
      final selected = snapshot(newAction.current);
      expect(released.value!.relationCounts.dailySelected, 0);
      expect(selected.value!.relationCounts.dailySelected, 1);
      expect(
        released.revision.compareTo(selected.revision),
        GraphRevisionOrder.same,
      );
    },
  );

  test('посторонняя правка не перечитывает путь открытого выбора', () async {
    await create();
    final events = StreamIterator(repository.watchDailyChoice(_choice(201)));
    addTearDown(events.cancel);
    expect(await events.moveNext(), isTrue);
    final readsBefore = readObserver.pathReads;

    await repository.execute(
      UpdateIntention(
        id: _intention(4),
        title: 'Постороннее действие',
        description: null,
      ),
    );
    await pumpEventQueue();
    expect(readObserver.pathReads, readsBefore);

    await repository.execute(
      UpdateIntention(
        id: _intention(2),
        title: 'Участник пути',
        description: null,
      ),
    );
    expect(await events.moveNext(), isTrue);
    expect(readObserver.pathReads, greaterThan(readsBefore));
  });

  test('поздний снимок помечен прежней ревизией перед удалением', () async {
    await create();
    final queued = Completer<void>();
    late Future<Object> deletion;
    readObserver.onPathRead = () {
      readObserver.onPathRead = null;
      deletion = Zone.root.run(
        () => repository.execute(DeleteDailyChoice(_choice(201))),
      );
      queued.complete();
    };

    final events = StreamIterator(repository.watchDailyChoice(_choice(201)));
    addTearDown(events.cancel);
    final pendingRead = events.moveNext();
    await queued.future;
    final deleted = await deletion;
    expect(deleted, isA<GraphCommandSucceeded>());
    expect(await pendingRead, isTrue);
    final confirmedRevision = (deleted as GraphCommandSucceeded).value.revision;
    var snapshot = _snapshot(events.current);
    if (snapshot.value != null) {
      expect(
        snapshot.revision.compareTo(confirmedRevision),
        GraphRevisionOrder.older,
      );
      expect(await events.moveNext(), isTrue);
      snapshot = _snapshot(events.current);
    }
    expect(snapshot.value, isNull);
    expect(
      snapshot.revision.compareTo(confirmedRevision),
      GraphRevisionOrder.same,
    );
  });
}
