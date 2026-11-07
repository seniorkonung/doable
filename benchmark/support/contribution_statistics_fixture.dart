import 'package:doable/src/shared/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../test/support/action_seed.dart';
import '../../test/support/graph_seed.dart';

enum ContributionStatisticsProfile { shortPaths, longPaths }

typedef FixtureContribution = ({String id, int planned, int contribution});
typedef _Action = ({String date, int chain, bool completed});

/// Число действий каждого дня фикстур статистики.
const statisticsActionsPerDay = 60;

/// Сохраняет настоящие пути из намерений цепочки первой полосы связей.
/// Некоторые цепочки начинаются или заканчиваются удалённым намерением: его
/// данные и разорванное звено хранят надгробия. Ожидаемые вклады вычисляются
/// из заданных путей, без чтения SQL-агрегата.
final class ContributionStatisticsFixture {
  ContributionStatisticsFixture(this.profile);

  final ContributionStatisticsProfile profile;
  final _actions = <_Action>[];
  late final int graphBytes;

  static String id(int value) =>
      '018f0b5d-6b2e-7c80-8000-${value.toRadixString(16).padLeft(12, '0')}';

  /// Номера удалённых намерений начинаются здесь и не пересекаются с
  /// номерами существующих намерений, связей и действий.
  static const deletedIntentionBase = 60000;

  bool get _short => profile == ContributionStatisticsProfile.shortPaths;
  int get _chains => _short ? 500 : 5;

  /// Узлы пути цепочки [chain]; узел с номером n — намерение `id(n + 1)`.
  /// Пять длинных цепочек дают 145 промежуточных намерений: проверка
  /// охватывает продолжение, а не только первую порцию.
  List<int> _path(int chain) {
    final source = _short ? chain * 8 : chain * 100;
    final length = _short ? chain % 6 + 1 : 30;
    return [
      if (_deletedRoot(chain)) deletedIntentionBase + 2 * chain,
      for (var node = source; node <= source + length; node++) node,
      if (_deletedTail(chain)) deletedIntentionBase + 2 * chain + 1,
    ];
  }

  // Цепочки с удалёнными намерениями не содержат намерений, статистику
  // которых проверяет бенчмарк раздела намерения.
  bool _deletedRoot(int chain) => _short ? chain % 25 == 19 : chain == 2;
  bool _deletedTail(int chain) => _short ? chain % 25 == 7 : chain == 4;

  static bool _deleted(int node) => node >= deletedIntentionBase;

