import 'dart:io';

import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/application/intention_command.dart';
import 'package:doable/src/intention/application/intention_catalog.dart';
import 'package:doable/src/intention/application/intention_details.dart';
import 'package:doable/src/intention/application/intention_result.dart';
import 'package:doable/src/intention/application/title_search_key.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/intention/domain/intention_text.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('поисковый ключ названия намерения', () {
    test('использует полный Unicode Default Case Folding 17.0.0', () {
      expect(unicodeDefaultCaseFoldingVersion, '17.0.0');
      expect(titleSearchKey('КУПИТЬ МОЛОКО'), 'купить молоко');
      expect(titleSearchKey('Straße'), 'strasse');
      expect(titleSearchKey('K'), 'k');
      expect(titleSearchKey('Σςσ'), 'σσσ');
      expect(titleSearchKey('ꭰᎠ'), 'ᎠᎠ');
      expect(titleSearchKey('𐐀'), '𐐨');
      expect(titleSearchKey('İ'), 'i̇');
      expect(titleSearchKey('Istanbul'), 'istanbul');
      expect(titleSearchKey('ışık'), 'ışık');
      expect(titleSearchKey('еé'), 'еé');
    });

    test('сопоставляет фильтр с названием через единый поисковый ключ', () {
      final filter = IntentionCatalogQuery(
        scope: IntentionScope.all,
        titleFilter: 'STRASSE',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
      ).titleFilter!;

      expect(filter.matchesTitle('Прогуляться по Straße'), isTrue);
      expect(filter.matchesTitle('Istanbul'), isFalse);
      expect(
        IntentionCatalogQuery(
          scope: IntentionScope.all,
          titleFilter: 'ı',
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        ).titleFilter!.matchesTitle('ışık'),
        isTrue,
      );
    });

    test(
      'повторяет весь закреплённый corpus Unicode Default Case Folding',
      () async {
        final lines = await File('test/fixtures/unicode/CaseFolding-17.0.0.txt')
            .readAsLines();
        var mappingCount = 0;

        for (final line in lines) {
          if (line.isEmpty || line.startsWith('#')) {
            continue;
          }
          final fields = line.split(';');
          final status = fields[1].trim();
          if (status != 'C' && status != 'F') {
            continue;
          }

          final input = int.parse(fields[0].trim(), radix: 16);
          final expected = String.fromCharCodes(
            fields[2]
                .trim()
                .split(RegExp(r'\s+'))
                .map((codePoint) => int.parse(codePoint, radix: 16)),
          );

          expect(
            titleSearchKey(String.fromCharCode(input)),
            expected,
            reason: 'U+${input.toRadixString(16).toUpperCase()}',
          );
          mappingCount++;
        }

        expect(mappingCount, 1585);
      },
    );
  });

  group('контракт каталога намерений', () {
    test(
      'нормализует фильтр, ограничивает порцию и применяет scope с фильтром',
      () {
        final query = IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: '  БЫТЬ ЗДОРОВЫМ  ',
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        );
        final active = _summary(
          id: '00000000-0000-4000-8000-000000000001',
          title: 'Быть здоровым',
        );
        final archived = _summary(
          id: '00000000-0000-4000-8000-000000000002',
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
        );

        expect(query.titleFilter, isA<IntentionTitleFilter>());
        expect(query.titleFilter!.matchesTitle('Быть здоровым'), isTrue);
        expect(query.pageSize, 1);
        expect(query.includes(active), isTrue);
        expect(query.includes(archived), isFalse);
        expect(
          IntentionCatalogQuery(
            scope: IntentionScope.all,
            titleFilter: '  \n\t ',
            order: IntentionCatalogOrder.createdAtDescending,
            pageSize: 100,
          ).titleFilter,
          isNull,
        );
      },
    );

    test('принимает границы page size и фильтра из 255 графем', () {
      final titleFilter = List.filled(255, '👩🏽‍💻').join();

      expect(
        () => IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: titleFilter,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 1,
        ),
        returnsNormally,
      );
      expect(
        () => IntentionCatalogQuery(
          scope: IntentionScope.active,
          titleFilter: titleFilter,
          order: IntentionCatalogOrder.createdAtDescending,
          pageSize: 100,
        ),
        returnsNormally,
      );
    });

    test('отклоняет выходящие за границы размер порции и фильтр', () {
      expect(
        () => _query(pageSize: 0),
        _throwsQueryFailure(
          IntentionCatalogQueryValidationFailure.pageSizeOutOfRange,
        ),
      );
      expect(
        () => _query(pageSize: 101),
        _throwsQueryFailure(
          IntentionCatalogQueryValidationFailure.pageSizeOutOfRange,
        ),
      );
      expect(
        () => _query(titleFilter: List.filled(256, '👩🏽‍💻').join()),
        _throwsQueryFailure(
          IntentionCatalogQueryValidationFailure.titleFilterTooLong,
        ),
      );
    });

    test('отклоняет некорректный Unicode фильтра до поиска', () {
      final invalidValues = [
        '\u0000',
        String.fromCharCode(0xd800),
        String.fromCharCode(0xdc00),
      ];

      for (final invalidValue in invalidValues) {
        expect(
          () => _query(titleFilter: 'до$invalidValueпосле'),
          _throwsInvalidUnicodeFilter(),
        );
      }
    });

    test('отклоняет некорректное название до case folding', () {
      final filter = _query(titleFilter: 'здоровье').titleFilter!;

      expect(
        () => filter.matchesTitle('Здоровье\u0000'),
        throwsA(
          isA<IntentionTextValidationException>()
              .having(
                (exception) => exception.failure.field,
                'field',
                IntentionTextField.title,
              )
              .having(
                (exception) => exception.failure.reason,
                'reason',
                IntentionTextValidationReason.invalidUnicodeRepertoire,
              ),
        ),
      );
    });

    test('сохраняет корректный Unicode фильтра без нормализации', () {
      const filter = 'е\u0301\t👩🏽‍💻\nтекст';
      final query = _query(titleFilter: filter);

      expect(query.titleFilter!.map((value) => value), filter);
    });

    test('сравнивает summaries полным порядком времени и идентификатора', () {
      final query = _query();
      final newer = _summary(
        id: '00000000-0000-4000-8000-000000000002',
        createdAt: DateTime.utc(2026, 8, 30, 13),
      );
      final older = _summary(
        id: '00000000-0000-4000-8000-000000000001',
        createdAt: DateTime.utc(2026, 8, 30, 12),
      );
      final sameTimeLaterId = _summary(
        id: '00000000-0000-4000-8000-000000000003',
        createdAt: DateTime.utc(2026, 8, 30, 13),
      );

      expect(query.compare(newer, older), isNegative);
      expect(query.compare(newer, sameTimeLaterId), isNegative);
      expect(query.compare(sameTimeLaterId, newer), isPositive);
    });

    test('выражает три scope и четыре сочетания поля с направлением', () {
      final active = _summary(
        id: '00000000-0000-4000-8000-000000000001',
        createdAt: DateTime.utc(2026, 8, 30, 12),
        updatedAt: DateTime.utc(2026, 8, 30, 14),
      );
      final archived = _summary(
        id: '00000000-0000-4000-8000-000000000002',
        archiveState: IntentionArchiveState.archived,
        createdAt: DateTime.utc(2026, 8, 30, 13),
        updatedAt: DateTime.utc(2026, 8, 30, 13),
      );

      expect(_queryForScope(IntentionScope.active).includes(active), isTrue);
      expect(_queryForScope(IntentionScope.active).includes(archived), isFalse);
      expect(_queryForScope(IntentionScope.archived).includes(active), isFalse);
      expect(
        _queryForScope(IntentionScope.archived).includes(archived),
        isTrue,
      );
      expect(_queryForScope(IntentionScope.all).includes(active), isTrue);
      expect(_queryForScope(IntentionScope.all).includes(archived), isTrue);

      expect(
        _order(
          IntentionCatalogSortField.createdAt,
          IntentionCatalogSortDirection.ascending,
        ).compare(active, archived),
        isNegative,
      );
      expect(
        _order(
          IntentionCatalogSortField.createdAt,
          IntentionCatalogSortDirection.descending,
        ).compare(active, archived),
        isPositive,
      );
      expect(
        _order(
          IntentionCatalogSortField.updatedAt,
          IntentionCatalogSortDirection.ascending,
        ).compare(active, archived),
        isPositive,
      );
      expect(
        _order(
          IntentionCatalogSortField.updatedAt,
          IntentionCatalogSortDirection.descending,
        ).compare(active, archived),
        isNegative,
      );
    });

    test('передаёт opaque cursor без раскрытия его реализации', () {
      const cursor = _TestCatalogCursor();

      final continuation = IntentionCatalogQuery(
        scope: IntentionScope.active,
        titleFilter: 'здоровье',
        order: IntentionCatalogOrder.createdAtDescending,
        pageSize: 1,
        cursor: cursor,
      );

      expect(continuation.cursor, same(cursor));
    });

    test(
      'различает sealed первую и последующую страницы без nullable count',
      () {
        final summary = _summary(id: '00000000-0000-4000-8000-000000000001');
        const cursor = _TestCatalogCursor();
        const revision = _TestGraphRevision(epoch: 'первая', sequence: 0);
        final pages = <IntentionCatalogPage>[
          IntentionCatalogFirstPage(
            items: [summary],
            totalCount: 2,
            nextCursor: cursor,
            revision: revision,
          ),
          IntentionCatalogContinuationPage(
            items: const [],
            nextCursor: null,
            revision: revision,
          ),
        ];

        expect(pages.map(_pageDescription), ['first:2', 'continuation']);
        expect(pages.map((page) => page.revision), everyElement(revision));
      },
    );

    test('сравнимая revision различает порядок и process-local эпоху', () {
      const first = _TestGraphRevision(epoch: 'первая', sequence: 0);
      const second = _TestGraphRevision(epoch: 'первая', sequence: 1);
      const anotherEpoch = _TestGraphRevision(epoch: 'вторая', sequence: 0);

      expect(first.compareTo(second), GraphRevisionOrder.older);
      expect(second.compareTo(first), GraphRevisionOrder.newer);
      expect(second.compareTo(second), GraphRevisionOrder.same);
      expect(first.compareTo(anotherEpoch), GraphRevisionOrder.differentEpoch);
    });

    test('первая страница отклоняет недопустимый total count в release', () {
      final summary = _summary(id: '00000000-0000-4000-8000-000000000001');

      expect(
        () => IntentionCatalogFirstPage(
          items: [summary],
          totalCount: 0,
          nextCursor: null,
          revision: const _TestGraphRevision(epoch: 'первая', sequence: 0),
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
      );
      expect(
        () => IntentionCatalogFirstPage(
          items: const [],
          totalCount: -1,
          nextCursor: null,
          revision: const _TestGraphRevision(epoch: 'первая', sequence: 0),
        ),
        throwsA(isA<IntentionCatalogPageValidationException>()),
      );
    });

    test(
      'summary сохраняет показание изменения после перевода часов назад',
      () {
        final summary = _summary(
          id: '00000000-0000-4000-8000-000000000001',
          createdAt: DateTime.utc(2026, 8, 30, 12),
          updatedAt: DateTime.utc(2026, 8, 30, 11),
        );

        expect(summary.createdAt.value, DateTime.utc(2026, 8, 30, 12));
        expect(summary.updatedAt.value, DateTime.utc(2026, 8, 30, 11));
      },
    );
  });

  group('commands и результаты намерений', () {
    test(
      'закрытый набор commands несёт только необходимые предметные данные',
      () {
        final id = _intentionId('00000000-0000-4000-8000-000000000001');
        final commands = <IntentionCommand>[
          const CreateIntention(title: 'Здоровье', description: null),
          UpdateIntention(
            id: id,
            title: 'Быть здоровым',
            description: 'Каждый день',
          ),
          EnableIntentionReadiness(id),
          DisableIntentionReadiness(id),
          ArchiveIntention(id),
          RestoreIntention(id),
          DeleteIntention(id),
        ];

        expect(commands.map(_commandDescription), [
          'create',
          'update',
          'enableReadiness',
          'disableReadiness',
          'archive',
          'restore',
          'delete',
        ]);
      },
    );

    test('saved, deleted и failures имеют исчерпывающие типы', () {
      final intention = _intention();
      final entry = _TestCatalogEntrySnapshot(
        _summary(id: intention.id.toCanonicalString()),
      );
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 1);
      final results = <Result<IntentionCommandSuccess>>[
        ResultSuccess(
          IntentionSaved(
            intention,
            catalogMutation: IntentionCatalogCreated(
              revision: revision,
              entry: entry,
            ),
          ),
        ),
        ResultSuccess(
          IntentionDeleted(
            intention.id,
            catalogMutation: IntentionCatalogDeleted(
              revision: revision,
              entry: entry,
            ),
          ),
        ),
        const ResultFailure(IntentionGenericValidationFailure()),
        const ResultFailure(IntentionNotFoundFailure()),
        const ResultFailure(IntentionConflictFailure()),
        const ResultFailure(IntentionUnavailableFailure()),
        const ResultFailure(IntentionCorruptionFailure()),
        const ResultFailure(IntentionUnexpectedFailure()),
      ];

      expect(
        results.whereType<ResultSuccess<IntentionCommandSuccess>>(),
        hasLength(2),
      );
      expect(
        results.whereType<ResultFailure<IntentionCommandSuccess>>(),
        hasLength(6),
      );
      expect(_resultSuccessDescription(results[0]), 'saved');
      expect(_resultSuccessDescription(results[1]), 'deleted');
      expect(results.skip(2).map(_resultFailureDescription), [
        'validation',
        'notFound',
        'conflict',
        'unavailable',
        'corruption',
        'unexpected',
      ]);
      expect(
        const IntentionUnexpectedFailure().code,
        IntentionFailureCode.unexpected,
      );
    });

    test('sealed catalog mutations выражают допустимые before и after', () {
      final before = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );
      final after = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 1);
      final mutations = <IntentionCatalogMutation>[
        IntentionCatalogCreated(revision: revision, entry: after),
        IntentionCatalogUpdated(
          revision: revision,
          before: before,
          after: after,
        ),
        IntentionCatalogDeleted(revision: revision, entry: before),
        IntentionCatalogUnchanged(revision: revision, entry: before),
      ];

      expect(mutations.map(_mutationDescription), [
        'created',
        'updated',
        'deleted',
        'unchanged',
      ]);
      expect(mutations[0].before, isNull);
      expect(mutations[0].after, same(after));
      expect(mutations[1].before, same(before));
      expect(mutations[1].after, same(after));
      expect(mutations[2].before, same(before));
      expect(mutations[2].after, isNull);
      expect(mutations[3].before, same(before));
      expect(mutations[3].after, same(before));
    });
  });

  group('общая граница личного графа', () {
    test('выражает чтения намерений и их счётчиков', () async {
      final PersonalGraphRepository repository =
          _FailingPersonalGraphRepository();
      final id = _intentionId('00000000-0000-4000-8000-000000000001');

      expect(
        await repository.getCatalogPage(_query()),
        isA<ResultFailure<IntentionCatalogPage>>(),
      );
      expect(
        await repository.getRelationCounts(id),
        isA<ResultFailure<GraphSnapshot<RelationCounts>>>(),
      );
      await expectLater(
        repository.watchIntention(id),
        emits(
          isA<ResultFailure<GraphSnapshot<IntentionDetails?>>>().having(
            (result) => result.failure,
            'failure',
            isA<IntentionUnavailableFailure>(),
          ),
        ),
      );
      expect(
        await repository.execute(
          const CreateIntention(title: 'Здоровье', description: null),
        ),
        isA<ResultFailure<ConfirmedGraphResult<IntentionCommandSuccess>>>(),
      );
    });

    test('снимок связывает подтверждённое значение с одной ревизией', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 3);
      final intention = _intention();
      final snapshot = GraphSnapshot(value: intention, revision: revision);

      expect(snapshot.value, same(intention));
      expect(snapshot.revision, same(revision));
    });

    test('пакет результата неизменно объединяет снимки одной ревизии', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
      final before = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );
      final after = _TestCatalogEntrySnapshot(
        _summary(
          id: '00000000-0000-4000-8000-000000000001',
          title: 'Быть здоровым',
        ),
      );
      final mutation = IntentionCatalogUpdated(
        revision: revision,
        before: before,
        after: after,
      );
      final success = IntentionSaved(_intention(), catalogMutation: mutation);
      final result = ConfirmedGraphResult(revision: revision, value: success);

      expect(result.revision, same(revision));
      expect(result.value, same(success));
      expect(result.changes, hasLength(1));
      expect(
        () => result.changes.add(
          IntentionCatalogUnchanged(revision: revision, entry: after),
        ),
        throwsUnsupportedError,
      );
    });

    test('пакет намерения включает неизменяемые абсолютные счётчики', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
      final intention = _intention();
      final entry = _TestCatalogEntrySnapshot(
        _summary(id: intention.id.toCanonicalString()),
      );
      final mutation = IntentionCatalogUpdated(
        revision: revision,
        before: entry,
        after: entry,
      );
      final countChange = IntentionRelationCountsChanged(
        revision: revision,
        intentionId: intention.id,
        counts: RelationCounts(
          activeNeedIncoming: 0,
          activeNeedOutgoing: 0,
          activeCanIncoming: 0,
          activeCanOutgoing: 0,
          archivedNeedIncoming: 1,
          archivedNeedOutgoing: 0,
          archivedCanIncoming: 0,
          archivedCanOutgoing: 0,
        ),
      );
      final success = IntentionSaved(
        intention,
        catalogMutation: mutation,
        additionalChanges: [countChange],
      );
      final result = ConfirmedGraphResult(revision: revision, value: success);

      expect(result.changes, [mutation, countChange]);
      expect(
        () => success.additionalChanges.add(mutation),
        throwsUnsupportedError,
      );
    });

    test('пакет результата отклоняет изменение другой ревизии', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);
      const newerRevision = _TestGraphRevision(epoch: 'первая', sequence: 5);
      final entry = _TestCatalogEntrySnapshot(
        _summary(id: '00000000-0000-4000-8000-000000000001'),
      );

      expect(
        () => ConfirmedGraphResult(
          revision: revision,
          value: IntentionSaved(
            _intention(),
            catalogMutation: IntentionCatalogCreated(
              revision: newerRevision,
              entry: entry,
            ),
          ),
        ),
        throwsA(isA<ConfirmedGraphResultValidationException>()),
      );
    });

    test('пакет подтверждённого результата не бывает пустым', () {
      const revision = _TestGraphRevision(epoch: 'первая', sequence: 4);

      expect(
        () => ConfirmedGraphResult(
          revision: revision,
          value: const _EmptyGraphCommandOutcome(),
        ),
        throwsA(
          isA<ConfirmedGraphResultValidationException>().having(
            (exception) => exception.failure,
            'failure',
            ConfirmedGraphResultValidationFailure.emptyChanges,
          ),
        ),
      );
    });
  });
}

