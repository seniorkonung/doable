import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_day_statuses.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_state.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_day_marks_view_model.dart';
import 'package:doable/src/daily_choice/presentation/catalog/daily_choice_calendar_viewport.dart';
import 'package:doable/src/graph/application/graph_command_coordinator.dart';
import 'package:doable/src/graph/application/graph_command_result.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/graph/application/personal_graph_repository_provider.dart';
import 'package:doable/src/tag/application/tag_change.dart';
import 'package:doable/src/tag/application/tag_command.dart';
import 'package:doable/src/tag/application/tag_result.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('начальное окно задано выбранной датой, просмотр внутри месяца и '
      'смена представления после успеха не перечитывают отметки', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    expect(harness.state.dayStatuses, isNull);
    expect(harness.state.hasReadFailure, isFalse);
    expect(harness.repository.queries.single.firstDate, _date(8, 31));
    expect(harness.repository.queries.single.lastDate, _date(12, 6));

    harness.repository.succeed(0, {
      _initialDate: DailyChoiceDayStatus.hasIncomplete,
    });
    await pumpEventQueue();
    expect(harness.marks, {_initialDate: DailyChoiceDayStatus.hasIncomplete});

    harness.model.setViewport(_viewport(10, 13));
    harness.model.setViewport(_viewport(10, 13, DailyChoiceCalendarMode.month));
    await pumpEventQueue();
    expect(harness.repository.queries, hasLength(1));
  });

  test(
    'смена окна в полёте сохраняет прежние отметки, отбрасывает поздний '
    'ответ и читает только последнее окно без параллельных запросов',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      final novemberMark = _date(11, 30);
      final decemberMark = _date(12, 15);
      harness.repository.succeed(0, {
        novemberMark: DailyChoiceDayStatus.hasIncomplete,
      });
      await pumpEventQueue();

      harness.model.setViewport(_viewport(11, 1));
      harness.model.setViewport(_viewport(12, 1));
      expect(harness.repository.queries, hasLength(2));
      expect(harness.marks, {novemberMark: DailyChoiceDayStatus.hasIncomplete});
      harness.repository.succeed(1, {
        novemberMark: DailyChoiceDayStatus.allCompleted,
      });
      await pumpEventQueue();
      expect(harness.repository.queries, hasLength(3));
      expect(harness.repository.queries.last.firstDate, _date(10, 26));
      expect(
        harness.repository.queries.last.lastDate,
        CalendarDate.fromParts(2027, 1, 31),
      );
      expect(harness.marks, {novemberMark: DailyChoiceDayStatus.hasIncomplete});

      harness.repository.succeed(2, {
        decemberMark: DailyChoiceDayStatus.hasIncomplete,
      });
      await pumpEventQueue();
      expect(harness.marks, {decemberMark: DailyChoiceDayStatus.hasIncomplete});
    },
  );

  test('новая ревизия от изменения тега обновляет отметки, а отказ команды '
      'и подтверждение без изменения ревизии не перечитывают их', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.succeed(0, {
      _initialDate: DailyChoiceDayStatus.hasIncomplete,
    });
    await pumpEventQueue();

    await harness.renameTag(1, unchanged: true);
    await harness.renameTag(1, failure: true);
    expect(harness.repository.queries, hasLength(1));

    await harness.renameTag(2);
    expect(harness.repository.queries, hasLength(2));
    expect(harness.marks, {_initialDate: DailyChoiceDayStatus.hasIncomplete});
    expect(harness.state.hasReadFailure, isFalse);
    harness.repository.succeed(1, {
      _initialDate: DailyChoiceDayStatus.allCompleted,
    }, revision: 2);
    await pumpEventQueue();
    expect(harness.marks, {_initialDate: DailyChoiceDayStatus.allCompleted});
  });

  test('ревизии, подтверждённые до первого ответа, объединяются в одно '
      'последующее чтение, устаревшие отметки не публикуются', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.renameTag(2);
    await harness.renameTag(3);
    expect(harness.repository.queries, hasLength(1));

    harness.repository.succeed(0, {
      _initialDate: DailyChoiceDayStatus.hasIncomplete,
    });
    await pumpEventQueue();
    expect(harness.marks, isNull);
    expect(harness.repository.queries, hasLength(2));
    harness.repository.succeed(1, {
      _initialDate: DailyChoiceDayStatus.allCompleted,
    }, revision: 3);
    await pumpEventQueue();
    expect(harness.marks, {_initialDate: DailyChoiceDayStatus.allCompleted});
    expect(harness.repository.queries, hasLength(2));
  });

  test(
    'отказ обновления сохраняет отметки, изменения недели и представления '
    'повторяют чтение, успех целиком заменяет результат и снимает отказ',
    () async {
      final harness = _Harness();
      addTearDown(harness.dispose);
      harness.repository.succeed(0, {
        _initialDate: DailyChoiceDayStatus.hasIncomplete,
      });
      await pumpEventQueue();
      harness.model.setViewport(_viewport(11, 1));
      harness.repository.fail(1);
      await pumpEventQueue();
      expect(harness.marks, {_initialDate: DailyChoiceDayStatus.hasIncomplete});
      expect(harness.state.hasReadFailure, isTrue);
      expect(harness.repository.queries, hasLength(2));

      harness.model.setViewport(_viewport(11, 1));
      expect(harness.repository.queries, hasLength(2));
      harness.model.setViewport(_viewport(11, 8));
      expect(harness.repository.queries, hasLength(3));
      expect(harness.state.hasReadFailure, isTrue);
      expect(harness.marks, {_initialDate: DailyChoiceDayStatus.hasIncomplete});
      harness.repository.fail(2);
      await pumpEventQueue();
      harness.model.setViewport(
        _viewport(11, 8, DailyChoiceCalendarMode.month),
      );
      expect(harness.repository.queries, hasLength(4));
      harness.repository.succeed(3, {});
      await pumpEventQueue();
      expect(harness.marks, isEmpty);
      expect(harness.state.hasReadFailure, isFalse);
    },
  );

  test('отказ первого чтения оставляет дни без отметок, новая ревизия '
      'повторяет чтение и восстанавливает состояние', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.repository.fail(0);
    await pumpEventQueue();
    expect(harness.marks, isNull);
    expect(harness.state.hasReadFailure, isTrue);

    await harness.renameTag(2);
    expect(harness.repository.queries, hasLength(2));
    expect(harness.state.hasReadFailure, isTrue);
    harness.repository.succeed(1, {
      _initialDate: DailyChoiceDayStatus.allCompleted,
    }, revision: 2);
    await pumpEventQueue();
    expect(harness.marks, {_initialDate: DailyChoiceDayStatus.allCompleted});
    expect(harness.state.hasReadFailure, isFalse);
  });

  test('освобождение модели прекращает подписку, поздний ответ не публикуется '
      'и не продолжает чтение', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    harness.model.setViewport(_viewport(11, 1));
    harness.subscription.close();
    await harness.container.pump();
    await harness.renameTag(2);
    harness.repository.succeed(0, {
      _initialDate: DailyChoiceDayStatus.hasIncomplete,
    });
    await pumpEventQueue();
    expect(harness.repository.queries, hasLength(1));
  });
}

