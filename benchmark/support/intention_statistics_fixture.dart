import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'contribution_statistics_fixture.dart';

typedef FixtureCounts = ({int planned, int contribution});
typedef FixtureBreakdownRow = ({String id, int planned, int contribution});

enum IntentionStatisticsProfile { shortPaths, longPaths, manyBreakdowns }

final class IntentionStatisticsFixture {
  IntentionStatisticsFixture(this.profile);

  final IntentionStatisticsProfile profile;
  ContributionStatisticsFixture? _base;
  static const target = 10001;

  void populate(sqlite.Database database) {
    if (profile != IntentionStatisticsProfile.manyBreakdowns) {
      _base = ContributionStatisticsFixture(
        profile == IntentionStatisticsProfile.shortPaths
            ? ContributionStatisticsProfile.shortPaths
            : ContributionStatisticsProfile.longPaths,
      )..populate(database);
      return;
    }
    final intention = database.prepare('''INSERT INTO intentions
      (id, title, is_action_ready, created_at, updated_at)
      VALUES (?, ?, 1, 0, 0)''');
    final relation = database.prepare('''INSERT INTO long_term_relations
      (id, source_intention_id, related_intention_id, type, priority)
      VALUES (?, ?, ?, 'need', 2)''');
    final choice = database.prepare('''INSERT INTO daily_choices
      (id, source_intention_id, selected_intention_id, choice_date, is_completed)
      VALUES (?, ?, ?, ?, ?)''');
    final step = database.prepare('''INSERT INTO daily_choice_path_steps
      (id, daily_choice_id, long_term_relation_id, previous_step_id)
      VALUES (?, ?, ?, ?)''');
    database.execute('BEGIN');
    try {
      for (var node = 1; node <= 50000; node++) {
        intention.execute([
          ContributionStatisticsFixture.id(node),
          'Намерение $node',
        ]);
      }
      for (var number = 0; number < 150000; number++) {
        final band = number ~/ 50000;
        final source = number % 50000 + 1;
        final (from, to) = switch (number) {
          >= 50000 && < 50500 => (20001 + number - 50000, target),
          >= 50500 && < 51000 => (target, 30001 + number - 50500),
          999 => (1000, 1),
          _ => (source, (source + band) % 50000 + 1),
        };
        relation.execute([
          ContributionStatisticsFixture.id(100000 + number),
          ContributionStatisticsFixture.id(from),
          ContributionStatisticsFixture.id(to),
        ]);
      }
      var choiceNumber = 0, stepNumber = 0;
      for (
        var day = DateTime.utc(2025);
        day.year <= 2027;
        day = day.add(const Duration(days: 1))
      ) {
        final date = CalendarDate.fromParts(
          day.year,
          day.month,
          day.day,
        ).toCanonicalString();
        for (var slot = 0; slot < 100; slot++) {
          final index = (choiceNumber ~/ 6) % 500;
          final incoming = 50000 + index;
          final outgoing = 50500 + index;
          final relations = switch ((choiceNumber ~/ 2) % 3) {
            0 => [incoming, outgoing],
            1 => [outgoing],
            _ => [incoming],
          };
          final source = relations.first == incoming ? 20001 + index : target;
          final selected = relations.last == outgoing ? 30001 + index : target;
          final choiceId = ContributionStatisticsFixture.id(
            300000 + choiceNumber,
          );
          choice.execute([
            choiceId,
            ContributionStatisticsFixture.id(source),
            ContributionStatisticsFixture.id(selected),
            date,
            slot < 50 ? 1 : 0,
          ]);
          String? previous;
          for (final link in relations) {
            final stepId = ContributionStatisticsFixture.id(
              1000000 + stepNumber++,
            );
            step.execute([
              stepId,
              choiceId,
              ContributionStatisticsFixture.id(100000 + link),
              previous,
            ]);
            previous = stepId;
          }
          choiceNumber++;
        }
      }
      database.execute(
        '''UPDATE long_term_relations SET is_archived = 1
        WHERE source_intention_id >= ? OR related_intention_id >= ?''',
        [
          ContributionStatisticsFixture.id(45001),
          ContributionStatisticsFixture.id(45001),
        ],
      );
      database.execute('UPDATE intentions SET is_archived = 1 WHERE id >= ?', [
        ContributionStatisticsFixture.id(45001),
      ]);
      database.execute('COMMIT');
    } on Object {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      intention.close();
      relation.close();
      choice.close();
      step.close();
    }
  }

