import 'package:doable/src/design_system/components/top_bar.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

// Экран 390 с системным отступом 54, как в макете экрана выбора.
void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме панель высотой 44 стоит под системным '
        'отступом: крестик 24 цвета ink по центру области 44 в space-2 от '
        'края и заголовок title цвета ink по центру панели', (tester) async {
      await _pump(tester, _app(brightness: brightness, bar: _bar()));

      expect(tester.getTopLeft(find.byKey(_body)).dy, 54 + 44);

      final cross = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(cross.icon, DoableIconData.close);
      expect(cross.size, 24);
      expect(cross.color, colors.ink);
      expect(tester.getRect(_crossArea()), const Rect.fromLTWH(8, 54, 44, 44));
      expect(tester.getCenter(find.byWidget(cross)), const Offset(30, 76));

      final title = _style(tester, 'Выбор');
      expect(title.color, colors.ink);
      expect(title.fontSize, DoableType.title.fontSize);
      expect(title.fontWeight, DoableType.title.fontWeight);
      expect(title.height, DoableType.title.height);
      expect(tester.getCenter(find.text('Выбор')), const Offset(195, 76));
    });
  }

  testWidgets('длинный заголовок занимает одну строку не шире панели без 64 '
      'с каждой стороны и кончается многоточием', (tester) async {
    const title = 'Выбор исходного намерения для нового дневного выбора';

    await _pump(tester, _app(bar: _bar(title: title)));

    final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
    expect(paragraph.didExceedMaxLines, isTrue);
    expect(
      tester.getRect(find.text(title)),
      const Rect.fromLTWH(64, 65, 262, 22),
    );
  });

  testWidgets('крестик — кнопка с названием от потребителя и вызывает его '
      'обработчик, а заголовок объявляется заголовком', (tester) async {
    final semantics = tester.ensureSemantics();
    var closings = 0;

    await _pump(tester, _app(bar: _bar(onClose: () => closings++)));

    final cross = tester.getSemantics(find.bySemanticsLabel('Закрыть выбор'));
    expect(
      cross,
      isSemantics(label: 'Закрыть выбор', isButton: true, hasTapAction: true),
    );
    expect(cross.childrenCount, 0);
    expect(
      tester.getSemantics(find.text('Выбор')),
      isSemantics(label: 'Выбор', isHeader: true, isButton: false),
    );

    await tester.tap(_crossArea());
    expect(closings, 1);
    semantics.dispose();
  });

  testWidgets('при тексте масштаба 2 заголовок по-прежнему вмещается в '
      'панель по центру', (tester) async {
    await _pump(tester, _app(textScale: 2, bar: _bar()));

    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.text('Выбор'));
    expect(title.height, 44);
    expect(title.center, const Offset(195, 76));
  });
}

TopBar _bar({String title = 'Выбор', VoidCallback? onClose}) => TopBar(
  title: title,
  closeLabel: 'Закрыть выбор',
  onClose: onClose ?? () {},
);

const _body = Key('body');

Finder _crossArea() => find.ancestor(
  of: find.byType(DoableIcon),
  matching: find.byType(InkResponse),
);

TextStyle _style(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Future<void> _pump(WidgetTester tester, Widget app) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
}

Widget _app({
  required TopBar bar,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        padding: const EdgeInsets.only(top: 54),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        appBar: bar,
        body: const SizedBox.expand(key: _body),
      ),
    ),
  ),
);
