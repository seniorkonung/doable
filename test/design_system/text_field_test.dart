import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/text_field.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме поле, метка, текст и ошибка следуют токенам', (tester) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          controller: TextEditingController(text: 'Спорт'),
          error: 'Тег с таким названием уже есть',
        ),
      );

      final field = tester.getRect(find.byType(InputDecorator));
      expect(field.height, 48);
      expect(
        find.byType(InputDecorator),
        paints..rrect(
          rrect: RRect.fromRectAndRadius(
            Offset.zero & field.size,
            const Radius.circular(DoableMetrics.radiusSm),
          ),
          color: colors.fill,
        ),
      );

      final dot = tester.getRect(find.byType(TagDot));
      expect(dot.left - field.left, 14);
      expect(dot.center.dy, field.center.dy);
      final input = tester.getRect(find.byType(EditableText));
      expect(input.left - dot.right, 10);
      expect(field.right - input.right, DoableMetrics.space3);

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.fontSize, DoableType.action.fontSize);
      expect(editable.style.fontWeight, DoableType.action.fontWeight);
      expect(editable.style.letterSpacing, DoableType.action.letterSpacing);
      expect(editable.style.color, colors.ink);
      expect(editable.maxLines, 1);

      final error = tester.getRect(find.text('Тег с таким названием уже есть'));
      expect(error.top - field.bottom, 6);
      expect(error.left - field.left, DoableMetrics.space1);
      final errorStyle = tester
          .widget<Text>(find.text('Тег с таким названием уже есть'))
          .style!;
      expect(errorStyle.fontSize, DoableType.hint.fontSize);
      expect(errorStyle.fontWeight, DoableType.hint.fontWeight);
      expect(errorStyle.color, colors.danger);
    });
  }

  testWidgets('заполнитель пустого поля приглушён и написан обычным весом', (
    tester,
  ) async {
    await tester.pumpWidget(_app(controller: TextEditingController()));

    final hint = tester.widget<Text>(find.text('Название'));
    expect(hint.style!.color, DoableColors.light.muted);
    expect(hint.style!.fontSize, DoableType.action.fontSize);
    expect(hint.style!.fontWeight, FontWeight.w400);
  });

  testWidgets('каждое изменение текста передаётся потребителю', (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await tester.pumpWidget(
      _app(controller: controller, onChanged: changes.add),
    );

    await tester.enterText(find.byType(EditableText), 'Дом');
    await tester.pump();

    expect(changes, ['Дом']);
    expect(controller.text, 'Дом');
  });

  testWidgets('поле названо для экранного диктора, а ошибка объявляется', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        controller: TextEditingController(text: 'Спорт'),
        error: 'Тег с таким названием уже есть',
      ),
    );

    expect(
      tester.getSemantics(find.byType(EditableText)),
      isSemantics(label: 'Название тега', value: 'Спорт', isTextField: true),
    );
    expect(
      tester.getSemantics(find.text('Тег с таким названием уже есть')),
      matchesSemantics(
        label: 'Тег с таким названием уже есть',
        isLiveRegion: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('без ошибки строки под полем нет', (tester) async {
    await tester.pumpWidget(_app(controller: TextEditingController()));

    expect(tester.getSize(find.byType(TextField)).height, 48);
  });
}

Widget _app({
  required TextEditingController controller,
  Brightness brightness = Brightness.light,
  ValueChanged<String>? onChanged,
  String? error,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: TextField(
        controller: controller,
        placeholder: 'Название',
        label: 'Название тега',
        leading: const TagDot(
          color: DoableTagColor.blue,
          size: TagDotSize.large,
        ),
        onChanged: onChanged ?? (_) {},
        error: error,
      ),
    ),
  ),
);
