import 'package:doable/src/long_term_relation/application/long_term_relation_id_generator.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('граница идентификатора долговременной связи', () {
    test('декодирует канонические ненулевые UUID v4 и v7', () {
      const v4 = '0f8fad5b-d9cb-469f-a165-70867728950e';
      const v7 = '018f0b5d-6b2e-7c80-8000-000000000001';

      final decodedV4 = _decode(v4);
      final decodedV7 = _decode(v7);

      expect(decodedV4.toCanonicalString(), v4);
      expect(decodedV7.toCanonicalString(), v7);
      expect(decodedV4, isNot(decodedV7));
      expect(decodedV4.compareTo(decodedV7), isPositive);
    });

    test('отклоняет неканоничные и недопустимые UUID-представления', () {
      const invalidValues = <String>[
        '00000000-0000-0000-0000-000000000000',
        '0F8FAD5B-D9CB-469F-A165-70867728950E',
        '0f8fad5bd9cb469fa16570867728950e',
        '0f8fad5b-d9cb-469f-7165-70867728950e',
        'not-a-uuid',
      ];

      for (final value in invalidValues) {
        expect(
          LongTermRelationId.decode(value),
          isA<InvalidLongTermRelationIdDecoding>(),
        );
      }
    });

    test('рабочий генератор создаёт уникальные канонические UUID v7', () {
      final generator = UuidV7LongTermRelationIdGenerator();
      final ids = List.generate(32, (_) => generator.generate());

      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        final canonical = id.toCanonicalString();
        expect(UuidValue.withValidation(canonical).isV7, isTrue);
        expect(_decode(canonical), id);
      }
    });

    test('тестовый генератор заменяет рабочую стратегию UUID v7', () {
      final expected = [
        _decode('018f0b5d-6b2e-7c80-8000-000000000001'),
        _decode('018f0b5d-6b2e-7c80-8000-000000000002'),
      ];
      final generator = _DeterministicLongTermRelationIdGenerator(expected);

      expect(generator.generate(), expected[0]);
      expect(generator.generate(), expected[1]);
      expect(generator.generate, throwsStateError);
    });
  });
}

LongTermRelationId _decode(String value) =>
    switch (LongTermRelationId.decode(value)) {
      LongTermRelationIdDecodingSuccess(:final id) => id,
      InvalidLongTermRelationIdDecoding() => throw StateError(
        'Ожидался корректный UUID.',
      ),
    };

final class _DeterministicLongTermRelationIdGenerator
    implements LongTermRelationIdGenerator {
  _DeterministicLongTermRelationIdGenerator(Iterable<LongTermRelationId> ids)
    : _ids = List.unmodifiable(ids);

  final List<LongTermRelationId> _ids;
  var _nextIndex = 0;

  @override
  LongTermRelationId generate() {
    if (_nextIndex == _ids.length) {
      throw StateError('Последовательность идентификаторов исчерпана.');
    }
    return _ids[_nextIndex++];
  }
}
