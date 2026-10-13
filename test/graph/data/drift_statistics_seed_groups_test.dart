import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_command.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/data/contribution_reachability.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_command.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/contribution_reachability_reference.dart';
import '../../support/daily_choice_durability_fixture.dart';
import '../../support/local_database_harness.dart';

const _relations = [
  (101, 1, 2),
  (102, 2, 3),
  (103, 1, 4),
  (104, 1, 5),
  (105, 3, 4),
  (106, 1, 3),
  (107, 3, 2),
  (108, 2, 4),
];

void main() {
  late LocalDatabaseHarness harness;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;
  late _SeedProbe probe;

  setUp(() async {
    harness = LocalDatabaseHarness.inMemory();
    probe = _SeedProbe();
    database = await harness.openReadyDatabase(observer: probe);
    await seedDurabilityGraph(database);
    for (final (number, source, target) in _relations.skip(4)) {
      await database.customStatement(
        '''INSERT INTO long_term_relations
           (id, source_intention_id, related_intention_id, type, priority)
           VALUES (?, ?, ?, 'need', 2)''',
        [
          durabilityUuid(number),
          durabilityUuid(source),
          durabilityUuid(target),
        ],
      );
    }
    repository = durabilityRepository(database);
  });
  tearDown(() => harness.dispose());

  Future<void> addChoice(
    int number,
    String date, {
    bool completed = false,
    List<int> path = const [101, 102, 105],
  }) async {
    final selected = _relations.singleWhere((r) => r.$1 == path.last).$3;
    await database.customStatement(
      '''INSERT INTO daily_choices
         (id, source_intention_id, selected_intention_id, choice_date, is_completed)
         VALUES (?, ?, ?, ?, ?)''',
      [
        durabilityUuid(number),
        durabilityUuid(1),
        durabilityUuid(selected),
        date,
        completed ? 1 : 0,
      ],
    );
    for (var index = 0; index < path.length; index++) {
      await database.customStatement(
        '''INSERT INTO daily_choice_path_steps
           (id, daily_choice_id, long_term_relation_id, previous_step_id)
           VALUES (?, ?, ?, ?)''',
        [
          durabilityUuid(number * 10 + index),
          durabilityUuid(number),
          durabilityUuid(path[index]),
          index == 0 ? null : durabilityUuid(number * 10 + index - 1),
        ],
      );
    }
  }

  Future<StatisticsSeedGroupsSnapshot> read({StatisticsPeriod? period}) =>
      repository.readStatisticsSeedGroups(
        period: period ?? StatisticsMonth(2026, 10),
        localDate: CalendarDate.fromParts(2026, 10, 12),
      );

  test(
    'равные наборы объединяются независимо от порядка шагов и дубликатов',
    () async {
      final paths = [
        [101, 102, 105],
        [101, 102, 105],
        [106, 107, 108],
        [103],
      ];
      for (var i = 0; i < paths.length; i++) {
        await addChoice(
          201 + i,
          '2026-10-12',
          completed: i < 2,
          path: paths[i],
        );
      }
      final active = await read();
      expect(active.groups, hasLength(1));
      expect(active.groups.single.seeds, [durabilityIntention(4)]);
      expect(active.groups.single.counts.planned, 4);
      expect(active.groups.single.counts.contribution, 2);

      final archived = {101, 105, 106, 107};
      for (final number in archived) {
        expect(
          await repository.execute(
            ArchiveLongTermRelation(durabilityRelation(number)),
          ),
          isA<GraphCommandSucceeded>(),
        );
      }
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(1))),
        isA<GraphCommandSucceeded>(),
      );
      archived.addAll([103, 104]);
      final snapshot = await read();
      expect(snapshot.groups, hasLength(2));
      expect(
        {
          for (final group in snapshot.groups)
            group.seeds.map((id) => id.toCanonicalString()).join(','): (
              group.counts.planned,
              group.counts.contribution,
            ),
        },
        {
          [1, 3, 4].map(durabilityUuid).join(','): (3, 2),
          [1, 4].map(durabilityUuid).join(','): (1, 0),
        },
      );
      expect(snapshot.summary.counts.planned, 4);
      expect(snapshot.summary.counts.contribution, 2);
      final relations = [
        for (final (number, source, target) in _relations)
          (
            source: durabilityIntention(source),
            target: durabilityIntention(target),
            archived: archived.contains(number),
          ),
      ];
      final expected = referenceContributionCounts(
        relations: relations,
        choices: [
          for (var i = 0; i < paths.length; i++)
            (
              path: [
                for (final number in paths[i])
                  relations[_relations.indexWhere((r) => r.$1 == number)],
              ],
              completed: i < 2,
            ),
        ],
      );
      final actual = computeContributionReachability(
        await repository.loadStatisticsRelationSnapshot(),
        snapshot.groups,
      );
      expect({
        for (final row in actual)
          row.intentionId: (
            planned: row.counts.planned,
            contribution: row.counts.contribution,
          ),
      }, expected);
    },
  );

  test(
    'группы и сводка ограничены месяцем и годом, включая високосный день',
    () async {
      final dates = [
        '2023-12-31',
        '2024-01-01',
        '2024-01-31',
        '2024-02-01',
        '2024-02-29',
        '2024-03-01',
        '2024-12-31',
        '2025-01-01',
      ];
      for (var i = 0; i < dates.length; i++) {
        await addChoice(201 + i, dates[i], completed: i == 3);
      }
      final month = await repository.readStatisticsSeedGroups(
        period: StatisticsMonth(2024, 2),
        localDate: CalendarDate.fromParts(2024, 2, 29),
      );
      expect(month.groups.single.counts.planned, 2);
      expect(month.groups.single.counts.contribution, 1);
      expect(month.summary.counts.planned, 2);
      expect(month.summary.uncompleted.missed, 0);
      expect(month.summary.uncompleted.upcoming, 1);
      final year = await repository.readStatisticsSeedGroups(
        period: StatisticsYear(2024),
        localDate: CalendarDate.fromParts(2024, 2, 29),
      );
      expect(year.groups.single.counts.planned, 6);
      expect(year.groups.single.counts.contribution, 1);
      expect(year.summary.counts.planned, 6);
      expect(year.summary.uncompleted.missed, 2);
      expect(year.summary.uncompleted.upcoming, 3);
      final empty = await read();
      expect(empty.groups, isEmpty);
      expect(empty.summary.counts.planned, 0);
    },
  );

  test(
    'замена пути убирает прежние опорные намерения на новой ревизии',
    () async {
      expect(
        await repository.execute(durabilityCreate()),
        isA<GraphCommandSucceeded>(),
      );
      expect(
        await repository.execute(ArchiveIntention(durabilityIntention(2))),
        isA<GraphCommandSucceeded>(),
      );
      final before = await read(period: StatisticsMonth(2026, 9));
      expect(before.groups.single.seeds, [
        for (final n in [1, 2, 3]) durabilityIntention(n),
      ]);
      final result = await repository.execute(
        ReplaceDailyChoicePath(
          choiceId: durabilityChoice(201),
          sourceIntentionId: durabilityIntention(1),
          selectedIntentionId: durabilityIntention(4),
          path: durabilityPath([103]),
        ),
      );
      expect(result, isA<GraphCommandSucceeded>());
      final after = await read(period: StatisticsMonth(2026, 9));
      expect(after.groups.single.seeds, [durabilityIntention(4)]);
      expect(after.groups.single.counts.planned, 1);
      expect(after.groups.single.counts.contribution, 1);
      expect(
        after.revision.compareTo(before.revision),
        GraphRevisionOrder.newer,
      );
      expect(
        after.revision.compareTo(
          (result as GraphCommandSucceeded).value.revision,
        ),
        GraphRevisionOrder.same,
      );
    },
  );

  test('команда между запросами не смешивает сводку и веса групп', () async {
    await addChoice(201, '2026-10-12');
    probe.entered = Completer<void>();
    probe.release = Completer<void>();
    final reading = read();
    await probe.entered!.future;
    final command = repository.execute(
      UpdateDailyChoiceFields(
        choiceId: durabilityChoice(201),
        patch: const DailyChoiceFieldsPatch(
          isCompleted: DailyChoiceFieldSet(true),
        ),
      ),
    );
    probe.release!.complete();
    final before = await reading;
    expect(await command, isA<GraphCommandSucceeded>());
    final after = await read();
    expect(before.summary.counts.contribution, 0);
    expect(before.groups.single.counts.contribution, 0);
    expect(after.summary.counts.contribution, 1);
    expect(after.groups.single.counts.contribution, 1);
    expect(after.revision.compareTo(before.revision), GraphRevisionOrder.newer);
  });

  for (final (name, error, failure) in <(String, Object, Matcher)>[
    (
      'недоступность',
      sqlite.SqliteException(message: 'Недоступно', extendedResultCode: 5),
      isA<StatisticsReadUnavailableFailure>(),
    ),
    (
      'повреждение',
      sqlite.SqliteException(message: 'Повреждение', extendedResultCode: 11),
      isA<StatisticsReadCorruptionFailure>(),
    ),
    (
      'неизвестный отказ',
      StateError('Неизвестный отказ'),
      isA<StatisticsReadUnexpectedFailure>(),
    ),
  ]) {
    test('отказ подготовки групп отклоняет всю выдачу: $name', () async {
      await addChoice(201, '2026-10-12');
      probe.failure = error;
      await expectLater(read(), throwsA(failure));
    });
  }

  test('некорректная календарная дата даёт отказ всего чтения', () async {
    await addChoice(201, '2026-02-30');
    await expectLater(
      read(period: StatisticsYear(2026)),
      throwsA(isA<StatisticsReadCorruptionFailure>()),
    );
  });

  for (final (field, value) in <(String, Object)>[
    ('seed_key', 'не идентификатор'),
    ('planned', -1),
    ('contribution', 2),
  ]) {
    test(
      'декодирование опорных групп отклоняет повреждённое поле $field',
      () async {
        await addChoice(201, '2026-10-12', completed: true);
        probe.replaceField = field;
        probe.replacement = value;
        await expectLater(
          read(),
          throwsA(isA<StatisticsReadCorruptionFailure>()),
        );
      },
    );
  }
}

final class _SeedProbe extends LocalDatabaseConnectionObserver {
  Object? failure;
  String? replaceField;
  Object? replacement;
  Completer<void>? entered;
  Completer<void>? release;

  @override
  Future<void> beforeStatement(LocalDatabaseSqlStatement statement) async {
    if (statement.operation != LocalDatabaseSqlOperation.select ||
        !statement.statements.single.contains('seed_key')) {
      return;
    }
    if (failure case final error?) throw error;
    if (entered case final gate? when !gate.isCompleted) {
      gate.complete();
      await release!.future;
    }
  }

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    final field = replaceField;
    if (field == null || rows.isEmpty || !rows.first.containsKey('seed_key')) {
      return rows;
    }
    return [
      {...rows.first, field: replacement},
      ...rows.skip(1),
    ];
  }
}
