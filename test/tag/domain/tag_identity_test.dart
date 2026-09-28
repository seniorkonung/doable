import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:doable/src/tag/application/tag_id_generator.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_assignment.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
import 'package:doable/src/tag/domain/tag_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('идентичность тега', () {
    test('принимает канонические ненулевые UUID разных версий', () {
      const v1 = 'f47ac10b-58cc-11cf-a447-001122334455';
      const v4 = '0f8fad5b-d9cb-469f-a165-70867728950e';
      const v7 = '018f0b5d-6b2e-7c80-8000-000000000001';

      for (final value in [v1, v4, v7]) {
        expect(_tagId(value).toCanonicalString(), value);
        expect(_tagId(value), _tagId(value));
      }
      expect({_tagId(v1), _tagId(v4), _tagId(v7)}, hasLength(3));
    });

    test('отклоняет нулевой и неканонический UUID', () {
      for (final value in [
        '00000000-0000-0000-0000-000000000000',
        '0F8FAD5B-D9CB-469F-A165-70867728950E',
        '0f8fad5bd9cb469fa16570867728950e',
        '0f8fad5b-d9cb-469f-7165-70867728950e',
        'not-a-uuid',
      ]) {
        expect(TagId.decode(value), isA<InvalidTagIdDecoding>());
      }
    });

    test('генератор даёт разные канонические UUID v7', () {
      final generator = UuidV7TagIdGenerator();
      final ids = List.generate(32, (_) => generator.generate());

      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        final value = id.toCanonicalString();
        expect(UuidValue.withValidation(value).isV7, isTrue);
        expect(_tagId(value), id);
      }
    });

    test('имя не определяет идентичность тега', () {
      final firstId = _tagId('018f0b5d-6b2e-7c80-8000-000000000001');
      final secondId = _tagId('018f0b5d-6b2e-7c80-8000-000000000002');
      final name = TagName.fromInput('  Дом  ');
      final first = Tag(id: firstId, name: name);
      final renamed = Tag(id: firstId, name: TagName.fromInput('Быт'));
      final second = Tag(id: secondId, name: name);

      expect(first.name.value, 'Дом');
      expect(renamed.id, first.id);
      expect(second.name, first.name);
      expect(second.id, isNot(first.id));
    });
  });

  group('получатель и назначение тега', () {
    test('различает намерение и долговременную связь с одинаковым UUID', () {
      const value = '018f0b5d-6b2e-7c80-8000-000000000001';
      final intention = IntentionTagTarget(_intentionId(value));
      final relation = LongTermRelationTagTarget(_relationId(value));

      expect(intention, IntentionTagTarget(_intentionId(value)));
      expect(relation, LongTermRelationTagTarget(_relationId(value)));
      expect(intention, isNot(relation));
      expect(<TagTarget>{intention, relation}, hasLength(2));
    });

    test(
      'назначение определяется только тегом и типизированным получателем',
      () {
        const first = '018f0b5d-6b2e-7c80-8000-000000000001';
        const second = '018f0b5d-6b2e-7c80-8000-000000000002';
        final intention = IntentionTagTarget(_intentionId(first));
        final relation = LongTermRelationTagTarget(_relationId(first));
        final assignment = TagAssignment(
          tagId: _tagId(first),
          target: intention,
        );

        expect(
          assignment,
          TagAssignment(tagId: _tagId(first), target: intention),
        );
        expect(<TagAssignment>{
          assignment,
          TagAssignment(tagId: _tagId(second), target: intention),
          TagAssignment(tagId: _tagId(first), target: relation),
        }, hasLength(3));
      },
    );
  });
}

TagId _tagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Ожидался корректный UUID тега.'),
};

IntentionId _intentionId(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Ожидался UUID намерения.'),
};

LongTermRelationId _relationId(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Ожидался UUID долговременной связи.',
      ),
    };
