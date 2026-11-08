import 'package:doable/src/intention/application/cascade/intention_cascade.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('каждый вариант получает свой состав из плана предпросмотра', () {
    final withSupporting = RestoreCascadeComposition(
      restored: const [],
      returnedAsMain: null,
      restoredRelationCount: 1,
    );
    final onlyThis = RestoreCascadeComposition(
      restored: const [],
      returnedAsMain: null,
      restoredRelationCount: 0,
    );
    final plan = CascadePlan(
      withSupporting: withSupporting,
      onlyThis: onlyThis,
      asksQuestion: true,
    );

    for (final (choice, composition) in [
      (CascadeChoice.withSupporting, withSupporting),
      (CascadeChoice.onlyThis, onlyThis),
    ]) {
      final execution = CascadeExecution.of(plan, choice);
      expect(execution.choice, choice);
      expect(execution.expected, same(composition));
    }
  });
}
