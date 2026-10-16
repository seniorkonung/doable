import 'package:doable/src/daily_choice/application/daily_choice_catalog.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_priority.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_schedule.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/tag_read_contract_test_fallback.dart';
import '../../support/catalog_reconciliation_test_fallback.dart';

void main() {
  test('размер порции допускает границы 1 и 100 и отвергает остальные', () {
    for (final size in [1, 100]) {
      expect(DailyChoiceCatalogQuery(pageSize: size).pageSize, size);
    }
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

  test(
    'краткая проекция проверяет участников и размер пути, сохраняет дубликаты',
    () {
      final source = _participant(
        1,
        ' Основание ',
        IntentionArchiveState.archived,
      );
      final selected = _participant(
        2,
        'Действие',
        IntentionArchiveState.active,
      );
      final date = CalendarDate.fromParts(2026, 9, 24);
      final first = DailyChoiceCatalogItem(
        id: _choice(1),
        source: source,
        selected: selected,
        date: date,
        isCompleted: true,
        schedule: const DailyChoiceAllDay(),
        priority: DailyChoicePriority.p4,
        description: null,
        pathIntentionCount: 2,
      );
      final duplicate = DailyChoiceCatalogItem(
        id: _choice(2),
        source: source,
        selected: selected,
        date: date,
        isCompleted: true,
        schedule: const DailyChoiceAllDay(),
        priority: DailyChoicePriority.p4,
        description: null,
        pathIntentionCount: 2,
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
          schedule: const DailyChoiceAllDay(),
          priority: DailyChoicePriority.p4,
          description: null,
          pathIntentionCount: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => DailyChoiceCatalogItem(
          id: _choice(3),
          source: source,
          selected: selected,
          date: date,
          isCompleted: false,
          schedule: const DailyChoiceAllDay(),
          priority: DailyChoicePriority.p4,
          description: null,
          pathIntentionCount: 1,
        ),
        throwsArgumentError,
      );
    },
  );

  test('первая порция копирует список и проверяет согласованность', () async {
    final items = [_item(1), _item(2)];
    final revision = _Revision(7);
    final page = DailyChoiceCatalogFirstPage(
      items: items,
      totalCount: 3,
      hasTimedChoices: false,
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
    expect(
      () => DailyChoiceCatalogFirstPage(
        items: [_item(1)],
        totalCount: 0,
        hasTimedChoices: false,
        nextCursor: null,
        revision: revision,
      ),
      throwsA(isA<DailyChoiceCatalogPageValidationException>()),
    );
  });
}

DailyChoiceCatalogItem _item(int value) => DailyChoiceCatalogItem(
  id: _choice(value),
  source: _participant(1, 'Основание', IntentionArchiveState.active),
  selected: _participant(2, 'Действие', IntentionArchiveState.active),
  date: CalendarDate.fromParts(2026, 9, 24),
  isCompleted: false,
  schedule: const DailyChoiceAllDay(),
  priority: DailyChoicePriority.p4,
  description: null,
  pathIntentionCount: 2,
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
    with TagReadContractTestFallback, CatalogReconciliationTestFallback
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
