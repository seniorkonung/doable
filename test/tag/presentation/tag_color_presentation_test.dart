import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/tag/domain/tag_color.dart';
import 'package:doable/src/tag/presentation/tag_color_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('предметные и визуальные цвета переводятся в одноимённые варианты, '
      'а отсутствие цвета сохраняется', () {
    expect(tagColorPresentation(null), isNull);
    expect(tagColorFromPresentation(null), isNull);
    for (final color in TagColor.values) {
      expect(
        tagColorPresentation(color),
        DoableTagColor.values.byName(color.name),
      );
    }
    for (final color in DoableTagColor.values) {
      expect(
        tagColorFromPresentation(color),
        TagColor.values.byName(color.name),
      );
    }
  });
}
