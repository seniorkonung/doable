import 'package:doable/l10n/app_localizations.dart';
import 'package:doable/src/intention/domain/intention.dart';
import 'package:doable/src/intention/presentation/intention_summary_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('показывает подтверждённое количество активных связей на двух '
      'языках, не изменяя название', (tester) async {
    await tester.pumpWidget(
      _testApp(
        view: IntentionSummaryView(
          title: 'Позвонить врачу',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(3),
        ),
      ),
    );

    expect(find.text('Позвонить врачу'), findsOneWidget);
    expect(find.text('Active relations: 3'), findsOneWidget);

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Позвонить врачу',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(3),
        ),
      ),
    );

    expect(find.text('Позвонить врачу'), findsOneWidget);
    expect(find.text('Активных связей: 3'), findsOneWidget);
  });

  testWidgets('показывает явный ноль активных связей', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Выбрать страховку',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: ConfirmedActiveRelationCount(0),
        ),
      ),
    );

    expect(find.text('Активных связей: 0'), findsOneWidget);
  });

  testWidgets('сохраняет прежнее число при ошибке обновления', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Много ходить',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: OutdatedActiveRelationCount(4),
        ),
      ),
    );

    expect(find.text('Активных связей: 4'), findsOneWidget);
    expect(
      find.text('Не удалось обновить количество активных связей.'),
      findsOneWidget,
    );
  });

  testWidgets('не изображает неизвестное количество нулём', (tester) async {
    await tester.pumpWidget(
      _testApp(
        view: const IntentionSummaryView(
          title: 'Иметь хорошую обувь',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: LoadingActiveRelationCount(),
        ),
      ),
    );

    expect(find.text('Loading the active relation count…'), findsOneWidget);
    expect(find.text('Active relations: 0'), findsNothing);

    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: const IntentionSummaryView(
          title: 'Иметь хорошую обувь',
          archiveState: IntentionArchiveState.active,
          showArchiveState: false,
          activeRelationCount: UnknownActiveRelationCount(),
        ),
      ),
    );

    expect(find.text('Количество активных связей неизвестно.'), findsOneWidget);
    expect(find.text('Активных связей: 0'), findsNothing);
  });

  testWidgets('представление участника сохраняет идентичность и явно '
      'показывает архив', (tester) async {
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Сходить в магазин',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          activeRelationCount: ConfirmedActiveRelationCount(0),
        ),
      ),
    );

    expect(find.text('Сходить в магазин'), findsOneWidget);
    expect(find.text('В архиве'), findsOneWidget);
    expect(find.text('Активных связей: 0'), findsOneWidget);
  });

  testWidgets('семантика сообщает название, состояние и активное количество', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          traits: const ['Готово к действию'],
          activeRelationCount: ConfirmedActiveRelationCount(2),
          onTap: () {},
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(IntentionSummaryView));
    expect(node.label, contains('Быть здоровым'));
    expect(node.label, contains('Готово к действию'));
    expect(node.label, contains('В архиве'));
    expect(node.label, contains('Активных связей: 2'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    semantics.dispose();
  });

  testWidgets('увеличенный текст не скрывает данные и переход', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        locale: const Locale('ru'),
        textScaler: const TextScaler.linear(3),
        view: IntentionSummaryView(
          title: 'Быть здоровым',
          archiveState: IntentionArchiveState.archived,
          showArchiveState: true,
          traits: const ['Готово к действию'],
          activeRelationCount: OutdatedActiveRelationCount(7),
          onTap: () => opened++,
        ),
      ),
    );

    expect(find.text('Быть здоровым'), findsOneWidget);
    expect(find.text('Готово к действию'), findsOneWidget);
    expect(find.text('В архиве'), findsOneWidget);
    expect(find.text('Активных связей: 7'), findsOneWidget);
    expect(
      find.text('Не удалось обновить количество активных связей.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Быть здоровым'));
    await tester.pump();

    expect(opened, 1);
  });
}

Widget _testApp({
  required IntentionSummaryView view,
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: Scaffold(body: ListView(children: [view])),
    ),
  ),
);
