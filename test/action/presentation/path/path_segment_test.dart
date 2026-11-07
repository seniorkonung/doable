import 'package:doable/src/action/application/action_details.dart';
import 'package:doable/src/action/presentation/path/path_segment.dart';
import 'package:doable/src/long_term_relation/domain/long_term_relation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/action_panel_fixture.dart';

/// Сохранённый путь фикстуры из трёх намерений, в котором намерение или звено
/// с номером позиции заменены удалёнными.
ActionSavedPath _path({
  Set<int> deletedIntentions = const {},
  Set<int> deletedLinks = const {},
}) {
  final path = actionDetailsFixture(pathLength: 3).path;
  ActionPathIntention intention(ActionPathIntention value, int position) =>
      deletedIntentions.contains(position)
      ? DeletedActionPathIntention(id: value.id, title: value.title)
      : value;
  return ActionSavedPath(
    root: intention(path.root, 0),
    steps: [
      for (final (index, step) in path.steps.indexed)
        ActionPathStep(
          link: deletedLinks.contains(index + 1)
              ? const DeletedActionPathLink(LongTermRelationType.need)
              : step.link,
          intention: intention(step.intention, index + 1),
        ),
    ],
  );
}

void main() {
  test('удалённая связь заканчивает участок перед собой', () {
    expect(firstWholeSegment(_path(deletedLinks: {2}))!.intentions, [
      intentionIdOf(10),
      intentionIdOf(11),
    ]);
  });

  test('удалённый корень сдвигает начало участка на следующее намерение', () {
    expect(firstWholeSegment(_path(deletedIntentions: {0}))!.intentions, [
      intentionIdOf(11),
      intentionIdOf(12),
    ]);
  });

  test('без существующих намерений участка нет', () {
    expect(firstWholeSegment(_path(deletedIntentions: {0, 1, 2})), isNull);
  });
}
