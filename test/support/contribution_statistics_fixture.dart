import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/statistics/application/statistics_period.dart';
import 'package:doable/src/statistics/application/statistics_read_contract.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

enum ContributionStatisticsProfile { shortPaths, longPaths }

typedef FixtureContribution = ({String id, int planned, int contribution});
typedef _Choice = ({String date, int source, int length, bool completed});

/// Сохраняет настоящие цепочки с отдельными шагами каждого дубликата.
/// Ожидаемые вклады вычисляются из заданных цепочек, без чтения SQL-агрегата.
final class ContributionStatisticsFixture {
  ContributionStatisticsFixture(this.profile);

  final ContributionStatisticsProfile profile;
  final _choices = <_Choice>[];
  late final int graphBytes;

  static String id(int value) =>
      '018f0b5d-6b2e-7c80-8000-${value.toRadixString(16).padLeft(12, '0')}';

  void populate(sqlite.Database database) {
    final insertIntention = database.prepare('''INSERT INTO intentions
      (id, title, is_action_ready, created_at, updated_at)
      VALUES (?, ?, 1, 0, 0)''');
    final insertRelation = database.prepare('''INSERT INTO long_term_relations
      (id, source_intention_id, related_intention_id, type, priority)
      VALUES (?, ?, ?, 'need', 2)''');
    final insertChoice = database.prepare('''INSERT INTO daily_choices
      (id, source_intention_id, selected_intention_id, choice_date, is_completed)
      VALUES (?, ?, ?, ?, ?)''');
    final insertStep = database.prepare('''INSERT INTO daily_choice_path_steps
      (id, daily_choice_id, long_term_relation_id, previous_step_id)
      VALUES (?, ?, ?, ?)''');
    database.execute('BEGIN');
    try {
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
      var stepNumber = 0;
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
          final short = profile == ContributionStatisticsProfile.shortPaths;
          final bucket = (_choices.length ~/ 2) % (short ? 500 : 5);
          // Пять длинных цепочек дают 145 промежуточных намерений:
          // проверка охватывает продолжение, а не только первую порцию.
          final source = short ? bucket * 8 : bucket * 100;
          final length = short ? bucket % 6 + 1 : 30;
          final choiceId = id(300000 + _choices.length);
          final completed = slot < 50;
          insertChoice.execute([
            choiceId,
            id(source + 1),
            id(source + length + 1),
            date,
            completed ? 1 : 0,
          ]);
          String? previous;
          for (var step = 0; step < length; step++) {
            final stepId = id(1000000 + stepNumber++);
            insertStep.execute([
              stepId,
              choiceId,
              id(100000 + source + step),
              previous,
            ]);
            previous = stepId;
          }
          _choices.add((
            date: date,
            source: source,
            length: length,
            completed: completed,
          ));
        }
      }
      database.execute(
        '''UPDATE long_term_relations SET is_archived = 1
          WHERE source_intention_id >= ? OR related_intention_id >= ?''',
        [id(45001), id(45001)],
      );
      database.execute('UPDATE intentions SET is_archived = 1 WHERE id >= ?', [
        id(45001),
      ]);
      if (profile == ContributionStatisticsProfile.shortPaths) {
        // Первые шаги ровно 5% из 500 коротких цепочек архивированы
        // после сохранения выборов; ограничения схемы остаются включены.
        database.execute('''UPDATE long_term_relations SET is_archived = 1
          WHERE creation_sequence <= 4000
          AND (creation_sequence - 1) % 160 = 0''');
      }
      database.execute('COMMIT');
    } on Object {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      insertIntention.close();
      insertRelation.close();
      insertChoice.close();
      insertStep.close();
    }
  }

  void archivePathParts(sqlite.Database database) {
    database.execute('''UPDATE long_term_relations SET is_archived = 1
      WHERE creation_sequence % 10 = 0''');
  }

  Map<String, Object> distribution(StatisticsPeriod? period) {
    final lengths = <String, int>{};
    final chains = <(int, int), int>{};
    for (final choice in _inPeriod(period)) {
      lengths.update(
        '${choice.length}',
        (count) => count + 1,
        ifAbsent: () => 1,
      );
      chains.update(
        (choice.source, choice.length),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return {
      'lengths': lengths,
      'distinctChains': chains.length,
      'maximumRepeats': chains.values.fold<int>(0, (a, b) => a > b ? a : b),
    };
  }

  ({int choices, int steps, int completed, int missed, int upcoming}) volume(
    StatisticsPeriod? period,
  ) {
    var choices = 0, steps = 0, completed = 0, missed = 0, upcoming = 0;
    for (final choice in _inPeriod(period)) {
      choices++;
      steps += choice.length;
      if (choice.completed) {
        completed++;
      } else if (choice.date.compareTo('2026-06-15') < 0) {
        missed++;
      } else {
        upcoming++;
      }
    }
    return (
      choices: choices,
      steps: steps,
      completed: completed,
      missed: missed,
      upcoming: upcoming,
    );
  }

  List<FixtureContribution> expected(
    StatisticsPeriod period,
    StatisticsView view,
  ) {
    final chains = <(int, int), ({int planned, int contribution})>{};
    for (final choice in _inPeriod(period)) {
      final key = (choice.source, choice.length);
      final previous = chains[key] ?? (planned: 0, contribution: 0);
      chains[key] = (
        planned: previous.planned + 1,
        contribution: previous.contribution + (choice.completed ? 1 : 0),
      );
    }
    final counts = <int, ({int planned, int contribution})>{};
    for (final MapEntry(key: (source, length), value: weight)
        in chains.entries) {
      final nodes = switch (view) {
        StatisticsView.sourceIntentions => [source],
        StatisticsView.selectedActions => [source + length],
        StatisticsView.intermediateIntentions => [
          for (var node = source + 1; node < source + length; node++) node,
        ],
      };
      for (final node in nodes) {
        final previous = counts[node] ?? (planned: 0, contribution: 0);
        counts[node] = (
          planned: previous.planned + weight.planned,
          contribution: previous.contribution + weight.contribution,
        );
      }
    }
    return [
      for (final MapEntry(key: node, value: weight) in counts.entries)
        (
          id: id(node + 1),
          planned: weight.planned,
          contribution: weight.contribution,
        ),
    ]..sort((a, b) {
      final contribution = b.contribution.compareTo(a.contribution);
      if (contribution != 0) return contribution;
      final planned = b.planned.compareTo(a.planned);
      return planned != 0 ? planned : b.id.compareTo(a.id);
    });
  }

  /// Эталон обходит активные входящие связи от полного сохранённого пути.
  /// Повторные цепочки переиспользуют обход, сохраняя вес каждого выбора;
  /// опорные наборы и сжатие компонент производственного подсчёта не нужны.
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
    final weights = <(int, int), ({int planned, int contribution})>{};
    for (final choice in _inPeriod(period)) {
      final key = (choice.source, choice.length);
      final previous = weights[key] ?? (planned: 0, contribution: 0);
      weights[key] = (
        planned: previous.planned + 1,
        contribution: previous.contribution + (choice.completed ? 1 : 0),
      );
    }
    final counts = <int, ({int planned, int contribution})>{};
    for (final MapEntry(key: (source, length), value: weight)
        in weights.entries) {
      final pending = [for (var i = 0; i <= length; i++) source + i + 1];
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
    return [
      for (final MapEntry(key: current, value: weight) in counts.entries)
        (
          id: id(current),
          planned: weight.planned,
          contribution: weight.contribution,
        ),
    ]..sort((a, b) {
      final contribution = b.contribution.compareTo(a.contribution);
      if (contribution != 0) return contribution;
      final planned = b.planned.compareTo(a.planned);
      return planned != 0 ? planned : b.id.compareTo(a.id);
    });
  }

  Iterable<_Choice> _inPeriod(StatisticsPeriod? period) => _choices.where(
    (choice) =>
        period == null ||
        (choice.date.compareTo(period.firstDate.toCanonicalString()) >= 0 &&
            choice.date.compareTo(period.lastDate.toCanonicalString()) <= 0),
  );
}