  void archivePathParts(sqlite.Database database) {
    if (_base case final base?) {
      base.archivePathParts(database);
    } else {
      database.execute('''UPDATE long_term_relations SET is_archived = 1
        WHERE creation_sequence BETWEEN 50501 AND 51000
          AND creation_sequence % 10 = 0''');
    }
  }

  int get intention => switch (profile) {
    IntentionStatisticsProfile.shortPaths => 10,
    IntentionStatisticsProfile.longPaths => 16,
    IntentionStatisticsProfile.manyBreakdowns => target,
  };

  /// Эталон читает сохранённые шаги и обходит исходный граф, минуя X.
  /// Он не использует опорные группы и сжатие компонент производственного кода.
  IntentionFixtureReference reference(
    sqlite.Database database,
    StatisticsPeriod period,
  ) => IntentionFixtureReference._(database, period, intention);
}

final class IntentionFixtureReference {
  IntentionFixtureReference._(
    sqlite.Database database,
    StatisticsPeriod period,
    int target,
  ) : _period = period,
      _target = target {
    _load(database);
  }

  final StatisticsPeriod _period;
  final int _target;
  final _choices = <_SavedChoice>[];
  final _relations = <String, _SavedRelation>{};
  final _children = <int, List<int>>{};
  final _parents = <int, List<int>>{};
  final _outgoing = <_SavedRelation>[];
  final _reachability = <String, _Attribution>{};
  late final Set<int> _reachableFromTarget;

  static int _number(Object? value) =>
      int.parse((value as String).substring(24), radix: 16);

  void _load(sqlite.Database database) {
    for (final row in database.select('''SELECT id, source_intention_id,
        related_intention_id, is_archived FROM long_term_relations''')) {
      final relation = _SavedRelation(
        row['id'] as String,
        _number(row['source_intention_id']),
        _number(row['related_intention_id']),
        row['is_archived'] == 1,
      );
      _relations[relation.id] = relation;
      if (!relation.archived) {
        (_children[relation.source] ??= []).add(relation.target);
        (_parents[relation.target] ??= []).add(relation.source);
        if (relation.source == _target) _outgoing.add(relation);
      }
    }
    _reachableFromTarget = _walk(_children, [_target]);
    _SavedChoice? current;
    for (final row in database.select(
      '''SELECT c.id, c.choice_date,
        c.source_intention_id, c.selected_intention_id, c.is_completed,
        s.long_term_relation_id
        FROM daily_choices c JOIN daily_choice_path_steps s
          ON s.daily_choice_id = c.id
        WHERE c.choice_date BETWEEN ? AND ?
        ORDER BY c.id, s.id''',
      [
        _period.firstDate.toCanonicalString(),
        _period.lastDate.toCanonicalString(),
      ],
    )) {
      final id = row['id'] as String;
      if (current?.id != id) {
        current = _SavedChoice(
          id,
          row['choice_date'] as String,
          _number(row['source_intention_id']),
          _number(row['selected_intention_id']),
          row['is_completed'] == 1,
        );
        _choices.add(current);
      }
      current!.relations.add(_relations[row['long_term_relation_id']]!);
    }
  }

