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
    (_CatalogFailurePoint.afterInsert, 'после вставки условий'),
    (_CatalogFailurePoint.read, 'при чтении после вставок'),
    (_CatalogFailurePoint.beforeCleanup, 'перед очисткой условий'),
    (_CatalogFailurePoint.afterCleanup, 'после удаления условий'),
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
          for (final table in [
            'doable_catalog_required_tags',
            'doable_catalog_excluded_tags',
          ]) {
            expect(raw.select('SELECT * FROM temp.$table'), isEmpty);
          }
        });
      }
    }
  }
}

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

enum _CatalogFailurePoint { afterInsert, read, beforeCleanup, afterCleanup }

final class _CatalogFilterFailureObserver
    extends LocalDatabaseConnectionObserver {
  _CatalogFilterFailureObserver(this.point, this.failure);

  final _CatalogFailurePoint point;
  final Object failure;
  var _armed = false;
  var hasFailed = false;
  var _requiredDeletes = 0;

  void arm() => _armed = true;

  @override
  void beforeStatement(LocalDatabaseSqlStatement statement) {
    if (!_armed || hasFailed) return;
    if (statement.statements.single ==
        'DELETE FROM temp.doable_catalog_required_tags') {
      _requiredDeletes++;
      if (point == _CatalogFailurePoint.beforeCleanup &&
          _requiredDeletes == 2) {
        _fail();
      }
    }
  }

  @override
  void afterStatement(LocalDatabaseSqlStatement statement) {
    if (!_armed || hasFailed) return;
    final sql = statement.statements.single;
    if ((point == _CatalogFailurePoint.afterInsert &&
            sql.startsWith('INSERT INTO temp.doable_catalog_excluded_tags')) ||
        (point == _CatalogFailurePoint.afterCleanup &&
            sql == 'DELETE FROM temp.doable_catalog_required_tags' &&
            _requiredDeletes == 2) ||
        (point == _CatalogFailurePoint.read &&
            sql.contains('FROM tag_assignments a'))) {
      _fail();
    }
  }

  Never _fail() {
    hasFailed = true;
    throw failure;
  }
}
