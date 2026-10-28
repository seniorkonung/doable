import 'package:doable/src/design_system/components/tag_dot.dart';
import 'package:doable/src/design_system/components/text_field.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart' hide TextField;
import 'package:flutter/rendering.dart';
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

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме сохранённый текст лежит на плоскости поля стилем field', (
      tester,
    ) async {
      final colors = _colors(brightness);
      await tester.pumpWidget(
        _savedApp(brightness: brightness, value: 'Ноги и спина'),
      );

      final plane = tester.getRect(_savedPlane);
      expect(plane.height, DoableMetrics.tapMin);
      final decoration =
          tester.widget<Ink>(_savedPlane).decoration! as BoxDecoration;
      expect(decoration.color, colors.fill);
      expect(
        decoration.borderRadius,
        const BorderRadius.all(Radius.circular(DoableMetrics.radiusSm)),
      );
      final text = tester.getRect(find.text('Ноги и спина'));
      expect(text.left - plane.left, DoableMetrics.space3);
      expect(text.top - plane.top, 11);
      expect(plane.bottom - text.bottom, 11);
      final style = _savedStyle(tester, 'Ноги и спина');
      expect(style.fontSize, DoableType.field.fontSize);
      expect(style.height, DoableType.field.height);
      expect(style.fontWeight, DoableType.field.fontWeight);
      expect(style.letterSpacing, DoableType.field.letterSpacing);
      expect(style.color, colors.ink);
    });

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме сохранённый текст показан целиком с переносами строк', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(240, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final value = [
        'Первая строка',
        List.filled(4, 'длинныйтекстбезпробелов').join(),
        'Последняя строка',
      ].join('\n');
      await tester.pumpWidget(_savedApp(brightness: brightness, value: value));

      final paragraph = tester.renderObject<RenderParagraph>(find.text(value));
      expect(paragraph.text.toPlainText(), value);
      expect(paragraph.maxLines, isNull);
      expect(paragraph.didExceedMaxLines, isFalse);
      final text = tester.getRect(find.text(value));
      expect(text.height, greaterThan(3 * 22));
      final plane = tester.getRect(_savedPlane);
      expect(plane.height, text.height + 2 * 11);
      expect(tester.takeException(), isNull);
    });

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме пустой сохранённый текст показывает приглашение в одну строку', (
      tester,
    ) async {
      final colors = _colors(brightness);
      await tester.pumpWidget(_savedApp(brightness: brightness, value: ''));

      expect(tester.getSize(_savedPlane).height, DoableMetrics.tapMin);
      expect(tester.getSize(find.text('Добавить заметку')).height, 22);
      final style = _savedStyle(tester, 'Добавить заметку');
      expect(style.fontSize, DoableType.field.fontSize);
      expect(style.fontWeight, FontWeight.w400);
      expect(style.color, colors.muted);
    });

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме сохранённый текст открывает правку только доступной кнопкой', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var opens = 0;
      await tester.pumpWidget(
        _savedApp(
          brightness: brightness,
          value: 'Ноги и спина',
          onOpen: () => opens++,
        ),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel(_savedLabel)),
        isSemantics(
          label: _savedLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
          children: const [],
        ),
      );
      await tester.tap(find.text('Ноги и спина'));
      expect(opens, 1);

      await tester.pumpWidget(
        _savedApp(brightness: brightness, value: 'Ноги и спина'),
      );

      expect(
        tester.getSemantics(find.bySemanticsLabel(_savedLabel)),
        isSemantics(
          label: _savedLabel,
          isButton: true,
          hasEnabledState: true,
          isEnabled: false,
          hasTapAction: false,
          children: const [],
        ),
      );
      await tester.tap(find.text('Ноги и спина'), warnIfMissed: false);
      expect(opens, 1);
      semantics.dispose();
    });

    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме сохранённый текст растёт без переполнения при крупном тексте', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(240, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _savedApp(
          brightness: brightness,
          value: 'Ноги и спина, сорок пять минут',
          textScale: 2,
        ),
      );

      final text = tester.getRect(find.text('Ноги и спина, сорок пять минут'));
      expect(text.height, greaterThan(2 * 22));
      expect(tester.getSize(_savedPlane).height, text.height + 2 * 11);
      expect(
        tester
            .renderObject<RenderParagraph>(
              find.text('Ноги и спина, сорок пять минут'),
            )
            .didExceedMaxLines,
        isFalse,
      );
      expect(tester.takeException(), isNull);
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

    expect(
      tester.getSize(find.byWidgetPredicate((w) => w is TextField)).height,
      48,
    );
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

const _savedLabel = 'Изменить заметку: Ноги и спина';

final _savedPlane = find.descendant(
  of: find.byWidgetPredicate((widget) => widget is TextField),
  matching: find.byType(Ink),
);

TextStyle _savedStyle(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Widget _savedApp({
  required String value,
  Brightness brightness = Brightness.light,
  VoidCallback? onOpen,
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
      child: TextField.saved(
        value: value,
        placeholder: 'Добавить заметку',
        label: _savedLabel,
        onOpen: onOpen,
      ),
    ),
  ),
);

DoableColors _colors(Brightness brightness) => switch (brightness) {
  Brightness.light => DoableColors.light,
  Brightness.dark => DoableColors.dark,
};