  Set<int> _walk(
    Map<int, List<int>> adjacency,
    Iterable<int> starts, {
    int? excluded,
  }) {
    final seen = <int>{};
    final pending = [...starts];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      if (next == excluded || !seen.add(next)) continue;
      pending.addAll(adjacency[next] ?? const []);
    }
    return seen;
  }

  _Attribution _attribution(_SavedChoice choice) {
    final key = choice.relations.map((relation) => relation.id).join('/');
    return _reachability.putIfAbsent(key, () {
      final path = [choice.source, ...choice.relations.map((r) => r.target)];
      final withoutTarget = _walk(_parents, path, excluded: _target);
      final explicit = path.contains(_target);
      final savedOutgoing = <String>{};
      for (var index = 0; index < path.length - 1; index++) {
        if (path[index] == _target) {
          savedOutgoing.add(choice.relations[index].id);
        }
      }
      return _Attribution(
        path,
        explicit,
        explicit || path.any(_reachableFromTarget.contains),
        choice.selected == _target
            ? <String>{}
            : {
                ...savedOutgoing,
                for (final relation in _outgoing)
                  if (withoutTarget.contains(relation.target)) relation.id,
              },
      );
    });
  }

  Map<String, Object> get distribution {
    final lengths = <int, int>{};
    final paths = <String, int>{};
    var archivedSteps = 0;
    for (final choice in _choices) {
      lengths.update(
        choice.relations.length,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      final path = choice.relations.map((relation) => relation.id).join('/');
      paths.update(path, (count) => count + 1, ifAbsent: () => 1);
      archivedSteps += choice.relations
          .where((relation) => relation.archived)
          .length;
    }
    return {
      'lengths': {
        for (final entry in lengths.entries) '${entry.key}': entry.value,
      },
      'distinctChains': paths.length,
      'maximumRepeats': paths.values.reduce((a, b) => a > b ? a : b),
      'archivedPeriodSteps': archivedSteps,
    };
  }

  IntentionFixtureSection section(StatisticsView view) {
    final cards = {
      for (final kind in StatisticsView.values) kind: _MutableCounts(),
    };
    final rows = {
      for (final kind in view.breakdowns) kind: <String, _MutableCounts>{},
    };
    final dayCounts = <String, _MutableCounts>{};
    var periodPlanned = 0, periodContribution = 0;
    var missed = 0, upcoming = 0, explicit = 0;
    for (final choice in _choices) {
      final path = _attribution(choice);
      periodPlanned++;
      if (choice.completed) periodContribution++;
      final credited = {
        StatisticsView.sourceIntentions: choice.source == _target,
        StatisticsView.intermediateIntentions: path.path
            .skip(1)
            .take(path.path.length - 2)
            .contains(_target),
        StatisticsView.selectedActions: choice.selected == _target,
        StatisticsView.throughRelations: path.through,
      };
      for (final kind in StatisticsView.values) {
        if (credited[kind]!) cards[kind]!.add(choice.completed);
      }
      if (!credited[view]!) continue;
      if (path.explicit) explicit++;
      (dayCounts[choice.date] ??= _MutableCounts()).add(choice.completed);
      if (!choice.completed) {
        if (choice.date.compareTo('2026-06-15') < 0) {
          missed++;
        } else {
          upcoming++;
        }
      }
      for (final kind in view.breakdowns) {
        final keys = switch (kind) {
          StatisticsBreakdown.sourceIntentions => [
            ContributionStatisticsFixture.id(choice.source),
          ],
          StatisticsBreakdown.selectedActions => [
            ContributionStatisticsFixture.id(choice.selected),
          ],
          StatisticsBreakdown.relations => path.outgoingRelations,
        };
        for (final key in keys) {
          (rows[kind]![key] ??= _MutableCounts()).add(choice.completed);
        }
      }
    }
    return IntentionFixtureSection(
      periodCounts: (planned: periodPlanned, contribution: periodContribution),
      cards: {for (final kind in cards.keys) kind: cards[kind]!.value},
      breakdowns: {
        for (final kind in rows.keys)
          kind:
              [
                for (final entry in rows[kind]!.entries)
                  (
                    id: entry.key,
                    planned: entry.value.planned,
                    contribution: entry.value.contribution,
                  ),
              ]..sort((a, b) {
                final contribution = b.contribution.compareTo(a.contribution);
                if (contribution != 0) return contribution;
                final planned = b.planned.compareTo(a.planned);
                return planned != 0 ? planned : b.id.compareTo(a.id);
              }),
      },
      days: {
        for (final entry in dayCounts.entries) entry.key: entry.value.value,
      },
      uncompleted: (missed: missed, upcoming: upcoming),
      explicitPathChoices: explicit,
    );
  }
}

final class IntentionFixtureSection {
  const IntentionFixtureSection({
    required this.periodCounts,
    required this.cards,
    required this.breakdowns,
    required this.days,
    required this.uncompleted,
    required this.explicitPathChoices,
  });
  final FixtureCounts periodCounts;
  final Map<StatisticsView, FixtureCounts> cards;
  final Map<StatisticsBreakdown, List<FixtureBreakdownRow>> breakdowns;
  final Map<String, FixtureCounts> days;
  final ({int missed, int upcoming}) uncompleted;
  final int explicitPathChoices;
}

final class _SavedRelation {
  const _SavedRelation(this.id, this.source, this.target, this.archived);
  final String id;
  final int source;
  final int target;
  final bool archived;
}

final class _SavedChoice {
  _SavedChoice(this.id, this.date, this.source, this.selected, this.completed);
  final String id;
  final String date;
  final int source;
  final int selected;
  final bool completed;
  final relations = <_SavedRelation>[];
}

final class _Attribution {
  const _Attribution(
    this.path,
    this.explicit,
    this.through,
    this.outgoingRelations,
  );
  final List<int> path;
  final bool explicit;
  final bool through;
  final Set<String> outgoingRelations;
}

final class _MutableCounts {
  var planned = 0;
  var contribution = 0;
  void add(bool completed) {
    planned++;
    if (completed) contribution++;
  }

  FixtureCounts get value => (planned: planned, contribution: contribution);
}
