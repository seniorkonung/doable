import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/domain/action_id.dart';
import 'package:doable/src/action/domain/action_priority.dart';
import 'package:doable/src/action/domain/action_schedule.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:doable/src/data/local/app_database.dart' hide Action;
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';
import '../../support/local_database_harness.dart';

ActionId _action(int number) =>
    (ActionId.decode(seedUuid(number)) as ActionIdDecodingSuccess).id;
IntentionId _intention(int number) =>
    (IntentionId.decode(seedUuid(number)) as IntentionIdDecodingSuccess).id;

DriftPersonalGraphRepository _repository(AppDatabase database) =>
    DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7, 12),
      InMemoryDiagnosticsSink(),
    );

Future<ActionDetails> _read(AppDatabase database) async =>
    ((await _repository(database).watchAction(_action(11)).first)
            as ActionReadSuccess)
        .value
        .value!;

void main() {
  test('после повторного открытия хранилища действие доступно с тем же '
      'идентификатором, подтверждёнными полями и путём', () async {
    final harness = await LocalDatabaseHarness.fileBacked();
    addTearDown(harness.dispose);
    var database = await harness.openReadyDatabase();
    await seedGraph(database, () async {
      for (var number = 1; number <= 3; number++) {
        await database.customStatement(
          'INSERT INTO intentions (id, title, created_at, updated_at) '
          'VALUES (?, ?, 1, 1)',
          [seedUuid(number), 'Намерение $number'],
        );
      }
      for (final (number, source, related) in [(101, 1, 2), (102, 2, 3)]) {
        await database.customStatement(
          '''INSERT INTO long_term_relations
             (id, source_intention_id, related_intention_id, type, priority,
              created_at, updated_at)
             VALUES (?, ?, ?, 'need', 1, 1, 1)''',
          [seedUuid(number), seedUuid(source), seedUuid(related)],
        );
      }
      await database.customStatement(
        '''INSERT INTO actions
           (id, title, description, date, scheduled_hour, priority,
            is_completed, created_at, updated_at)
           VALUES (?, 'Пробежка', NULL, '2026-10-08', NULL, 4, 0, 1, 1)''',
        [seedUuid(11)],
      );
      for (final (position, intention) in [1, 2, 3].indexed) {
        await database.customStatement(
          '''INSERT INTO action_path_items
             (action_id, position, intention_id, previous_intention_id)
             VALUES (?, ?, ?, ?)''',
          [
            seedUuid(11),
            position,
            seedUuid(intention),
            position == 0 ? null : seedUuid(intention - 1),
          ],
        );
      }
    });
    expect(
      await _repository(database).execute(
        UpdateActionFields(
          actionId: _action(11),
          patch: ActionFieldsPatch(
            title: ActionFieldSet(ActionTitle('Длинная пробежка')),
            description: ActionFieldSet(ActionDescription.fromInput('Утром')),
            date: ActionFieldSet(CalendarDate.fromParts(2026, 10, 12)),
            schedule: ActionFieldSet(ActionAtHour(7)),
            priority: const ActionFieldSet(ActionPriority.p1),
            isCompleted: const ActionFieldSet(true),
          ),
        ),
      ),
      isA<GraphCommandSucceeded>(),
    );
    final confirmed = await _read(database);
    await harness.closePersistenceObjectGraph();

    database = await harness.openReadyDatabase();
    final reopened = await _read(database);

    final action = reopened.action;
    expect(action.id, _action(11));
    expect(action.title, ActionTitle('Длинная пробежка'));
    expect(action.description, ActionDescription.fromInput('Утром'));
    expect(action.date, CalendarDate.fromParts(2026, 10, 12));
    expect(action.schedule, ActionAtHour(7));
    expect(action.priority, ActionPriority.p1);
    expect(action.isCompleted, isTrue);
    expect(action.creationSequence, confirmed.action.creationSequence);
    expect(action.createdAt, confirmed.action.createdAt);
    expect(action.updatedAt, confirmed.action.updatedAt);
    expect(
      [
        reopened.path.root.id,
        for (final step in reopened.path.steps) step.intention.id,
      ],
      [_intention(1), _intention(2), _intention(3)],
    );
    expect(
      reopened.path.steps.map((step) => step.link),
      everyElement(isA<ExistingActionPathLink>()),
    );
  });
}
