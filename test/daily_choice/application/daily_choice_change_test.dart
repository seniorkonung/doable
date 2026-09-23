import 'package:doable/src/daily_choice/domain/calendar_date.dart';
import 'package:doable/src/daily_choice/domain/daily_choice.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/graph/application/graph_change.dart';
import 'package:doable/src/graph/application/graph_revision.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/application/long_term_relation_permissions.dart';
import 'package:doable/src/long_term_relation/application/relation_counts.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const revision = _Revision(4);

  test('создание публикует целый пакет одной ревизии', () {
    final choice = _choice(_source, _selected);
    final counts = <IntentionId, RelationCounts>{
      _source: _counts(source: 1),
      _selected: _counts(selected: 1),
    };
    final permissions = <LongTermRelationId, LongTermRelationPermissions>{
      _relation: const LongTermRelationPermissions.referencedByDailyPath(),
    };
    final change = DailyChoiceChange(
      revision: revision,
      before: null,
      after: choice,
      releasedRelationIds: const [],
      occupiedRelationIds: [_relation],
      intentionCounts: counts,
      relationPermissions: permissions,
    );
    final result = ConfirmedGraphResult(
      revision: revision,
      value: _Outcome([change]),
    );

    counts.clear();
    permissions.clear();
    expect(result.changes, [same(change)]);
    expect(change.before, isNull);
    expect(change.after, same(choice));
    expect(change.previousParticipants, isEmpty);
    expect(change.currentParticipants, {_source, _selected});
    expect(change.releasedRelationIds, isEmpty);
    expect(change.occupiedRelationIds, {_relation});
    expect(change.intentionCounts[_source]!.dailySource, 1);
    expect(change.intentionCounts[_selected]!.dailySelected, 1);
    expect(change.relationPermissions[_relation]!.canDelete, isFalse);
    expect(() => change.occupiedRelationIds.clear(), throwsUnsupportedError);
    expect(() => change.intentionCounts.clear(), throwsUnsupportedError);
    expect(() => change.relationPermissions.clear(), throwsUnsupportedError);
  });

  test(
    'замена передаёт обе пары участников и новые разрешения без правки связи',
    () {
      final change = DailyChoiceChange(
        revision: revision,
        before: _choice(_source, _selected),
        after: _choice(_replacement, _selected),
        releasedRelationIds: [_relation],
        occupiedRelationIds: [_newRelation],
        intentionCounts: {
          _source: _counts(),
          _selected: _counts(selected: 1),
          _replacement: _counts(source: 1),
        },
        relationPermissions: {
          _relation: const LongTermRelationPermissions.unrestricted(),
          _newRelation:
              const LongTermRelationPermissions.referencedByDailyPath(),
        },
      );

      expect(change.previousParticipants, {_source, _selected});
      expect(change.currentParticipants, {_replacement, _selected});
      expect(change.relationPermissions[_relation]!.canChangeMeaning, isTrue);
      expect(
        change.relationPermissions[_newRelation]!.canChangeMeaning,
        isFalse,
      );
      expect(change.intentionCounts[_source]!.dailyTotal, 0);
    },
  );

  test('освобождение пути сохраняет фактическую блокировку другой ссылкой', () {
    final change = DailyChoiceChange(
      revision: revision,
      before: _choice(_source, _selected),
      after: null,
      releasedRelationIds: [_relation],
      occupiedRelationIds: const [],
      intentionCounts: {_source: _counts(), _selected: _counts()},
      relationPermissions: {
        _relation: const LongTermRelationPermissions.referencedByDailyPath(),
      },
    );

    expect(change.relationPermissions[_relation]!.canDelete, isFalse);
    expect(change.currentParticipants, isEmpty);
  });

  test('изменение только даты не выдаёт освобождение пути', () {
    final before = _choice(_source, _selected);
    final after = DailyChoice(
      id: _choiceId,
      sourceIntentionId: _source,
      selectedIntentionId: _selected,
      date: CalendarDate.fromParts(2026, 9, 24),
      description: null,
      isCompleted: false,
    );
    final change = DailyChoiceChange(
      revision: revision,
      before: before,
      after: after,
      releasedRelationIds: const [],
      occupiedRelationIds: const [],
      intentionCounts: {
        _source: _counts(source: 1),
        _selected: _counts(selected: 1),
      },
      relationPermissions: const {},
    );

    expect(change.before!.date, before.date);
    expect(change.after!.date, after.date);
    expect(change.releasedRelationIds, isEmpty);
    expect(change.occupiedRelationIds, isEmpty);
  });

  test('не принимает неполный пакет и смешанные ревизии', () {
    final choice = _choice(_source, _selected);
    expect(
      () => DailyChoiceChange(
        revision: revision,
        before: null,
        after: choice,
        releasedRelationIds: const [],
        occupiedRelationIds: [_relation],
        intentionCounts: {_source: _counts(source: 1)},
        relationPermissions: {
          _relation: const LongTermRelationPermissions.unknown(),
        },
      ),
      throwsA(isA<DailyChoiceChangeValidationException>()),
    );
    expect(
      () => DailyChoiceChange(
        revision: revision,
        before: null,
        after: choice,
        releasedRelationIds: const [],
        occupiedRelationIds: [_relation],
        intentionCounts: {
          _source: _counts(source: 1),
          _selected: _counts(selected: 1),
        },
        relationPermissions: const {},
      ),
      throwsA(
        isA<DailyChoiceChangeValidationException>().having(
          (error) => error.failure,
          'причина',
          DailyChoiceChangeValidationFailure.missingPermissions,
        ),
      ),
    );
    expect(
      () => DailyChoiceChange(
        revision: revision,
        before: null,
        after: choice,
        releasedRelationIds: const [],
        occupiedRelationIds: [_relation],
        intentionCounts: {
          _source: _counts(source: 1),
          _selected: _counts(selected: 1),
        },
        relationPermissions: {
          _relation: const LongTermRelationPermissions.unknown(),
        },
      ),
      throwsA(
        isA<DailyChoiceChangeValidationException>().having(
          (error) => error.failure,
          'причина',
          DailyChoiceChangeValidationFailure.unconfirmedPermissions,
        ),
      ),
    );
    final change = DailyChoiceChange(
      revision: const _Revision(5),
      before: null,
      after: choice,
      releasedRelationIds: const [],
      occupiedRelationIds: [_relation],
      intentionCounts: {
        _source: _counts(source: 1),
        _selected: _counts(selected: 1),
      },
      relationPermissions: {
        _relation: const LongTermRelationPermissions.referencedByDailyPath(),
      },
    );
    expect(
      () => ConfirmedGraphResult(revision: revision, value: _Outcome([change])),
      throwsA(isA<ConfirmedGraphResultValidationException>()),
    );
  });
}

