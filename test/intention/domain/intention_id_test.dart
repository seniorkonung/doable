import 'package:doable/src/intention/application/intention_id_generator.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('граница идентификатора намерения', () {
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
        expect(IntentionId.decode(value), isA<InvalidIntentionIdDecoding>());
      }
    });

    test('production generator создаёт уникальные канонические UUID v7', () {
      final generator = UuidV7IntentionIdGenerator();
      final ids = List.generate(32, (_) => generator.generate());

      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        final canonical = id.toCanonicalString();
        expect(UuidValue.withValidation(canonical).isV7, isTrue);
        expect(_decode(canonical), id);
      }
    });

    test('тестовый generator возвращает заданные корректные UUID v7 одной миллисекунды', () {
      final expected = [
        _decode('018f0b5d-6b2e-7c80-8000-000000000001'),
        _decode('018f0b5d-6b2e-7c80-8000-000000000002'),
      ];
      final generator = _DeterministicIntentionIdGenerator(expected);

      expect(
        expected.map((id) => id.toCanonicalString().substring(0, 12)).toSet(),
        hasLength(1),
      );
      expect(generator.generate(), expected[0]);
      expect(generator.generate(), expected[1]);
      expect(generator.generate, throwsStateError);
    });
  });
}

IntentionId _decode(String value) => switch (IntentionId.decode(value)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Ожидался корректный UUID.'),
};

final class _DeterministicIntentionIdGenerator implements IntentionIdGenerator {
  _DeterministicIntentionIdGenerator(Iterable<IntentionId> ids)
    : _ids = List.unmodifiable(ids);

  final List<IntentionId> _ids;
  var _nextIndex = 0;

  @override
  IntentionId generate() {
    if (_nextIndex == _ids.length) {
      throw StateError('Последовательность идентификаторов исчерпана.');
    }
    return _ids[_nextIndex++];
  }
}