final _initialDate = _date(10, 6);

CalendarDate _date(int month, int day) =>
    CalendarDate.fromParts(2026, month, day);

DailyChoiceCalendarViewport _viewport(
  int month,
  int day, [
  DailyChoiceCalendarMode mode = DailyChoiceCalendarMode.week,
]) => DailyChoiceCalendarViewport(focusedDate: _date(month, day), mode: mode);

final class _Harness {
  _Harness() {
    container = ProviderContainer(
      overrides: [
        personalGraphRepositoryProvider.overrideWith((ref) => repository),
      ],
    );
    subscription = container.listen(provider, (_, _) {});
  }

  final repository = _Repository();
  final provider = dailyChoiceCalendarDayMarksViewModelProvider(_initialDate);
  late final ProviderContainer container;
  late final ProviderSubscription<DailyChoiceCalendarDayMarksState>
  subscription;
  var _tag = Tag(
    id: (TagId.decode(
      '00000000-0000-4000-8000-000000000001',
    ) as TagIdDecodingSuccess).id,
    name: TagName.fromInput('Дом'),
  );

  DailyChoiceCalendarDayMarksViewModel get model =>
      container.read(provider.notifier);
  DailyChoiceCalendarDayMarksState get state => container.read(provider);
  Map<CalendarDate, DailyChoiceDayStatus>? get marks =>
      state.dayStatuses?.statuses;

  Future<void> renameTag(
    int revision, {
    bool unchanged = false,
    bool failure = false,
  }) async {
    final next = Tag(
      id: _tag.id,
      name: unchanged ? _tag.name : TagName.fromInput('Тег $revision'),
    );
    final graphRevision = _Revision(revision);
    repository.commandResult = failure
        ? const TagCommandFailed(TagUnavailableFailure())
        : TagCommandSucceeded(
            ConfirmedGraphResult(
              revision: graphRevision,
              value: unchanged
                  ? TagUnchanged(
                      TagUnchangedChange(revision: graphRevision, tag: _tag),
                    )
                  : TagRenamed(
                      TagRenamedChange(
                        revision: graphRevision,
                        before: _tag,
                        after: next,
                      ),
                    ),
            ),
          );
    final coordinator = container.read(
      graphCommandCoordinatorProvider.notifier,
    );
    final accepted = coordinator.acceptTagRename(
      RenameTag(tagId: _tag.id, name: next.name),
    ) as TagCommandAccepted;
    await accepted.future;
    if (!failure) _tag = next;
    await pumpEventQueue();
  }

  void dispose() => container.dispose();
}

final class _Repository implements PersonalGraphRepository {
  final queries = <DailyChoiceDayStatusQuery>[];
  final _reads = <Completer<DailyChoiceDayStatusesReadResult>>[];
  late TagCommandResult commandResult;

  @override
  Future<DailyChoiceDayStatusesReadResult> getDailyChoiceDayStatuses(
    DailyChoiceDayStatusQuery query,
  ) {
    queries.add(query);
    final read = Completer<DailyChoiceDayStatusesReadResult>();
    _reads.add(read);
    return read.future;
  }

  void succeed(
    int index,
    Map<CalendarDate, DailyChoiceDayStatus> statuses, {
    int revision = 1,
  }) => _reads[index].complete(
    DailyChoiceDayStatusesReadSuccess(
      GraphSnapshot(
        revision: _Revision(revision),
        value: DailyChoiceDayStatuses(
          query: queries[index],
          statuses: statuses,
        ),
      ),
    ),
  );

  void fail(int index) => _reads[index].complete(
    const DailyChoiceDayStatusesReadError(DailyChoiceDayStatusesReadFailure()),
  );

  @override
  Future<GraphCommandResult<T, F>>
  execute<T extends GraphCommandOutcome, F extends GraphCommandFailure>(
    GraphCommand<T, F> command,
  ) async => commandResult as GraphCommandResult<T, F>;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is! _Revision
      ? GraphRevisionOrder.differentEpoch
      : value < other.value
      ? GraphRevisionOrder.older
      : value > other.value
      ? GraphRevisionOrder.newer
      : GraphRevisionOrder.same;
}
