import 'dart:ui' show SemanticsRole, Tristate;

import 'package:doable/src/design_system/components/tabs.dart';
import 'package:doable/src/design_system/components/time_dial.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_shadows.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _clock12Pm = TimeDialClock12(
  initialHalf: TimeDialHalf.pm,
  switchLabel: 'До или после полудня',
  am: TimeDialHalfLabel(text: 'AM', semanticLabel: 'До полудня'),
  pm: TimeDialHalfLabel(text: 'PM', semanticLabel: 'После полудня'),
);

const _clock12Am = TimeDialClock12(
  initialHalf: TimeDialHalf.am,
  switchLabel: 'До или после полудня',
  am: TimeDialHalfLabel(text: 'AM', semanticLabel: 'До полудня'),
  pm: TimeDialHalfLabel(text: 'PM', semanticLabel: 'После полудня'),
);

void main() {
  setUpAll(() async {
    await (FontLoader('Inter')..addFont(
          rootBundle.load('lib/src/design_system/fonts/InterVariable.ttf'),
        ))
        .load();
  });

  for (final (themeName, brightness, colors, shadows) in [
    ('светлой', Brightness.light, DoableColors.light, DoableShadows.light),
    ('тёмной', Brightness.dark, DoableColors.dark, DoableShadows.dark),
  ]) {
    testWidgets('в $themeName теме 24-часовой циферблат ставит часы 00–11 '
        'на внешнее кольцо, а 12–23 под ними на внутреннее', (tester) async {
      await tester.pumpWidget(_app(brightness, _dial()));

      final face = tester.getRect(_face);
      expect(face.size, const Size(316, 316));
      expect(find.byType(Tabs<TimeDialHalf>), findsNothing);
      for (final (text, offset) in [
        ('00', const Offset(0, -130)),
        ('03', const Offset(130, 0)),
        ('06', const Offset(0, 130)),
        ('09', const Offset(-130, 0)),
        ('12', const Offset(0, -86)),
        ('15', const Offset(86, 0)),
        ('18', const Offset(0, 86)),
        ('21', const Offset(-86, 0)),
      ]) {
        expect(
          tester.getCenter(_hour(text)).dx,
          closeTo((face.center + offset).dx, .01),
          reason: text,
        );
        expect(
          tester.getCenter(_hour(text)).dy,
          closeTo((face.center + offset).dy, .01),
          reason: text,
        );
      }
      for (var hour = 0; hour < 24; hour++) {
        expect(_hour('$hour'.padLeft(2, '0')), findsOneWidget);
      }
      expect(tester.getCenter(find.text('Весь день')), face.center);
    });

    testWidgets('в $themeName теме 12-часовой циферблат ставит 12 наверх '
        'и сообщает час выбранной половины суток', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(
        _app(brightness, _dial(clock: _clock12Am, onPickHour: picked.add)),
      );

      final face = tester.getRect(_face);
      expect(face.size, const Size(264, 264));
      for (final (text, offset) in [
        ('12', const Offset(0, -104)),
        ('3', const Offset(104, 0)),
        ('6', const Offset(0, 104)),
        ('9', const Offset(-104, 0)),
      ]) {
        expect(
          tester.getCenter(_hour(text)).dx,
          closeTo(face.center.dx + offset.dx, .01),
        );
        expect(
          tester.getCenter(_hour(text)).dy,
          closeTo(face.center.dy + offset.dy, .01),
        );
      }
      expect(find.text('00'), findsNothing);
      await tester.tap(_hour('12'));
      await tester.tap(_hour('7'));
      expect(picked, [0, 7]);

      await tester.tap(find.text('PM'));
      await tester.pumpAndSettle();
      expect(picked, [0, 7], reason: 'переключатель не выбирает час');
      await tester.tap(_hour('12'));
      await tester.tap(_hour('7'));
      expect(picked, [0, 7, 12, 19]);
    });

    testWidgets('в $themeName теме переключатель стоит над кругом по центру, '
        'пилюли равны по ширине и не меньше 64', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(_app(brightness, _dial(clock: _clock12Pm)));

      final face = tester.getRect(_face);
      final am = tester.getRect(_pill('AM'));
      final pm = tester.getRect(_pill('PM'));
      expect(am.width, pm.width);
      expect(am.width, greaterThanOrEqualTo(64));
      expect(am.height, 36);
      expect(pm.left - am.right, 4);
      final half = tester
          .getSemantics(find.bySemanticsLabel('После полудня'))
          .getSemanticsData();
      expect(half.role, isNot(SemanticsRole.tab));
      expect(half.flagsCollection.isButton, isTrue);
      expect(half.flagsCollection.isToggled, Tristate.isTrue);
      expect((am.left + pm.right) / 2, closeTo(face.center.dx, .01));
      expect(pm.bottom, lessThanOrEqualTo(face.top));
      expect(
        tester.widget<Ink>(_pill('PM')).decoration,
        BoxDecoration(
          color: colors.fill,
          borderRadius: BorderRadius.circular(9999),
        ),
      );
      semantics.dispose();
    });

    testWidgets('в $themeName теме выбранный час лежит на accent с текстом '
        'on-accent, а «Весь день» остаётся пилюлей raised с тенью', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(brightness, _dial(selection: const TimeDialSelectedHour(18))),
      );

      expect(_circle(tester, '18').color, colors.accent);
      expect(_circle(tester, '17').color, isNull);
      expect(_text(tester, '18').color, colors.onAccent);
      expect(_text(tester, '18').fontWeight, const FontWeight(650));
      expect(_text(tester, '17').color, colors.ink);
      expect(_text(tester, '17').fontWeight, FontWeight.w500);
      expect(_text(tester, '18').fontSize, 15);
      expect(_text(tester, '06').fontSize, 17);
      expect(tester.getSize(_ink('18')), const Size(40, 40));
      final allDay = tester.widget<Ink>(_ink('Весь день')).decoration!;
      expect(
        allDay,
        BoxDecoration(
          color: colors.raised,
          border: Border.all(color: colors.hairline),
          borderRadius: BorderRadius.circular(9999),
          boxShadow: shadows.sm,
        ),
      );
      expect(tester.getSize(_ink('Весь день')).height, 36);
      expect(_text(tester, 'Весь день').color, colors.ink);
    });

    testWidgets('в $themeName теме выбранный «Весь день» лежит на accent '
        'без границы и тени, а часы не отмечены', (tester) async {
      await tester.pumpWidget(
        _app(brightness, _dial(selection: const TimeDialSelectedAllDay())),
      );

      expect(
        tester.widget<Ink>(_ink('Весь день')).decoration,
        BoxDecoration(
          color: colors.accent,
          borderRadius: BorderRadius.circular(9999),
        ),
      );
      expect(_text(tester, 'Весь день').color, colors.onAccent);
      for (var hour = 0; hour < 24; hour++) {
        expect(_circle(tester, '$hour'.padLeft(2, '0')).color, isNull);
      }
    });

    testWidgets('в $themeName теме без отметки не выбран ни час, ни '
        '«Весь день»', (tester) async {
      await tester.pumpWidget(
        _app(brightness, _dial(selection: const TimeDialNothingSelected())),
      );

      expect(
        tester.widget<Ink>(_ink('Весь день')).decoration,
        BoxDecoration(
          color: colors.raised,
          border: Border.all(color: colors.hairline),
          borderRadius: BorderRadius.circular(9999),
          boxShadow: shadows.sm,
        ),
      );
      for (var hour = 0; hour < 24; hour++) {
        expect(_circle(tester, '$hour'.padLeft(2, '0')).color, isNull);
      }
    });
  }

  testWidgets('отмеченный час виден только на кольце своей половины суток', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _dial(clock: _clock12Am, selection: const TimeDialSelectedHour(18)),
      ),
    );

    expect(_circle(tester, '6').color, isNull);
    await tester.tap(find.text('PM'));
    await tester.pumpAndSettle();
    expect(_circle(tester, '6').color, DoableColors.light.accent);
    await tester.tap(find.text('AM'));
    await tester.pumpAndSettle();
    expect(_circle(tester, '6').color, isNull);
  });

  testWidgets('нажатие на «Весь день» сообщает потребителю, а выбор часа '
      'сообщает час', (tester) async {
    var allDay = 0;
    final picked = <int>[];
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _dial(onPickHour: picked.add, onAllDay: () => allDay++),
      ),
    );

    await tester.tap(find.text('Весь день'));
    await tester.tap(_hour('23'));

    expect(allDay, 1);
    expect(picked, [23]);
  });

  testWidgets('каждый час и «Весь день» — кнопка не меньше tap-min с названием '
      'потребителя и отметкой выбранного', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _dial(clock: _clock12Pm, selection: const TimeDialSelectedHour(18)),
      ),
    );

    for (final text in ['12', '1', '6', '11', 'Весь день']) {
      final size = tester.getSize(_tap(text));
      expect(size.width, greaterThanOrEqualTo(44), reason: text);
      expect(size.height, greaterThanOrEqualTo(44), reason: text);
    }
    void expectButton(String label, {required bool selected}) {
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue, reason: label);
      expect(
        data.flagsCollection.isSelected,
        selected ? Tristate.isTrue : Tristate.isFalse,
        reason: label,
      );
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
    }

    expectButton('Час 18', selected: true);
    expectButton('Час 17', selected: false);
    expectButton('Без времени', selected: false);
    semantics.dispose();
  });

  testWidgets('при крупном шрифте цифры остаются в кружке, а пилюля «Весь '
      'день» — между часами внутреннего кольца', (tester) async {
    await tester.pumpWidget(
      _app(
        Brightness.light,
        _dial(selection: const TimeDialSelectedAllDay()),
        textScale: 2,
      ),
    );

    for (var hour = 0; hour < 24; hour++) {
      final text = '$hour'.padLeft(2, '0');
      final circle = tester.getRect(_ink(text));
      final digits = tester.getRect(find.text(text));
      expect(
        digits.left,
        greaterThanOrEqualTo(circle.left - .01),
        reason: text,
      );
      expect(digits.right, lessThanOrEqualTo(circle.right + .01), reason: text);
      expect(digits.top, greaterThanOrEqualTo(circle.top - .01), reason: text);
      expect(
        digits.bottom,
        lessThanOrEqualTo(circle.bottom + .01),
        reason: text,
      );
    }
    final pill = tester.getRect(_ink('Весь день'));
    final face = tester.getRect(_face);
    expect(pill.width, lessThanOrEqualTo(128));
    expect(pill.center, face.center);
    expect(pill.left, greaterThanOrEqualTo(tester.getRect(_hour('21')).right));
    expect(pill.right, lessThanOrEqualTo(tester.getRect(_hour('15')).left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('клавиатура рисует кольцо фокуса вокруг одного часа и Enter '
      'выбирает его', (tester) async {
    final picked = <int>[];
    await tester.pumpWidget(
      _app(Brightness.light, _dial(onPickHour: picked.add)),
    );

    List<int> focused() => [
      for (var hour = 0; hour < 24; hour++)
        if (_ring(tester, '$hour'.padLeft(2, '0')) != null) hour,
    ];
    expect(focused(), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final hours = focused();
    expect(hours, hasLength(1));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    expect(picked, hours);
  });
}

final _face = find.byWidgetPredicate(
  (widget) =>
      widget is SizedBox &&
      widget.width == widget.height &&
      widget.width! > 200,
);

Finder _tap(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(InkWell));
Finder _hour(String text) => _tap(text);
Finder _ink(String text) =>
    find.ancestor(of: find.text(text), matching: find.byType(Ink));
Finder _pill(String text) => _ink(text);

BoxDecoration _circle(WidgetTester tester, String text) =>
    tester.widget<Ink>(_ink(text)).decoration! as BoxDecoration;

TextStyle _text(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

CustomPainter? _ring(WidgetTester tester, String text) => tester
    .widget<CustomPaint>(
      find
          .ancestor(of: find.text(text), matching: find.byType(CustomPaint))
          .first,
    )
    .foregroundPainter;

Widget _dial({
  TimeDialClock clock = const TimeDialClock24(),
  TimeDialSelection selection = const TimeDialSelectedAllDay(),
  ValueChanged<int>? onPickHour,
  VoidCallback? onAllDay,
}) => TimeDial(
  clock: clock,
  selection: selection,
  allDayLabel: 'Весь день',
  allDayHint: 'Без времени',
  hourLabel: (hour) => 'Час $hour',
  onPickHour: onPickHour ?? (_) {},
  onAllDay: onAllDay ?? () {},
);

Widget _app(Brightness brightness, Widget child, {double textScale = 1}) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 900),
            textScaler: TextScaler.linear(textScale),
          ),
          child: SingleChildScrollView(
            child: SizedBox(width: 390, child: child),
          ),
        ),
      ),
    );
