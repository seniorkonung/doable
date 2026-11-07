import 'dart:async';

import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/data/local/app_database.dart'
    hide Intention, LongTermRelation;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

IntentionId _intention(int number) =>
    (IntentionId.decode(seedUuid(number)) as IntentionIdDecodingSuccess).id;
LongTermRelationId _relation(int number) => (LongTermRelationId.decode(
  seedUuid(number),
) as LongTermRelationIdDecodingSuccess).id;

ActionDraftIntention _draftIntention(int number, String title) =>
    ActionDraftIntention(id: _intention(number), title: title);

void main() {
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    database = AppDatabase(openInMemoryLocalDatabase(setup: (db) => raw = db));
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7, 12),
      InMemoryDiagnosticsSink(),
    );
    seedRawGraph(raw, () {
      for (var number = 1; number <= 3; number++) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      seedRelation(raw, seedUuid(101), seedUuid(1), seedUuid(2));
      seedRelation(raw, seedUuid(102), seedUuid(2), seedUuid(3));
    });
  });

  tearDown(() => database.close());

  Future<void> confirm(Object command) async {
    final result = await switch (command) {
      final IntentionCommand intention => repository.execute(intention),
      final LongTermRelationCommand relation => repository.execute(relation),
      _ => throw ArgumentError.value(command),
    };
    expect(result, isA<GraphCommandSucceeded>());
  }

  test('путь черновика без надгробий показывает удалённое намерение '
      'последним прочитанным названием, а удалённую связь — видом из '
      'черновика', () async {
    // Черновик знает прежнее название корня: чтение показывает текущее.
    final events = StreamIterator(
      repository.watchActionPathState(
        ActionDraftPath(
          root: _draftIntention(1, 'Старое название'),
          steps: [
            ActionDraftPathStep(
              relation: LongTermRelationType.need,
              intention: _draftIntention(2, 'Намерение 2'),
            ),
            ActionDraftPathStep(
              relation: LongTermRelationType.need,
              intention: _draftIntention(3, 'Намерение 3'),
            ),
          ],
        ),
      ),
    );
    addTearDown(events.cancel);
    Future<ActionSavedPath> next() async {
      expect(await events.moveNext(), isTrue);
      return (events.current as ActionPathStateReadSuccess).value.value;
    }

    expect((await next()).root.title, 'Намерение 1');

    await confirm(
      UpdateIntention(
        id: _intention(1),
        title: 'Быть здоровым',
        description: null,
      ),
    );
    expect((await next()).root.title, 'Быть здоровым');

    await confirm(DeleteLongTermRelation(_relation(101)));
    final withoutLink = await next();
    final link = withoutLink.steps.first.link;
    expect(link, isA<DeletedActionPathLink>());
    expect(link.type, LongTermRelationType.need);

    await confirm(ArchiveIntention(_intention(3)));
    final archived = await next();
    expect(
      (archived.steps.last.intention as ExistingActionPathIntention)
          .intention
          .archiveState,
      IntentionArchiveState.archived,
    );

    await confirm(DeleteIntention(_intention(1)));
    final withoutRoot = await next();
    expect(withoutRoot.root, isA<DeletedActionPathIntention>());
    expect(withoutRoot.root.title, 'Быть здоровым');
    expect(
      [for (final step in withoutRoot.steps) step.intention.id],
      [_intention(2), _intention(3)],
    );
  });
}
