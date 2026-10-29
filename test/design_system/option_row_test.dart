import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (themeName, brightness, colors) in [
    ('светлой', Brightness.light, DoableColors.light),
    ('тёмной', Brightness.dark, DoableColors.dark),
  ]) {
    testWidgets('в $themeName теме опасная строка — плитка danger-soft со '
        'значком danger и название danger, а пояснение остаётся muted', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          brightness: brightness,
          OptionRow(
            icon: DoableIconData.delete,
            name: 'Удалить намерение',
            hint: 'Его теги сохранятся',
            tone: OptionRowTone.danger,
            onPressed: () {},
          ),
        ),
      );

      expect(_tileColor(tester), colors.dangerSoft);
      expect(_iconColor(tester), colors.danger);
      expect(_textColor(tester, 'Удалить намерение'), colors.danger);
      expect(_textColor(tester, 'Его теги сохранятся'), colors.muted);
    });

    testWidgets('в $themeName теме выключенная опасная строка — плитка fill '
        'со значком и названием grip, причина muted, а строка объявлена '
        'недоступной', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _app(
          brightness: brightness,
          const OptionRow(
            icon: DoableIconData.delete,
            name: 'Удалить намерение',
            hint: 'Сначала удалите его связи',
            tone: OptionRowTone.danger,
            onPressed: null,
          ),
        ),
      );

      expect(_tileColor(tester), colors.fill);
      expect(_iconColor(tester), colors.grip);
      expect(_textColor(tester, 'Удалить намерение'), colors.grip);
      expect(_textColor(tester, 'Сначала удалите его связи'), colors.muted);
      expect(
        tester.getSemantics(find.text('Удалить намерение')),
        matchesSemantics(
          label: 'Удалить намерение\nСначала удалите его связи',
          isButton: true,
          hasEnabledState: true,
          hasSelectedState: true,
        ),
      );
      semantics.dispose();
    });
  }

  testWidgets('недоступная строка объявляет недоступность экранному диктору '
      'и не принимает выбор', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        const OptionRow(
          icon: DoableIconData.export,
          name: 'Экспорт данных',
          hint: 'Пока нечего экспортировать',
          onPressed: null,
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Экспорт данных')),
      matchesSemantics(
        label: 'Экспорт данных\nПока нечего экспортировать',
        isButton: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('ход строки виден кольцом вокруг значка, а экранный диктор '
      'читает его значением строки', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _app(
        const OptionRow(
          icon: DoableIconData.export,
          name: 'Экспорт данных',
          hint: 'Сохраняется в файл…',
          onPressed: null,
          progress: OptionRowProgress(share: 0.42, label: '42 %'),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Экспорт данных')),
      matchesSemantics(
        label: 'Экспорт данных\nСохраняется в файл…',
        value: '42 %',
        isButton: true,
        hasEnabledState: true,
        hasSelectedState: true,
      ),
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      0.42,
    );
    semantics.dispose();
  });
}

Color? _tileColor(WidgetTester tester) =>
    (tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.byType(DoableIcon),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration)
        .color;

Color _iconColor(WidgetTester tester) =>
    tester.widget<DoableIcon>(find.byType(DoableIcon)).color;

Color? _textColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color;

Widget _app(OptionRow row, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: doableTheme(brightness),
      home: Scaffold(body: row),
    );
