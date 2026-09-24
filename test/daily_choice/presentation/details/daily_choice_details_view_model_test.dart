import 'dart:async';

import 'package:doable/src/daily_choice/application/daily_choice_details.dart';
import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_state.dart';
import 'package:doable/src/daily_choice/presentation/details/daily_choice_details_view_model.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/graph/application/personal_graph_repository.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'наблюдает нужный выбор, отклоняет старый снимок и закрывает поток',
    () async {
      final repository = _Repository();
      final id = (DailyChoiceId.decode(
        '018f0b5d-6b2e-7c80-8000-000000000001',
      ) as DailyChoiceIdDecodingSuccess).id;
      final model = DailyChoiceDetailsViewModel(repository, id);
      expect(repository.observedId, id);
      repository.emit(null, revision: 2);
      await pumpEventQueue();
      expect(model.state, isA<DailyChoiceDetailsNotFound>());
      repository.emit(_details(id), revision: 1);
      await pumpEventQueue();
      expect(model.state, isA<DailyChoiceDetailsNotFound>());
      model.dispose();
      await pumpEventQueue();
      expect(repository.hasListener, isFalse);
      await repository.dispose();
    },
  );

  test('ошибка чтения не превращается в частичный путь', () async {
    final repository = _Repository();
    final id = (DailyChoiceId.decode(
      '018f0b5d-6b2e-7c80-8000-000000000001',
    ) as DailyChoiceIdDecodingSuccess).id;
    final model = DailyChoiceDetailsViewModel(repository, id);
    addTearDown(() async {
      model.dispose();
      await repository.dispose();
    });
    repository.fail(const DailyChoiceReadCorruptionFailure());
    await pumpEventQueue();
    expect(model.state, isA<DailyChoiceDetailsCorruption>());
  });
}

DailyChoiceDetails _details(DailyChoiceId id) {
  Intention participant(int number) => Intention(
    id: (IntentionId.decode(
      '018f0b5d-6b2e-7c80-8000-${number.toRadixString(16).padLeft(12, '0')}',
    ) as IntentionIdDecodingSuccess).id,
    title: 'Намерение $number',
    description: null,
    readiness: IntentionReadiness.ready,
    archiveState: IntentionArchiveState.active,
    createdAt: IntentionTimestamp(DateTime.utc(2026)),
    updatedAt: IntentionTimestamp(DateTime.utc(2026)),
  );
  final source = participant(1);
  final selected = participant(2);
  final relationId = (LongTermRelationId.decode(
    '018f0b5d-6b2e-7c80-8000-000000000003',
  ) as LongTermRelationIdDecodingSuccess).id;
  final stepId = (ChoicePathStepId.decode(
    '018f0b5d-6b2e-7c80-8000-000000000004',
  ) as ChoicePathStepIdDecodingSuccess).id;
  return DailyChoiceDetails(
    choice: DailyChoice(
      id: id,
      sourceIntentionId: source.id,
      selectedIntentionId: selected.id,
      date: CalendarDate.fromParts(2026, 9, 24),
      description: null,
      isCompleted: false,
    ),
    source: source,
    selected: selected,
    path: [
      DailyChoicePathStepDetails(
        step: ChoicePathStep(
          id: stepId,
          dailyChoiceId: id,
          relationId: relationId,
          previousStepId: null,
        ),
        relation: LongTermRelation(
          id: relationId,
          sourceIntentionId: source.id,
          relatedIntentionId: selected.id,
          type: LongTermRelationType.need,
          priority: RelationPriority.p1,
          scope: RelationScope.active,
          creationSequence: RelationCreationSequence(1),
        ),
        description: null,
        source: source,
        related: selected,
      ),
    ],
  );
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;
  @override
  GraphRevisionOrder compareTo(GraphRevision other) {
    final difference = value.compareTo((other as _Revision).value);
    return difference < 0
        ? GraphRevisionOrder.older
        : difference > 0
        ? GraphRevisionOrder.newer
        : GraphRevisionOrder.same;
  }
}

final class _Repository implements PersonalGraphRepository {
  final controller = StreamController<DailyChoiceReadResult>(sync: true);
  DailyChoiceId? observedId;
  bool get hasListener => controller.hasListener;
  @override
  Stream<DailyChoiceReadResult> watchDailyChoice(DailyChoiceId id) {
    observedId = id;
    return controller.stream;
  }

  void emit(DailyChoiceDetails? details, {required int revision}) =>
      controller.add(
        DailyChoiceReadSuccess(
          GraphSnapshot(value: details, revision: _Revision(revision)),
        ),
      );
  void fail(DailyChoiceReadFailure failure) =>
      controller.add(DailyChoiceReadError(failure));
  Future<void> dispose() => controller.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