final class _Revision implements GraphRevision {
  const _Revision(this.value);
  final int value;

  @override
  GraphRevisionOrder compareTo(GraphRevision other) => other is! _Revision
      ? GraphRevisionOrder.differentEpoch
      : switch (value.compareTo(other.value)) {
          < 0 => GraphRevisionOrder.older,
          > 0 => GraphRevisionOrder.newer,
          _ => GraphRevisionOrder.same,
        };
}

DailyChoice _choice(IntentionId source, IntentionId selected) => DailyChoice(
  id: _choiceId,
  sourceIntentionId: source,
  selectedIntentionId: selected,
  date: CalendarDate.fromParts(2026, 9, 23),
  description: null,
  isCompleted: false,
);

RelationCounts _counts({int source = 0, int selected = 0}) => RelationCounts(
  activeNeedIncoming: 0,
  activeNeedOutgoing: 0,
  activeCanIncoming: 0,
  activeCanOutgoing: 0,
  archivedNeedIncoming: 0,
  archivedNeedOutgoing: 0,
  archivedCanIncoming: 0,
  archivedCanOutgoing: 0,
  dailySource: source,
  dailySelected: selected,
);

final class _Outcome implements GraphCommandOutcome {
  const _Outcome(this.changes);

  @override
  final List<GraphChange> changes;
}

IntentionId _intention(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  _ => throw StateError('Некорректный UUID намерения.'),
};

LongTermRelationId _longTermRelation(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      _ => throw StateError('Некорректный UUID связи.'),
    };

DailyChoiceId _dailyChoice(String value) =>
    switch (DailyChoiceId.decode(value)) {
      DailyChoiceIdDecodingSuccess(:final id) => id,
      _ => throw StateError('Некорректный UUID выбора.'),
    };

final _source = _intention('018f0b5d-6b2e-7c80-8000-000000000001');
final _selected = _intention('018f0b5d-6b2e-7c80-8000-000000000002');
final _replacement = _intention('018f0b5d-6b2e-7c80-8000-000000000003');
final _relation = _longTermRelation('018f0b5d-6b2e-7c80-8000-000000000004');
final _newRelation = _longTermRelation('018f0b5d-6b2e-7c80-8000-000000000005');
final _choiceId = _dailyChoice('018f0b5d-6b2e-7c80-8000-000000000006');