IntentionCatalogQuery _query({int pageSize = 100, String? titleFilter}) =>
    IntentionCatalogQuery(
      scope: IntentionScope.active,
      titleFilter: titleFilter,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: pageSize,
    );

IntentionCatalogQuery _queryForScope(IntentionScope scope) =>
    IntentionCatalogQuery(
      scope: scope,
      titleFilter: null,
      order: IntentionCatalogOrder.createdAtDescending,
      pageSize: 100,
    );

IntentionCatalogQuery _order(
  IntentionCatalogSortField field,
  IntentionCatalogSortDirection direction,
) => IntentionCatalogQuery(
  scope: IntentionScope.all,
  titleFilter: null,
  order: IntentionCatalogOrder(field: field, direction: direction),
  pageSize: 100,
);

IntentionSummary _summary({
  required String id,
  String title = 'Здоровье',
  IntentionArchiveState archiveState = IntentionArchiveState.active,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  final created = IntentionTimestamp(
    createdAt ?? DateTime.utc(2026, 8, 30, 12),
  );
  return IntentionSummary(
    id: _intentionId(id),
    title: title,
    hasDescription: false,
    readiness: IntentionReadiness.notReady,
    archiveState: archiveState,
    activeRelationCount: 0,
    createdAt: created,
    updatedAt: IntentionTimestamp(updatedAt ?? created.value),
  );
}

Intention _intention() {
  final timestamp = IntentionTimestamp(DateTime.utc(2026, 8, 30, 12));
  return Intention(
    id: _intentionId('00000000-0000-4000-8000-000000000001'),
    title: 'Здоровье',
    description: null,
    readiness: IntentionReadiness.notReady,
    archiveState: IntentionArchiveState.active,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

String _pageDescription(IntentionCatalogPage page) => switch (page) {
  IntentionCatalogFirstPage(:final totalCount) => 'first:$totalCount',
  IntentionCatalogContinuationPage() => 'continuation',
};

String _successDescription(IntentionCommandSuccess success) =>
    switch (success) {
      IntentionSaved() => 'saved',
      IntentionDeleted() => 'deleted',
    };

String _mutationDescription(IntentionCatalogMutation mutation) =>
    switch (mutation) {
      IntentionCatalogCreated() => 'created',
      IntentionCatalogUpdated() => 'updated',
      IntentionCatalogDeleted() => 'deleted',
      IntentionCatalogUnchanged() => 'unchanged',
    };

String _commandDescription(IntentionCommand command) => switch (command) {
  CreateIntention() => 'create',
  UpdateIntention() => 'update',
  EnableIntentionReadiness() => 'enableReadiness',
  DisableIntentionReadiness() => 'disableReadiness',
  ArchiveIntention() => 'archive',
  RestoreIntention() => 'restore',
  DeleteIntention() => 'delete',
};

String _failureDescription(IntentionFailure failure) => switch (failure) {
  IntentionValidationFailure() => 'validation',
  IntentionNotFoundFailure() => 'notFound',
  IntentionConflictFailure() => 'conflict',
  IntentionUnavailableFailure() => 'unavailable',
  IntentionCorruptionFailure() => 'corruption',
  IntentionUnexpectedFailure() => 'unexpected',
};

String _resultSuccessDescription(Result<IntentionCommandSuccess> result) =>
    switch (result) {
      ResultSuccess(:final value) => _successDescription(value),
      ResultFailure() => throw StateError('Ожидался успешный результат.'),
    };

String _resultFailureDescription(Result<IntentionCommandSuccess> result) =>
    switch (result) {
      ResultSuccess() => throw StateError('Ожидался неуспешный результат.'),
      ResultFailure(:final failure) => _failureDescription(failure),
    };

Matcher _throwsQueryFailure(IntentionCatalogQueryValidationFailure failure) =>
    throwsA(
      isA<IntentionCatalogQueryValidationException>().having(
        (exception) => exception.failure,
        'failure',
        failure,
      ),
    );

Matcher _throwsInvalidUnicodeFilter() => throwsA(
  isA<IntentionCatalogQueryValidationException>()
      .having(
        (exception) => exception.failure,
        'failure',
        IntentionCatalogQueryValidationFailure.invalidUnicodeRepertoire,
      )
      .having(
        (exception) => exception.textFailure?.field,
        'field',
        IntentionTextField.titleFilter,
      )
      .having(
        (exception) => exception.textFailure?.reason,
        'reason',
        IntentionTextValidationReason.invalidUnicodeRepertoire,
      ),
);

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Ожидался корректный UUID.'),
};

final class _FailingPersonalGraphRepository implements PersonalGraphRepository {
  @override
  Future<Result<ConfirmedGraphResult<IntentionCommandSuccess>>> execute(
    IntentionCommand command,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Future<Result<IntentionCatalogPage>> getCatalogPage(
    IntentionCatalogQuery query,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Future<Result<GraphSnapshot<RelationCounts>>> getRelationCounts(
    IntentionId intentionId,
  ) async => const ResultFailure(IntentionUnavailableFailure());

  @override
  Stream<Result<GraphSnapshot<IntentionDetails?>>> watchIntention(
    IntentionId id,
  ) => Stream.value(const ResultFailure(IntentionUnavailableFailure()));
}

final class _EmptyGraphCommandOutcome implements GraphCommandOutcome {
  const _EmptyGraphCommandOutcome();

  @override
  Iterable<GraphChange> get changes => const [];
}

final class _TestCatalogCursor implements IntentionCatalogCursor {
  const _TestCatalogCursor();
}

final class _TestGraphRevision implements GraphRevision {
  const _TestGraphRevision({required this.epoch, required this.sequence});

  final String epoch;
  final int sequence;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    if (other is! _TestGraphRevision || other.epoch != epoch) {
      return GraphRevisionOrder.differentEpoch;
    }
    return switch (sequence.compareTo(other.sequence)) {
      < 0 => GraphRevisionOrder.older,
      > 0 => GraphRevisionOrder.newer,
      _ => GraphRevisionOrder.same,
    };
  }
}

final class _TestCatalogEntrySnapshot implements IntentionCatalogEntrySnapshot {
  const _TestCatalogEntrySnapshot(this.summary);

  @override
  final IntentionSummary summary;

  @override
  bool matches(IntentionCatalogQuery query) => query.includes(summary);
}
