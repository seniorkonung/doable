import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/delete_blocking_relations.dart';
import 'package:doable/src/graph/application/blocking_relation_reference.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/daily_choice_durability_fixture.dart';

void main() {
  late AppDatabase database;
  late _SqlGate gate;
  late DriftPersonalGraphRepository repository;

  setUp(() async {
    gate = _SqlGate();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(),
        gate,
      ),
    );
    await database.open();
    await seedDurabilityGraph(database);
    repository = durabilityRepository(
      database,
      choiceNumber: 202,
      firstStepNumber: 401,
    );
  });

  tearDown(() async {
    gate.release();
    await database.close();
  });

  Future<(Object, Object)> overlap(
    Future<Object> Function() first,
    Future<Object> Function() second,
  ) async {
    gate.arm();
    final firstResult = first();
    await gate.entered;
    final secondResult = second();
    gate.release();
    return (await firstResult, await secondResult);
  }

  Future<Object> mutate(_Interference interference) => switch (interference) {
    _Interference.type => repository.execute(
      UpdateLongTermRelation(
        relationId: durabilityRelation(103),
        patch: const LongTermRelationPatch(
          type: LongTermRelationFieldSet(LongTermRelationType.can),
          priority: LongTermRelationFieldSet(RelationPriority.p4),
        ),
      ),
    ),
    _Interference.participant => repository.execute(
      UpdateLongTermRelation(
        relationId: durabilityRelation(103),
        patch: LongTermRelationPatch(
          sourceIntentionId: LongTermRelationFieldSet(durabilityIntention(5)),
          priority: const LongTermRelationFieldSet(RelationPriority.p4),
        ),
      ),
    ),
    _Interference.delete => repository.execute(
      DeleteLongTermRelation(durabilityRelation(103)),
    ),
    _Interference.archive => repository.execute(
      ArchiveLongTermRelation(durabilityRelation(103)),
    ),
    _Interference.readiness => repository.execute(
      DisableIntentionReadiness(durabilityIntention(4)),
    ),
  };

  for (final replacing in [false, true]) {
    for (final interference in _Interference.values) {
      for (final dailyFirst in [false, true]) {
        test(
          '${replacing ? 'Замена' : 'Создание'} и ${interference.label}: '
          '${dailyFirst ? 'путь первым' : 'изменение графа первым'}',
          () async {
            if (replacing) {
              expect(
                await durabilityRepository(database)
                    .execute(durabilityCreate()),
                isA<GraphCommandSucceeded>(),
              );
            }
            final relationBefore = (await durabilityRows(
              database,
              'long_term_relations',
            )).singleWhere((row) => row['id'] == durabilityUuid(103));
            final choicesBefore = await durabilityRows(
              database,
              'daily_choices',
            );
            final stepsBefore = await durabilityRows(
              database,
              'daily_choice_path_steps',
            );
            Future<Object> daily() => repository.execute(
              replacing
                  ? durabilityReplace(201)
                  : durabilityCreate(path: [103]),
            );
            final (first, second) = dailyFirst
                ? await overlap(daily, () => mutate(interference))
                : await overlap(() => mutate(interference), daily);
            final choice = await repository.getDailyChoice(
              durabilityChoice(replacing ? 201 : 202),
            );
            expect(choice, isA<DailyChoiceReadSuccess>());
            final snapshot = (choice as DailyChoiceReadSuccess).value;

            if (dailyFirst) {
              expect(first, isA<GraphCommandSucceeded>());
              expect(snapshot.value!.path.map((step) => step.relation.id), [
                durabilityRelation(103),
              ]);
              if (interference.isAllowedAfterSave) {
                expect(second, isA<GraphCommandSucceeded>());
                expect(
                  snapshot.revision.compareTo(
                    (first as GraphCommandSucceeded).value.revision,
                  ),
                  GraphRevisionOrder.newer,
                );
              } else {
                expect(
                  (second as GraphCommandFailed).failure.category,
                  GraphFailureCategory.conflict,
                );
                expect(
                  snapshot.revision.compareTo(
                    (first as GraphCommandSucceeded).value.revision,
                  ),
                  GraphRevisionOrder.same,
                );
                final relation = (await durabilityRows(
                  database,
                  'long_term_relations',
                )).singleWhere((row) => row['id'] == durabilityUuid(103));
                expect(relation, relationBefore);
              }
            } else {
              expect(first, isA<GraphCommandSucceeded>());
              expect(
                (second as GraphCommandFailed).failure.category,
                GraphFailureCategory.conflict,
              );
              expect(
                snapshot.value?.path.map((step) => step.relation.id),
                replacing
                    ? [durabilityRelation(101), durabilityRelation(102)]
                    : null,
              );
              expect(
                snapshot.revision.compareTo(
                  (first as GraphCommandSucceeded).value.revision,
                ),
                GraphRevisionOrder.same,
              );
              expect(
                await durabilityRows(database, 'daily_choices'),
                choicesBefore,
              );
              expect(
                await durabilityRows(database, 'daily_choice_path_steps'),
                stepsBefore,
              );
            }
          },
        );
      }
    }
  }

  for (final replacing in [false, true]) {
    for (final dailyFirst in [false, true]) {
      test('${replacing ? 'замена' : 'создание'} пути и массовое удаление: '
          '${dailyFirst ? 'путь первым' : 'удаление первым'}', () async {
        if (replacing) {
          expect(
            await durabilityRepository(database).execute(durabilityCreate()),
            isA<GraphCommandSucceeded>(),
          );
        }
        final used = replacing ? 103 : 101;
        final other = replacing ? 104 : 103;
        Future<Object> save() => repository.execute(
          replacing ? durabilityReplace(201) : durabilityCreate(),
        );
        Future<Object> delete() => repository.execute(
          DeleteBlockingRelations.longTerm(
            intentionId: durabilityIntention(1),
            relationIds: [durabilityRelation(used), durabilityRelation(other)],
          ),
        );
        final (first, second) = dailyFirst
            ? await overlap(save, delete)
            : await overlap(delete, save);
        expect(first, isA<GraphCommandSucceeded>());
        expect(
          (second as GraphCommandFailed).failure.category,
          GraphFailureCategory.conflict,
        );
        final saved = await repository.getDailyChoice(
          durabilityChoice(replacing ? 201 : 202),
        );
        expect(saved, isA<DailyChoiceReadSuccess>());
        expect(
          (saved as DailyChoiceReadSuccess).value.value?.path.map(
            (step) => step.relation.id,
          ),
          dailyFirst
              ? (replacing
                    ? [durabilityRelation(103)]
                    : [durabilityRelation(101), durabilityRelation(102)])
              : (replacing
                    ? [durabilityRelation(101), durabilityRelation(102)]
                    : null),
        );
        final relations = await durabilityRows(database, 'long_term_relations');
        for (final number in [used, other]) {
          expect(
            relations.any((row) => row['id'] == durabilityUuid(number)),
            dailyFirst,
          );
        }
        expect(
          saved.value.revision.compareTo(
            (first as GraphCommandSucceeded).value.revision,
          ),
          GraphRevisionOrder.same,
        );
      });
    }
  }

  for (final dailyFirst in [false, true]) {
    test('замена и устаревшее смешанное подтверждение: '
        '${dailyFirst ? 'замена первой' : 'удаление первым'}', () async {
      expect(
        await durabilityRepository(database).execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      Future<Object> replace() => repository.execute(durabilityReplace(201));
      Future<Object> delete() => repository.execute(
        DeleteBlockingRelations(
          intentionId: durabilityIntention(1),
          references: [
            DailyChoiceBlockingRelationReference(durabilityChoice(201)),
            LongTermBlockingRelationReference(durabilityRelation(103)),
          ],
        ),
      );
      final (first, second) = dailyFirst
          ? await overlap(replace, delete)
          : await overlap(delete, replace);
      expect(first, isA<GraphCommandSucceeded>());
      expect(
        (second as GraphCommandFailed).failure.category,
        dailyFirst
            ? GraphFailureCategory.conflict
            : GraphFailureCategory.notFound,
      );
      final saved = await repository.getDailyChoice(durabilityChoice(201));
      expect(saved, isA<DailyChoiceReadSuccess>());
      expect(
        (saved as DailyChoiceReadSuccess).value.value?.path.map(
          (step) => step.relation.id,
        ),
        dailyFirst ? [durabilityRelation(103)] : null,
      );
      expect(
        saved.value.revision.compareTo(
          (first as GraphCommandSucceeded).value.revision,
        ),
        GraphRevisionOrder.same,
      );
    });
  }

  test(
    'непоследняя ссылка сохраняет блокировку, последняя снимает её',
    () async {
      expect(
        await durabilityRepository(database).execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      final (first, second) = await overlap(
        () => repository.execute(DeleteDailyChoice(durabilityChoice(201))),
        () =>
            repository.execute(DeleteLongTermRelation(durabilityRelation(101))),
      );
      expect(first, isA<GraphCommandSucceeded>());
      expect(
        (second as GraphCommandFailed).failure.category,
        GraphFailureCategory.conflict,
      );
      final (last, released) = await overlap(
        () => repository.execute(DeleteDailyChoice(durabilityChoice(202))),
        () =>
            repository.execute(DeleteLongTermRelation(durabilityRelation(101))),
      );
      expect(last, isA<GraphCommandSucceeded>());
      expect(released, isA<GraphCommandSucceeded>());
      expect(
        (await durabilityRows(
          database,
          'long_term_relations',
        )).any((row) => row['id'] == durabilityUuid(101)),
        isFalse,
      );
    },
  );
}

enum _Interference {
  type('смена типа', false),
  participant('смена участника', false),
  delete('удаление связи', false),
  archive('архивирование связи', true),
  readiness('выключение готовности', true);

  const _Interference(this.label, this.isAllowedAfterSave);
  final String label;
  final bool isAllowedAfterSave;
}

final class _SqlGate extends LocalDatabaseConnectionObserver {
  Completer<void> _entered = Completer<void>();
  Completer<void> _released = Completer<void>();
  bool _armed = false;

  Future<void> get entered => _entered.future;

  void arm() {
    _entered = Completer<void>();
    _released = Completer<void>();
    _armed = true;
  }

  void release() {
    if (!_released.isCompleted) _released.complete();
  }

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (!_armed || statement.operation != LocalDatabaseSqlOperation.select) {
      return;
    }
    _armed = false;
    _entered.complete();
    await _released.future;
  }
}
