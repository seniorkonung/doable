import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';

void main() {
  test('запрос по умолчанию охватывает все даты и оба состояния', () {
    final query = DailyChoiceCatalogQuery();

    expect(query.date, isNull);
    expect(query.isCompleted, isNull);
    expect(query.pageSize, 50);
    expect(query.cursor, isNull);
  });

  test('запрос сохраняет явные фильтры и границы порции', () {
    final date = CalendarDate.fromParts(2026, 9, 24);
    const cursor = _Cursor();
    for (final size in [1, 100]) {
      final query = DailyChoiceCatalogQuery(
        date: date,
        isCompleted: false,
        pageSize: size,
        cursor: cursor,
      );
      expect(query.date, date);
      expect(query.isCompleted, false);
      expect(query.pageSize, size);
      expect(query.cursor, same(cursor));
    }
    expect(DailyChoiceCatalogQuery(isCompleted: true).isCompleted, true);
    for (final size in [-1, 0, 101]) {
      expect(
        () => DailyChoiceCatalogQuery(pageSize: size),
        throwsA(
          isA<DailyChoiceCatalogQueryValidationException>().having(
            (error) => error.failure,
            'failure',
            DailyChoiceCatalogQueryValidationFailure.pageSizeOutOfRange,
          ),
        ),
      );
    }
  });

  test('краткая проекция проверяет участников и сохраняет дубликаты', () {
    final source = _participant(
      1,
      ' Основание ',
      IntentionArchiveState.archived,
    );
    final selected = _participant(2, 'Действие', IntentionArchiveState.active);
    final date = CalendarDate.fromParts(2026, 9, 24);
    final first = DailyChoiceCatalogItem(
      id: _choice(1),
      source: source,
      selected: selected,
      date: date,
      isCompleted: true,
    );
    final duplicate = DailyChoiceCatalogItem(
      id: _choice(2),
      source: source,
      selected: selected,
      date: date,
      isCompleted: true,
    );

    expect(first.source.title, 'Основание');
    expect(first.source.archiveState, IntentionArchiveState.archived);
    expect(first.selected.title, 'Действие');
    expect(first.date, date);
    expect(first.isCompleted, true);
    expect(first.id, isNot(duplicate.id));
    expect(
      () => DailyChoiceCatalogItem(
        id: _choice(3),
        source: source,
        selected: source,
        date: date,
        isCompleted: false,
      ),
      throwsArgumentError,
    );
  });

  test('первая порция сохраняет один снимок и неизменяемый список', () async {
    final items = [_item(1), _item(2)];
    final revision = _Revision(7);
    final page = DailyChoiceCatalogFirstPage(
      items: items,
      totalCount: 3,
      nextCursor: const _Cursor(),
      revision: revision,
    );
    final PersonalGraphRepository repository = _Repository(
      DailyChoiceCatalogPageSuccess(page),
    );
    final result = await repository.getDailyChoiceCatalogPage(
      DailyChoiceCatalogQuery(),
    );

    items.clear();
    expect(result, isA<DailyChoiceCatalogPageSuccess>());
    expect(page.items.map((item) => item.id), [_choice(1), _choice(2)]);
    expect(page.totalCount, 3);
    expect(page.revision, same(revision));
    expect(page.nextCursor, isA<DailyChoiceCatalogCursor>());
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => DailyChoiceCatalogFirstPage(
        items: [_item(1)],
        totalCount: 0,
        nextCursor: null,
        revision: revision,
      ),
      throwsA(isA<DailyChoiceCatalogPageValidationException>()),
    );
  });

  test(
    'продолжение не выдаёт новое количество за согласованное с первой порцией',
    () {
      final page = DailyChoiceCatalogContinuationPage(
        items: [_item(3)],
        nextCursor: null,
        revision: _Revision(7),
      );
      expect(page.items.single.id, _choice(3));
      expect(page.nextCursor, isNull);
    },
  );

  test('типизированные исходы различают чужой и устаревший курсор', () {
    const failures = <DailyChoiceCatalogReadFailure>[
      DailyChoiceCatalogValidationFailure(),
      DailyChoiceCatalogSnapshotExpired(),
      DailyChoiceCatalogUnavailableFailure(),
      DailyChoiceCatalogCorruptionFailure(),
      DailyChoiceCatalogUnexpectedFailure(),
    ];
    expect(failures.map((failure) => failure.category), [
      GraphFailureCategory.validation,
      GraphFailureCategory.conflict,
      GraphFailureCategory.unavailable,
      GraphFailureCategory.corruption,
      GraphFailureCategory.unexpected,
    ]);
    for (final failure in failures) {
      final DailyChoiceCatalogPageResult result = DailyChoiceCatalogPageError(
        failure,
      );
      expect(result, isA<DailyChoiceCatalogPageError>());
    }
  });
}

DailyChoiceCatalogItem _item(int value) => DailyChoiceCatalogItem(
  id: _choice(value),
  source: _participant(1, 'Основание', IntentionArchiveState.active),
  selected: _participant(2, 'Действие', IntentionArchiveState.active),
  date: CalendarDate.fromParts(2026, 9, 24),
  isCompleted: false,
);

DailyChoiceCatalogParticipant _participant(
  int value,
  String title,
  IntentionArchiveState archiveState,
) => DailyChoiceCatalogParticipant(
  id: _intention(value),
  title: title,
  archiveState: archiveState,
  readiness: IntentionReadiness.ready,
);

DailyChoiceId _choice(int value) => (DailyChoiceId.decode(
  '00000000-0000-4000-8002-${value.toString().padLeft(12, '0')}',
) as DailyChoiceIdDecodingSuccess).id;

IntentionId _intention(int value) => (IntentionId.decode(
  '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}',
) as IntentionIdDecodingSuccess).id;

final class _Cursor implements DailyChoiceCatalogCursor {
  const _Cursor();
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);

  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => switch (other) {
    _Revision(value: final otherValue) when otherValue == value =>
      GraphRevisionOrder.same,
    _Revision(value: final otherValue) when otherValue < value =>
      GraphRevisionOrder.newer,
    _Revision() => GraphRevisionOrder.older,
    _ => GraphRevisionOrder.differentEpoch,
  };
}

final class _Repository
    with TagReadContractTestFallback
    implements PersonalGraphRepository {
  const _Repository(this.result);

  final DailyChoiceCatalogPageResult result;

  @override
  Future<DailyChoiceCatalogPageResult> getDailyChoiceCatalogPage(
    DailyChoiceCatalogQuery query,
  ) async => result;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
