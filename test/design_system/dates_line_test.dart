import 'package:doable/src/design_system/components/dates_line.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _created = (label: 'Создано', date: '27 мар');
const _changed = (label: 'Изменено', date: '29 апр 2025');

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме строка называет две даты через среднюю '
        'точку стилем hint в muted с табличными цифрами по левому краю', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: const DatesLine(created: _created, changed: _changed),
        ),
      );

      final text = find.text('Создано 27 мар · Изменено 29 апр 2025');
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final style = paragraph.text.style!;
      expect(style.color, colors.muted);
      expect(style.fontFamily, DoableType.hint.fontFamily);
      expect(style.fontSize, DoableType.hint.fontSize);
      expect(style.fontWeight, DoableType.hint.fontWeight);
      expect(style.height, DoableType.hint.height);
      expect(style.fontFeatures, const [FontFeature.tabularFigures()]);
      expect(
        paragraph
            .getOffsetForCaret(const TextPosition(offset: 0), Rect.zero)
            .dx,
        0,
      );
    });

    testWidgets('в $themeName теме без даты изменения строка называет одну '
        'дату создания', (tester) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          child: const DatesLine(created: _created),
        ),
      );

      expect(find.text('Создано 27 мар'), findsOneWidget);
    });
  }

  testWidgets('экранный диктор читает строку целиком', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        child: const DatesLine(created: _created, changed: _changed),
      ),
    );

    expect(
      tester.getSemantics(find.byType(DatesLine)),
      isSemantics(label: 'Создано 27 мар · Изменено 29 апр 2025'),
    );
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 строка переносится в ширине поля без '
      'переполнения', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2,
        child: const DatesLine(created: _created, changed: _changed),
      ),
    );

    expect(tester.takeException(), isNull);
    final field = tester.getRect(find.byType(_Field));
    final line = tester.getRect(find.byType(DatesLine));
    expect(line.width, lessThanOrEqualTo(field.width));
    expect(
      line.height,
      greaterThan(2 * DoableType.hint.fontSize! * DoableType.hint.height!),
    );
  });
}

/// Поле содержимого шириной 240, в котором стоит строка.
final class _Field extends StatelessWidget {
  const _Field({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(width: 240, child: child);
}

Widget _app({
  required Widget child,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: _Field(child: child),
      ),
    ),
  ),
);
