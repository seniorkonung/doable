import 'package:doable/src/tag/application/tag_id_generator.dart';
import 'package:doable/src/tag/domain/tag.dart';
import 'package:doable/src/tag/domain/tag_id.dart';
import 'package:doable/src/tag/domain/tag_name.dart';
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
      final first = Tag(id: firstId, name: name, color: null);
      final renamed = Tag(
        id: firstId,
        name: TagName.fromInput('Быт'),
        color: first.color,
      );
      final second = Tag(id: secondId, name: name, color: null);

      expect(first.name.value, 'Дом');
      expect(renamed.id, first.id);
      expect(second.name, first.name);
      expect(second.id, isNot(first.id));
    });
  });
}

TagId _tagId(String value) => switch (TagId.decode(value)) {
  TagIdDecodingSuccess(:final id) => id,
  InvalidTagIdDecoding() => throw StateError('Ожидался корректный UUID тега.'),
};
