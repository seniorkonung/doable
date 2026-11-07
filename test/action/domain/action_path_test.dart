import 'package:doable/src/action/domain/action_path.dart';
import 'package:doable/src/intention/domain/intention_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('путь действия', () {
    test('допускает путь из одного намерения', () {
      final path = ActionPath([_id(1)]);

      expect(path.intentions, [_id(1)]);
    });

    test('сохраняет порядок намерений от корневого к конечному', () {
      final path = ActionPath([_id(3), _id(1), _id(2)]);

      expect(path.intentions, [_id(3), _id(1), _id(2)]);
    });

    test('отклоняет пустой путь', () {
      expect(() => ActionPath(const []), throwsArgumentError);
    });

    test('отклоняет повтор намерения, в том числе не соседнего', () {
      expect(() => ActionPath([_id(1), _id(1)]), throwsArgumentError);
      expect(() => ActionPath([_id(1), _id(2), _id(1)]), throwsArgumentError);
    });

    test('не меняется от последующих правок переданного списка', () {
      final source = [_id(1), _id(2)];
      final path = ActionPath(source);

      source.add(_id(3));

      expect(path.intentions, [_id(1), _id(2)]);
      expect(() => path.intentions.add(_id(3)), throwsUnsupportedError);
    });
  });
}

IntentionId _id(int index) => switch (IntentionId.decode(
  '018f0b5d-6b2e-7c80-8000-${index.toString().padLeft(12, '0')}',
)) {
  IntentionIdDecodingSuccess(:final id) => id,
  InvalidIntentionIdDecoding() => throw StateError('Ожидался корректный UUID.'),
};
