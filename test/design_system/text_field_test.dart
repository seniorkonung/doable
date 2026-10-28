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
          error: Builder(
            builder: (_) => const Text('Тег с таким названием уже есть'),
          ),
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
      final errorStyle = DefaultTextStyle.of(
        tester.element(find.text('Тег с таким названием уже есть')),
      ).style;
      expect(errorStyle.fontSize, DoableType.hint.fontSize);
      expect(errorStyle.fontWeight, DoableType.hint.fontWeight);
      expect(errorStyle.color, colors.danger);
    });

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме описание растёт в пределах строк и дальше прокручивается', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          controller: controller,
          multiline: true,
          minLines: 2,
          maxLines: 3,
        ),
      );

      final field = find.byType(InputDecorator);
      expect(tester.getSize(field).height, 2 * 22 + 2 * 11);
      final input = tester.getRect(find.byType(EditableText));
      final plane = tester.getRect(field);
      expect(input.left - plane.left, DoableMetrics.space3);
      expect(plane.right - input.right, DoableMetrics.space3);
      expect(input.top - plane.top, 11);
      expect(plane.bottom - input.bottom, 11);
      final style = tester
          .widget<EditableText>(find.byType(EditableText))
          .style;
      expect(style.fontSize, DoableType.field.fontSize);
      expect(style.height, DoableType.field.height);
      expect(style.fontWeight, DoableType.field.fontWeight);
      expect(style.letterSpacing, DoableType.field.letterSpacing);
      expect(style.color, _colors(brightness).ink);

      await tester.enterText(find.byType(EditableText), 'Один\nДва\nТри');
      await tester.pump();
      expect(tester.getSize(field).height, 3 * 22 + 2 * 11);

      await tester.enterText(
        find.byType(EditableText),
        'Один\nДва\nТри\nЧетыре',
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(field).height, 3 * 22 + 2 * 11);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(EditableText),
          matching: find.byType(Scrollable),
        ),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      final previousOffset = scrollable.position.pixels;
      await tester.drag(find.byType(EditableText), const Offset(0, 50));
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, lessThan(previousOffset));
      expect(controller.text, 'Один\nДва\nТри\nЧетыре');

      await tester.enterText(find.byType(EditableText), 'Один');
      await tester.pump();
      expect(tester.getSize(field).height, 2 * 22 + 2 * 11);
    });

    testWidgets(
      'в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
      'теме название без метки растёт и переносится целиком при крупном тексте',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(240, 600));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            controller: controller,
            multiline: true,
            kind: TextFieldKind.name,
          ),
        );
        expect(tester.getSize(find.byType(InputDecorator)).height, 48);
        await tester.pumpWidget(
          _app(
            brightness: brightness,
            controller: controller,
            multiline: true,
            kind: TextFieldKind.name,
            textScale: 2,
            error: const Text('Название слишком длинное, сократите его'),
          ),
        );

        final field = find.byType(InputDecorator);
        final initialHeight = tester.getSize(field).height;
        expect(initialHeight, 2 * 22 + 2 * 13);
        expect(find.byType(TagDot), findsNothing);
        final style = tester
            .widget<EditableText>(find.byType(EditableText))
            .style;
        expect(style.fontSize, DoableType.action.fontSize);
        expect(style.height, DoableType.action.height);
        expect(style.fontWeight, DoableType.action.fontWeight);
        expect(style.letterSpacing, DoableType.action.letterSpacing);
        expect(style.color, _colors(brightness).ink);
        final hint = tester.widget<Text>(find.text('Имя')).style!;
        expect(hint.color, _colors(brightness).muted);
        expect(hint.fontWeight, FontWeight.w400);
        final input = tester.getRect(find.byType(EditableText));
        final plane = tester.getRect(field);
        expect(input.left - plane.left, DoableMetrics.space3);
        expect(plane.right - input.right, DoableMetrics.space3);
        expect(input.top - plane.top, 13);
        expect(plane.bottom - input.bottom, 13);

        final name = List.filled(3, 'Длинноеназваниебезпробелов').join();
        await tester.enterText(find.byType(EditableText), name);
        await tester.pumpAndSettle();

        expect(tester.getSize(field).height, greaterThan(initialHeight));
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(EditableText),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.maxScrollExtent, 0);
        expect(controller.text, name);
        final error = find.text('Название слишком длинное, сократите его');
        expect(tester.getSize(error).height, greaterThan(2 * 18));
        expect(tester.getRect(error).top - tester.getRect(field).bottom, 6);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме автофокус ставит курсор без нажатия', (tester) async {
      final controller = TextEditingController(text: 'Сохранённый текст');
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          controller: controller,
          multiline: true,
          autofocus: true,
        ),
      );
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);
      tester.testTextInput.enterText('Новый текст');
      await tester.pump();
      expect(controller.text, 'Новый текст');
    });
  }

  testWidgets(
    'растущее название заменяет перенос строки пробелом и не предлагает его '
    'на клавиатуре',
    (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await tester.pumpWidget(
        _app(
          controller: controller,
          onChanged: changes.add,
          multiline: true,
          kind: TextFieldKind.name,
        ),
      );

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.keyboardType, TextInputType.text);
      expect(editable.textInputAction, TextInputAction.next);
      for (final lineBreak in ['\n', '\r\n', '\r']) {
        await tester.enterText(
          find.byType(EditableText),
          'Бегать$lineBreakпо утрам',
        );
        await tester.pump();

        expect(controller.text, 'Бегать по утрам');
        expect(changes.last, 'Бегать по утрам');
      }
    },
  );

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

  testWidgets('поле только для чтения не меняет текст вводом', (tester) async {
    final controller = TextEditingController(text: 'Дом');
    final changes = <String>[];
    await tester.pumpWidget(
      _app(
        controller: controller,
        onChanged: changes.add,
        multiline: true,
        readOnly: true,
      ),
    );

    await tester.enterText(find.byType(EditableText), 'Сад');
    await tester.pump();

    expect(changes, isEmpty);
    expect(controller.text, 'Дом');
  });

  testWidgets('поле названо для экранного диктора, а ошибка объявляется', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        controller: TextEditingController(text: 'Спорт'),
        error: const Text('Тег с таким названием уже есть'),
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
  Widget? error,
  bool multiline = false,
  int minLines = 1,
  int? maxLines,
  TextFieldKind kind = TextFieldKind.text,
  bool autofocus = false,
  bool readOnly = false,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      child: multiline
          ? TextField.multiline(
              controller: controller,
              placeholder: kind == TextFieldKind.name ? 'Имя' : 'Описание',
              label: 'Описание намерения',
              minLines: minLines,
              maxLines: maxLines,
              kind: kind,
              autofocus: autofocus,
              readOnly: readOnly,
              onChanged: onChanged ?? (_) {},
              error: error,
            )
          : TextField(
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

DoableColors _colors(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableColors.light,
  Brightness.dark => DoableColors.dark,
};
