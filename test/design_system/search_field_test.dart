import 'package:doable/src/design_system/components/search_field.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме поле, значки, крестик и ошибка следуют токенам', (tester) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          controller: TextEditingController(text: 'мин'),
          error: 'Слишком длинный запрос',
        ),
      );

      final field = tester.getRect(find.byType(InputDecorator));
      expect(field.height, DoableMetrics.tapMin);
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

      final search = _icon(tester, DoableIconData.search);
      expect(search.size, 20);
      expect(search.color, colors.muted);
      final searchRect = tester.getRect(_iconFinder(DoableIconData.search));
      expect(searchRect.left - field.left, DoableMetrics.space3);
      final input = tester.getRect(find.byType(EditableText));
      expect(input.left - searchRect.right, DoableMetrics.space2);

      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.style.fontSize, DoableType.field.fontSize);
      expect(editable.style.fontWeight, DoableType.field.fontWeight);
      expect(editable.style.color, colors.ink);

      final clear = tester.getRect(_clearButton);
      expect(clear.size, const Size.square(32));
      expect(field.right - clear.right, 6);
      expect(clear.left - input.right, DoableMetrics.space2);
      final cross = _icon(tester, DoableIconData.clear);
      expect(cross.size, 12);
      expect(cross.color, colors.fill);
      final disc = tester.widget<Container>(
        find.ancestor(
          of: _iconFinder(DoableIconData.clear),
          matching: find.byType(Container),
        ),
      );
      expect(
        disc.decoration,
        BoxDecoration(shape: BoxShape.circle, color: colors.grip),
      );
      expect(
        tester.getSize(
          find.ancestor(
            of: _iconFinder(DoableIconData.clear),
            matching: find.byType(Container),
          ),
        ),
        const Size.square(20),
      );

      final error = tester.getRect(find.text('Слишком длинный запрос'));
      expect(error.top - field.bottom, 6);
      expect(error.left - field.left, DoableMetrics.space1);
      final errorStyle = tester
          .widget<Text>(find.text('Слишком длинный запрос'))
          .style!;
      expect(errorStyle.fontSize, DoableType.hint.fontSize);
      expect(errorStyle.fontWeight, DoableType.hint.fontWeight);
      expect(errorStyle.color, colors.danger);
    });
  }

  testWidgets('заполнитель пустого поля приглушён, а клавиатура предлагает '
      'действие поиска', (tester) async {
    await tester.pumpWidget(_app(controller: TextEditingController()));

    final hint = tester.widget<Text>(find.text('Найти или создать тег'));
    expect(hint.style!.color, DoableColors.light.muted);
    expect(hint.style!.fontSize, DoableType.field.fontSize);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).textInputAction,
      TextInputAction.search,
    );
  });

  testWidgets('крестик виден только при непустом поле и очищает его, '
      'передавая потребителю пустой запрос', (tester) async {
    final controller = TextEditingController();
    final changes = <String>[];
    await tester.pumpWidget(
      _app(controller: controller, onChanged: changes.add),
    );
    expect(_clearButton, findsNothing);

    await tester.enterText(find.byType(TextField), 'дом');
    await tester.pump();
    expect(changes, ['дом']);
    expect(_clearButton, findsOneWidget);

    await tester.tap(_clearButton);
    await tester.pump();
    expect(controller.text, isEmpty);
    expect(changes, ['дом', '']);
    expect(_clearButton, findsNothing);
  });

  testWidgets('поле и крестик названы для экранного диктора, '
      'а ошибка ввода объявляется', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        controller: TextEditingController(text: 'мин'),
        error: 'Слишком длинный запрос',
      ),
    );

    expect(
      tester.getSemantics(find.byType(EditableText)),
      isSemantics(label: 'Поиск тегов', value: 'мин', isTextField: true),
    );
    expect(
      tester.getSemantics(_clearButton),
      matchesSemantics(
        label: 'Очистить поиск',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.text('Слишком длинный запрос')),
      matchesSemantics(label: 'Слишком длинный запрос', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('без ошибки строки под полем нет', (tester) async {
    await tester.pumpWidget(_app(controller: TextEditingController()));

    expect(
      tester.getSize(find.byType(SearchField)).height,
      DoableMetrics.tapMin,
    );
  });
}

final _clearButton = find.bySemanticsLabel('Очистить поиск');

Finder _iconFinder(DoableIconData icon) => find.byWidgetPredicate(
  (widget) => widget is DoableIcon && widget.icon == icon,
);

DoableIcon _icon(WidgetTester tester, DoableIconData icon) =>
    tester.widget<DoableIcon>(_iconFinder(icon));

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
      child: SearchField(
        controller: controller,
        placeholder: 'Найти или создать тег',
        label: 'Поиск тегов',
        clearLabel: 'Очистить поиск',
        onChanged: onChanged ?? (_) {},
        error: error,
      ),
    ),
  ),
);