  void populate(sqlite.Database database) {
    final insertIntention = database.prepare('''INSERT INTO intentions
      (id, title, is_action_ready, created_at, updated_at)
      VALUES (?, ?, 1, 0, 0)''');
    final insertRelation = database.prepare('''INSERT INTO long_term_relations
      (id, source_intention_id, related_intention_id, type, priority, created_at, updated_at)
      VALUES (?, ?, ?, 'need', 2, 0, 0)''');
    final insertDeletedIntention = database.prepare(
      'INSERT INTO deleted_intentions (intention_id, title) VALUES (?, ?)',
    );
    final insertDeletedPair = database.prepare(
      '''INSERT INTO deleted_relation_pairs
      (source_intention_id, related_intention_id, type) VALUES (?, ?, 'need')''',
    );
    final insertAction = database.prepare('''INSERT INTO actions
      (id, title, date, priority, is_completed, created_at, updated_at)
      VALUES (?, ?, ?, 4, ?, 0, 0)''');
    final insertItem = database.prepare(insertActionPathItem);
    try {
      seedRawGraph(database, () {
        for (var node = 0; node < 50000; node++) {
          insertIntention.execute([id(node + 1), 'Намерение $node']);
        }
        // Первая полоса — цепочка всех узлов с замыканием в цикл.
        // Остальные полосы дают 150 000 разных направленных пар.
        for (var relation = 0; relation < 150000; relation++) {
          final source = relation % 50000;
          final offset = relation ~/ 50000 + 1;
          final target = relation == 50999 ? 0 : (source + offset) % 50000;
          insertRelation.execute([
            id(100000 + relation),
            id(source + 1),
            id(target + 1),
          ]);
        }
        graphBytes =
            (database.select('PRAGMA page_count').single.values.single as int) *
            (database.select('PRAGMA page_size').single.values.single as int);
        final paths = [
          for (var chain = 0; chain < _chains; chain++) _path(chain),
        ];
        // Удалённое намерение было связано с соседом по пути: надгробия
        // хранят и намерение, и пару его звена.
        for (final path in paths) {
          for (var position = 0; position < path.length; position++) {
            final node = path[position];
            if (!_deleted(node)) continue;
            insertDeletedIntention.execute([id(node + 1), 'Удалённое $node']);
            final (source, related) = position == 0
                ? (node, path[1])
                : (path[position - 1], node);
            insertDeletedPair.execute([id(source + 1), id(related + 1)]);
          }
        }
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
            // Соседние действия повторяют цепочку целиком.
            final chain = (_actions.length ~/ 2) % _chains;
            final actionId = id(300000 + _actions.length);
            final completed = slot < statisticsActionsPerDay ~/ 2;
            insertAction.execute([
              actionId,
              'Действие ${_actions.length}',
              date,
              completed ? 1 : 0,
            ]);
            final path = paths[chain];
            for (var position = 0; position < path.length; position++) {
              insertItem.execute([
                actionId,
                position,
                id(path[position] + 1),
                position == 0 ? null : id(path[position - 1] + 1),
                actionPathRole(position, path.length),
              ]);
            }
            _actions.add((date: date, chain: chain, completed: completed));
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
        if (_short) {
          // Первые звенья ровно 5% из 500 коротких цепочек архивированы
          // после сохранения действий; ограничения схемы остаются включены.
          database.execute('''UPDATE long_term_relations SET is_archived = 1
            WHERE creation_sequence <= 4000
            AND (creation_sequence - 1) % 160 = 0''');
        }
      });
    } finally {
      insertIntention.close();
      insertRelation.close();
      insertDeletedIntention.close();
      insertDeletedPair.close();
      insertAction.close();
      insertItem.close();
    }
  }

  /// Номер первого главного намерения: узлы до него — вспомогательные,
  /// которые связи первой полосы и замыкание 999 → 0 соединяют в цикл без
  /// входящих активных связей от главных, поэтому они не удерживаются.
  static const firstMainIntention = 1000;

  /// Делит граф на главные и вспомогательные намерения: начиная с
  /// [firstMainIntention] главное каждое десятое, остальные вспомогательные.
  /// Связи ведут только вперёд по номерам, кроме замыкающих цикл, поэтому
  /// активные узлы от [firstMainIntention] удерживаются, а цикл до него — нет.
  void assignIntentionKinds(sqlite.Database database) {
    final markMain = database.prepare(
      "UPDATE intentions SET kind = 'main' WHERE id = ?",
    );
    try {
      seedRawGraph(database, () {
        database.execute("UPDATE intentions SET kind = 'supporting'");
        for (var node = firstMainIntention; node < 50000; node += 10) {
          markMain.execute([id(node + 1)]);
        }
      });
    } finally {
      markMain.close();
    }
  }

  void archivePathParts(sqlite.Database database) {
    seedRawGraph(database, () {
      database.execute('''UPDATE long_term_relations SET is_archived = 1
        WHERE creation_sequence % 10 = 0''');
    });
  }

