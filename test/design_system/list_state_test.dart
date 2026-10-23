import 'package:doable/src/design_system/components/list_state.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме загрузка — кольцо 18 и текст body цвета muted в строке 24', (
      tester,
    ) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          state: const ListState.loading(text: 'Загрузка тегов…'),
        ),
      );

      final line = tester.getRect(_listState);
      expect(line.height, 24);
      final spinner = tester.getRect(_spinner);
      expect(spinner.size, const Size.square(18));
      expect(spinner.center.dy, line.center.dy);
      final text = tester.getRect(find.text('Загрузка тегов…'));
      expect(text.left - spinner.right, 10);

      final style = _textStyle(tester, 'Загрузка тегов…');
      expect(style.color, colors.muted);
      expect(style.fontSize, DoableType.body.fontSize);
      expect(style.fontWeight, DoableType.body.fontWeight);
      expect(
        _spinner,
        paints
          ..circle(
            color: colors.hairline,
            style: PaintingStyle.stroke,
            strokeWidth: 2,
          )
          ..arc(
            color: colors.muted,
            style: PaintingStyle.stroke,
            strokeWidth: 2,
          ),
      );
    });
  }

  testWidgets('кольцо загрузки делает оборот за 0,8 с, а при уменьшенной '
      'анимации — втрое медленнее, не останавливаясь', (tester) async {
    await tester.pumpWidget(
      _app(state: const ListState.loading(text: 'Загрузка тегов…')),
    );
    expect(_turns(tester), 0);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_turns(tester), closeTo(0.25, 1e-9));

    await tester.pumpWidget(
      _app(
        disableAnimations: true,
        state: const ListState.loading(text: 'Загрузка тегов…'),
      ),
    );
    final start = _turns(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect((_turns(tester) - start) % 1, closeTo(0.25, 1e-9));
  });

  testWidgets('загрузка объявляется как статус текстом без кольца', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(state: const ListState.loading(text: 'Загрузка тегов…')),
    );

    expect(
      tester.getSemantics(find.text('Загрузка тегов…')),
      isSemantics(label: 'Загрузка тегов…', isLiveRegion: true),
    );
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsOneWidget);
    expect(
      tester.getSemantics(_spinner),
      same(tester.getSemantics(find.text('Загрузка тегов…'))),
      reason: 'кольцо не даёт своего узла диктора',
    );
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме подгрузка — одно кольцо 18 по центру строки высотой 40 без '
        'видимого текста', (tester) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          state: const ListState.more(text: 'Загрузка следующих действий'),
        ),
      );

      final line = tester.getRect(_listState);
      expect(line.size, const Size(360, 40));
      final spinner = tester.getRect(_spinner);
      expect(spinner.size, const Size.square(18));
      expect(spinner.center, line.center);
      expect(find.text('Загрузка следующих действий'), findsNothing);
      expect(
        _spinner,
        paints
          ..circle(color: colors.hairline, strokeWidth: 2)
          ..arc(color: colors.muted, strokeWidth: 2),
      );
    });
  }

  testWidgets('подгрузка объявляется как статус своим текстом', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(state: const ListState.more(text: 'Загрузка следующих действий')),
    );

    expect(
      tester.getSemantics(_listState),
      isSemantics(label: 'Загрузка следующих действий', isLiveRegion: true),
    );
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsOneWidget);
    semantics.dispose();
  });

  for (final brightness in Brightness.values) {
    testWidgets('в ${brightness == Brightness.light ? 'светлой' : 'тёмной'} '
        'теме ошибка — карточка fill со значком danger, сообщением и '
        'повтором', (tester) async {
      final colors = switch (brightness) {
        Brightness.light => DoableColors.light,
        Brightness.dark => DoableColors.dark,
      };

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          state: ListState.error(
            message: 'Не удалось загрузить теги.',
            retry: (label: 'Повторить', onPressed: () {}),
          ),
        ),
      );

      final card = tester.widget<DecoratedBox>(_card);
      final decoration = card.decoration as BoxDecoration;
      expect(decoration.color, colors.fill);
      expect(
        decoration.borderRadius,
        BorderRadius.circular(DoableMetrics.radiusLg),
      );
      final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
      expect(icon.icon, DoableIconData.warning);
      expect(icon.size, 20);
      expect(icon.color, colors.danger);
      final style = _textStyle(tester, 'Не удалось загрузить теги.');
      expect(style.color, colors.ink);
      expect(style.fontSize, DoableType.body.fontSize);
      expect(find.text('Повторить'), findsOneWidget);
    });
  }

  testWidgets('ошибка объявляется как оповещение, а повтор — кнопка, '
      'нажатие которой получает потребитель', (tester) async {
    final semantics = tester.ensureSemantics();
    var retries = 0;
    await tester.pumpWidget(
      _app(
        state: ListState.error(
          message: 'Не удалось загрузить теги.',
          retry: (label: 'Повторить', onPressed: () => retries++),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Не удалось загрузить теги.')),
      isSemantics(label: 'Не удалось загрузить теги.', isLiveRegion: true),
    );
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Повторить')),
      isSemantics(
        label: 'Повторить',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
        hasFocusAction: true,
      ),
    );
    await tester.tap(find.text('Повторить'));
    expect(retries, 1);
    semantics.dispose();
  });

  testWidgets('ошибка без повтора — только значок и сообщение', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(state: const ListState.error(message: 'Данные тегов повреждены.')),
    );

    expect(find.text('Данные тегов повреждены.'), findsOneWidget);
    expect(find.semantics.byFlag(SemanticsFlag.isButton), findsNothing);
    expect(find.semantics.byAction(SemanticsAction.tap), findsNothing);
    semantics.dispose();
  });

  testWidgets('с крупным шрифтом строка загрузки и карточка ошибки растут '
      'вместе с текстом', (tester) async {
    await tester.pumpWidget(
      _app(
        textScale: 2,
        state: const ListState.loading(text: 'Загрузка тегов…'),
      ),
    );
    expect(tester.getSize(_listState).height, greaterThan(24));

    await tester.pumpWidget(
      _app(
        textScale: 2,
        state: ListState.error(
          message: 'Не удалось загрузить теги.',
          retry: (label: 'Повторить', onPressed: () {}),
        ),
      ),
    );
    final card = tester.getRect(_card);
    expect(
      card.contains(tester.getBottomRight(find.text('Повторить'))),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}

// Виды состояния — разные классы, поэтому поиск по точному типу их не видит.
final _listState = find.byWidgetPredicate((widget) => widget is ListState);

final _spinner = find.descendant(
  of: _listState,
  matching: find.byType(CustomPaint),
);

final _card = find.descendant(
  of: _listState,
  matching: find.byType(DecoratedBox),
);

double _turns(WidgetTester tester) => tester
    .widget<RotationTransition>(
      find.descendant(
        of: _listState,
        matching: find.byType(RotationTransition),
      ),
    )
    .turns
    .value;

TextStyle _textStyle(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

Widget _app({
  required ListState state,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool disableAnimations = false,
}) => MaterialApp(
  theme: doableTheme(brightness),
  home: MediaQuery(
    data: MediaQueryData(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: disableAnimations,
    ),
    child: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: 360, child: state),
      ),
    ),
  ),
);
