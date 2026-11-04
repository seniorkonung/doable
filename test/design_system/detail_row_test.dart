import 'package:doable/src/design_system/components/button.dart';
import 'package:doable/src/design_system/components/detail_row.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _valueLabel = 'Дата: четверг, 8 октября 2026. Изменить дату';
const _slotKey = ValueKey('slot');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме подпись стоит слева стилем row цвета ink, '
        'а справа у края пилюля со значком и значением, и строка не ниже '
        'tap-min', (tester) async {
      await tester.pumpWidget(_app(brightness, _pill(onPressed: () {})));

      final row = tester.getRect(find.byType(DetailRow));
      final label = tester.getRect(find.text('Дата'));
      final pill = tester.getRect(
        find.descendant(
          of: find.byType(Button),
          matching: find.byType(Material),
        ),
      );
      expect(row.height, greaterThanOrEqualTo(DoableMetrics.tapMin));
      expect(label.left, row.left);
      expect(label.center.dy, row.center.dy);
      expect(pill.right, row.right);
      expect(pill.center.dy, row.center.dy);
      expect(
        tester.widget<DoableIcon>(find.byType(DoableIcon)).icon,
        DoableIconData.calendar,
      );
      expect(find.text('Сегодня'), findsOneWidget);
      final style = tester
          .renderObject<RenderParagraph>(find.text('Дата'))
          .text
          .style!;
      expect(style.color, colors.ink);
      expect(style.fontSize, DoableType.row.fontSize);
      expect(style.fontWeight, DoableType.row.fontWeight);
    });
  }

  testWidgets('нажатие на пилюлю вызывает обработчик', (tester) async {
    var presses = 0;
    await tester.pumpWidget(
      _app(Brightness.light, _pill(onPressed: () => presses++)),
    );

    await tester.tap(find.text('Сегодня'));

    expect(presses, 1);
  });

  testWidgets('без обработчика пилюля недоступна, а значение остаётся на '
      'экране и называется диктору полным названием, подпись в имя не '
      'входит', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(Brightness.light, _pill()));

    expect(find.text('Сегодня'), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(Button)),
      matchesSemantics(
        label: _valueLabel,
        isButton: true,
        hasEnabledState: true,
      ),
    );
    expect(find.bySemanticsLabel(RegExp(r'^Дата$')), findsNothing);
    semantics.dispose();
  });

  testWidgets('виджет потребителя стоит вместо пилюли у правого края, а '
      'сдвиг выводит его за край и принимает там касания', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        Brightness.light,
        DetailRow.slot(
          label: 'Приоритет',
          shift: 2,
          child: GestureDetector(
            key: _slotKey,
            onTap: () => taps++,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(width: 120, height: DoableMetrics.tapMin),
          ),
        ),
      ),
    );

    final row = tester.getRect(find.byType(DetailRow));
    final slot = tester.getRect(find.byKey(_slotKey));
    expect(find.byType(Button), findsNothing);
    expect(slot.right, row.right + 2);
    expect(row.height, DoableMetrics.tapMin);

    await tester.tapAt(Offset(row.right + 1, slot.center.dy));
    expect(taps, 1);
  });

  testWidgets('с крупным шрифтом строка растёт вместе с текстом, а подпись и '
      'значение пилюли целы и не накладываются', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _pill(value: 'Весь день', onPressed: () {}),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    final row = tester.getRect(find.byType(DetailRow));
    final label = tester.getRect(find.text('Дата'));
    final value = tester.getRect(find.text('Весь день'));
    expect(row.height, greaterThan(DoableMetrics.tapMin));
    expect(row.contains(label.topLeft), isTrue);
    expect(row.contains(label.bottomRight), isTrue);
    expect(row.contains(value.topLeft), isTrue);
    expect(row.contains(value.bottomRight), isTrue);
    expect(label.right, lessThan(value.left));
  });
}

DetailRow _pill({String value = 'Сегодня', VoidCallback? onPressed}) =>
    DetailRow(
      label: 'Дата',
      icon: DoableIconData.calendar,
      value: value,
      valueLabel: _valueLabel,
      onPressed: onPressed,
    );

Widget _app(Brightness brightness, Widget child, {double textScale = 1}) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
