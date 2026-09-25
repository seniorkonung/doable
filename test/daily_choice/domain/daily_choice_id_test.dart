import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('идентификатор дневного выбора', () {
    test('принимает канонические UUID разных версий и сохраняет значение', () {
      const v4 = '0f8fad5b-d9cb-469f-a165-70867728950e';
      const v7 = '018f0b5d-6b2e-7c80-8000-000000000001';

      expect(_decode(v4).toCanonicalString(), v4);
      expect(_decode(v7).toCanonicalString(), v7);
      expect(_decode(v4), isNot(_decode(v7)));
      expect(_decode(v4).compareTo(_decode(v7)), isPositive);
    });

    test('отклоняет nil, неверную форму и неканоничную запись', () {
      const invalid = <String>[
        '00000000-0000-0000-0000-000000000000',
        '0F8FAD5B-D9CB-469F-A165-70867728950E',
        '0f8fad5bd9cb469fa16570867728950e',
        '0f8fad5b-d9cb-469f-7165-70867728950e',
        'not-a-uuid',
      ];

      for (final value in invalid) {
        expect(
          DailyChoiceId.decode(value),
          isA<InvalidDailyChoiceIdDecoding>(),
        );
      }
    });

    test('равенство ограничено типом дневного выбора', () {
      const uuid = '018f0b5d-6b2e-7c80-8000-000000000001';
      final first = _decode(uuid);
      final second = _decode(uuid);
      final intention = switch (IntentionId.decode(uuid)) {
        IntentionIdDecodingSuccess(:final id) => id,
        InvalidIntentionIdDecoding() => throw StateError('Некорректный UUID.'),
      };
      final relation = switch (LongTermRelationId.decode(uuid)) {
        LongTermRelationIdDecodingSuccess(:final id) => id,
        InvalidLongTermRelationIdDecoding() => throw StateError(
          'Некорректный UUID.',
        ),
      };
      final step = switch (ChoicePathStepId.decode(uuid)) {
        ChoicePathStepIdDecodingSuccess(:final id) => id,
        InvalidChoicePathStepIdDecoding() => throw StateError(
          'Некорректный UUID.',
        ),
      };

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect({first, second}, hasLength(1));
      expect(first, isNot(intention));
      expect(first, isNot(relation));
      expect(first, isNot(step));
    });

    test('рабочий генератор создаёт уникальные UUID v7', () {
      final generator = UuidV7DailyChoiceIdGenerator();
      final ids = List.generate(32, (_) => generator.generate());

      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(UuidValue.withValidation(id.toCanonicalString()).isV7, isTrue);
        expect(_decode(id.toCanonicalString()), id);
      }
    });

    test('подменяемый генератор позволяет воспроизвести коллизию', () {
      final id = _decode('018f0b5d-6b2e-7c80-8000-000000000001');
      final DailyChoiceIdGenerator generator = _FixedDailyChoiceIdGenerator(id);

      expect(generator.generate(), id);
      expect(generator.generate(), id);
    });
  });
}

DailyChoiceId _decode(String value) => switch (DailyChoiceId.decode(value)) {
  DailyChoiceIdDecodingSuccess(:final id) => id,
  InvalidDailyChoiceIdDecoding() => throw StateError(
    'Ожидался корректный UUID.',
  ),
};

final class _FixedDailyChoiceIdGenerator implements DailyChoiceIdGenerator {
  const _FixedDailyChoiceIdGenerator(this.id);

  final DailyChoiceId id;

  @override
  DailyChoiceId generate() => id;
}
