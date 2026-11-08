import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/intention_statistics_breakdown.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/action_seed.dart';
import '../../test/support/graph_seed.dart';
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
      (id, title, kind, created_at, updated_at)
      VALUES (?, ?, 'main', 0, 0)''');
    final relation = database.prepare('''INSERT INTO long_term_relations
      (id, source_intention_id, related_intention_id, type, priority, created_at, updated_at)
      VALUES (?, ?, ?, 'need', 2, 0, 0)''');
    final deletedIntention = database.prepare(
      'INSERT INTO deleted_intentions (intention_id, title) VALUES (?, ?)',
    );
    final deletedPair = database.prepare(
      '''INSERT INTO deleted_relation_pairs
      (source_intention_id, related_intention_id, type) VALUES (?, ?, 'need')''',
    );
    final action = database.prepare('''INSERT INTO actions
      (id, title, date, priority, is_completed, created_at, updated_at)
      VALUES (?, ?, ?, 4, ?, 0, 0)''');
    final item = database.prepare(insertActionPathItem);
    String id(int number) => ContributionStatisticsFixture.id(number);
    // Часть путей начинается или заканчивается удалённым намерением.
    int? deletedRoot(int index) => index % 50 == 33 ? 61001 + index : null;
    int? deletedTail(int index) => index % 50 == 17 ? 60001 + index : null;
    try {
      seedRawGraph(database, () {
        for (var node = 1; node <= 50000; node++) {
          intention.execute([id(node), 'Намерение $node']);
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
          relation.execute([id(100000 + number), id(from), id(to)]);
        }
        for (var index = 0; index < 500; index++) {
          if (deletedRoot(index) case final root?) {
            deletedIntention.execute([id(root), 'Удалённое $root']);
            deletedPair.execute([id(root), id(20001 + index)]);
          }
          if (deletedTail(index) case final tail?) {
            deletedIntention.execute([id(tail), 'Удалённое $tail']);
            deletedPair.execute([id(30001 + index), id(tail)]);
          }
        }
        var actionNumber = 0;
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
          for (var slot = 0; slot < statisticsActionsPerDay; slot++) {
            final index = (actionNumber ~/ 6) % 500;
            final incoming = 20001 + index;
            final outgoing = 30001 + index;
            final path = switch ((actionNumber ~/ 2) % 3) {
              0 => [incoming, target, outgoing],
              1 => [target, outgoing],
              _ => [incoming, target],
            };
            if (path.first == incoming) {
              if (deletedRoot(index) case final root?) path.insert(0, root);
            }
            if (path.last == outgoing) {
              if (deletedTail(index) case final tail?) path.add(tail);
            }
            final actionId = id(300000 + actionNumber);
            action.execute([
              actionId,
              'Действие $actionNumber',
              date,
              slot < statisticsActionsPerDay ~/ 2 ? 1 : 0,
            ]);
            for (var position = 0; position < path.length; position++) {
              item.execute([
                actionId,
                position,
                id(path[position]),
                position == 0 ? null : id(path[position - 1]),
                actionPathRole(position, path.length),
              ]);
            }
            actionNumber++;
          }
        }
        database.execute(
          '''UPDATE long_term_relations SET is_archived = 1
          WHERE source_intention_id >= ? OR related_intention_id >= ?''',
          [id(45001), id(45001)],
        );
        database.execute(
          'UPDATE intentions SET is_archived = 1 WHERE id >= ?',
          [id(45001)],
        );
      });
    } finally {
      intention.close();
      relation.close();
      deletedIntention.close();
      deletedPair.close();
      action.close();
      item.close();
    }
  }

  void archivePathParts(sqlite.Database database) {
    if (_base case final base?) {
      base.archivePathParts(database);
    } else {
      seedRawGraph(database, () {
        database.execute('''UPDATE long_term_relations SET is_archived = 1
          WHERE creation_sequence BETWEEN 50501 AND 51000
            AND creation_sequence % 10 = 0''');
      });
    }
  }

  int get intention => switch (profile) {
    IntentionStatisticsProfile.shortPaths => 10,
    IntentionStatisticsProfile.longPaths => 16,
    IntentionStatisticsProfile.manyBreakdowns => target,
  };

  /// Эталон читает сохранённые пути и обходит исходный граф, минуя X.
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
  final _actions = <_SavedAction>[];
  final _relations = <(int, int), _SavedRelation>{};
  final _deleted = <int>{};
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
      _relations[(relation.source, relation.target)] = relation;
      if (!relation.archived) {
        (_children[relation.source] ??= []).add(relation.target);
        (_parents[relation.target] ??= []).add(relation.source);
        if (relation.source == _target) _outgoing.add(relation);
      }
    }
    for (final row in database.select(
      'SELECT intention_id FROM deleted_intentions',
    )) {
      _deleted.add(_number(row['intention_id']));
    }
    _reachableFromTarget = _walk(_children, [_target]);
    _SavedAction? current;
    for (final row in database.select(
      '''SELECT a.id, a.date, a.is_completed, p.intention_id
        FROM actions a JOIN action_path_items p ON p.action_id = a.id
        WHERE a.date BETWEEN ? AND ?
        ORDER BY a.id, p.position''',
      [
        _period.firstDate.toCanonicalString(),
        _period.lastDate.toCanonicalString(),
      ],
    )) {
      final id = row['id'] as String;
      if (current?.id != id) {
        current = _SavedAction(
          id,
          row['date'] as String,
          row['is_completed'] == 1,
        );
        _actions.add(current);
      }
      current!.path.add(_number(row['intention_id']));
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

  _Attribution _attribution(_SavedAction action) {
    final path = action.path;
    return _reachability.putIfAbsent(path.join('/'), () {
      final existing = path.where((node) => !_deleted.contains(node));
      final withoutTarget = _walk(_parents, existing, excluded: _target);
      final explicit = path.contains(_target);
      // Связь, следующая за намерением в пути, — текущая связь пары звена,
      // в том числе архивированная; у разорванного звена её нет.
      final savedOutgoing = <String>{
        for (var index = 0; index < path.length - 1; index++)
          if (path[index] == _target)
            if (_relations[(_target, path[index + 1])] case final relation?)
              relation.id,
      };
      return _Attribution(
        explicit,
        explicit || existing.any(_reachableFromTarget.contains),
        path.last == _target
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
    var archivedLinks = 0, deletedItems = 0;
    for (final action in _actions) {
      final path = action.path;
      lengths.update(path.length, (count) => count + 1, ifAbsent: () => 1);
      paths.update(path.join('/'), (count) => count + 1, ifAbsent: () => 1);
      for (var index = 1; index < path.length; index++) {
        if (_relations[(path[index - 1], path[index])]?.archived ?? false) {
          archivedLinks++;
        }
      }
      deletedItems += path.where(_deleted.contains).length;
    }
    return {
      'pathLengths': {
        for (final entry in lengths.entries) '${entry.key}': entry.value,
      },
      'distinctPaths': paths.length,
      'maximumRepeats': paths.values.reduce((a, b) => a > b ? a : b),
      'archivedPeriodLinks': archivedLinks,
      'deletedPeriodPathItems': deletedItems,
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
    var periodPlanned = 0, periodContribution = 0, explicit = 0;
    for (final action in _actions) {
      final path = action.path;
      final attribution = _attribution(action);
      periodPlanned++;
      if (action.completed) periodContribution++;
      final credited = {
        StatisticsView.rootIntentions: path.first == _target,
        StatisticsView.intermediateIntentions: path
            .sublist(1, path.length - 1)
            .contains(_target),
        StatisticsView.terminalIntentions: path.last == _target,
        StatisticsView.throughRelations: attribution.through,
      };
      for (final kind in StatisticsView.values) {
        if (credited[kind]!) cards[kind]!.add(action.completed);
      }
      if (!credited[view]!) continue;
      if (attribution.explicit) explicit++;
      (dayCounts[action.date] ??= _MutableCounts()).add(action.completed);
      // Разбивки не содержат само намерение и удалённые намерения.
      String? other(int node) => node == _target || _deleted.contains(node)
          ? null
          : ContributionStatisticsFixture.id(node);
      for (final kind in view.breakdowns) {
        final keys = switch (kind) {
          StatisticsBreakdown.rootIntentions => [?other(path.first)],
          StatisticsBreakdown.terminalIntentions => [?other(path.last)],
          StatisticsBreakdown.relations => attribution.outgoingRelations,
        };
        for (final key in keys) {
          (rows[kind]![key] ??= _MutableCounts()).add(action.completed);
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
                final planned = b.planned.compareTo(a.planned);
                if (planned != 0) return planned;
                final contribution = b.contribution.compareTo(a.contribution);
                return contribution != 0 ? contribution : b.id.compareTo(a.id);
              }),
      },
      days: {
        for (final entry in dayCounts.entries) entry.key: entry.value.value,
      },
      explicitPathActions: explicit,
    );
  }
}

final class IntentionFixtureSection {
  const IntentionFixtureSection({
    required this.periodCounts,
    required this.cards,
    required this.breakdowns,
    required this.days,
    required this.explicitPathActions,
  });
  final FixtureCounts periodCounts;
  final Map<StatisticsView, FixtureCounts> cards;
  final Map<StatisticsBreakdown, List<FixtureBreakdownRow>> breakdowns;
  final Map<String, FixtureCounts> days;
  final int explicitPathActions;
}

final class _SavedRelation {
  const _SavedRelation(this.id, this.source, this.target, this.archived);
  final String id;
  final int source;
  final int target;
  final bool archived;
}

/// Путь — номера намерений от корневого к конечному.
final class _SavedAction {
  _SavedAction(this.id, this.date, this.completed);
  final String id;
  final String date;
  final bool completed;
  final path = <int>[];
}

final class _Attribution {
  const _Attribution(this.explicit, this.through, this.outgoingRelations);
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
