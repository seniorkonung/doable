import 'package:doable/src/action/application/path_candidates.dart';
import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/data/local/app_database.dart';
import 'package:doable/src/graph/data/drift_personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../../support/action_seed.dart';
import '../../support/graph_seed.dart';
import '../../support/in_memory_diagnostics_sink.dart';

const _pageSize = 3;
const _segmentLength = 4;
const _halfCandidates = 8;

/// Запоминает запросы и материализованные строки для проверки стоимости чтения.
final class _ReadTrace extends LocalDatabaseConnectionObserver {
  final reads =
      <
        ({LocalDatabaseSqlStatement statement, List<Map<String, Object?>> rows})
      >[];

  void clear() => reads.clear();

  @override
  List<Map<String, Object?>> afterSelect(
    LocalDatabaseSqlStatement statement,
    List<Map<String, Object?>> rows,
  ) {
    reads.add((statement: statement, rows: rows));
    return rows;
  }
}

void main() {
  late _ReadTrace trace;
  late sqlite.Database raw;
  late AppDatabase database;
  late DriftPersonalGraphRepository repository;

  final draft = ActionPath([
    for (var number = 1; number <= _segmentLength; number++)
      seedIntentionId(number),
  ]);

  setUp(() async {
    trace = _ReadTrace();
    database = AppDatabase(
      observeConfiguredLocalDatabaseConnection(
        openInMemoryLocalDatabase(setup: (db) => raw = db),
        trace,
      ),
    );
    await database.open();
    repository = DriftPersonalGraphRepository(
      database,
      UuidV7IntentionIdGenerator(),
      () => DateTime.utc(2026, 10, 7),
      InMemoryDiagnosticsSink(),
    );
    seedRawGraph(raw, () {
      var relationNumber = 1000;
      void relation(int source, int related, String type, int priority) =>
          raw.execute(
            '''INSERT INTO long_term_relations
               (id, source_intention_id, related_intention_id, type, priority,
                created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, 1, 1)''',
            [
              seedUuid(relationNumber++),
              seedUuid(source),
              seedUuid(related),
              type,
              priority,
            ],
          );

      const firstCandidate = 100;
      for (
        var number = 1;
        number < firstCandidate + 2 * _halfCandidates;
        number++
      ) {
        seedIntention(raw, seedUuid(number), 'Намерение $number');
      }
      for (var number = 2; number <= _segmentLength; number++) {
        relation(number - 1, number, 'need', 1);
      }
      // Последнее намерение участка ведёт ко всем прежним с наивысшим
      // приоритетом: исключённые строки стоят впереди кандидатов.
      for (var number = 1; number < _segmentLength; number++) {
        relation(_segmentLength, number, number.isEven ? 'need' : 'can', 1);
      }
      for (var index = 0; index < 2 * _halfCandidates; index++) {
        relation(
          _segmentLength,
          firstCandidate + index,
          index.isEven ? 'need' : 'can',
          index % 4 + 1,
        );
      }
    });
    trace.clear();
  });

  tearDown(() => database.close());

  test('порция каждой половины читает не больше своих строк, а запросы идут '
      'по индексам связей без сортировки', () async {
    final candidateStatements = <LocalDatabaseSqlStatement>[];
    final continuations = <LocalDatabaseSqlStatement>[];
    final segmentStatements = <LocalDatabaseSqlStatement>[];
    final countStatements = <LocalDatabaseSqlStatement>[];
    for (final half in LongTermRelationType.values) {
      trace.clear();
      final first =
          ((await repository.getPathCandidates(
                PathCandidatesQuery(
                  draft: draft,
                  half: half,
                  pageSize: _pageSize,
                ),
              )) as PathCandidatesSuccess).value
              as PathCandidatesFirstPage;
      expect(first.segment.steps, hasLength(_segmentLength - 1));
      expect(first.items, hasLength(_pageSize));
      final next =
          ((await repository.getPathCandidates(
                PathCandidatesQuery(
                  draft: draft,
                  half: half,
                  pageSize: _pageSize,
                  cursor: first.nextCursor,
                ),
              )) as PathCandidatesSuccess).value
              as PathCandidatesPage;
      expect(next.items, hasLength(_pageSize));

      // Участок — по строке на намерение черновика, числа — одна строка,
      // порции — лишняя строка за признак продолжения.
      expect(trace.reads.map((read) => read.rows.length), [
        _segmentLength,
        1,
        _pageSize + 1,
        _pageSize + 1,
      ]);
      segmentStatements.add(trace.reads[0].statement);
      countStatements.add(trace.reads[1].statement);
      candidateStatements.addAll([
        trace.reads[2].statement,
        trace.reads[3].statement,
      ]);
      continuations.add(trace.reads[3].statement);
    }

    String planOf(LocalDatabaseSqlStatement statement) => raw
        .select(
          'EXPLAIN QUERY PLAN ${statement.statements.single}',
          statement.arguments,
        )
        .map((row) => row['detail'] as String)
        .join('\n');
    for (final statement in [
      ...segmentStatements,
      ...countStatements,
      ...candidateStatements,
    ]) {
      final plan = planOf(statement);
      printOnFailure(plan);
      expect(plan, isNot(contains('TEMP B-TREE')));
      expect(plan, isNot(contains('SCAN long_term_relations')));
      expect(plan, isNot(contains('SCAN r')));
      expect(plan, isNot(contains('SCAN i')));
      expect(plan, isNot(contains('SCAN intentions')));
    }
    for (final statement in candidateStatements) {
      expect(
        planOf(statement),
        contains('INDEX long_term_relations_source_group_order'),
      );
    }
    // Числа берут все связи половины из индекса без чтения строк, а
    // вычитаемое находит связи к намерениям участка по паре.
    for (final statement in countStatements) {
      final plan = planOf(statement);
      expect(
        'COVERING INDEX long_term_relations_source_group_order'.allMatches(
          plan,
        ),
        hasLength(2),
      );
      expect(
        '(source_intention_id=? AND related_intention_id=?)'.allMatches(plan),
        hasLength(2),
      );
    }
    // Продолжение начинает диапазон половины с приоритета границы, а не
    // проходит строки более высоких приоритетов.
    for (final statement in continuations) {
      expect(
        planOf(statement),
        contains(
          'long_term_relations_source_group_order (source_intention_id=? AND '
          'type=? AND is_archived=? AND priority>?)',
        ),
      );
    }
  });
}
