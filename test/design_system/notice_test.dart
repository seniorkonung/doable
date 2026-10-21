import 'package:doable/src/design_system/components/notice.dart';
import 'package:doable/src/design_system/doable_colors.dart';
import 'package:doable/src/design_system/doable_icon.dart';
import 'package:doable/src/design_system/doable_metrics.dart';
import 'package:doable/src/design_system/doable_theme.dart';
import 'package:doable/src/design_system/doable_type.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('сообщение об отказе объявляется без интерактивного действия', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const message = 'Отметки дней не загружены.';

    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: const Scaffold(body: Notice(message: message)),
      ),
    );

    expect(find.text(message), findsOne);
    final announcement = tester.getSemantics(find.bySemanticsLabel(message));
    expect(announcement.flagsCollection.isLiveRegion, isTrue);
    expect(find.semantics.byFlag(SemanticsFlag.isButton), findsNothing);
    expect(find.semantics.byAction(SemanticsAction.tap), findsNothing);
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, DoableColors.light.danger);
    expect(icon.size, 20);
    expect(find.byType(DoableIcon), findsNothing);
    semantics.dispose();
  });

  testWidgets('действие сообщения об отказе — кнопка с названием, которая '
      'срабатывает по всей области нажатия выше своей плашки', (tester) async {
    final semantics = tester.ensureSemantics();
    var presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: Notice.content(
            message: const Text('Не удалось прочитать файл.'),
            action: (label: 'Повторить', onPressed: () => presses++),
          ),
        ),
      ),
    );

    final button = find.bySemanticsLabel('Повторить');
    final node = tester.getSemantics(button);
    expect(node.flagsCollection.isButton, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.rect.height, greaterThanOrEqualTo(DoableMetrics.tapMin));
    await tester.tapAt(tester.getTopLeft(button) + const Offset(1, 1));
    await tester.pumpAndSettle();

    expect(presses, 1);
    semantics.dispose();
  });

  testWidgets('карточка с виджетом сообщения сохраняет предупреждающий '
      'значок, стиль текста и единственное объявление потребителя', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const message = 'Не удалось прочитать файл.';
    await tester.pumpWidget(
      MaterialApp(
        theme: doableTheme(Brightness.light),
        home: Scaffold(
          body: Notice.content(
            message: Semantics(
              container: true,
              liveRegion: true,
              child: const Text(message),
            ),
          ),
        ),
      ),
    );

    final icon = tester.widget<DoableIcon>(find.byType(DoableIcon));
    expect(icon.icon, DoableIconData.warning);
    expect(icon.color, DoableColors.light.accent);
    expect(icon.size, 20);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    final style = DefaultTextStyle.of(tester.element(find.text(message))).style;
    expect(style.color, DoableColors.light.ink);
    expect(style.fontFamily, DoableType.body.fontFamily);
    expect(style.fontSize, DoableType.body.fontSize);
    expect(style.fontWeight, DoableType.body.fontWeight);
    expect(style.height, DoableType.body.height);
    expect(find.semantics.byFlag(SemanticsFlag.isLiveRegion), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel(message)),
      isSemantics(label: message, isLiveRegion: true),
    );
    expect(find.semantics.byFlag(SemanticsFlag.isButton), findsNothing);
    semantics.dispose();
  });
}