  Map<String, Object> distribution(StatisticsPeriod? period) {
    final lengths = <String, int>{};
    final chains = <int, int>{};
    for (final action in _inPeriod(period)) {
      lengths.update(
        '${_path(action.chain).length}',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      chains.update(action.chain, (count) => count + 1, ifAbsent: () => 1);
    }
    return {
      'pathLengths': lengths,
      'distinctChains': chains.length,
      'maximumRepeats': chains.values.fold<int>(0, (a, b) => a > b ? a : b),
      'deletedPathIntentions': [
        for (var chain = 0; chain < _chains; chain++) ..._path(chain),
      ].where(_deleted).length,
    };
  }

  ({int actions, int pathItems, int completed}) volume(
    StatisticsPeriod? period,
  ) {
    var actions = 0, pathItems = 0, completed = 0;
    for (final action in _inPeriod(period)) {
      actions++;
      pathItems += _path(action.chain).length;
      if (action.completed) completed++;
    }
    return (actions: actions, pathItems: pathItems, completed: completed);
  }

  List<FixtureContribution> expected(
    StatisticsPeriod period,
    StatisticsView view,
  ) {
    final counts = <int, ({int planned, int contribution})>{};
    for (final MapEntry(key: chain, value: weight) in _chainWeights(
      period,
    ).entries) {
      final path = _path(chain);
      final nodes = switch (view) {
        StatisticsView.throughRelations => throw ArgumentError.value(
          view,
          'view',
          'Для вида через связи используется отдельный эталон обхода графа',
        ),
        StatisticsView.rootIntentions => [path.first],
        StatisticsView.terminalIntentions => [path.last],
        StatisticsView.intermediateIntentions => path.sublist(
          1,
          path.length - 1,
        ),
      };
      // Удалённое намерение не передаёт свою роль соседям.
      for (final node in nodes.where((node) => !_deleted(node))) {
        final previous = counts[node] ?? (planned: 0, contribution: 0);
        counts[node] = (
          planned: previous.planned + weight.planned,
          contribution: previous.contribution + weight.contribution,
        );
      }
    }
    return _sorted({
      for (final MapEntry(key: node, value: weight) in counts.entries)
        node + 1: weight,
    });
  }

  /// Эталон обходит активные входящие связи от существующих намерений
  /// полного сохранённого пути. Повторные цепочки переиспользуют обход,
  /// сохраняя вес каждого действия; опорные наборы и сжатие компонент
  /// производственного подсчёта не нужны.
  List<FixtureContribution> expectedThroughRelations(
    StatisticsPeriod period,
    sqlite.Database database,
  ) {
    int node(Object? value) =>
        int.parse((value as String).substring(24), radix: 16);
    final parents = <int, List<int>>{};
    for (final row in database.select(
      '''SELECT source_intention_id,
        related_intention_id FROM long_term_relations WHERE is_archived = 0''',
    )) {
      (parents[node(row['related_intention_id'])] ??= []).add(
        node(row['source_intention_id']),
      );
    }
    final counts = <int, ({int planned, int contribution})>{};
    for (final MapEntry(key: chain, value: weight) in _chainWeights(
      period,
    ).entries) {
      final pending = [
        for (final step in _path(chain))
          if (!_deleted(step)) step + 1,
      ];
      final visited = <int>{};
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (!visited.add(current)) continue;
        pending.addAll(parents[current] ?? const []);
      }
      for (final current in visited) {
        final previous = counts[current] ?? (planned: 0, contribution: 0);
        counts[current] = (
          planned: previous.planned + weight.planned,
          contribution: previous.contribution + weight.contribution,
        );
      }
    }
    return _sorted(counts);
  }

  Map<int, ({int planned, int contribution})> _chainWeights(
    StatisticsPeriod period,
  ) {
    final weights = <int, ({int planned, int contribution})>{};
    for (final action in _inPeriod(period)) {
      final previous = weights[action.chain] ?? (planned: 0, contribution: 0);
      weights[action.chain] = (
        planned: previous.planned + 1,
        contribution: previous.contribution + (action.completed ? 1 : 0),
      );
    }
    return weights;
  }

  /// Порядок элементов вида по номерам их намерений.
  static List<FixtureContribution> _sorted(
    Map<int, ({int planned, int contribution})> counts,
  ) =>
      [
        for (final MapEntry(key: number, value: weight) in counts.entries)
          (
            id: id(number),
            planned: weight.planned,
            contribution: weight.contribution,
          ),
      ]..sort((a, b) {
        final planned = b.planned.compareTo(a.planned);
        if (planned != 0) return planned;
        final contribution = b.contribution.compareTo(a.contribution);
        return contribution != 0 ? contribution : b.id.compareTo(a.id);
      });

  Iterable<_Action> _inPeriod(StatisticsPeriod? period) => _actions.where(
    (action) =>
        period == null ||
        (action.date.compareTo(period.firstDate.toCanonicalString()) >= 0 &&
            action.date.compareTo(period.lastDate.toCanonicalString()) <= 0),
  );
}
