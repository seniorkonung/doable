import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('представление участника сохраняет идентичность и явно '
      'показывает архив', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Сходить в магазин',
          archiveState: IntentionArchiveState.archived,
        ),
      ),
    );

    expect(find.text('Сходить в магазин'), findsOneWidget);
    expect(find.text('В архиве'), findsOneWidget);
  });

  testWidgets('семантика сообщает название и состояние', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          onTap: () {},
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(node.label, contains('Быть здоровым'));
    expect(node.label, contains('В архиве'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
  });

  testWidgets('показывает данные и переход', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          onTap: () => opened++,
        ),
      ),
    );

    expect(find.text('Быть здоровым'), findsOneWidget);
    expect(find.text('В архиве'), findsOneWidget);

    await tester.tap(find.text('Быть здоровым'));
    await tester.pump();

    expect(opened, 1);
  });

  testWidgets('длинное название не скрывает название и состояние', (
    tester,
  ) async {
    const longTitle =
        'Научиться хорошо плавать и перестать бояться глубины в открытой '
        'воде даже при сильном волнении и холодной погоде';
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: longTitle,
          archiveState: IntentionArchiveState.active,
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final rowRect = tester.getRect(find.byType(IntentionSummaryView));
    final titleFinder = find.text(longTitle);
    final titleParagraph = tester.renderObject<RenderParagraph>(titleFinder);
    expect(titleParagraph.didExceedMaxLines, isFalse);
    final state = find.text('Активно');
    expect(state, findsOneWidget);
    expect(rowRect.contains(tester.getRect(state).bottomRight), isTrue);
  });
}

Widget _testApp({
  required IntentionSummaryView view,
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => Scaffold(body: ListView(children: [view])),
  ),
);
