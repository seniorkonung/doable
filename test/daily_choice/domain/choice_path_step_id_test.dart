import 'package:doable/src/daily_choice/application/daily_choice_id_generator.dart';
import 'package:doable/src/daily_choice/domain/choice_path_step_id.dart';
import 'package:doable/src/daily_choice/domain/daily_choice_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('идентификатор шага пути выбора', () {
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
          ChoicePathStepId.decode(value),
          isA<InvalidChoicePathStepIdDecoding>(),
        );
      }
    });

    test('равенство ограничено типом шага пути выбора', () {
      const uuid = '018f0b5d-6b2e-7c80-8000-000000000001';
      final first = _decode(uuid);
      final second = _decode(uuid);
      final choice = switch (DailyChoiceId.decode(uuid)) {
        DailyChoiceIdDecodingSuccess(:final id) => id,
        InvalidDailyChoiceIdDecoding() => throw StateError(
          'Некорректный UUID.',
        ),
      };

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect({first, second}, hasLength(1));
      expect(first, isNot(choice));
    });

    test('рабочий генератор создаёт уникальные UUID v7', () {
      final generator = UuidV7ChoicePathStepIdGenerator();
      final ids = List.generate(32, (_) => generator.generate());

      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(UuidValue.withValidation(id.toCanonicalString()).isV7, isTrue);
        expect(_decode(id.toCanonicalString()), id);
      }
    });

    test('подменяемый генератор позволяет воспроизвести коллизию', () {
      final id = _decode('018f0b5d-6b2e-7c80-8000-000000000001');
      final ChoicePathStepIdGenerator generator =
          _FixedChoicePathStepIdGenerator(id);

      expect(generator.generate(), id);
      expect(generator.generate(), id);
    });
  });
}

ChoicePathStepId _decode(String value) =>
    switch (ChoicePathStepId.decode(value)) {
      ChoicePathStepIdDecodingSuccess(:final id) => id,
      InvalidChoicePathStepIdDecoding() => throw StateError(
        'Ожидался корректный UUID.',
      ),
    };

final class _FixedChoicePathStepIdGenerator
    implements ChoicePathStepIdGenerator {
  const _FixedChoicePathStepIdGenerator(this.id);

  final ChoicePathStepId id;

  @override
  ChoicePathStepId generate() => id;
}
