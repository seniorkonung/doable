part of 'drift_intention_repository_fault_test.dart';

void _catalogTagFilterFailureScenarios(
  Future<
    ({
      AppDatabase database,
      DriftPersonalGraphRepository repository,
      InMemoryDiagnosticsSink diagnostics,
    })
  >
  Function(LocalDatabaseConnectionObserver, void Function(Database))
  replace,
) {
  for (final (point, label) in [
    (_CatalogFailurePoint.count, 'при подсчёте совпадений'),
    (_CatalogFailurePoint.rows, 'при чтении порции'),
    (_CatalogFailurePoint.tags, 'при чтении тегов порции'),
  ]) {
    for (final (error, failure, code)
        in <(Object, Matcher, DiagnosticsFailureCode)>[
          (
            StateError('CANARY-неизвестный отказ'),
            isA<IntentionUnexpectedFailure>(),
            DiagnosticsFailureCode.unexpected,
          ),
          (
            SqliteException(
              extendedResultCode: SqlError.SQLITE_BUSY,
              message: 'CANARY-недоступность',
            ),
            isA<IntentionUnavailableFailure>(),
            DiagnosticsFailureCode.unavailable,
          ),
          (
            SqliteException(
              extendedResultCode: SqlError.SQLITE_CORRUPT,
              message: 'CANARY-повреждение',
            ),
            isA<IntentionCorruptionFailure>(),
            DiagnosticsFailureCode.corruption,
          ),
        ]) {
      for (final warmed in [false, true]) {
        test('отказ $label категории $code сохраняет навигацию и откат '
            '${warmed ? 'повторного' : 'первого'} поиска', () async {
          final observer = _CatalogFilterFailureObserver(point, error);
          late Database raw;
          final (:repository, :diagnostics, database: _) = await replace(
            observer,
            (db) => raw = db,
          );
          seedTagStorageFixture(raw);
          final required = _fixtureTag(firstTagNumber);
          final excluded = _fixtureTag(lastTagNumber);
          IntentionCatalogQuery query(TagId required, TagId excluded) =>
              IntentionCatalogQuery(
                scope: IntentionScope.active,
                titleFilter: 'Намерение',
                tagFilter: IntentionTagFilter(
                  requiredTagIds: [required],
                  excludedTagIds: [excluded],
                ),
                order: IntentionCatalogOrder.createdAtAscending,
                pageSize: 1,
              );
          if (warmed) {
            expect(
              await repository.getCatalogPage(query(required, excluded)),
              isA<ResultSuccess<IntentionCatalogPage>>(),
            );
          }
          final first = (await repository.getTaggedEntitiesPage(
            TaggedEntitiesQuery(
              tagId: required,
              scope: TaggedEntitiesScope.active,
              pageSize: 1,
            ),
          ) as TaggedEntitiesPageSuccess).value;
          expect(first.nextCursor, isNotNull);
          final before = _storedFilterFailureGraph(raw);
          final changesBefore = _connectionChanges(raw);
          observer.arm();

          expect(
            await repository.getCatalogPage(query(required, excluded)),
            isA<ResultFailure<IntentionCatalogPage>>().having(
              (result) => result.failure,
              'причина',
              failure,
            ),
          );
          expect(observer.hasFailed, isTrue);
          expect(_storedFilterFailureGraph(raw), before);
          expect(_connectionChanges(raw), changesBefore);
          expect(
            diagnostics.events.last,
            isA<CatalogPageReadDiagnosticsEvent>().having(
              (event) => event.status,
              'исход',
              isA<DiagnosticsFailed>()
                  .having((status) => status.code, 'категория', code)
                  .having(
                    (status) => status.duration,
                    'длительность',
                    greaterThanOrEqualTo(Duration.zero),
                  ),
            ),
          );
          expect(diagnostics.events.toString(), isNot(contains('CANARY')));
          expect(
            diagnostics.events.toString(),
            isNot(contains(tagFixtureId(firstTagNumber))),
          );

          final continuation = await repository.getTaggedEntitiesPage(
            TaggedEntitiesQuery(
              tagId: required,
              scope: first.scope,
              pageSize: first.pageSize,
              cursor: first.nextCursor,
            ),
          );
          expect(continuation, isA<TaggedEntitiesPageSuccess>());
          final next = (continuation as TaggedEntitiesPageSuccess).value;
          expect(
            next.revision.compareTo(first.revision),
            GraphRevisionOrder.same,
          );
          expect(next.items.single.target, isNot(first.items.single.target));
          expect(next.nextCursor, isNull);

          final success = (await repository.getCatalogPage(
            query(excluded, required),
          ) as ResultSuccess<IntentionCatalogPage>).value;
          expect(success.items.single.id, _id(tagFixtureId(3)));
          expect((success as IntentionCatalogFirstPage).totalCount, 1);
          expect(
            success.revision.compareTo(first.revision),
            GraphRevisionOrder.same,
          );
          expect(_storedFilterFailureGraph(raw), before);
          expect(_connectionChanges(raw), changesBefore);
        });
      }
    }
  }
}

