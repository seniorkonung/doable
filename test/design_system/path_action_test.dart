import 'package:doable/src/design_system/components/path_action.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('пустое название приглушено, действие объявляется без кнопки', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: const Scaffold(
          body: PathAction(
            name: '',
            emptyText: 'Новое действие',
            label: 'Путь ведёт к новому действию',
          ),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Новое действие'));
    expect(
      text.style!.color,
      doableTheme(Brightness.light).extension<DoableColors>()!.muted,
    );
    expect(
      tester.getSemantics(find.byType(PathAction)),
      matchesSemantics(label: 'Путь ведёт к новому действию'),
    );
    semantics.dispose();
  });
}
