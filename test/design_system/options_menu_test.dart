import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/components/options_menu.dart';
import 'package:doable/src/design_system/components/sheet.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness) in [
    ('светлой', Brightness.light),
    ('тёмной', Brightness.dark),
  ]) {
    group('в $themeName теме', () {
      testWidgets('лист называет свой маршрут заголовком вида предмета и '
          'показывает пункты строками со значком в переданном порядке', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await _open(
          tester,
          brightness: brightness,
          items: [_items[0], _items[1], _availableDelete],
        );

        expect(
          tester.getSemantics(find.text('Намерение')),
          isSemantics(
            label: 'Намерение',
            isHeader: true,
            namesRoute: true,
            children: const [],
          ),
        );
        final rows = tester
            .widgetList<OptionRow>(find.byType(OptionRow))
            .toList();
        expect(rows.map((row) => row.name), [
          'Изменить',
          'Архивировать',
          'Удалить',
        ]);
        expect(rows.map((row) => row.icon), [
          DoableIconData.edit,
          DoableIconData.archive,
          DoableIconData.delete,
        ]);
        expect(rows.last.tone, OptionRowTone.danger);
        expect(
          tester.getTopLeft(find.text('Изменить')).dy,
          lessThan(tester.getTopLeft(find.text('Архивировать')).dy),
        );
        expect(
          tester.getTopLeft(find.text('Архивировать')).dy,
          lessThan(tester.getTopLeft(find.text('Удалить')).dy),
        );
        semantics.dispose();
      });

      testWidgets('выбор доступного пункта закрывает лист и возвращает этот '
          'пункт после закрытия', (tester) async {
        final menu = await _open(tester, brightness: brightness);

        await tester.tap(find.text('Архивировать'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 90));

        expect(find.byType(Sheet), findsOne);
        expect(menu.result, isNull);

        await tester.pumpAndSettle();

        expect(find.byType(Sheet), findsNothing);
        expect(menu.result, (value: _Option.archive));
      });

      testWidgets('выключенный пункт с причиной не принимает выбор и не '
          'закрывает лист', (tester) async {
        final menu = await _open(tester, brightness: brightness);

        await tester.tap(find.text('Удалить'));
        await tester.pumpAndSettle();

        expect(
          tester.widget<OptionRow>(find.byType(OptionRow).last).onPressed,
          isNull,
        );
        expect(find.text('Сначала удалите его связи'), findsOne);
        expect(find.byType(Sheet), findsOne);
        expect(menu.result, isNull);
      });

      testWidgets('касание затемнения закрывает лист без выбора', (
        tester,
      ) async {
        final menu = await _open(tester, brightness: brightness);

        await tester.tapAt(const Offset(195, 100));
        await tester.pumpAndSettle();

        expect(find.byType(Sheet), findsNothing);
        expect(menu.result, (value: null));
      });

      testWidgets('«назад» закрывает лист без выбора', (tester) async {
        final menu = await _open(tester, brightness: brightness);

        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(Sheet), findsNothing);
        expect(menu.result, (value: null));
      });

      testWidgets('при увеличенном тексте длинные названия и пояснения '
          'переносятся без переполнения', (tester) async {
        await _open(
          tester,
          brightness: brightness,
          textScale: 2,
          items: const [
            OptionsMenuItem(
              value: _Option.archive,
              icon: DoableIconData.archive,
              name: 'Архивировать намерение вместе со связями',
              hint: 'Его связи архивируются вместе с ним',
            ),
            OptionsMenuItem.unavailable(
              icon: DoableIconData.delete,
              name: 'Удалить намерение',
              reason: 'Сначала удалите его связи и дневные выборы',
            ),
          ],
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Удалить намерение'), findsOne);
      });
    });
  }
}

enum _Option { edit, archive, delete }

const _items = [
  OptionsMenuItem(
    value: _Option.edit,
    icon: DoableIconData.edit,
    name: 'Изменить',
  ),
  OptionsMenuItem(
    value: _Option.archive,
    icon: DoableIconData.archive,
    name: 'Архивировать',
    hint: 'Его связи архивируются вместе с ним',
  ),
  OptionsMenuItem<_Option>.unavailable(
    icon: DoableIconData.delete,
    name: 'Удалить',
    reason: 'Сначала удалите его связи',
  ),
];

const _availableDelete = OptionsMenuItem(
  value: _Option.delete,
  icon: DoableIconData.delete,
  name: 'Удалить',
  hint: 'Его теги сохранятся',
  tone: OptionRowTone.danger,
);

/// Открытый лист и результат его показа, когда показ завершился.
final class _OpenedMenu {
  ({_Option? value})? result;
}

Future<_OpenedMenu> _open(
  WidgetTester tester, {
  required Brightness brightness,
  double textScale = 1,
  List<OptionsMenuItem<_Option>> items = _items,
}) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final menu = _OpenedMenu();
  await tester.pumpWidget(
    MaterialApp(
      theme: doableTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final value = await showDoableSheet<_Option>(
                  context: context,
                  builder: (_, sheet) =>
                      OptionsMenu(sheet, title: 'Намерение', items: items),
                );
                menu.result = (value: value);
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  return menu;
}
