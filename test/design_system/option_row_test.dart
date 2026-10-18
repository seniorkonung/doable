import 'package:doable/src/design_system/components/option_row.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

Widget _app(OptionRow row) => MaterialApp(
  theme: doableTheme(Brightness.light),
  home: Scaffold(body: row),
);