void _catalogReconciliationFailureScenarios(
  Future<
    ({
      AppDatabase database,
      DriftPersonalGraphRepository repository,
      InMemoryDiagnosticsSink diagnostics,
    })
  >
  Function(LocalDatabaseConnectionObserver, void Function(Database))
  replace,
) {
  for (final (point, label) in [
    (_CatalogFailurePoint.count, 'при подсчёте абсолютного количества'),
    (_CatalogFailurePoint.rows, 'при чтении недостающих совпадений'),
    (_CatalogFailurePoint.tags, 'при чтении тегов порции'),
  ]) {
    for (final (error, failure, code)
        in <(Object, Matcher, DiagnosticsFailureCode)>[
          (
            StateError('CANARY-неизвестный отказ'),
            isA<IntentionUnexpectedFailure>(),
            DiagnosticsFailureCode.unexpected,
          ),
          (
            SqliteException(
              extendedResultCode: SqlError.SQLITE_BUSY,
              message: 'CANARY-недоступность',
            ),
            isA<IntentionUnavailableFailure>(),
            DiagnosticsFailureCode.unavailable,
          ),
          (
            SqliteException(
              extendedResultCode: SqlError.SQLITE_CORRUPT,
              message: 'CANARY-повреждение',
            ),
            isA<IntentionCorruptionFailure>(),
            DiagnosticsFailureCode.corruption,
          ),
        ]) {
      test('отказ чтения согласования $label сохраняет категорию, граф и '
          'соединение и записывает безопасную диагностику: $error', () async {
        final observer = _CatalogFilterFailureObserver(point, error);
        late Database raw;
        final (:repository, :diagnostics, database: _) = await replace(
          observer,
          (db) => raw = db,
        );
        seedTagStorageFixture(raw);
        final query = IntentionCatalogReconciliationQuery(
          catalogQuery: IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: null,
            tagFilter: IntentionTagFilter(
              excludedTagIds: [_fixtureTag(lastTagNumber)],
            ),
            order: IntentionCatalogOrder.createdAtAscending,
            pageSize: 1,
          ),
          boundary: const IntentionCatalogCompletedBoundary(),
          window: IntentionCatalogFinalReconciliationWindow(const []),
        );
        final before = _storedFilterFailureGraph(raw);
        final changesBefore = _connectionChanges(raw);
        observer.arm();
        final failureOffset = diagnostics.events.length;

        expect(
          await repository.getCatalogReconciliationPortion(query),
          isA<ResultFailure<IntentionCatalogReconciliationOutcome>>().having(
            (result) => result.failure,
            'причина',
            failure,
          ),
        );
        expect(observer.hasFailed, isTrue);
        expect(_storedFilterFailureGraph(raw), before);
        expect(_connectionChanges(raw), changesBefore);
        // Отказ SQLite виден только в событиях самого чтения согласования и
        // только безопасной категорией, без сообщения исключения.
        expect(diagnostics.events.skip(failureOffset), [
          _reconciliationDiagnostics(isA<DiagnosticsStarted>()),
          _reconciliationDiagnostics(
            isA<DiagnosticsFailed>()
                .having((status) => status.code, 'категория', code)
                .having(
                  (status) => status.duration,
                  'длительность',
                  greaterThanOrEqualTo(Duration.zero),
                ),
          ),
        ]);

        final recoveryOffset = diagnostics.events.length;
        final recovered = await repository.getCatalogReconciliationPortion(
          query,
        );
        expect(diagnostics.events.skip(recoveryOffset), [
          _reconciliationDiagnostics(isA<DiagnosticsStarted>()),
          _reconciliationDiagnostics(
            isA<DiagnosticsSucceeded>(),
            completion: CatalogReconciliationReadCompletion.portion,
          ),
        ]);
        final portion =
            (recovered as ResultSuccess<IntentionCatalogReconciliationOutcome>)
                    .value
                as IntentionCatalogReconciliationFirstPortion;
        expect(portion.totalCount, 2);
        expect(portion.items.single.id, _id(tagFixtureId(1)));
        expect(portion.items.single.tags.map((tag) => tag.id), [
          _fixtureTag(firstTagNumber),
        ]);
        expect(portion.nextCursor, isNotNull);
        expect(_storedFilterFailureGraph(raw), before);
        expect(_connectionChanges(raw), changesBefore);
      });
    }
  }
}

Matcher _reconciliationDiagnostics(
  Matcher status, {
  CatalogReconciliationReadCompletion? completion,
}) => isA<CatalogReconciliationReadDiagnosticsEvent>()
    .having((event) => event.pageSize, 'размер порции', 1)
    .having((event) => event.completion, 'завершение', completion)
    .having((event) => event.status, 'статус', status);

TagId _fixtureTag(int number) =>
    (TagId.decode(tagFixtureId(number)) as TagIdDecodingSuccess).id;

Map<String, List<List<Object?>>> _storedFilterFailureGraph(Database raw) => {
  ...retainedTagFixtureGraph(raw),
  for (final table in ['tags', 'tag_assignments', 'sqlite_sequence'])
    table: raw
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => row.values.toList())
        .toList(),
};

int _connectionChanges(Database raw) =>
    raw.select('SELECT total_changes() AS count').single['count'] as int;

enum _CatalogFailurePoint { count, rows, tags }

final class _CatalogFilterFailureObserver
    extends LocalDatabaseConnectionObserver {
  _CatalogFilterFailureObserver(this.point, this.failure);

  final _CatalogFailurePoint point;
  final Object failure;
  var _armed = false;
  var hasFailed = false;

  void arm() => _armed = true;

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_armed || hasFailed) return;
    final sql = statement.statements.single;
    final matches = switch (point) {
      _CatalogFailurePoint.count =>
        sql.contains('json_each(') && sql.startsWith('SELECT COUNT('),
      _CatalogFailurePoint.rows =>
        sql.contains('json_each(') && sql.contains('LIMIT'),
      _CatalogFailurePoint.tags => sql.contains('FROM tag_assignments a'),
    };
    if (matches) {
      hasFailed = true;
      throw failure;
    }
  }
}
