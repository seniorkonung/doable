import 'package:doable/src/action/application/action_command.dart';
import 'package:doable/src/action/domain/action_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('правка поля действия', () {
    test('без правки сохраняет текущее описание и его отсутствие', () {
      const unchanged = ActionFieldUnchanged<ActionDescription?>();
      final description = ActionDescription.fromInput('Описание');

      expect(unchanged.resolve(description), description);
      expect(unchanged.resolve(null), isNull);
    });

    test(
      'установка отсутствия описания очищает его, а не оставляет прежнее',
      () {
        final description = ActionDescription.fromInput('Прежнее описание');
        const cleared = ActionFieldSet<ActionDescription?>(null);

        expect(cleared.resolve(description), isNull);
      },
    );
  });
}
